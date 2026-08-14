#!/usr/bin/env python3
"""Apply one legal task-status transition as a surgical, byte-preserving
line rewrite—so a wave of several tasks moving per orchestrator turn is a
checked operation instead of a hand-edit that can silently corrupt the
file's comments, key order, or body prose.

    .agent-guild/scripts/task-status.py T-NNN <status> [--increment-retries] [STATE_DIR]

STATE_DIR defaults to the repo's `.agent-guild/state` (this script's own
grandparent directory plus `state/`), the same convention ready-set.py
uses for its own optional state-dir positional.

## The transition map

Derived from .agent-guild/CLAUDE.md's "Task lifecycle" table and the
numbered loop beneath it—that section is the source of truth; this script
does not invent transitions. The map:

    pending      -> assigned, abandoned
    assigned     -> needs-check, disputed, abandoned
    needs-check  -> checking, rework, abandoned
    checking     -> complete, rework, abandoned
    rework       -> assigned, abandoned
    disputed     -> complete, rework, checking, abandoned
    complete     -> rework
    abandoned    -> (terminal)

Rationale for the two edges the table doesn't spell out in one line:

  - assigned -> disputed. The table says disputed is "set by" the worker,
    and the worker is only ever active while a task reads `assigned`
    (dispatched or re-dispatched). The retry ladder's step 2 has the
    orchestrator attach diagnosis and set the task back to `assigned`
    before re-dispatching the same executor; a re-dispatched worker that
    believes the checker was wrong sets `disputed` itself instead of
    doing the rework. The table does not distinguish "first assignment"
    from "rework re-dispatch"—both are just `assigned`—so this script
    doesn't either.
  - disputed -> {complete, rework, checking}. The Disputes section gives
    the orchestrator's ruling two branches: "Worker upheld -> mark the
    verdict superseded, set the task complete (or re-check with corrected
    instructions)" is disputed->complete or disputed->checking (a fresh
    checker dispatch). "Checker upheld -> normal rework path" is
    disputed->rework, mirroring the checking->rework edge that path
    starts from.

Two more edges exist for invalidation (#135), which is what happens when a
dependency fails its check after something downstream already built on its
artifact. The descendant never failed anything itself, so it doesn't arrive
at rework the usual way:

  - needs-check -> rework. The worker returned and the dep failed before a
    checker ran. Sending it back now instead of through `checking` is the
    point: nothing is learned by spending a checker on an artifact already
    known to rest on something about to change.
  - complete -> rework. A task can pass its own check before the dep it
    built on fails, and that work still has to be rebuilt. It's an edge
    rather than a refusal because a job that can't be driven out of a wrong
    state is worse than one status that reopens. Holding a task at
    `checking` to avoid needing this edge was considered and rejected: a
    dep only becomes buildable-on for a grandchild once it is `complete`,
    so sitting on a landed PASS stalls the chain that speculation exists to
    unstall.

`complete` is therefore no longer terminal, though `abandoned` still is.
A reopened task rejoins `open_tasks()` and the stop gate drives it, which
is what you want: work resting on a failed dependency should hold the turn
open until it's rebuilt.

Judgment call: `abandoned` is reachable from every non-terminal status
(pending, assigned, needs-check, checking, rework, disputed)—"cancelled,
with a logged reason" is not scoped to any one point in the lifecycle by
the contract text. `complete` is NOT a legal predecessor of `abandoned`:
a finished task being retroactively cancelled isn't the "cancelled before
it got done" shape the word describes.

## Byte preservation

This is a surgical rewrite, not a YAML round-trip: a load-and-dump would
reformat comments, key order, and blank lines that a hand-authored task
file (see .agent-guild/templates/task.md) depends on to stay readable.
The file is read with `newline=''` so original line terminators survive
untouched, split with `str.splitlines(keepends=True)`, and exactly one
(or two, under --increment-retries) lines are replaced in place—the
`status:`/`retries:` key text, its spacing, and its line terminator are
all preserved verbatim; only the value token changes.

## Exit codes

0   a legal transition was applied.
1   the transition is illegal; stderr names the legal successors of the
    task's current status (or says it's terminal, if there are none).
3   infrastructure trouble: no such task file, unreadable, or
    unparseable frontmatter (missing '---' delimiters, or missing the
    `status`/`retries` key this operation needs)—reported on stderr,
    prefixed `task-status: `.

Stdlib only, so the kit stays copy-in portable.
"""
import argparse
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Canonical lifecycle order, used only to make a "legal successors" message
# read in the same order as the CLAUDE.md table rather than alphabetically.
STATUS_ORDER = [
    "pending",
    "assigned",
    "needs-check",
    "checking",
    "rework",
    "disputed",
    "complete",
    "abandoned",
]

