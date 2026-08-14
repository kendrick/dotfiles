#!/usr/bin/env python3
"""Fixture-based tests for task-status.py. Every fixture is a scratch
`state/tasks/` directory in a fresh temp dir, and the script runs as a
subprocess so these tests exercise the real CLI contract (exit codes,
stderr messages, on-disk bytes)—matching test_ready_set.py's approach for
its sibling script.

The transition map below is hardcoded independently of task-status.py's
own TRANSITIONS constant, not imported from it: importing it would only
prove the script agrees with itself, not that it matches
.agent-guild/CLAUDE.md's "Task lifecycle" table, which is what these tests
are actually checking.

Run: python3 .agent-guild/scripts/test_task_status.py
"""
import os
import subprocess
import sys
import tempfile

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(SCRIPTS_DIR, "task-status.py")

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


# The map under test, derived independently from CLAUDE.md's lifecycle
# table for the same reason test_ready_set.py doesn't reuse ready-set.py's
# own constants for its fixtures' expected values.
LEGAL_TRANSITIONS = {
    "pending": ["assigned", "abandoned"],
    "assigned": ["needs-check", "disputed", "abandoned"],
    # needs-check -> rework is invalidation (#135): the worker returned, then
    # a dependency failed its check, so the artifact goes back without
    # spending a checker on it.
    "needs-check": ["checking", "rework", "abandoned"],
    "checking": ["complete", "rework", "abandoned"],
    "rework": ["assigned", "abandoned"],
    "disputed": ["complete", "rework", "checking", "abandoned"],
}
TERMINAL_STATUSES = ["complete", "abandoned"]
ALL_STATUSES = list(LEGAL_TRANSITIONS) + TERMINAL_STATUSES


