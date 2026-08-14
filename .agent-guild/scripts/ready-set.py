#!/usr/bin/env python3
"""The host-neutral computation of which tasks are ready to dispatch right
now, as one wave.

    .agent-guild/scripts/ready-set.py [STATE_DIR] [--running T-NNN ...]

STATE_DIR defaults to the repo's `.agent-guild/state` (this script's own
grandparent directory plus `state/`). `--running`, repeatable-by-space, names
task ids the caller has already dispatched—typically the ids behind
stop-gate.py's fresh in-flight markers.

This is a pure function of the task files under STATE_DIR/tasks/*.md plus
the supplied --running list. It deliberately does NOT read the in-flight
marker directory itself: the caller supplies what is running, which is what
lets a Claude host and a Codex host compute identical wave decisions from
identical inputs. "Helpfully" falling back to reading markers here would
reintroduce exactly the host-specific drift this script exists to remove.

Emits one JSON object on stdout with four keys, in this order:

    wave      — tasks to dispatch as executors right now, each
                {"id", "agent" (the task's `executor`), "reason",
                "speculative_on"}. `speculative_on` is present only when
                non-empty (see below), and always comes after `reason` so
                key order stays deterministic.
    checks    — checker fan-outs due now: every task at `needs-check`, each
                {"id", "agent" (the task's `checker`), "reason"}.
    deferred  — tasks held back, each {"id", "reason", "kind"}. A reason is
                one of: "unmet deps: ..." (naming each unmet dep and its
                status), "owns overlap with T-NNN" (naming the task it
                collides with), "cannot share a wave with T-NNN: ..."
                (naming an undeclared or malformed `owns`, see below), or
                "spent retry budget: retries=N max_retries=M". `kind` is the
                machine-readable twin of that same reason—"deps", "owns",
                "owns-undeclared", "owns-malformed", or "budget"—so a caller
                can tell them apart without pattern-matching prose that's
                free to keep changing. stop-gate.py consumes it to decide
                whether a deferred task's stall counter should hold or
                advance. "deps" and "owns" name obstacles nothing but waiting
                resolves, so the counter holds. The rest must keep advancing
                it. "budget" is retry-ladder step 4, an orchestrator judgment
                call (escalate a tier, re-decompose, or hand it to the user)
                that waiting can never resolve, so holding it would deadlock
                the backstop on any job whose last open task sits at a spent
                budget. "owns-undeclared" and "owns-malformed" are deferred
                against EVERY id in --running, and `owns: []` is what
                templates/task.md ships, so holding either would let one live
                subagent freeze every other pending task's counter—the same
                crowding-out #163 was filed to remove. A "deps" reason always
                keeps the exact prefix "unmet deps: " and `kind` "deps"—
                stop-gate.py matches both (its DEFERRAL_HOLD_KINDS set and,
                for an older copied-in kit's deferred entries with no `kind`
                at all, a prefix fallback)—even though the status fragments
                inside that prefix now cover more than "not complete" (see
                the speculative dispatch predicate below).

Two tasks share a wave only if BOTH declare `owns` and both declarations
are well-formed. An empty `owns` is the absence of a claim, not a claim to
write nothing, and it is what templates/task.md ships, so undeclared is a
fresh task's default state (#162). Treating it as "collides with nothing"
would void the wave's whole safety guarantee precisely where nobody has
thought about ownership yet. A malformed entry is unknown territory in the
same way: R15 refuses one at DEC-audit, but a task file can be hand-edited
afterwards, so the shape is re-checked here rather than assumed. An
undeclared or malformed task still dispatches, alone, which is the pre-wave
behavior; every peer defers with a reason naming what to fix. Deferring the
task itself instead would deadlock a decomposition that declares none.
    attention — tasks needing a human/orchestrator judgment call, each
                {"id", "reason"}: a `disputed` task, a task whose `deps`
                names an `abandoned` task (waiting it out can never
                resolve, so it's never just "unmet"—it's escalated
                straight past `deferred`), or an INVALIDATED task—one at
                `needs-check`/`checking`/`complete` (not in --running) whose
                own dep has regressed to a status outside
                {complete, needs-check, checking}. That task could only have
                legally dispatched while the dep satisfied the predicate
                below, so the dep regressing under an already-built child is
                the signal that the child's artifact (and any verdict on it)
                may no longer be trustworthy. The reason names both tasks and
                the move to make: for a dep back at `rework`/`assigned`/
                `pending`, copy an invalidation note into the child's
                `## Rework diagnosis`, set it `assigned`, bump `retries`
                (voiding this round's verdict), and re-dispatch once the dep
                is ready to build on again; for a dep at `disputed`, rule the
                dispute first and only invalidate if it lands as rework.

Speculative dispatch (#135): a dep `d` of task `t` satisfies as a build
input—lets `t` into the wave—under either of two clauses:

    1. `d.status == "complete"`, the pre-#135 rule, or
    2. `d.status` is `needs-check` or `checking` AND every one of `d`'s OWN
       deps is `complete`.

`dep_unmet_reason(dep_id, tasks)` and `unmet_deps(task, tasks)` are the pure
functions that decide this (frozen exports—dispatch-guard.py imports them by
path, same idiom as `paths_overlap`/`owns_entry_problem` above).
`compute_ready_set` has no private copy of the logic; it calls `unmet_deps`.
A dep id absent from `tasks` fails closed under either clause (rendered
"(unknown)", as before).

Clause 2 is deliberately narrow. `pending`/`assigned` are excluded because no
artifact exists yet to build on. `rework` is excluded because the artifact is
known bad. `disputed` is excluded because the artifact is contested—neither
side has settled whether it's good. `abandoned` is excluded because the
existing attention rule above already escalates it past ordinary waiting.
What's left, `needs-check`/`checking`, is exactly "a worker returned
something, nobody has said it's wrong yet"—speculative enough to build on,
not speculative enough to build ON TOP OF an already-speculative input. That
second half is what caps speculation depth at one level: on a chain
A→B→C, requiring B's own deps (i.e. A) to be `complete`—not merely
satisfied—means C cannot dispatch while both A and B are still unverified.
Nothing here treats a chain specially; each dep is evaluated independently
against its own deps, so the one-level cap and the chain's progressive
collapse (A completes → B now satisfies clause 2 → C's dep B satisfies →
C waves) both fall out of the plain per-dep predicate. Diamonds need no
special code either, for the same reason: two children sharing one
speculative parent are just two independent evaluations of the same clause.

A wave entry whose deps are ALL `complete` is byte-identical to the
pre-#135 output: no `speculative_on` key, and `reason` is still exactly
"deps complete, owns checked against every wave peer, retry budget
available" (or the undeclared/malformed-owns variant of it). A wave entry
with at least one dep satisfied only via clause 2 carries
`"speculative_on": [...]`—the sorted ids of those unverified deps—and its
`reason` opens with "deps satisfied (T-NNN unverified at STATUS, ...)"
instead of "deps complete", naming exactly what was speculated on. The
"owns checked against every wave peer" / "alone because owns is
undeclared/malformed" half of the sentence is unchanged either way: a
reason must never certify a property that wasn't checked (#162), and here
the owns check genuinely did run the same way regardless of speculation.

No `owns` check runs between a speculative child and the dep it's
speculating on, and that's not an oversight: `_pairing_blocked` (and the
`owns`/`--running` checks generally) exist to keep two concurrent WRITERS
off overlapping territory. A dep at `needs-check`/`checking` has a worker
that already returned—its only live agent from here is a checker, which
never edits the artifact—so there is no concurrent writer on that side to
collide with. The child is still checked against every wave peer and
everything in `--running`, exactly as before; only the parent/child pairing
inside a single dependency edge is exempt, because nothing writes there.

A task counted in --running is excluded from `wave` and from every other
bucket—the caller already knows it's in flight, so it would be redundant
data, not new information. Only `pending` tasks are wave candidates.
`rework` is deliberately never one: the retry ladder requires the
orchestrator to copy the checker's diagnosis, increment `retries`, and move
the task to `assigned` before it's legal to dispatch (dispatch-guard.py
refuses a worker on anything else), so offering a `rework` task in the wave
would invite skipping those steps. A `rework` task therefore never appears
in `wave`, `deferred`, or `attention`—the caller's own `_next_move`-style
per-task advice is what owns it, same as `assigned`/`checking` tasks
(already dispatched, per the caller's own bookkeeping), which also don't
appear anywhere in this output—the caller's existing mid-flight/stale-marker
logic still owns those.

Determinism is a hard requirement: same inputs always produce the same
output, key order included. Every bucket is sorted ascending by numeric
task id. Where two dep-free candidates overlap in `owns`, exactly one goes
in the wave and the other defers—the one processed first in ascending id
order wins, so T-002 beats T-010.

Exit codes: 0, a set was computed (possibly all-empty buckets, including
when STATE_DIR/tasks/ doesn't exist—no job active is not an error). 3,
infrastructure trouble: a task file that can't be read, or whose
frontmatter can't be parsed, or is missing one of the required keys (id,
status, retries, deps, executor, checker), or whose `id` duplicates one
already declared by an earlier file—reported on stderr, prefixed
`ready-set: `, naming the file(s). A task silently skipped here is a task
nobody would ever dispatch, so this fails loud rather than dropping it.

Imports `paths_overlap` and `owns_entry_problem` from check-diff-scope.py
via the `_load_module` idiom check-job-spec.py already uses for the same
two imports, rather than reimplementing ownership-path semantics a second
time.

Stdlib only, so the kit stays copy-in portable.
"""
import argparse
import glob
import importlib.util
import json
import os
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _load_module(name, filename):
    path = os.path.join(SCRIPT_DIR, filename)
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_diff_scope = _load_module("check_diff_scope_module_scope", "check-diff-scope.py")
paths_overlap = _diff_scope.paths_overlap
owns_entry_problem = _diff_scope.owns_entry_problem