TRANSITIONS = {
    "pending": frozenset({"assigned", "abandoned"}),
    "assigned": frozenset({"needs-check", "disputed", "abandoned"}),
    "needs-check": frozenset({"checking", "rework", "abandoned"}),
    "checking": frozenset({"complete", "rework", "abandoned"}),
    "rework": frozenset({"assigned", "abandoned"}),
    "disputed": frozenset({"complete", "rework", "checking", "abandoned"}),
    # Invalidation only (#135). See the transition-map notes above for why
    # this edge exists and why reaching for it should be rare.
    "complete": frozenset({"rework"}),
    "abandoned": frozenset(),
}

_STATUS_LINE_RE = re.compile(r"^(status:)([ \t]*)(\S+)([ \t]*)$")
_DEPS_LINE_RE = re.compile(r"^(deps:)([ \t]*)(\[.*\])([ \t]*)$")
_BUILT_ON_LINE_RE = re.compile(r"^(built_on:)([ \t]*)(\[.*\])([ \t]*)$")
_RETRIES_LINE_RE = re.compile(r"^(retries:)([ \t]*)(\d+)([ \t]*)$")


class TaskStatusError(Exception):
    """Infrastructure trouble (exit 3): the task file can't be trusted
    enough to compute or apply a transition."""


def _sort_key(status):
    try:
        return (0, STATUS_ORDER.index(status))
    except ValueError:
        return (1, status)


def _split_frontmatter(lines):
    """(start, end) line indices of the frontmatter body, i.e. the lines
    strictly between the opening and closing '---' delimiters. Raises
    TaskStatusError if either delimiter is missing—the same "genuinely
    untrustworthy, not just incomplete" bar ready-set.py's parser holds
    task files to."""
    if not lines or lines[0].rstrip("\r\n") != "---":
        raise TaskStatusError("missing opening '---' frontmatter delimiter")
    end = None
    for i in range(1, len(lines)):
        if lines[i].rstrip("\r\n") == "---":
            end = i
            break
    if end is None:
        raise TaskStatusError("missing closing '---' frontmatter delimiter")
    return 1, end


def _find_line(lines, start, end, pattern):
    for i in range(start, end):
        m = pattern.match(lines[i].rstrip("\r\n"))
        if m:
            # Reattach whatever terminator the original line carried, so
            # the rebuilt line is byte-identical apart from the value.
            terminator = lines[i][len(lines[i].rstrip("\r\n")):]
            return i, m, terminator
    return None, None, None


def read_lines(path):
    if not os.path.isfile(path):
        raise TaskStatusError(f"no such task file: {path}")
    try:
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
    except OSError as e:
        raise TaskStatusError(f"cannot read {path}: {e}")
    return text.splitlines(keepends=True)


def current_status(lines):
    start, end = _split_frontmatter(lines)
    idx, m, _ = _find_line(lines, start, end, _STATUS_LINE_RE)
    if idx is None:
        raise TaskStatusError("missing required frontmatter field: status")
    return m.group(3)


def _inline_list(value):
    """The ids in a flat `[a, b]` frontmatter list. The block form isn't
    accepted here because `deps` is inline everywhere it's written—the
    template, new-task.py, and every archived corpus—and guessing at a
    shape nothing produces would be inventing a contract."""
    value = value.strip()
    if not (value.startswith("[") and value.endswith("]")):
        return []
    return [p.strip() for p in value[1:-1].split(",") if p.strip()]


def built_on_record(lines, state_dir):
    """`built_on` for a task about to be dispatched: each of its deps paired
    with that dep's retry count right now, as `T-001:0` entries.

    This is what makes invalidation survive (#135). A descendant that built
    on a dep needs to notice when that dep is reworked afterward, and the
    dep's own status can't carry that: the orchestrator walks rework ->
    assigned -> re-dispatch inside a single turn, so a signal derived from
    the dep's current status is gone by the next time any gate looks. A
    retry count is monotonic and the comparison stays true until this task
    is dispatched again, which is exactly when it stops being true.

    A dep whose file can't be read is recorded as `?`, which never equals a
    later count and so reads as "rebuild me" rather than as agreement.
    """
    start, end = _split_frontmatter(lines)
    idx, m, _ = _find_line(lines, start, end, _DEPS_LINE_RE)
    if idx is None:
        return []
    entries = []
    for dep_id in _inline_list(m.group(3)):
        retries = "?"
        try:
            dep_lines = read_lines(os.path.join(state_dir, "tasks", f"{dep_id}.md"))
            d_start, d_end = _split_frontmatter(dep_lines)
            _, dm, _ = _find_line(dep_lines, d_start, d_end, _RETRIES_LINE_RE)
            if dm is not None:
                retries = dm.group(3)
        except (TaskStatusError, OSError):
            pass
        entries.append(f"{dep_id}:{retries}")
    return entries