def write_task(tasks_dir, tid, status="pending", retries=0, extra=""):
    """A minimal task fixture in the real frontmatter shape: id, status,
    retries, plus whatever `extra` frontmatter lines the caller wants."""
    os.makedirs(tasks_dir, exist_ok=True)
    content = (
        "---\n"
        f"id: {tid}\n"
        f"status: {status}\n"
        f"retries: {retries}\n"
        f"{extra}"
        "---\n\n## Spec excerpt\n\nFixture body.\n"
    )
    path = os.path.join(tasks_dir, f"{tid}.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


def run_script(state_dir, task_id, status, *extra_argv):
    proc = subprocess.run(
        [sys.executable, SCRIPT, task_id, status, state_dir, *extra_argv],
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


# ------------------------------------------------- 1. every legal transition
print("every legal transition applies and exits 0")

for cur, successors in LEGAL_TRANSITIONS.items():
    for nxt in successors:
        with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
            tasks_dir = os.path.join(d, "tasks")
            path = write_task(tasks_dir, "T-001", status=cur)
            rc, out, err = run_script(d, "T-001", nxt)
            check(f"{cur} -> {nxt}: exit 0", rc == 0, f"rc={rc} err={err}")
            check(
                f"{cur} -> {nxt}: status line updated",
                f"status: {nxt}\n" in read(path),
                read(path),
            )

# --------------------------------------------------- 2. terminal statuses
print("abandoned accepts no transition; complete accepts only rework")

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-001", status="abandoned")
    for nxt in ALL_STATUSES:
        if nxt == "abandoned":
            continue
        rc, out, err = run_script(d, "T-001", nxt)
        check(f"abandoned -> {nxt}: exit 1 (terminal)", rc == 1, f"rc={rc} err={err}")
        check(f"abandoned -> {nxt}: stderr names it terminal", "terminal" in err, err)

# `complete` stopped being terminal with #135: invalidation has to be able to
# reopen a task that built on a dependency which then failed its check. Every
# other successor stays refused, so the hatch is one edge and not a general
# reopening. Each case gets a fresh fixture—a shared one would let the legal
# transition land and leave the rest testing a task that had already moved.
for nxt in ALL_STATUSES:
    if nxt == "complete":
        continue
    with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
        tasks_dir = os.path.join(d, "tasks")
        write_task(tasks_dir, "T-001", status="complete")
        rc, out, err = run_script(d, "T-001", nxt)
        if nxt == "rework":
            check("complete -> rework: exit 0 (invalidation hatch)", rc == 0,
                  f"rc={rc} err={err}")
        else:
            check(f"complete -> {nxt}: exit 1", rc == 1, f"rc={rc} err={err}")
            check(f"complete -> {nxt}: stderr names rework as the only successor",
                  "rework" in err and "legal successors" in err, err)

# -------------------------------------------- 3. illegal transitions, named
print("an illegal transition exits 1 and names the legal successors")

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-001", status="pending")
    # pending's only legal successors are assigned and abandoned; needs-check
    # is never legal directly from pending.
    rc, out, err = run_script(d, "T-001", "needs-check")
    check("illegal: exit 1", rc == 1, f"rc={rc} err={err}")
    check("illegal: names 'assigned' as a legal successor", "assigned" in err, err)
    check("illegal: names 'abandoned' as a legal successor", "abandoned" in err, err)
    check(
        "illegal: does not claim needs-check is legal",
        "legal successors of pending: needs-check" not in err,
        err,
    )
    check("illegal: file left untouched", "status: pending" in read(
        os.path.join(tasks_dir, "T-001.md")
    ), "status line should not have changed")

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-001", status="checking")
    # checking's legal successors are complete, rework, abandoned—never
    # straight back to needs-check.
    rc, out, err = run_script(d, "T-001", "needs-check")
    check("illegal (checking): exit 1", rc == 1, f"rc={rc} err={err}")
    for name in ("complete", "rework", "abandoned"):
        check(f"illegal (checking): names '{name}'", name in err, err)

# ------------------------------------------------- 4. --increment-retries
print("--increment-retries bumps retries and leaves everything else alone")

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    path = write_task(tasks_dir, "T-001", status="rework", retries=1)
    before = read(path)
    rc, out, err = run_script(d, "T-001", "assigned", "--increment-retries")
    check("increment: exit 0", rc == 0, f"rc={rc} err={err}")
    after = read(path)
    check("increment: retries bumped to 2", "retries: 2\n" in after, after)
    check("increment: status updated to assigned", "status: assigned\n" in after, after)

    before_lines = before.splitlines()
    after_lines = after.splitlines()
    diff = [
        (i, b, a)
        for i, (b, a) in enumerate(zip(before_lines, after_lines))
        if b != a
    ]
    check(
        "increment: exactly the status and retries lines differ",
        len(diff) == 2
        and {b for _, b, _ in diff} == {"status: rework", "retries: 1"},
        diff,
    )

# without the flag, retries must not move at all
with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    path = write_task(tasks_dir, "T-001", status="rework", retries=1)
    rc, out, err = run_script(d, "T-001", "assigned")
    check("no-increment: exit 0", rc == 0, f"rc={rc} err={err}")
    check("no-increment: retries untouched", "retries: 1\n" in read(path), read(path))

# --------------------------------------------------- 5. byte preservation
print("byte preservation: only the status line changes, nothing else")

FIXTURE_EXTRA = (
    "max_retries: 2\n"
    "deps: []\n"
    "dep_rationale: []\n"
    "# One entry per dep in `deps`, naming what THIS task actually needs\n"
    "# from that one task—not a summary of what the other task does.\n"
    "owns: []\n"
    "# Each entry is an exact file path, or a directory prefix ending in\n"
    "# `/` (covers everything under it).\n"
    "escalations: []\n"
    "artifacts:\n"
    "  - some/weird/path.py\n"
)

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    path = write_task(tasks_dir, "T-001", status="checking", retries=0, extra=FIXTURE_EXTRA)
    before = read(path)
    rc, out, err = run_script(d, "T-001", "complete")
    check("byte-preservation: exit 0", rc == 0, f"rc={rc} err={err}")
    after = read(path)

    before_lines = before.splitlines()
    after_lines = after.splitlines()
    check(
        "byte-preservation: same number of lines",
        len(before_lines) == len(after_lines),
        (len(before_lines), len(after_lines)),
    )
    diff = [
        (i, b, a)
        for i, (b, a) in enumerate(zip(before_lines, after_lines))
        if b != a
    ]
    check(
        "byte-preservation: exactly ONE line differs",
        len(diff) == 1,
        diff,
    )
    check(
        "byte-preservation: the differing line is the status line",
        bool(diff) and diff[0][1] == "status: checking" and diff[0][2] == "status: complete",
        diff,
    )
    check(
        "byte-preservation: file still ends with the original trailing newline",
        after.endswith("\n") == before.endswith("\n"),
        (before[-5:], after[-5:]),
    )

# ------------------------------------------------- 6. missing task file
print("a missing task file exits 3")

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    os.makedirs(tasks_dir, exist_ok=True)
    rc, out, err = run_script(d, "T-999", "assigned")
    check("missing: exit 3", rc == 3, f"rc={rc} out={out} err={err}")
    check("missing: names T-999.md", "T-999.md" in err, err)
    check("missing: uses the task-status: prefix", "task-status:" in err, err)

# --------------------------------------------- 7. no frontmatter delimiters
print("a task file with no frontmatter delimiters exits 3")

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    os.makedirs(tasks_dir, exist_ok=True)
    with open(os.path.join(tasks_dir, "T-001.md"), "w", encoding="utf-8") as f:
        f.write("not frontmatter at all\njust some prose\n")
    rc, out, err = run_script(d, "T-001", "assigned")
    check("no-frontmatter: exit 3", rc == 3, f"rc={rc} out={out} err={err}")
    check("no-frontmatter: names the delimiter problem", "'---'" in err, err)

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    os.makedirs(tasks_dir, exist_ok=True)
    # Opening delimiter present, closing one missing.
    with open(os.path.join(tasks_dir, "T-002.md"), "w", encoding="utf-8") as f:
        f.write("---\nid: T-002\nstatus: pending\nretries: 0\n")
    rc, out, err = run_script(d, "T-002", "assigned")
    check("unclosed-frontmatter: exit 3", rc == 3, f"rc={rc} out={out} err={err}")
    check("unclosed-frontmatter: names the closing delimiter", "closing" in err, err)

# ------------------------------------------------- 8. missing status field
print("frontmatter with no status: field exits 3")

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    os.makedirs(tasks_dir, exist_ok=True)
    with open(os.path.join(tasks_dir, "T-001.md"), "w", encoding="utf-8") as f:
        f.write("---\nid: T-001\nretries: 0\n---\n")
    rc, out, err = run_script(d, "T-001", "assigned")
    check("no-status-field: exit 3", rc == 3, f"rc={rc} out={out} err={err}")
    check("no-status-field: names the missing field", "status" in err, err)

# ------------------------------------------- built_on stamping (#135)
# Invalidation needs to survive its own dependency's rework: the ladder walks
# rework -> assigned -> re-dispatch inside one turn, so anything read off the
# dep's current status is gone before the next gate fires. The retry count is
# not, so a task records each dep's count at the moment it goes `assigned`,
# which is the moment its worker is about to read those artifacts.
print("moving to assigned records what each dep was at, for invalidation")

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-001", status="needs-check", retries=2)
    write_task(tasks_dir, "T-002", status="pending", extra="deps: [T-001]\n")
    rc, out, err = run_script(d, "T-002", "assigned")
    body = open(os.path.join(tasks_dir, "T-002.md"), encoding="utf-8").read()
    check("built_on: exit 0", rc == 0, f"rc={rc} err={err}")
    check("built_on: records the dep at its current retry count",
          "built_on: [T-001:2]" in body, body)

    # Re-dispatch re-stamps. This is the only thing that clears an
    # invalidation, so it has to track rather than stick at the first value.
    write_task(tasks_dir, "T-001", status="needs-check", retries=5)
    run_script(d, "T-002", "needs-check")
    run_script(d, "T-002", "rework")
    rc, out, err = run_script(d, "T-002", "assigned")
    body = open(os.path.join(tasks_dir, "T-002.md"), encoding="utf-8").read()
    check("built_on: re-dispatch overwrites rather than accumulating",
          "built_on: [T-001:5]" in body and "T-001:2" not in body, body)

# Only `assigned` stamps. Every other transition must leave the record
# alone, and this is the assertion that matters most: re-stamping when the
# descendant reaches `needs-check` would capture the dep's CURRENT retry
# count and erase the very invalidation the record exists to preserve.
with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-001", status="needs-check", retries=0)
    write_task(tasks_dir, "T-002", status="pending", extra="deps: [T-001]\n")
    run_script(d, "T-002", "assigned")
    # The dep now fails and burns a retry, which is exactly what the
    # descendant's record has to keep pointing at.
    write_task(tasks_dir, "T-001", status="needs-check", retries=1)
    for nxt in ("needs-check", "checking", "complete"):
        run_script(d, "T-002", nxt)
        body = open(os.path.join(tasks_dir, "T-002.md"), encoding="utf-8").read()
        check(f"built_on: moving to {nxt} does not re-stamp",
              "built_on: [T-001:0]" in body, body)

with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-001", status="complete", retries=0)
    write_task(tasks_dir, "T-002", status="complete", retries=1)
    write_task(tasks_dir, "T-003", status="pending", extra="deps: [T-001, T-002]\n")
    rc, out, err = run_script(d, "T-003", "assigned")
    body = open(os.path.join(tasks_dir, "T-003.md"), encoding="utf-8").read()
    check("built_on: every dep is recorded, in the order deps names them",
          "built_on: [T-001:0, T-002:1]" in body, body)

# A dep that can't be read is stamped `?`, which never equals a later count
# and so reads as "rebuild me" instead of as agreement.
with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-002", status="pending", extra="deps: [T-404]\n")
    rc, out, err = run_script(d, "T-002", "assigned")
    body = open(os.path.join(tasks_dir, "T-002.md"), encoding="utf-8").read()
    check("built_on: an unreadable dep stamps '?' rather than a number",
          rc == 0 and "built_on: [T-404:?]" in body, f"rc={rc} body={body}")

# A task with no deps has nothing to record, and gains no field.
with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-001", status="pending")
    rc, out, err = run_script(d, "T-001", "assigned")
    body = open(os.path.join(tasks_dir, "T-001.md"), encoding="utf-8").read()
    check("built_on: a dep-less task gains no built_on field",
          rc == 0 and "built_on" not in body, body)

# Byte preservation still holds: the stamp is an inserted line, and nothing
# else in the file may move.
with tempfile.TemporaryDirectory(prefix="task-status-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    write_task(tasks_dir, "T-001", status="complete", retries=0)
    write_task(tasks_dir, "T-002", status="pending", extra="deps: [T-001]\n")
    path = os.path.join(tasks_dir, "T-002.md")
    before = open(path, encoding="utf-8").read()
    run_script(d, "T-002", "assigned")
    after = open(path, encoding="utf-8").read()
    lost = [ln for ln in before.splitlines()
            if ln not in after.splitlines() and not ln.startswith("status:")]
    check("built_on: no other line is disturbed by the insertion",
          lost == [], f"lost={lost}")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
