#!/usr/bin/env python3
"""Fixture-based tests for ready-set.py. Every fixture is a scratch
`state/tasks/` directory in a fresh temp dir, and the script runs as a
subprocess so these tests exercise the real CLI contract (exit codes,
stdout JSON)—matching test_check_diff_scope.py's approach for its sibling
script.

Run: python3 .agent-guild/scripts/test_ready_set.py
"""
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(SCRIPTS_DIR, "ready-set.py")

sys.path.insert(0, SCRIPTS_DIR)
from _corpus import ARCHIVE_117, add_owns  # noqa: E402

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


def write_task(
    state_dir,
    tid,
    status="pending",
    deps=(),
    owns=(),
    executor="worker-standard",
    checker="checker-deterministic",
    retries=0,
    max_retries=2,
):
    """A minimal but complete task fixture—every field ready-set.py
    requires, in the flat `--- ... ---` frontmatter shape real task files
    use."""
    deps_str = "[" + ", ".join(deps) + "]"
    owns_str = "[" + ", ".join(owns) + "]"
    content = (
        "---\n"
        f"id: {tid}\n"
        f"status: {status}\n"
        f"retries: {retries}\n"
        f"deps: {deps_str}\n"
        f"owns: {owns_str}\n"
        f"executor: {executor}\n"
        f"checker: {checker}\n"
        f"max_retries: {max_retries}\n"
        "---\n\n## Spec excerpt\n\nFixture body.\n"
    )
    tasks_dir = os.path.join(state_dir, "tasks")
    os.makedirs(tasks_dir, exist_ok=True)
    path = os.path.join(tasks_dir, f"{tid}.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


def run_script(state_dir, *extra_argv):
    proc = subprocess.run(
        [sys.executable, SCRIPT, state_dir, *extra_argv],
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def run_and_parse(state_dir, *extra_argv):
    rc, out, err = run_script(state_dir, *extra_argv)
    try:
        return rc, json.loads(out), err
    except json.JSONDecodeError:
        return rc, None, err


def ids(entries):
    return [e["id"] for e in entries]


# --------------------------------------- 1. two dep-free disjoint tasks (headline)
print("two dep-free disjoint tasks land in ONE wave")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["file-a.py"])
    write_task(d, "T-002", owns=["file-b.py"])
    rc, result, err = run_and_parse(d)
    check("headline: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "headline: both land in the SAME wave call",
        ids(result["wave"]) == ["T-001", "T-002"],
        result,
    )
    check("headline: nothing deferred", result["deferred"] == [], result)
    check("headline: nothing needs attention", result["attention"] == [], result)

# --------------------------------------------------- 2. owns overlap defers
print("owns overlap defers the higher-numbered task, naming the collision")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-002", owns=["shared/"])
    write_task(d, "T-010", owns=["shared/file.py"])
    rc, result, err = run_and_parse(d)
    check("overlap: exit 0", rc == 0, f"rc={rc} err={err}")
    check("overlap: lower id wins the wave", ids(result["wave"]) == ["T-002"], result)
    check(
        "overlap: higher id defers",
        ids(result["deferred"]) == ["T-010"],
        result,
    )
    check(
        "overlap: reason names the colliding task",
        "T-002" in result["deferred"][0]["reason"],
        result["deferred"],
    )
    check(
        "overlap: kind is owns",
        result["deferred"][0]["kind"] == "owns",
        result["deferred"],
    )

# ------------------------------------- 2b. undeclared owns never shares a wave
# #162: `owns: []` is what templates/task.md ships and what new-task.py
# stamps, so undeclared is the DEFAULT state of a fresh task. Reading it as
# "writes nothing" let the wave group tasks nobody had checked and then
# announce "no owns overlap" as the reason, certifying a comparison it had
# skipped. Undeclared is now treated as unknown, and unknown rides alone.
print("a task with undeclared owns never shares a wave, and says so")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001")  # no owns
    write_task(d, "T-002")  # no owns
    rc, result, err = run_and_parse(d)
    check("undeclared: exit 0", rc == 0, f"rc={rc} err={err}")
    # Not deadlock: deferring EVERY undeclared task would mean nothing ever
    # reaches a wave in a decomposition that declares none, and the job
    # would never dispatch anything at all.
    check(
        "undeclared: one task still dispatches, so the job can't deadlock",
        len(result["wave"]) == 1 and result["wave"][0]["id"] == "T-001",
        result,
    )
    check(
        "undeclared: the peer defers rather than riding along unchecked",
        ids(result["deferred"]) == ["T-002"],
        result,
    )
    check(
        "undeclared: the deferral says what to do about it",
        "owns" in result["deferred"][0]["reason"]
        and "T-001" in result["deferred"][0]["reason"],
        result["deferred"],
    )
    check(
        "undeclared: kind is owns-undeclared",
        result["deferred"][0]["kind"] == "owns-undeclared",
        result["deferred"],
    )

# One declared, one not: the unknown side is what blocks the pairing, so a
# task that did its homework still can't ride with one that didn't.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001")                      # no owns
    write_task(d, "T-002", owns=["file-b.py"])  # declared
    rc, result, err = run_and_parse(d)
    check(
        "mixed: a declared task can't pair with an undeclared one",
        ids(result["wave"]) == ["T-001"] and ids(result["deferred"]) == ["T-002"],
        result,
    )
    check(
        "mixed: kind is owns-undeclared",
        result["deferred"][0]["kind"] == "owns-undeclared",
        result["deferred"],
    )

# The reason string is the assertion the gate makes about its own work, so
# it must never claim an overlap check that no task could have supplied.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001")
    rc, result, err = run_and_parse(d)
    check(
        "undeclared: the wave reason never claims 'no owns overlap'",
        "no owns overlap" not in result["wave"][0]["reason"],
        result["wave"],
    )
    check(
        "undeclared: the wave reason names the undeclared owns instead",
        "undeclared" in result["wave"][0]["reason"],
        result["wave"],
    )

# --------------------------------------- 2c. a malformed owns entry rides alone
# #162's other half. R15 refuses `./file-a.py` at DEC-audit, but nothing
# stops a task file from being hand-edited after the audit passed, and this
# script runs on every turn. `paths_overlap('./file-a.py', 'file-a.py')` is
# False, so without this the two tasks below would ride together over one
# file with the wave reporting a clean check.
print("a task whose owns entry is malformed never shares a wave either")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["file-a.py"])
    write_task(d, "T-002", owns=["./file-a.py"])
    rc, result, err = run_and_parse(d)
    check("malformed: exit 0, not a parse failure", rc == 0, f"rc={rc} err={err}")
    check(
        "malformed: the well-formed task dispatches, the other defers",
        ids(result["wave"]) == ["T-001"] and ids(result["deferred"]) == ["T-002"],
        result,
    )
    check(
        "malformed: kind is owns-malformed",
        result["deferred"][0]["kind"] == "owns-malformed",
        result["deferred"],
    )
    check(
        "malformed: the deferral quotes the offending entry back",
        "./file-a.py" in result["deferred"][0]["reason"],
        result["deferred"],
    )