DEFAULT_MAX_RETRIES = 2
REQUIRED_KEYS = ("id", "status", "retries", "deps", "executor", "checker")
TASK_FILENAME_RE = re.compile(r"^T-\d+\.md$")

_KEY_RE = re.compile(r"^([A-Za-z0-9_]+):\s*(.*)$")
_LIST_ITEM_RE = re.compile(r"^\s+-\s+(.*)$")
_ID_NUM_RE = re.compile(r"^T-(\d+)$")


class TaskParseError(Exception):
    """A task file could not be trusted enough to compute a ready set
    from—raised instead of returning a partial/best-guess result, per this
    script's fail-loud contract."""


def _coerce(val):
    """A frontmatter value: an inline `[a, b]` list, or a scalar with
    matching quotes stripped. Mirrors hooks/_lib.py's `_coerce`, kept as a
    separate copy here (not imported) so scripts/ stays independent of
    hooks/—the same posture every other script in this directory takes."""
    val = val.strip()
    if val.startswith("[") and val.endswith("]"):
        inner = val[1:-1].strip()
        if not inner:
            return []
        return [x.strip().strip("'\"") for x in inner.split(",")]
    return val.strip("'\"")


def parse_task_frontmatter(text, path):
    """Parse a task file's leading `--- ... ---` block. Handles scalars,
    inline `[a, b]` lists, and block `- item` list continuations—the two
    shapes `deps` and `owns` actually appear in. Deliberately narrower than
    hooks/_lib.py's parser: no block-scalar (`|`/`>`) decoding, because
    ready-set.py never reads a block-scalar field (check_method is the only
    one any task carries, and it isn't read here). A block scalar's
    indented body lines simply fail to match any key or list-item pattern
    and are skipped—harmless, since nothing here consumes them.

    Raises TaskParseError, naming `path`, if the opening or closing '---'
    delimiter is missing—the one failure mode that leaves the result
    genuinely untrustworthy rather than just incomplete.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise TaskParseError(
            f"{path}: missing opening '---' frontmatter delimiter"
        )
    fm = {}
    key = None  # the key a following '- item' line would extend
    closed = False
    for line in lines[1:]:
        if line.strip() == "---":
            closed = True
            break
        m = _LIST_ITEM_RE.match(line)
        if m and key is not None:
            if not isinstance(fm.get(key), list):
                fm[key] = []
            fm[key].append(m.group(1).strip().strip("'\""))
            continue
        m = _KEY_RE.match(line)
        if m:
            k, v = m.group(1), m.group(2).strip()
            if v == "":
                fm[k] = ""
                key = k
            else:
                fm[k] = _coerce(v)
                key = None
        # else: a block scalar's body line, or blank—ignored (see docstring)
    if not closed:
        raise TaskParseError(
            f"{path}: missing closing '---' frontmatter delimiter"
        )
    return fm


def _as_list(val):
    """"" (an fm key present with a blank scalar and no following '- item'
    lines—an empty `deps:`/`owns:`) is the same as []; anything else that
    isn't already a list is a caller error."""
    if val == "":
        return []
    return val


