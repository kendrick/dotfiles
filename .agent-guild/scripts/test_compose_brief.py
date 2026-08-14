#!/usr/bin/env python3
"""Fixture-based tests for compose-brief.py. No repo state touched: every
fixture is built fresh in a temp dir and the script is run as a subprocess
with that dir as cwd, exercising the real `.agent-guild/state/`-relative
path resolution rather than calling internals directly.

Run: python3 .agent-guild/scripts/test_compose_brief.py
"""
import os
import subprocess
import sys
import tempfile

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "compose-brief.py")

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


def fresh_state():
    """A temp dir with .agent-guild/state/{tasks,briefs} plus the fixture
    constitution. Returns the dir path."""
    d = tempfile.mkdtemp(prefix="compose-brief-test-")
    os.makedirs(os.path.join(d, ".agent-guild", "state", "tasks"))
    with open(os.path.join(d, ".agent-guild", "state", "constitution.md"), "w") as f:
        f.write(CONSTITUTION)
    return d


def write_task(state_dir, task_id, content):
    path = os.path.join(state_dir, ".agent-guild", "state", "tasks", f"{task_id}.md")
    with open(path, "w") as f:
        f.write(content)


def run(state_dir, *argv):
    proc = subprocess.run(
        [sys.executable, SCRIPT, *argv],
        cwd=state_dir,
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


CONSTITUTION = """# Constitution: Fixture

## Clauses

### C-1: First clause
- **text**: text of first clause.
- **check**: checker-judgment: some check.
- **severity**: blocker
- **failing example**: an example.

### C-2: Second clause
- **text**: text of second clause.
- **check**: checker-judgment: some check two.
- **severity**: major
- **failing example**: another example.

### C-3: Third clause
- **text**: text of third clause.
- **check**: .agent-guild/scripts/check-foo.sh --mode checker-judgment:x
- **severity**: minor
- **failing example**: a third example.

## Protected content

- none

## Non-goals

- none
"""

TASK_NO_DIAG = """---
id: T-100
title: Sample task without diagnosis
spec: .agent-guild/state/spec.md#section
clauses: [C-1, C-2]
executor: worker-standard
executor_model: sonnet
checker: checker-deterministic
check_method: >-
  Test check method.
status: assigned
retries: 0
max_retries: 2
deps: []
escalations: []
artifacts: []
---

## Spec excerpt

Do the thing. Build file X per the spec.

## Rework diagnosis

<!-- ORCHESTRATOR appends here on each FAIL, copied verbatim from the checker's
verdict Diagnosis. Newest at the bottom, headed with the attempt it addresses
(e.g. "### sonnet r1"). Empty until the first failure. -->
"""

EXPECTED_NO_DIAG = """# Brief: T-100

**Task:** T-100 — Sample task without diagnosis

## Constitution clauses

### C-1: First clause
- **text**: text of first clause.
- **check**: checker-judgment: some check.
- **severity**: blocker
- **failing example**: an example.

### C-2: Second clause
- **text**: text of second clause.
- **check**: checker-judgment: some check two.
- **severity**: major
- **failing example**: another example.

## Spec excerpt

Do the thing. Build file X per the spec.
"""

TASK_WITH_DIAG = """---
id: T-101
title: Sample task with diagnosis
spec: .agent-guild/state/spec.md#section
clauses: [C-1, C-2]
executor: worker-standard
executor_model: sonnet
checker: checker-deterministic
check_method: >-
  Test check method.
status: assigned
retries: 1
max_retries: 2
deps: []
escalations: []
artifacts: []
---

## Spec excerpt

Do the thing. Build file X per the spec.

## Rework diagnosis

### sonnet r1

- file: foo.py:12
  clause: C-1
  issue: missing error handling.
"""

EXPECTED_WITH_DIAG = """# Brief: T-101

**Task:** T-101 — Sample task with diagnosis

## Constitution clauses

### C-1: First clause
- **text**: text of first clause.
- **check**: checker-judgment: some check.
- **severity**: blocker
- **failing example**: an example.

### C-2: Second clause
- **text**: text of second clause.
- **check**: checker-judgment: some check two.
- **severity**: major
- **failing example**: another example.

## Spec excerpt

Do the thing. Build file X per the spec.

## Prior attempt diagnosis

### sonnet r1

- file: foo.py:12
  clause: C-1
  issue: missing error handling.
"""

TASK_BAD_CLAUSE = """---
id: T-102
title: Bad clause id
spec: .agent-guild/state/spec.md#section
clauses: [C-9]
executor: worker-standard
executor_model: sonnet
checker: checker-deterministic
check_method: >-
  Test check method.
status: assigned
retries: 0
max_retries: 2
deps: []
escalations: []
artifacts: []
---

## Spec excerpt

Do the thing.

## Rework diagnosis

<!-- placeholder -->
"""

TASK_ZERO_CLAUSES = """---
id: T-103
title: Zero clauses
spec: .agent-guild/state/spec.md#section
clauses: []
executor: worker-standard
executor_model: sonnet
checker: checker-deterministic
check_method: >-
  Test check method.
status: assigned
retries: 0
max_retries: 2
deps: []
escalations: []
artifacts: []
---

## Spec excerpt

Do the thing.

## Rework diagnosis

<!-- placeholder -->
"""

# One script-checked clause (C-3) and one judgment clause (C-2): the
# partition's mixed case. C-3's check reads
# `.agent-guild/scripts/check-foo.sh --mode checker-judgment:x` on purpose —
# it contains the word `checker-judgment` without starting with it, so this
# fixture doubles as the anchored-prefix negative case.
TASK_MIXED = """---
id: T-104
title: One script clause, one judgment clause
spec: .agent-guild/state/spec.md#section
clauses: [C-2, C-3]
executor: worker-standard
executor_model: sonnet
checker: checker-deterministic
check_method: >-
  Test check method.
status: assigned
retries: 0
max_retries: 2
deps: []
escalations: []
artifacts: []
---

## Spec excerpt

Do the thing.

## Rework diagnosis

<!-- placeholder -->
"""

# Every cited clause (C-3 alone) is script-checked: the all-script case.
TASK_ALL_SCRIPT = """---
id: T-105
title: Every cited clause is script-checked
spec: .agent-guild/state/spec.md#section
clauses: [C-3]
executor: worker-standard
executor_model: sonnet
checker: checker-deterministic
check_method: >-
  Test check method.
status: assigned
retries: 0
max_retries: 2
deps: []
escalations: []
artifacts: []
---

## Spec excerpt

Do the thing.

## Rework diagnosis

<!-- placeholder -->
"""


# The identity block is the whole point of #113: the far side is validated on
# `checker` and `model` and used to be told neither, so it guessed and two
# sound judgments were discarded. Pinned as a golden file because the values
# have to arrive verbatim — a reworded contract is a contract that stopped
# working, and nothing downstream would say so.
EXPECTED_WITH_CONTRACT = EXPECTED_NO_DIAG.rstrip("\n") + """

## Verdict contract

Return the canonical verdict object. Echo these four fields exactly as given:

  task_id  T-100
  checker  checker-courier
  vendor   openai
  model    gpt-5.6-terra

Set duration_ms and cost_usd to null; call metrics are recorded on this side. A fail carries at least one finding with concrete evidence.

severity is the impact of a defect: blocker, major, minor, or info. Use info for a finding that records a clause being satisfied. A clause's own severity in the text above is the cost of violating it, not the label for every finding about it. A pass carries only info and minor findings.
"""


def read_brief(state_dir, task_id):
    path = os.path.join(state_dir, ".agent-guild", "state", "briefs", f"{task_id}.md")
    with open(path, encoding="utf-8") as f:
        return f.read()


# --------------------------------------------------------------- golden files
print("golden files")

d = fresh_state()
write_task(d, "T-100", TASK_NO_DIAG)
rc, out, err = run(d, "T-100")
check("no-diagnosis: exit 0", rc == 0, f"rc={rc} err={err}")
check(
    "no-diagnosis: default output path used",
    os.path.exists(os.path.join(d, ".agent-guild", "state", "briefs", "T-100.md")),
)
check("no-diagnosis: stdout is a one-line confirmation, not the brief body", out.count("\n") == 1 and "Brief:" not in out, f"out={out!r}")
brief = read_brief(d, "T-100")
check("no-diagnosis: brief matches golden file exactly", brief == EXPECTED_NO_DIAG, f"got:\n{brief!r}")
check("no-diagnosis: no 'Prior attempt diagnosis' heading", "## Prior attempt diagnosis" not in brief)

d = fresh_state()
write_task(d, "T-101", TASK_WITH_DIAG)
rc, out, err = run(d, "T-101")
check("with-diagnosis: exit 0", rc == 0, f"rc={rc} err={err}")
brief = read_brief(d, "T-101")
check("with-diagnosis: brief matches golden file exactly", brief == EXPECTED_WITH_DIAG, f"got:\n{brief!r}")
check("with-diagnosis: 'Prior attempt diagnosis' heading present", "## Prior attempt diagnosis" in brief)
check("with-diagnosis: original 'Rework diagnosis' heading not carried over", "## Rework diagnosis" not in brief)

# --out redirection, checked once here rather than duplicated per fixture.
d = fresh_state()
write_task(d, "T-100", TASK_NO_DIAG)
custom_out = os.path.join(d, "elsewhere", "custom.md")
rc, out, err = run(d, "T-100", "--out", custom_out)
check("--out: exit 0, writes to PATH, creating dirs on demand", rc == 0 and os.path.exists(custom_out), f"rc={rc} err={err}")
check("--out: default briefs/ path is untouched", not os.path.exists(os.path.join(d, ".agent-guild", "state", "briefs", "T-100.md")))
with open(custom_out, encoding="utf-8") as f:
    check("--out: content matches golden file exactly", f.read() == EXPECTED_NO_DIAG)

# ------------------------------------------------------- verdict contract (#113)
print("verdict contract")

d = fresh_state()
write_task(d, "T-100", TASK_NO_DIAG)
rc, out, err = run(d, "T-100", "--vendor", "openai", "--model", "gpt-5.6-terra")
check("identity flags: exit 0", rc == 0, f"rc={rc} err={err}")
brief = read_brief(d, "T-100")
check("identity flags: brief matches golden file exactly",
      brief == EXPECTED_WITH_CONTRACT, f"got:\n{brief!r}")
check("identity flags: contract comes last, after the evidence",
      brief.index("## Verdict contract") > brief.index("## Spec excerpt"))

# Without the flags the brief is byte-identical to what every earlier crossing
# received, so the golden files above stay a real regression guard rather than
# a record of the new shape.
d = fresh_state()
write_task(d, "T-100", TASK_NO_DIAG)
rc, out, err = run(d, "T-100")
check("no flags: brief unchanged from before the contract existed",
      read_brief(d, "T-100") == EXPECTED_NO_DIAG)

for flag, value, missing in (("--vendor", "openai", "--model"),
                             ("--model", "gpt-5.6-terra", "--vendor")):
    d = fresh_state()
    write_task(d, "T-100", TASK_NO_DIAG)
    rc, out, err = run(d, "T-100", flag, value)
    check(f"{flag} alone: nonzero exit", rc != 0, f"rc={rc}")
    check(f"{flag} alone: message names the missing flag, no traceback",
          missing in err and "Traceback" not in err, f"err={err!r}")
    check(f"{flag} alone: nothing written to briefs/",
          not os.path.exists(os.path.join(d, ".agent-guild", "state", "briefs")))

# ------------------------------------------------------------- failure modes
print("failure modes")

d = fresh_state()
rc, out, err = run(d, "T-999")
check("missing task file: nonzero exit", rc != 0, f"rc={rc}")
check("missing task file: one-line message naming the task, no traceback", "T-999" in err and "Traceback" not in err, f"err={err!r}")
check("missing task file: nothing written to briefs/", not os.path.exists(os.path.join(d, ".agent-guild", "state", "briefs")))

d = fresh_state()
write_task(d, "T-102", TASK_BAD_CLAUSE)
rc, out, err = run(d, "T-102")
check("unresolvable clause id: nonzero exit", rc != 0, f"rc={rc}")
check("unresolvable clause id: message names the clause id, no traceback", "C-9" in err and "Traceback" not in err, f"err={err!r}")

d = fresh_state()
write_task(d, "T-103", TASK_ZERO_CLAUSES)
rc, out, err = run(d, "T-103")
check("zero cited clauses: nonzero exit", rc != 0, f"rc={rc}")
check("zero cited clauses: message names the task, no traceback", "T-103" in err and "Traceback" not in err, f"err={err!r}")

# ------------------------------------------------------- partition (#128)
print("partition: script-checked clauses don't cross")

# all-judgment: both cited clauses (C-1, C-2) are judgment-checked, so the
# partition is a no-op and the brief stays byte-identical to what the
# composer produced before the partition existed — EXPECTED_NO_DIAG already
# embeds both clauses verbatim. Named explicitly here so the shape reads as
# a deliberate case rather than a side effect of the golden-file tests above.
d = fresh_state()
write_task(d, "T-100", TASK_NO_DIAG)
rc, out, err = run(d, "T-100")
check("all-judgment: exit 0", rc == 0, f"rc={rc} err={err}")
brief = read_brief(d, "T-100")
check("all-judgment: brief byte-identical to the pre-partition composer's output",
      brief == EXPECTED_NO_DIAG, f"got:\n{brief!r}")

# mixed: C-2 is judgment-checked, C-3 is script-checked. C-3's check value
# also contains the literal substring "checker-judgment" without starting
# with it — the anchored-prefix negative case — so this fixture doubles as
# proof the filter anchors at the start rather than searching anywhere in
# the value.
d = fresh_state()
write_task(d, "T-104", TASK_MIXED)
rc, out, err = run(d, "T-104")
check("mixed: exit 0", rc == 0, f"rc={rc} err={err}")
brief = read_brief(d, "T-104")
check("mixed: script clause's heading is absent", "### C-3:" not in brief, f"got:\n{brief!r}")
check("mixed: script clause's check line is absent",
      ".agent-guild/scripts/check-foo.sh --mode checker-judgment:x" not in brief, f"got:\n{brief!r}")
check("mixed: judgment clause survives verbatim",
      "### C-2: Second clause\n"
      "- **text**: text of second clause.\n"
      "- **check**: checker-judgment: some check two.\n"
      "- **severity**: major\n"
      "- **failing example**: another example." in brief,
      f"got:\n{brief!r}")

# all-script: the one cited clause (C-3) is script-checked. Exit 3, the
# exact stderr line, and no brief written — a different problem from the
# existing zero-clauses-cited error above, so it gets a different code.
d = fresh_state()
write_task(d, "T-105", TASK_ALL_SCRIPT)
rc, out, err = run(d, "T-105")
check("all-script: exit 3", rc == 3, f"rc={rc} err={err}")
check("all-script: exact stderr line",
      err == "compose-brief: nothing to cross: T-105 cites only script-checked clauses\n",
      f"err={err!r}")
check("all-script: no brief file written",
      not os.path.exists(os.path.join(d, ".agent-guild", "state", "briefs", "T-105.md")))
check("all-script: briefs/ directory never created",
      not os.path.exists(os.path.join(d, ".agent-guild", "state", "briefs")))

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