def apply_transition(lines, new_status, increment_retries, state_dir=None):
    """Returns the rewritten list of lines. Raises TaskStatusError if a
    field --increment-retries needs (retries:) is missing—the transition
    itself is assumed already validated as legal by the caller."""
    start, end = _split_frontmatter(lines)

    idx, m, terminator = _find_line(lines, start, end, _STATUS_LINE_RE)
    if idx is None:
        raise TaskStatusError("missing required frontmatter field: status")
    lines = list(lines)
    lines[idx] = f"{m.group(1)}{m.group(2)}{new_status}{m.group(4)}{terminator}"

    if increment_retries:
        idx, m, terminator = _find_line(lines, start, end, _RETRIES_LINE_RE)
        if idx is None:
            raise TaskStatusError("missing required frontmatter field: retries")
        bumped = str(int(m.group(3)) + 1)
        lines[idx] = f"{m.group(1)}{m.group(2)}{bumped}{m.group(4)}{terminator}"

    # Stamp on the way INTO assigned, which is the moment the worker is
    # about to read its deps' artifacts. Doing it on any other transition
    # would record a state the worker never saw.
    if new_status == "assigned" and state_dir is not None:
        record = built_on_record(lines, state_dir)
        if record:
            start, end = _split_frontmatter(lines)
            idx, m, terminator = _find_line(lines, start, end, _BUILT_ON_LINE_RE)
            rendered = "[" + ", ".join(record) + "]"
            if idx is None:
                d_idx, _, d_term = _find_line(lines, start, end, _DEPS_LINE_RE)
                lines.insert(d_idx + 1, f"built_on: {rendered}{d_term}")
            else:
                lines[idx] = f"{m.group(1)}{m.group(2)}{rendered}{m.group(4)}{terminator}"

    return lines


def _default_state_dir():
    # This file lives at .agent-guild/scripts/task-status.py, so the repo
    # root's .agent-guild/state is two directories up from here plus
    # 'state'—the same copy-in-kit assumption ready-set.py makes.
    return os.path.join(os.path.dirname(SCRIPT_DIR), "state")


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Apply one legal task-status transition, as a surgical "
        "line rewrite that leaves everything else in the file untouched."
    )
    ap.add_argument("task_id", metavar="T-NNN")
    ap.add_argument("status", metavar="STATUS")
    ap.add_argument(
        "state_dir",
        nargs="?",
        default=None,
        metavar="STATE_DIR",
        help="defaults to the repo's .agent-guild/state",
    )
    ap.add_argument(
        "--increment-retries",
        action="store_true",
        help="also bump the retries: field by one",
    )
    args = ap.parse_args(argv)

    state_dir = args.state_dir if args.state_dir is not None else _default_state_dir()
    path = os.path.join(state_dir, "tasks", f"{args.task_id}.md")

    try:
        lines = read_lines(path)
        cur = current_status(lines)
    except TaskStatusError as e:
        sys.stderr.write(f"task-status: {path}: {e}\n")
        return 3

    legal = TRANSITIONS.get(cur)
    if legal is None:
        sys.stderr.write(
            f"task-status: {path}: status has an unrecognized value: {cur!r} "
            f"(expected one of: {', '.join(STATUS_ORDER)})\n"
        )
        return 3

    if args.status not in legal:
        if legal:
            successors = ", ".join(sorted(legal, key=_sort_key))
            sys.stderr.write(
                f"task-status: illegal transition {cur} -> {args.status} for "
                f"{args.task_id}; legal successors of {cur}: {successors}\n"
            )
        else:
            sys.stderr.write(
                f"task-status: illegal transition {cur} -> {args.status} for "
                f"{args.task_id}; {cur} is terminal, it has no legal successors\n"
            )
        return 1

    try:
        new_lines = apply_transition(lines, args.status, args.increment_retries, state_dir)
    except TaskStatusError as e:
        sys.stderr.write(f"task-status: {path}: {e}\n")
        return 3

    try:
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write("".join(new_lines))
    except OSError as e:
        sys.stderr.write(f"task-status: cannot write {path}: {e}\n")
        return 3

    print(f"{args.task_id}: {cur} -> {args.status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