def read_task(path):
    """Parse one task file into the flat dict compute_ready_set() needs.
    Raises TaskParseError—naming `path` and the specific defect—for
    anything unreadable, unparseable, or missing a required key."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        raise TaskParseError(f"{path}: cannot read: {e}")

    fm = parse_task_frontmatter(text, path)

    missing = [k for k in REQUIRED_KEYS if k not in fm]
    if missing:
        raise TaskParseError(
            f"{path}: missing required frontmatter field(s): "
            f"{', '.join(missing)}"
        )

    try:
        retries = int(str(fm["retries"]).strip())
    except (ValueError, TypeError):
        raise TaskParseError(f"{path}: retries is not an integer: {fm['retries']!r}")

    deps = _as_list(fm["deps"])
    if not isinstance(deps, list):
        raise TaskParseError(f"{path}: deps is not a list: {fm['deps']!r}")

    owns = _as_list(fm.get("owns", []))
    if not isinstance(owns, list):
        raise TaskParseError(f"{path}: owns is not a list: {fm.get('owns')!r}")

    # R15 refuses a malformed entry at DEC-audit, but a task file can be
    # hand-edited afterwards and this script runs on every turn, so the
    # shape is re-checked here rather than assumed. Textual checks only: the
    # ones needing the tree (a directory spelled without its slash) would
    # make the wave a function of the filesystem, and identical inputs on a
    # Claude and a Codex host have to compute identical waves. A malformed
    # entry is reported, never raised—an unparseable shape is the
    # orchestrator's to fix, and exiting 3 would blind the stop gate to
    # every other task in the job.
    owns_problem = None
    for entry in owns:
        problem = owns_entry_problem(entry)
        if problem:
            owns_problem = (entry, problem)
            break

    max_retries_raw = fm.get("max_retries", DEFAULT_MAX_RETRIES)
    if max_retries_raw == "":
        max_retries_raw = DEFAULT_MAX_RETRIES
    try:
        max_retries = int(str(max_retries_raw).strip())
    except (ValueError, TypeError):
        raise TaskParseError(
            f"{path}: max_retries is not an integer: {fm.get('max_retries')!r}"
        )

    return {
        "id": str(fm["id"]).strip(),
        "status": str(fm["status"]).strip(),
        "retries": retries,
        "deps": deps,
        "owns": owns,
        "owns_problem": owns_problem,
        "executor": str(fm["executor"]).strip(),
        "checker": str(fm["checker"]).strip(),
        "max_retries": max_retries,
        # Optional, and absent on every task file written before #135 and on
        # any task never dispatched. Carried through raw rather than parsed
        # here so read_task stays a normalizer: _built_on() owns the shape.
        "built_on": _as_list(fm.get("built_on", [])),
    }


def _sort_key(tid):
    """Ascending numeric order for T-NNN ids (T-002 before T-010), falling
    back to plain string order for anything that doesn't match the shape—
    so a malformed id sorts last and deterministically rather than
    crashing the whole computation."""
    m = _ID_NUM_RE.match(tid)
    if m:
        return (0, int(m.group(1)), tid)
    return (1, 0, tid)


def load_tasks(state_dir):
    """{id: task dict} for every T-NNN.md under state_dir/tasks/, loaded
    regardless of status—dep resolution needs to see complete/abandoned
    tasks too, not just the open ones.

    A state dir with no tasks/ subdir is no job active, which is not an
    error: {}. A state dir that isn't there at all is a different animal,
    and it exits 3. Both would otherwise print an empty wave, and a caller
    reading that JSON cannot tell "nothing is ready" from "I was pointed at
    the wrong path"—which is the same silent-drop failure the per-file exit
    3 below exists to prevent, just one directory up.

    Keying on frontmatter `id` rather than filename means two files can
    declare the same id—a copy-paste of a task file that forgot to update
    its own `id:` line, say. Silently letting the second one overwrite the
    first in this dict would make the earlier file (and whatever task it
    actually names) vanish from every bucket with no error anywhere: a task
    nobody would ever dispatch, and nothing on stderr to explain why. That's
    exactly the silent-skip this module's fail-loud contract exists to rule
    out, so a repeated id raises TaskParseError naming both files instead.
    """
    if not os.path.isdir(state_dir):
        raise TaskParseError(f"state dir does not exist: {state_dir}")
    tasks_dir = os.path.join(state_dir, "tasks")
    if not os.path.isdir(tasks_dir):
        return {}
    tasks = {}
    sources = {}  # id -> path that first declared it, for the duplicate error
    for name in sorted(os.listdir(tasks_dir)):
        if not TASK_FILENAME_RE.match(name):
            continue
        path = os.path.join(tasks_dir, name)
        t = read_task(path)
        tid = t["id"]
        if tid in tasks:
            raise TaskParseError(
                f"{path}: id {tid!r} is already declared by {sources[tid]}—"
                "two task files cannot share one id"
            )
        tasks[tid] = t
        sources[tid] = path
    return tasks


def _owns_overlap(owns_a, owns_b):
    """True if any declared entry in owns_a overlaps any in owns_b. Says
    nothing about the undeclared case: an empty list is not a claim that a
    task writes nothing, it's the absence of a claim. _pairing_blocked is
    what tells those apart."""
    if not owns_a or not owns_b:
        return False
    return any(paths_overlap(a, b) for a in owns_a for b in owns_b)


def _pairing_blocked(task_a, task_b):
    """`(kind, detail)` for why two tasks may not share a wave, or None if
    they may. `detail` is the explanatory half of the deferral reason, or
    None for a plain overlap, which the caller states in its own words.

    `owns: []` is what templates/task.md ships and what new-task.py stamps,
    so undeclared is the DEFAULT state of a fresh task, not an unusual one.
    Reading it as "writes nothing" would make the wave's safety guarantee
    evaporate exactly where nobody has thought about ownership yet, and the
    wave would still announce "no owns overlap" as its reason (#162). An
    absent claim is treated as an unknown one instead: unknown never rides
    with anything else. A malformed entry is unknown too, for the same
    reason and with a better fix attached, so it's reported ahead of the
    undeclared case even when both apply.

    Deferring every undeclared task instead would deadlock a decomposition
    that declares none, since nothing would ever reach a wave. So an
    undeclared task still dispatches; it just goes alone, which is the
    pre-wave behavior and safe by construction.
    """
    for t in (task_a, task_b):
        if t["owns_problem"]:
            entry, problem = t["owns_problem"]
            return (
                "owns-malformed",
                f"{t['id']}'s `owns` entry {entry!r} is malformed ({problem}), "
                "so no collision check is possible; fix the entry to run them "
                "together",
            )
    if not task_a["owns"] or not task_b["owns"]:
        return (
            "owns-undeclared",
            "`owns` is undeclared on one or both, so no collision check is "
            "possible; declare it on both to run them together",
        )
    if _owns_overlap(task_a["owns"], task_b["owns"]):
        return ("owns", None)
    return None


# Statuses whose deps are worth trusting enough to build ON: a worker has
# returned something (needs-check/checking) and nobody has said it's wrong
# (that's what excludes rework/disputed), or the whole thing is settled
# (complete). See the module docstring's "Speculative dispatch" section for
# why each excluded status is excluded.
_SPECULATIVE_STATUSES = frozenset({"needs-check", "checking"})


def _built_on(task):
    """{dep_id: retries-at-dispatch} from a task's `built_on` field, which
    task-status.py stamps when the task moves to `assigned`. Entries are
    `T-001:0`; a count of `?` means the dep couldn't be read at dispatch and
    reads as "rebuild me" rather than as agreement. Absent field means a task
    dispatched before #135, or one that was never dispatched—nothing to
    compare, so the status-based signal below is all there is."""
    out = {}
    raw = task.get("built_on")
    if isinstance(raw, str):
        raw = [raw] if raw.strip() else []
    for entry in raw or []:
        dep_id, _, count = str(entry).partition(":")
        dep_id, count = dep_id.strip(), count.strip()
        if not dep_id:
            continue
        try:
            out[dep_id] = int(count)
        except ValueError:
            out[dep_id] = "?"
    return out


def dep_unmet_reason(dep_id, tasks):
    """None if `dep_id` satisfies as a build input for some other task's
    dep list, else the "T-00X (status)" fragment the deferred/attention
    reasons are built from.

    Satisfies means: `dep_id`'s status is `complete`, OR it's `needs-check`/
    `checking` AND every one of ITS OWN deps is `complete`. A dep id absent
    from `tasks` fails closed—reported as "(unknown)"—same as before #135.
    Frozen export: dispatch-guard.py imports this by path, so it stays a
    pure function of its two arguments with no side effects.
    """
    if dep_id not in tasks:
        return f"{dep_id} (unknown)"
    d = tasks[dep_id]
    if d["status"] == "complete":
        return None
    if d["status"] in _SPECULATIVE_STATUSES:
        own_deps_complete = all(
            dd in tasks and tasks[dd]["status"] == "complete" for dd in d["deps"]
        )
        if own_deps_complete:
            return None
    return f"{dep_id} ({d['status']})"


def unmet_deps(task, tasks):
    """[fragment, ...]—dep_unmet_reason's output—for every dep of `task`
    that doesn't satisfy. Empty means every dep clears the bar. Frozen
    export, same contract as dep_unmet_reason."""
    return [
        frag
        for frag in (dep_unmet_reason(d, tasks) for d in task["deps"])
        if frag is not None
    ]


def compute_ready_set(tasks, running):
    """The four buckets, computed from `tasks` ({id: task dict}, as
    load_tasks() returns) and `running` (an iterable of task ids the
    caller already has in flight)."""
    running = set(running)
    ids_sorted = sorted(tasks.keys(), key=_sort_key)

    attention = []
    for tid in ids_sorted:
        if tid in running:
            continue
        if tasks[tid]["status"] == "disputed":
            attention.append(
                (
                    tid,
                    "disputed: worker filed a dispute; rule on it and set "
                    "the task to complete or rework",
                )
            )

        # Invalidation: X could only have legally dispatched (as a wave
        # member itself, or by riding a speculative dep) while its own deps
        # satisfied the predicate above. A dep that has since regressed
        # behind X is the signal that X's artifact—and any verdict already
        # filed on it—may no longer be trustworthy. Collected into ONE
        # attention entry per tid, not one per violating dep: stop-gate.py
        # keys its own reason lookup by id (`{a["id"]: a["reason"] ...}`), so
        # a second entry for the same tid would silently overwrite the
        # first's advice rather than add to it.
        if tasks[tid]["status"] in ("needs-check", "checking", "complete"):
            invalidations = []
            built_on = _built_on(tasks[tid])
            for dep_id in tasks[tid]["deps"]:
                if dep_id not in tasks:
                    # A dep that isn't on disk can't be compared against, and
                    # a built task standing on a missing one is its own
                    # problem: say so rather than passing over it.
                    invalidations.append(
                        f"built on {dep_id}, which no longer has a task file: "
                        "restore it or re-decompose, then rebuild this task"
                    )
                    continue
                dep_status = tasks[dep_id]["status"]

                # The latched signal, and the one that actually holds (#135).
                # A dep's status walks rework -> assigned -> needs-check
                # inside one orchestrator turn, so anything derived from it
                # is gone before the next gate fires. Its retry count isn't:
                # it only moves forward, and it stays ahead of what this task
                # recorded at dispatch until this task is dispatched again.
                was = built_on.get(dep_id)
                now = tasks[dep_id]["retries"]
                if was is not None and (was == "?" or now > was):
                    invalidations.append(
                        f"built against {dep_id} at retry {was}, which is now "
                        f"at retry {now}: its artifact changed underneath this "
                        f"task—invalidate (see the retry ladder), then "
                        f"re-dispatch once {dep_id} is ready to build on again"
                    )
                    continue

                if dep_status in ("complete", "needs-check", "checking"):
                    continue
                if dep_status == "disputed":
                    invalidations.append(
                        f"built on {dep_id}, which is disputed: rule the "
                        "dispute first, and invalidate only if it lands "
                        "as rework"
                    )
                else:
                    invalidations.append(
                        f"built on {dep_id}, which has gone back to "
                        f"{dep_status!r}: invalidate — copy an invalidation "
                        f"note naming {dep_id}'s diagnosis into ## Rework "
                        "diagnosis, set assigned, increment retries "
                        f"(voiding this round's verdict), and re-dispatch "
                        f"once {dep_id} is ready to build on again"
                    )
            if invalidations:
                attention.append((tid, "; ".join(invalidations)))

    wave = []
    wave_members = []  # [(tid, task)] already placed, in placement order
    deferred = []

    for tid in ids_sorted:
        t = tasks[tid]
        # rework is deliberately excluded from wave candidacy (see the
        # module docstring): the retry ladder requires the orchestrator to
        # do the diagnosis-copy/retries-increment/assigned steps first, and
        # a rework task offered here would invite skipping them straight
        # into a dispatch-guard refusal.
        if t["status"] != "pending":
            # An `assigned` task whose deps aren't ready is the shape
            # invalidation leaves behind: sent back for a rebuild and now
            # waiting on the dep that invalidated it. It isn't a wave
            # candidate, but it needs to land in `deferred` all the same,
            # because that is the only bucket whose `deps` kind holds the
            # stall counter. Left in no bucket it falls through to the stop
            # gate's own advice, which says to dispatch the executor, and
            # dispatch-guard refuses it every turn until STALLED.md lands on
            # a task that is doing exactly what it was told to.
            # `running` is checked here rather than relying on the wave
            # loop's own check below, which this branch returns before
            # reaching: a task whose worker is genuinely in flight is not
            # waiting on anything and must not be reported as deferred.
            if t["status"] == "assigned" and tid not in running:
                waiting = unmet_deps(t, tasks)
                if waiting:
                    deferred.append(
                        (tid, f"unmet deps: {', '.join(waiting)}", "deps")
                    )
            continue
        if tid in running:
            continue

        abandoned_deps = sorted(
            (d for d in t["deps"] if d in tasks and tasks[d]["status"] == "abandoned"),
            key=_sort_key,
        )
        if abandoned_deps:
            attention.append(
                (tid, f"depends on abandoned task(s): {', '.join(abandoned_deps)}")
            )
            continue

        if t["retries"] >= t["max_retries"]:
            deferred.append(
                (
                    tid,
                    f"spent retry budget: retries={t['retries']} "
                    f"max_retries={t['max_retries']}",
                    "budget",
                )
            )
            continue

        unmet = unmet_deps(t, tasks)
        if unmet:
            deferred.append((tid, f"unmet deps: {', '.join(unmet)}", "deps"))
            continue

        # Every dep satisfies (unmet is empty). Any dep that isn't itself
        # `complete` got in via clause 2 of dep_unmet_reason—needs-check or
        # checking, with ITS OWN deps complete—which is exactly what
        # `speculative_on` reports.
        speculative_on = sorted(
            (d for d in t["deps"] if tasks[d]["status"] != "complete"),
            key=_sort_key,
        )

        collision = blocked = None
        for other_tid, other_task in wave_members:
            blocked = _pairing_blocked(t, other_task)
            if blocked:
                collision = other_tid
                break
        if collision is None:
            for rtid in sorted(running, key=_sort_key):
                if rtid not in tasks:
                    continue
                blocked = _pairing_blocked(t, tasks[rtid])
                if blocked:
                    collision = rtid
                    break
        if collision is not None:
            kind, detail = blocked
            if kind == "owns":
                deferred.append((tid, f"owns overlap with {collision}", "owns"))
            else:
                deferred.append(
                    (tid, f"cannot share a wave with {collision}: {detail}", kind)
                )
            continue

        # The reason names what was actually compared. Claiming "no owns
        # overlap" for a task nobody could check was #162's sharpest edge:
        # the gate certified a property it had skipped—and a speculative
        # entry must never claim "deps complete" for a dep it never saw
        # finish, the same lesson applied to the new clause.
        if speculative_on:
            deps_clause = "deps satisfied (" + ", ".join(
                f"{d} unverified at {tasks[d]['status']}" for d in speculative_on
            ) + ")"
        else:
            deps_clause = "deps complete"

        if t["owns_problem"]:
            entry, problem = t["owns_problem"]
            reason = (f"{deps_clause}, retry budget available; alone in this "
                      f"wave because its `owns` entry {entry!r} is malformed "
                      f"({problem})")
        elif t["owns"]:
            reason = (f"{deps_clause}, owns checked against every wave peer, "
                      "retry budget available")
        else:
            reason = (f"{deps_clause}, retry budget available; alone in this "
                      "wave because its `owns` is undeclared")
        wave_entry = {"id": tid, "agent": t["executor"], "reason": reason}
        if speculative_on:
            wave_entry["speculative_on"] = speculative_on
        wave.append(wave_entry)
        wave_members.append((tid, t))

    checks = [
        {
            "id": tid,
            "agent": tasks[tid]["checker"],
            "reason": "worker finished; checker of record is owed",
        }
        for tid in ids_sorted
        if tasks[tid]["status"] == "needs-check" and tid not in running
    ]

    deferred_sorted = sorted(deferred, key=lambda entry: _sort_key(entry[0]))
    attention_sorted = sorted(attention, key=lambda pair: _sort_key(pair[0]))

    return {
        "wave": wave,
        "checks": checks,
        "deferred": [
            {"id": tid, "reason": reason, "kind": kind}
            for tid, reason, kind in deferred_sorted
        ],
        "attention": [{"id": tid, "reason": reason} for tid, reason in attention_sorted],
    }


def _default_state_dir():
    # This file lives at .agent-guild/scripts/ready-set.py, so the repo
    # root's .agent-guild/state is two directories up from here plus
    # 'state'—the same copy-in-kit assumption check-diff-scope.py and its
    # siblings make (see this module's own SCRIPT_DIR).
    return os.path.join(os.path.dirname(SCRIPT_DIR), "state")


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Compute the host-neutral ready-to-dispatch task wave."
    )
    ap.add_argument(
        "state_dir",
        nargs="?",
        default=None,
        metavar="STATE_DIR",
        help="defaults to the repo's .agent-guild/state",
    )
    ap.add_argument(
        "--running",
        nargs="*",
        default=[],
        metavar="T-NNN",
        help="task ids the caller already has dispatched (repeatable)",
    )
    args = ap.parse_args(argv)

    state_dir = args.state_dir if args.state_dir is not None else _default_state_dir()

    try:
        tasks = load_tasks(state_dir)
    except TaskParseError as e:
        sys.stderr.write(f"ready-set: {e}\n")
        return 3

    result = compute_ready_set(tasks, args.running)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