# The malformed task itself still dispatches (deferring both sides would
# deadlock a job whose every task carries a typo), and its wave reason says
# why it's alone rather than claiming a check nobody could run.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["src/lib/", "../outside.py"])
    rc, result, err = run_and_parse(d)
    check(
        "malformed alone: still dispatches",
        ids(result["wave"]) == ["T-001"],
        result,
    )
    check(
        "malformed alone: the wave reason never claims owns was checked",
        "owns checked" not in result["wave"][0]["reason"],
        result["wave"],
    )
    check(
        "malformed alone: the wave reason names the bad entry",
        "../outside.py" in result["wave"][0]["reason"],
        result["wave"],
    )

# #162's opening reproduction, end to end and with nothing on disk. Two
# tasks name one directory, one of them without its trailing slash. The
# linter refuses that spelling when the directory already exists, which it
# usually doesn't when the task's job is to create it, so the wave has to
# catch this pair on the strings alone.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["src/lib"])
    write_task(d, "T-002", owns=["src/lib/"])
    rc, result, err = run_and_parse(d)
    check(
        "'src/lib' and 'src/lib/' never share a wave",
        ids(result["wave"]) == ["T-001"] and ids(result["deferred"]) == ["T-002"],
        result,
    )
    check(
        "'src/lib' vs 'src/lib/': deferred as a real overlap, not as a typo",
        result["deferred"][0]["kind"] == "owns",
        result["deferred"],
    )

# A file and the directory above it are the same territory too.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["src/foo"])
    write_task(d, "T-002", owns=["src/foo/bar.py"])
    rc, result, err = run_and_parse(d)
    check(
        "a file claim under another task's slashless directory claim defers",
        ids(result["wave"]) == ["T-001"] and ids(result["deferred"]) == ["T-002"],
        result,
    )

# A malformed entry outranks an undeclared peer: same wave refusal either
# way, and naming the typo is the more actionable of the two reasons.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["/absolute/file-a.py"])
    write_task(d, "T-002")  # no owns
    rc, result, err = run_and_parse(d)
    check(
        "malformed beats undeclared: kind is owns-malformed",
        result["deferred"][0]["kind"] == "owns-malformed",
        result["deferred"],
    )

# ------------------------------------------------- 3. --running excludes a task
print("--running excludes a task from the wave")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["file-a.py"])
    write_task(d, "T-002", owns=["file-b.py"])
    rc, result, err = run_and_parse(d, "--running", "T-001")
    check("running: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "running: only the non-running task waves",
        ids(result["wave"]) == ["T-002"],
        result,
    )
    check(
        "running: excluded task isn't dumped into deferred either",
        result["deferred"] == [],
        result,
    )

# ------------------------------------- 3b. --running excludes EVERY bucket
# The module docstring promises "excluded from `wave` and from every other
# bucket," but the `attention` loop and the `checks` comprehension used to
# never consult `running` at all—a task named with --running still came back
# in attention or checks. Both buckets pull from statuses the wave loop
# never touches (`disputed`, `needs-check`), so this needs its own fixture
# rather than reusing #3's pending/owns one.
print("--running excludes a task from attention and checks too, not just wave")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="disputed")
    write_task(d, "T-002", status="needs-check")
    rc, result, err = run_and_parse(d, "--running", "T-001", "T-002")
    check("running (all buckets): exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "running (all buckets): a disputed task named in --running is "
        "excluded from attention",
        result["attention"] == [],
        result,
    )
    check(
        "running (all buckets): a needs-check task named in --running is "
        "excluded from checks",
        result["checks"] == [],
        result,
    )

# ------------------------------------------- 4. dep on an abandoned task
print("a task whose dep is abandoned lands in attention")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="abandoned")
    write_task(d, "T-002", deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("abandoned-dep: exit 0", rc == 0, f"rc={rc} err={err}")
    check("abandoned-dep: not in wave", result["wave"] == [], result)
    check("abandoned-dep: not in deferred", result["deferred"] == [], result)
    check(
        "abandoned-dep: lands in attention naming T-001",
        len(result["attention"]) == 1
        and result["attention"][0]["id"] == "T-002"
        and "T-001" in result["attention"][0]["reason"],
        result["attention"],
    )

# ------------------------------------------------- 5. malformed task file
print("a malformed task file exits 3")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    os.makedirs(tasks_dir, exist_ok=True)
    with open(os.path.join(tasks_dir, "T-001.md"), "w", encoding="utf-8") as f:
        f.write("not frontmatter at all\n")
    rc, out, err = run_script(d)
    check("malformed: exit 3", rc == 3, f"rc={rc} out={out}")
    check("malformed: names the offending file", "T-001.md" in err, err)
    check("malformed: uses the ready-set: prefix", "ready-set:" in err, err)

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    tasks_dir = os.path.join(d, "tasks")
    os.makedirs(tasks_dir, exist_ok=True)
    # Missing required fields (status, deps, executor, checker): frontmatter
    # parses fine, but the task can't be trusted to compute a ready set from.
    with open(os.path.join(tasks_dir, "T-002.md"), "w", encoding="utf-8") as f:
        f.write("---\nid: T-002\nretries: 0\n---\n")
    rc, out, err = run_script(d)
    check("missing-fields: exit 3", rc == 3, f"rc={rc} out={out}")
    check("missing-fields: names T-002.md", "T-002.md" in err, err)

# ------------------------------------------- 5b. duplicate frontmatter id
# load_tasks() keys its dict on the frontmatter `id`, not the filename—two
# files declaring the same id used to collapse silently into one dict entry,
# so the earlier file (and whatever real task it names) vanished from every
# bucket with nothing on stderr to explain why. This module's own fail-loud
# contract says a task silently skipped here is a task nobody would ever
# dispatch, so a repeated id has to raise, naming both files.
print("two task files declaring the same id exits 3, naming both files")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["file-a.py"])
    write_task(d, "T-005", owns=["file-b.py"])
    # write_task() names the file after its first arg, but its frontmatter's
    # `id:` line is written the same way—force the collision by rewriting
    # T-005.md's own id to T-001 directly, the on-disk shape a stale
    # copy-paste of a task file would actually produce.
    dup_path = os.path.join(d, "tasks", "T-005.md")
    with open(dup_path, encoding="utf-8") as f:
        content = f.read()
    content = content.replace("id: T-005", "id: T-001", 1)
    with open(dup_path, "w", encoding="utf-8") as f:
        f.write(content)
    rc, out, err = run_script(d)
    check("duplicate-id: exit 3", rc == 3, f"rc={rc} out={out}")
    check(
        "duplicate-id: names both files",
        "T-001.md" in err and "T-005.md" in err,
        err,
    )
    check("duplicate-id: names the duplicated id", "T-001" in err, err)
    check("duplicate-id: uses the ready-set: prefix", "ready-set:" in err, err)

# ------------------------------------------------------------ 6. determinism
print("determinism: same input, byte-identical output across repeated runs")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", owns=["file-a.py"])
    write_task(d, "T-002", owns=["file-b.py"], deps=["T-001"], status="rework", retries=1)
    write_task(d, "T-003", status="needs-check")
    write_task(d, "T-004", status="disputed")
    outputs = set()
    for _ in range(5):
        rc, out, err = run_script(d)
        check("determinism: each run exits 0", rc == 0, f"rc={rc} err={err}")
        outputs.add(out)
    check(
        "determinism: every run produced byte-identical stdout",
        len(outputs) == 1,
        outputs,
    )

# --------------------------------------------------------- bonus: needs-check
print("a needs-check task owes its checker")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="needs-check", checker="checker-judgment")
    rc, result, err = run_and_parse(d)
    check("needs-check: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "needs-check: shows up in checks naming its checker",
        result["checks"] == [
            {
                "id": "T-001",
                "agent": "checker-judgment",
                "reason": "worker finished; checker of record is owed",
            }
        ],
        result["checks"],
    )

# --------------------------------------------------- bonus: spent retry budget
print("a task with a spent retry budget defers instead of waving")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="pending", retries=2, max_retries=2)
    rc, result, err = run_and_parse(d)
    check("spent-budget: exit 0", rc == 0, f"rc={rc} err={err}")
    check("spent-budget: not in wave", result["wave"] == [], result)
    check(
        "spent-budget: deferred naming the budget",
        len(result["deferred"]) == 1
        and result["deferred"][0]["id"] == "T-001"
        and "retries=2" in result["deferred"][0]["reason"],
        result["deferred"],
    )
    check(
        "spent-budget: kind is budget",
        result["deferred"][0]["kind"] == "budget",
        result["deferred"],
    )

# ------------------------------------------------- bonus: rework is never waved
# The retry ladder (.agent-guild/CLAUDE.md) requires the orchestrator to copy
# the checker's diagnosis, increment `retries`, and move the task back to
# `assigned` before a worker may run on it—dispatch-guard.py refuses a
# worker dispatch on anything but `assigned`. A `rework` task offered in the
# wave would invite skipping straight past those steps into that refusal, so
# ready-set.py must never place one there—or in `deferred`/`attention`
# either: those buckets exist for pending-task obstacles, and a rework
# task's next move is the ladder itself, which only the caller (not
# ready-set) knows how to word.
print("a rework task is never offered in any bucket, even with no obstacles")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="rework", owns=["file-a.py"], retries=1)
    rc, result, err = run_and_parse(d)
    check("rework: exit 0", rc == 0, f"rc={rc} err={err}")
    check("rework: not in wave", result["wave"] == [], result)
    check("rework: not in deferred", result["deferred"] == [], result)
    check("rework: not in attention", result["attention"] == [], result)

# --------------------------------------------------------- bonus: unmet deps
print("a task with an unmet (incomplete) dep defers, naming it")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="assigned")
    write_task(d, "T-002", deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("unmet-deps: exit 0", rc == 0, f"rc={rc} err={err}")
    check("unmet-deps: not in wave", result["wave"] == [], result)
    check(
        "unmet-deps: deferred naming T-001 and its status",
        len(result["deferred"]) == 1
        and result["deferred"][0]["id"] == "T-002"
        and "T-001" in result["deferred"][0]["reason"]
        and "assigned" in result["deferred"][0]["reason"],
        result["deferred"],
    )
    check(
        "unmet-deps: kind is deps",
        result["deferred"][0]["kind"] == "deps",
        result["deferred"],
    )

# ------------------------------------------------------ bonus: no job active
print("an absent tasks/ directory is a clean empty result, not an error")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    rc, result, err = run_and_parse(d)
    check("no-job: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "no-job: every bucket empty",
        result == {"wave": [], "checks": [], "deferred": [], "attention": []},
        result,
    )

# A state dir that ISN'T THERE is a different animal from one holding no
# tasks/. Both would print the same empty wave, and a caller reading that
# JSON could not tell "nothing is ready" from "I was pointed at the wrong
# path"—the same silent-drop failure the per-file exit 3 exists to stop,
# one directory up. The workflow driver in #134 reads this JSON to decide a
# job is finished, so the two must not look alike.
print("a state dir that does not exist exits 3, unlike one with no tasks/")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    missing = os.path.join(d, "no-such-state")
    rc, out, err = run_script(missing)
    check("missing-state-dir: exit 3", rc == 3, f"rc={rc} out={out}")
    check("missing-state-dir: names the path", missing in err, err)
    check("missing-state-dir: prints no JSON", out.strip() == "", out)

# --------------------------------------------------------- bonus: disputed
print("a disputed task lands in attention, not deferred or wave")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="disputed")
    rc, result, err = run_and_parse(d)
    check("disputed: exit 0", rc == 0, f"rc={rc} err={err}")
    check("disputed: not in wave", result["wave"] == [], result)
    check("disputed: not in deferred", result["deferred"] == [], result)
    check(
        "disputed: lands in attention",
        ids(result["attention"]) == ["T-001"],
        result["attention"],
    )

# --------------------------------------------- S1/S2: speculative dispatch
# #135: a dep at needs-check/checking, with all of ITS OWN deps complete,
# satisfies as a build input. A pending child gets to speculative-dispatch
# rather than wait for the dep's checker.
print("S1: a needs-check dep with no deps of its own lets a pending child speculative-wave")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="needs-check")
    write_task(d, "T-002", deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("S1: exit 0", rc == 0, f"rc={rc} err={err}")
    check("S1: T-002 lands in the wave", ids(result["wave"]) == ["T-002"], result)
    check(
        "S1: speculative_on names the unverified dep",
        result["wave"][0].get("speculative_on") == ["T-001"],
        result["wave"],
    )
    check(
        "S1: reason says unverified and never claims deps complete",
        "unverified" in result["wave"][0]["reason"]
        and "deps complete" not in result["wave"][0]["reason"],
        result["wave"],
    )

print("S2: same, with the dep at checking instead of needs-check")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="checking")
    write_task(d, "T-002", deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("S2: exit 0", rc == 0, f"rc={rc} err={err}")
    check("S2: T-002 lands in the wave", ids(result["wave"]) == ["T-002"], result)
    check(
        "S2: speculative_on names the unverified dep",
        result["wave"][0].get("speculative_on") == ["T-001"],
        result["wave"],
    )
    check(
        "S2: reason says unverified and never claims deps complete",
        "unverified" in result["wave"][0]["reason"]
        and "deps complete" not in result["wave"][0]["reason"],
        result["wave"],
    )

# -------------------------------------- S3/S4: a chain caps speculation at
# one level, then collapses progressively as the head resolves
print("S3: on an unresolved chain, the tail still defers—unmet-deps prefix intact")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="needs-check")
    write_task(d, "T-002", status="needs-check", deps=["T-001"])
    write_task(d, "T-003", deps=["T-002"])
    rc, result, err = run_and_parse(d)
    check("S3: exit 0", rc == 0, f"rc={rc} err={err}")
    check("S3: T-003 defers", ids(result["deferred"]) == ["T-003"], result)
    reason = result["deferred"][0]["reason"]
    # stop-gate.py falls back to this exact prefix for an older copied-in
    # kit's deferred entries carrying no `kind`—see ready-set.py:139-142 in
    # the plugin copy. A change to this literal breaks that fallback.
    check("S3: reason keeps the exact 'unmet deps: ' prefix",
          reason.startswith("unmet deps: "), reason)
    check("S3: reason names T-002 and its status",
          "T-002 (needs-check)" in reason, reason)
    check("S3: kind is deps", result["deferred"][0]["kind"] == "deps", result["deferred"])

    print("S4: completing the head collapses the chain one link")
    write_task(d, "T-001", status="complete")
    rc, result, err = run_and_parse(d)
    check("S4: exit 0", rc == 0, f"rc={rc} err={err}")
    check("S4: T-003 now waves", ids(result["wave"]) == ["T-003"], result)
    check(
        "S4: speculative_on names T-002, the now-satisfied middle link",
        result["wave"][0].get("speculative_on") == ["T-002"],
        result["wave"],
    )

# ------------------------------------------------------ S5: a diamond needs
# no special-case code—each dep is evaluated independently
print("S5: a diamond's two children both speculative-wave off one shared parent")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="needs-check")
    # owns declared and disjoint on both, so #162's owns-undeclared rule
    # doesn't strand one of them alone—this fixture is about the diamond,
    # not about owns pairing.
    write_task(d, "T-002", deps=["T-001"], owns=["file-b.py"])
    write_task(d, "T-003", deps=["T-001"], owns=["file-c.py"])
    rc, result, err = run_and_parse(d)
    check("S5: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "S5: both children land in the wave",
        ids(result["wave"]) == ["T-002", "T-003"],
        result,
    )
    check(
        "S5: both name T-001 as their speculative dep",
        all(e.get("speculative_on") == ["T-001"] for e in result["wave"]),
        result["wave"],
    )

    print("S5b: once both children reach needs-check, the grandchild waves on both")
    write_task(d, "T-001", status="complete")
    write_task(d, "T-002", status="needs-check", deps=["T-001"])
    write_task(d, "T-003", status="needs-check", deps=["T-001"])
    write_task(d, "T-004", deps=["T-002", "T-003"])
    rc, result, err = run_and_parse(d)
    check("S5b: exit 0", rc == 0, f"rc={rc} err={err}")
    check("S5b: T-004 waves", ids(result["wave"]) == ["T-004"], result)
    check(
        "S5b: speculative_on names both unverified deps, sorted",
        result["wave"][0].get("speculative_on") == ["T-002", "T-003"],
        result["wave"],
    )

# ------------------------------- S6: everything but complete/needs-check/
# checking is excluded from satisfying a dep
print("S6: rework/assigned/pending/disputed deps never satisfy—only complete/needs-check/checking do")

for dep_status in ("rework", "assigned", "pending", "disputed"):
    with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
        write_task(d, "T-001", status=dep_status)
        write_task(d, "T-002", deps=["T-001"])
        rc, result, err = run_and_parse(d)
        check(f"S6 ({dep_status}): exit 0", rc == 0, f"rc={rc} err={err}")
        check(
            f"S6 ({dep_status}): T-002 defers",
            ids(result["deferred"]) == ["T-002"],
            result,
        )
        check(
            f"S6 ({dep_status}): kind is deps",
            result["deferred"][0]["kind"] == "deps",
            result["deferred"],
        )
        check(
            f"S6 ({dep_status}): reason names the dep and its status",
            f"T-001 ({dep_status})" in result["deferred"][0]["reason"],
            result["deferred"],
        )

# --------------------------------------------------- S7: the non-speculative
# case is untouched, byte for byte
print("S7: a fully-complete dep produces the pre-#135 wave entry, byte-identical")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="complete")
    write_task(d, "T-002", deps=["T-001"], owns=["file-b.py"])
    rc, result, err = run_and_parse(d)
    check("S7: exit 0", rc == 0, f"rc={rc} err={err}")
    check("S7: T-002 waves", ids(result["wave"]) == ["T-002"], result)
    check(
        "S7: no speculative_on key at all",
        "speculative_on" not in result["wave"][0],
        result["wave"],
    )
    check(
        "S7: reason is byte-equal to the current non-speculative string",
        result["wave"][0]["reason"]
        == "deps complete, owns checked against every wave peer, "
           "retry budget available",
        result["wave"],
    )

# ------------------------------------------------------- S8: determinism
# holds for a speculative wave too, not just the plain case #6 already covers
print("S8: determinism holds for a speculative wave too")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="needs-check")
    write_task(d, "T-002", deps=["T-001"])
    write_task(d, "T-003", status="checking")
    write_task(d, "T-004", deps=["T-003"], owns=["file-x.py"])
    outputs = set()
    for _ in range(5):
        rc, out, err = run_script(d)
        check("S8: each run exits 0", rc == 0, f"rc={rc} err={err}")
        outputs.add(out)
    check(
        "S8: every run produced byte-identical stdout",
        len(outputs) == 1,
        outputs,
    )

# --------------------------------------- S9: invalidation—a built task whose
# dep regresses behind it needs a human/orchestrator call, not silent waiting
print("S9: a built task's dep regressing behind it lands the task in attention")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="rework", retries=1)
    write_task(d, "T-002", status="needs-check", deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("S9a: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "S9a: T-002 lands in attention, naming T-001, its status, and 'invalidate'",
        ids(result["attention"]) == ["T-002"]
        and "T-001" in result["attention"][0]["reason"]
        and "rework" in result["attention"][0]["reason"]
        and "invalidate" in result["attention"][0]["reason"],
        result["attention"],
    )

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="assigned")
    write_task(d, "T-002", status="complete", deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("S9b: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "S9b: an already-complete T-002 is flagged too, not just needs-check/checking",
        ids(result["attention"]) == ["T-002"]
        and "T-001" in result["attention"][0]["reason"]
        and "assigned" in result["attention"][0]["reason"],
        result["attention"],
    )

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="disputed")
    write_task(d, "T-002", status="checking", deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("S9c: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "S9c: T-001's own disputed entry and T-002's invalidation entry both appear",
        ids(result["attention"]) == ["T-001", "T-002"],
        result["attention"],
    )
    t002_entry = next(e for e in result["attention"] if e["id"] == "T-002")
    check(
        "S9c: a disputed dep gets the rule-first variant, naming T-001",
        "T-001" in t002_entry["reason"] and "rule the dispute" in t002_entry["reason"],
        t002_entry,
    )

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="rework", retries=1)
    write_task(d, "T-002", status="needs-check", deps=["T-001"])
    rc, result, err = run_and_parse(d, "--running", "T-002")
    check("S9d: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "S9d: a running T-002 is excluded from the invalidation rule too",
        result["attention"] == [],
        result["attention"],
    )

# ------------------------------- S10: invalidation survives the dep's rework
# The signal S9 checks is derived from the dep's CURRENT status, and that
# status is only wrong for part of one orchestrator turn: the ladder walks
# rework -> assigned -> re-dispatch, and the worker returns the dep to
# needs-check, all inside a turn a gate may never fire during. A descendant
# that built against an artifact which has since been rebuilt has to keep
# saying so, which is what `built_on` is for—task-status.py stamps each dep's
# retry count when the task goes `assigned`, and a count only moves forward.
print("S10: an invalidated task keeps saying so after its dep's rework returns")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="needs-check", retries=1)
    write_task(d, "T-002", status="needs-check", deps=["T-001"])
    # Stamped when T-002 was dispatched, i.e. before T-001 burned a retry.
    path = os.path.join(d, "tasks", "T-002.md")
    text = open(path, encoding="utf-8").read().replace(
        "deps: [T-001]\n", "deps: [T-001]\nbuilt_on: [T-001:0]\n")
    open(path, "w", encoding="utf-8").write(text)
    rc, result, err = run_and_parse(d)
    check("S10a: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "S10a: dep back at needs-check but a retry ahead → still invalidated",
        ids(result["attention"]) == ["T-002"]
        and "retry" in result["attention"][0]["reason"],
        result["attention"],
    )

# The same file with the dep at every later point in its own lifecycle. None
# of these is a status that would trip S9's rule, which is the entire point.
for later_status in ("checking", "complete"):
    with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
        write_task(d, "T-001", status=later_status, retries=1)
        write_task(d, "T-002", status="complete", deps=["T-001"])
        path = os.path.join(d, "tasks", "T-002.md")
        text = open(path, encoding="utf-8").read().replace(
            "deps: [T-001]\n", "deps: [T-001]\nbuilt_on: [T-001:0]\n")
        open(path, "w", encoding="utf-8").write(text)
        rc, result, err = run_and_parse(d)
        check(
            f"S10b: dep at {later_status} a retry ahead → still invalidated",
            ids(result["attention"]) == ["T-002"], result["attention"],
        )

# Re-dispatch re-stamps, which is the only thing that clears it.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="complete", retries=1)
    write_task(d, "T-002", status="needs-check", deps=["T-001"])
    path = os.path.join(d, "tasks", "T-002.md")
    text = open(path, encoding="utf-8").read().replace(
        "deps: [T-001]\n", "deps: [T-001]\nbuilt_on: [T-001:1]\n")
    open(path, "w", encoding="utf-8").write(text)
    rc, result, err = run_and_parse(d)
    check("S10c: rebuilt against the current retry → nothing owed",
          result["attention"] == [], result["attention"])

# A dep that couldn't be read at dispatch was stamped `?`, which must read as
# "rebuild me" rather than as agreement with whatever it says now.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="complete", retries=0)
    write_task(d, "T-002", status="needs-check", deps=["T-001"])
    path = os.path.join(d, "tasks", "T-002.md")
    text = open(path, encoding="utf-8").read().replace(
        "deps: [T-001]\n", "deps: [T-001]\nbuilt_on: [T-001:?]\n")
    open(path, "w", encoding="utf-8").write(text)
    rc, result, err = run_and_parse(d)
    check("S10d: an unreadable stamp reads as invalidated, not as agreement",
          ids(result["attention"]) == ["T-002"], result["attention"])

# ---------------------------- S11: the holes the adversarial review found
# A dangling dep id. The docstring promises this fails closed under both
# clauses; nothing tested it, and returning None instead of "(unknown)" left
# every suite green while a task depending on a nonexistent id waved.
print("S11: a dangling dep id fails closed, in the wave and in invalidation")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-002", status="pending", deps=["T-999"], owns=["b.py"])
    rc, result, err = run_and_parse(d)
    check("S11a: a task depending on a nonexistent id never waves",
          result["wave"] == [], result)
    check("S11a: it defers on deps, naming the id as unknown",
          ids(result["deferred"]) == ["T-002"]
          and "T-999" in result["deferred"][0]["reason"]
          and result["deferred"][0]["kind"] == "deps",
          result["deferred"])

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-002", status="needs-check", deps=["T-999"])
    rc, result, err = run_and_parse(d)
    check("S11b: a BUILT task whose dep file vanished is flagged, not skipped",
          ids(result["attention"]) == ["T-002"]
          and "T-999" in result["attention"][0]["reason"],
          result["attention"])

# Two regressed deps on one descendant. stop-gate keys its reason lookup by
# task id, so two entries for one task would silently drop the first's advice.
with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="rework", retries=1)
    write_task(d, "T-002", status="rework", retries=1)
    write_task(d, "T-003", status="needs-check", deps=["T-001", "T-002"])
    rc, result, err = run_and_parse(d)
    check("S11c: two regressed deps produce exactly ONE attention entry",
          len(result["attention"]) == 1 and result["attention"][0]["id"] == "T-003",
          result["attention"])
    check("S11c: and that one entry names both deps",
          "T-001" in result["attention"][0]["reason"]
          and "T-002" in result["attention"][0]["reason"],
          result["attention"])

# ------------------------ S12: an invalidated task waiting holds its counter
# Sent back for a rebuild and now waiting on the dep that invalidated it, an
# `assigned` task used to land in no bucket at all—so the stop gate fell
# through to its own advice ("dispatch the executor"), dispatch-guard refused,
# and STALLED.md landed in three turns on a task doing what it was told.
print("S12: an invalidated task waiting on its dep is deferred, not stalled")

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="rework", retries=1)
    write_task(d, "T-002", status="assigned", retries=1, deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("S12a: it lands in deferred with the stall-holding kind",
          ids(result["deferred"]) == ["T-002"]
          and result["deferred"][0]["kind"] == "deps",
          result["deferred"])
    rc, result, err = run_and_parse(d, "--running", "T-002")
    check("S12b: but not while its worker is genuinely in flight",
          result["deferred"] == [], result["deferred"])

with tempfile.TemporaryDirectory(prefix="ready-set-fixture-") as d:
    write_task(d, "T-001", status="complete", retries=1)
    write_task(d, "T-002", status="assigned", retries=1, deps=["T-001"])
    rc, result, err = run_and_parse(d)
    check("S12c: once the dep is ready to build on, nothing is deferred",
          result["deferred"] == [], result["deferred"])

# ------------------------------------------- replay: the archived #117 graph
# Everything above is a fixture built to exercise one rule. This section is the
# only case driven by a job that actually ran (#169). The wave path's headline
# claim is that grouping beats the serial dispatch it replaced, and until this
# existed nothing would have failed if a change to the grouping quietly
# serialized the whole thing again.
#
# #134 carried this criterion and was closed without it, because the driver it
# specified turned out to be infeasible—guild hooks don't fire for
# workflow-spawned agents. The criterion never needed that driver. ready-set.py
# is a pure function of task files plus --running, so the replay runs offline:
# no hosts, no agents, no vendor calls.
# Guard on the two paths the replay actually opens, not just the archive
# directory. A partial archive is a real state: `dispatches.log` was missing
# from every corpus in git until this branch, because a global
# core.excludesFile carrying `*.log` outranked nothing that put it back. The
# directory existed, so a guard that only checked for it skipped nothing and
# the replay died on the missing file instead.
REPLAY_INPUTS = [
    os.path.join(ARCHIVE_117, "tasks"),
    os.path.join(ARCHIVE_117, "log", "dispatches.log"),
]
if not all(os.path.exists(p) for p in REPLAY_INPUTS):
    missing = [p for p in REPLAY_INPUTS if not os.path.exists(p)]
    print(f"note: skipping the #117 replay, missing {missing}. This suite "
          f"ships into user projects; the archive under state/ does not, so "
          f"the skip is expected there and the remaining cases still cover "
          f"the script.")
else:
    print("replaying the archived #117 graph takes fewer waves than the run did")

    def corpus_deps():
        """Each task's declared deps, read from the archive itself so the
        dependency-order assertion can't drift from the graph it checks."""
        deps = {}
        for name in sorted(os.listdir(os.path.join(ARCHIVE_117, "tasks"))):
            with open(os.path.join(ARCHIVE_117, "tasks", name), encoding="utf-8") as f:
                for line in f:
                    m = re.match(r"^deps:\s*\[(.*)\]\s*$", line)
                    if m:
                        deps[name[:-3]] = [d.strip() for d in m.group(1).split(",") if d.strip()]
                        break
        return deps

    def dispatched_tasks():
        """The tasks the real run actually sent workers to. Read from the
        run's own log rather than hardcoded, so "covers the same work" is
        anchored to what happened. Every line in this log appears twice—the
        run predates #41's double-registration fix—and T-006 was genuinely
        dispatched twice after a FAIL, so dedupe by task rather than by line
        and count tasks, not dispatches."""
        seen = set()
        with open(os.path.join(ARCHIVE_117, "log", "dispatches.log"), encoding="utf-8") as f:
            for line in f:
                fields = [p.strip() for p in line.split("|")]
                if len(fields) >= 3 and "worker-" in fields[1]:
                    seen.add(fields[2])
        return seen

    def set_status(state_dir, tid, status):
        path = os.path.join(state_dir, "tasks", f"{tid}.md")
        with open(path, encoding="utf-8") as f:
            text = f.read()
        with open(path, "w", encoding="utf-8") as f:
            f.write(re.sub(r"^status:.*$", f"status: {status}", text, count=1, flags=re.M))

    def archive_digest():
        """A fingerprint of the archived tasks, so "the fixture works on a
        copy" is checked rather than asserted. add_owns mutates on disk by
        contract, and pointing it one directory to the left would rewrite the
        run this suite exists to preserve—a slip only `git status` would
        otherwise catch, and only if someone looked."""
        h = hashlib.sha256()
        tasks = os.path.join(ARCHIVE_117, "tasks")
        for name in sorted(os.listdir(tasks)):
            h.update(name.encode())
            with open(os.path.join(tasks, name), "rb") as f:
                h.update(f.read())
        return h.hexdigest()

    before = archive_digest()

    with tempfile.TemporaryDirectory(prefix="ready-set-replay-") as d:
        state = os.path.join(d, "state")
        os.makedirs(state)
        shutil.copytree(os.path.join(ARCHIVE_117, "tasks"), os.path.join(state, "tasks"))

        # The archive holds the job as it finished. Rewind it to the state the
        # orchestrator faced at the start: every task pending, no retries
        # spent. T-006's `retries: 1` wouldn't have deferred it on budget
        # anyway (the ladder defers at retries >= max_retries, and its max is
        # 2), so clearing it changes no wave here—it's rewound because a
        # replay that starts mid-run isn't replaying the run. The archived
        # files themselves are never touched; this is a copy.
        for name in sorted(os.listdir(os.path.join(state, "tasks"))):
            path = os.path.join(state, "tasks", name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            text = re.sub(r"^status:.*$", "status: pending", text, count=1, flags=re.M)
            text = re.sub(r"^retries:.*$", "retries: 0", text, count=1, flags=re.M)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)

        # The corpus predates #133 and carries no `owns`. Replayed as-is every
        # pair reads as owns-undeclared, every wave holds one task, and the
        # replay reproduces exactly the serial behavior it exists to disprove
        # while appearing to pass. Same derivation the linter suite proves
        # against, imported rather than repeated.
        add_owns(state)

        waves = []
        deferrals = []
        remaining = set(corpus_deps())
        # A cap, not a loop bound: an empty wave with work left means the
        # grouping stalled, and that has to fail loudly rather than spin.
        for _ in range(12):
            if not remaining:
                break
            rc, result, err = run_and_parse(state)
            if rc != 0 or result is None or not result["wave"]:
                check("replay: every call yields a non-empty wave",
                      False, f"rc={rc} err={err} result={result}")
                break
            members = sorted(ids(result["wave"]))
            waves.append(members)
            deferrals.append(result["deferred"])
            for tid in members:
                set_status(state, tid, "complete")
                remaining.discard(tid)

        check("replay: every task was dispatched", not remaining, f"left={sorted(remaining)}")

        # What the real run did: seven tasks, dispatched one at a time.
        serial = dispatched_tasks()
        covered = {tid for wave in waves for tid in wave}
        check("replay: covers exactly the tasks the run dispatched workers for",
              covered == serial, f"replayed={sorted(covered)} run={sorted(serial)}")

        # The thesis. Fewer waves than serial dispatches, with the count named
        # so a regression in grouping fails here instead of passing quietly.
        check(f"replay: {len(waves)} waves against {len(serial)} serially dispatched tasks",
              len(waves) < len(serial), f"waves={waves}")
        check("replay: takes exactly 6 waves", len(waves) == 6, f"waves={waves}")

        # Composition, not just count: a change that holds the number while
        # shuffling membership is still a change to the grouping.
        check(
            "replay: wave composition is unchanged",
            waves == [
                ["T-001", "T-005"],
                ["T-002"],
                ["T-004"],
                ["T-006"],
                ["T-007"],
                ["T-003"],
            ],
            waves,
        )

        # T-004 is why this is six waves and not five. Its lone artifact is
        # `~/repos/skills/...`, so the cloned owns entry is a tilde path, which
        # owns_entry_problem refuses—an unreadable claim is an unknown one, so
        # it rides alone instead of pairing with T-002. Asserted so the pinned
        # composition reads as a consequence rather than a snapshot.
        check(
            "replay: T-004 defers on malformed owns, splitting it from T-002",
            len(deferrals) > 1 and any(
                e["id"] == "T-004" and e["kind"] == "owns-malformed"
                for e in deferrals[1]),
            deferrals,
        )

        # No wave may contain a task whose dep hasn't already landed.
        deps = corpus_deps()
        # corpus_deps reads only the inline `deps: [...]` shape, which is what
        # the corpus uses. ready-set.py also accepts a block sequence, so a
        # task respelled that way would drop out of this dict and its
        # constraint would go unchecked while everything still reported green.
        # Parsing has to be complete before the comparison means anything.
        check("replay: parsed deps for every replayed task",
              set(deps) == covered, f"parsed={sorted(deps)} replayed={sorted(covered)}")
        wave_of = {tid: i for i, wave in enumerate(waves) for tid in wave}
        violations = [
            (tid, dep) for tid, dep_ids in deps.items() for dep in dep_ids
            if tid in wave_of and dep in wave_of and wave_of[dep] >= wave_of[tid]
        ]
        check("replay: no task waves at or before one of its deps",
              violations == [], f"violations={violations}")

    check("replay: the archived corpus is left untouched",
          archive_digest() == before, "the replay wrote to the archive")

    # ------------------------------------- replay: the same graph, speculating
    # The leg above marks a wave's members straight to `complete` between
    # calls, which measures the OLD rule (a dep must be complete) and can
    # never exercise speculative dispatch (#135)—a dep is never sitting at
    # needs-check/checking when the next call happens, because it's already
    # complete. This leg models the real pipeline instead: a wave's members
    # land at `needs-check` (their workers returned) and stay there for one
    # full call before the orchestrator's next call marks them `complete`
    # (their checks passed). That needs-check window is exactly what
    # speculation is for.
    print("replaying the same graph with a needs-check window between dispatch and completion")

    with tempfile.TemporaryDirectory(prefix="ready-set-replay-spec-") as d:
        state = os.path.join(d, "state")
        os.makedirs(state)
        shutil.copytree(os.path.join(ARCHIVE_117, "tasks"), os.path.join(state, "tasks"))

        # Same rewind as the leg above: pending, retries cleared, owns cloned
        # onto a corpus that predates it.
        for name in sorted(os.listdir(os.path.join(state, "tasks"))):
            path = os.path.join(state, "tasks", name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            text = re.sub(r"^status:.*$", "status: pending", text, count=1, flags=re.M)
            text = re.sub(r"^retries:.*$", "retries: 0", text, count=1, flags=re.M)
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
        add_owns(state)

        deps = corpus_deps()
        waves = []
        speculative_entries = []  # (tid, speculative_on) for every wave entry that carried it
        dispatch_snapshots = []   # (tid, speculative deps, what was complete at dispatch)
        complete_set = set()      # what's actually `complete` on disk as of the CURRENT call
        # tid -> turns remaining before it reads `complete`. A worker's return
        # is not the end of the lifecycle: the contract's step 2 has the
        # orchestrator set `checking` and dispatch the checker, and only a
        # later turn accepts the verdict. So a task dispatched this turn is
        # `needs-check` now, `checking` next turn, `complete` the turn after.
        # That gap is the thing speculation spends, and a harness that
        # completes a wave the moment the next call runs doesn't have one.
        countdown = {}
        ticks = 0
        hit_cap = True

        for _ in range(12):
            ticks += 1
            for tid in sorted(countdown):
                countdown[tid] -= 1
                if countdown[tid] == 1:
                    set_status(state, tid, "checking")
                elif countdown[tid] == 0:
                    set_status(state, tid, "complete")
                    complete_set.add(tid)
            countdown = {t: n for t, n in countdown.items() if n > 0}

            rc, result, err = run_and_parse(state)
            if rc != 0 or result is None:
                check("spec-replay: every call parses", False, f"rc={rc} err={err}")
                break
            entries = result["wave"]
            if not entries:
                # An empty wave is not the end unless nothing is in flight
                # either. Under the old rule this is where the run would sit
                # and wait for a checker, which is the wall clock speculation
                # is trying to reclaim, so a waiting turn still costs a tick.
                if not countdown:
                    hit_cap = False
                    break
                continue

            # Depth cap, checked against ready-set's own claim rather than
            # trusted: a wave entry may speculate on a dep sitting at
            # needs-check/checking, but that dep's OWN deps must already be
            # complete—never themselves needs-check/checking. complete_set
            # here is the state exactly as ready-set.py saw it for this call,
            # captured before this iteration's advance step runs.
            for e in entries:
                for dep in e.get("speculative_on", []):
                    dep_own_deps = deps.get(dep, [])
                    check(
                        f"spec-replay: {dep}'s own deps were complete when "
                        f"{e['id']} speculated on it (depth cap holds)",
                        all(dd in complete_set for dd in dep_own_deps),
                        f"dep_own_deps={dep_own_deps} complete_set={sorted(complete_set)}",
                    )

            members = sorted(ids(entries))
            waves.append(members)
            speculative_entries.extend(
                (e["id"], e["speculative_on"]) for e in entries if e.get("speculative_on")
            )
            dispatch_snapshots.extend(
                (e["id"], e.get("speculative_on", []), frozenset(complete_set))
                for e in entries
            )

            for tid in members:
                set_status(state, tid, "needs-check")
                countdown[tid] = 2

        check("spec-replay: terminates before the 12-call cap", not hit_cap, f"waves={waves}")

        covered = {tid for wave in waves for tid in wave}
        serial = dispatched_tasks()
        check("spec-replay: covers exactly the tasks the run dispatched workers for",
              covered == serial, f"replayed={sorted(covered)} run={sorted(serial)}")

        # Wave COUNT is not what speculation improves, and asserting it
        # against the leg above would measure the wrong quantity. Both legs
        # cross one dependency layer per wave because the graph decides that,
        # not the rule: this replay and the non-speculative one produce the
        # same six waves, in the same order. What changes is the turns spent
        # waiting between them. Driving this same pipeline against a copy of
        # ready-set.py with clause 2 removed takes 12 turns for that identical
        # composition, against 8 here, because a dependent that waits for
        # `complete` waits two turns past its dep's worker returning instead
        # of one. Pin the count so a regression reinstating the wait shows up
        # as a number rather than as a wave shape nobody can tell apart.
        check(f"spec-replay: drains the graph in {ticks} turns",
              ticks == 8, f"ticks={ticks} waves={waves}")

        # The mechanism itself, asserted rather than inferred from a count:
        # at least one task went out while the dep it needed had not yet been
        # checked. That dispatch is precisely the one the old rule refused.
        check(
            "spec-replay: a task dispatched while its dep was still unchecked",
            any(dep not in complete_at_dispatch
                for _tid, dep_list, complete_at_dispatch in dispatch_snapshots
                for dep in dep_list),
            dispatch_snapshots,
        )

        check(
            "spec-replay: wave composition",
            waves == [
                ["T-001", "T-005"],
                ["T-002"],
                ["T-004"],
                ["T-006"],
                ["T-007"],
                ["T-003"],
            ],
            waves,
        )

# The weaker property speculation leaves intact. The strict-ordering
        # check on the leg above holds only because that leg's deps are never
        # satisfied except by `complete`, which is always further back than
        # the task itself. Here a dep can satisfy while still at
        # needs-check—but needs-check itself requires the dep to have been
        # dispatched on a STRICTLY earlier call (ready-set.py reads each
        # dep's status from the snapshot loaded before this call's wave was
        # computed, so a task can never observe its own dep as a peer in the
        # same call). So a task and its dep still can never land in the same
        # wave, and the dep's wave index is still always the smaller one—the
        # same comparison as the leg above, just no longer implying the dep
        # had fully passed its check by the time its dependent waved.
        wave_of = {tid: i for i, wave in enumerate(waves) for tid in wave}
        violations = [
            (tid, dep) for tid, dep_ids in deps.items() for dep in dep_ids
            if tid in wave_of and dep in wave_of and wave_of[dep] >= wave_of[tid]
        ]
        check("spec-replay: no task waves in the same wave as, or before, one of its deps",
              violations == [], f"violations={violations}")

        check(
            "spec-replay: at least one wave entry carries speculative_on",
            len(speculative_entries) > 0,
            speculative_entries,
        )
        check(
            "spec-replay: speculative_on names the exact task/dep pairs this graph produces",
            sorted(speculative_entries) == [
                ("T-002", ["T-001"]),
                ("T-003", ["T-007"]),
                ("T-006", ["T-004"]),
                ("T-007", ["T-006"]),
            ],
            speculative_entries,
        )

    check("spec-replay: the archived corpus is left untouched",
          archive_digest() == before, "the replay wrote to the archive")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
