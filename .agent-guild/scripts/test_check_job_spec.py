#!/usr/bin/env python3
"""Regression suite for check-job-spec.py (#132). Two kinds of case:

1. The real #117 corpus (`.agent-guild/state/archive/2026-08-10-issue-117/`)
   must still pass, run against a pinned fixture repo-root rather than this
   live repo. The corpus cites `conventions.md:65`, and that line still
   resolves in the live repo today, but it no longer names the bullet it
   did when #117 shipped: #117's own commit grew the file out from under
   its own citation. A test pinned to live files rots the moment someone
   edits them, so the fixture repo-root fixes the cited files' line
   numbers by construction instead.
2. Each of #117's own audit findings, reproduced as a one-line mutation of
   that same corpus, must fire the rule that would have caught it.

Every script runs as a subprocess, so these tests exercise the real CLI
contract (exit codes, stderr) rather than internals.

Run: python3 .agent-guild/scripts/test_check_job_spec.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(SCRIPTS_DIR, "check-job-spec.py")

sys.path.insert(0, SCRIPTS_DIR)
from _corpus import ARCHIVE_117 as ARCHIVE_DIR, add_owns  # noqa: E402

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


def run_linter(*argv):
    proc = subprocess.run(
        [sys.executable, SCRIPT, *argv], capture_output=True, text=True
    )
    return proc.returncode, proc.stdout, proc.stderr


def rule_hit(err, rule):
    """A rule id appears as its own token, e.g. don't let a search for R1
    match inside R10 or R12."""
    return re.search(rf"(?<!\d){re.escape(rule)}(?!\d)", err) is not None


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def write_exec(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(path, 0o755)


def mutate(path, old, new, label):
    """Apply a one-line string replacement and prove it actually landed—a
    mutation that silently no-ops (because the corpus text moved under it)
    would make the case that follows pass for no reason."""
    with open(path, encoding="utf-8") as f:
        content = f.read()
    count = content.count(old)
    check(f"{label}: mutation string found exactly once", count == 1, f"count={count} old={old!r}")
    if count != 1:
        return False
    with open(path, "w", encoding="utf-8") as f:
        f.write(content.replace(old, new, 1))
    return True


def copy_corpus_state(state_dir):
    """The linter's own inputs are just constitution.md + tasks/; the rest
    of the archive (verdicts, notes, log, briefs) is run history it never
    reads."""
    os.makedirs(state_dir)
    shutil.copy(
        os.path.join(ARCHIVE_DIR, "constitution.md"),
        os.path.join(state_dir, "constitution.md"),
    )
    shutil.copytree(
        os.path.join(ARCHIVE_DIR, "tasks"), os.path.join(state_dir, "tasks")
    )


# add_owns lives in _corpus.py because test_ready_set.py replays this same
# corpus and needs the identical derivation. Two copies would drift, and a
# fixture that derives `owns` differently from the one the linter was proved
# against is a fixture agreeing with itself about the wrong thing.


DEPS_LINE_RE = re.compile(r"^deps:\s*(\[.*\])\s*$")


def add_dep_rationale(state_dir):
    """Give every task in `state_dir/tasks/` a `dep_rationale:` entry for
    each id in its own `deps:`—the #117 corpus predates #125, so
    `dep_rationale` doesn't exist in it yet. Every corpus `deps:` is the
    flat `[T-001, ...]` shape (unlike `artifacts:`, which mixes flat and
    block), so this only needs to parse that one form. A task whose `deps`
    is empty still gets an explicit `dep_rationale: []`, mirroring how
    add_owns() always inserts a field rather than leaving it absent.
    Mutates the task files on disk."""
    tasks_dir = os.path.join(state_dir, "tasks")
    for name in sorted(os.listdir(tasks_dir)):
        path = os.path.join(tasks_dir, name)
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        out = []
        inserted = False
        for line in lines:
            out.append(line)
            if not inserted:
                m = DEPS_LINE_RE.match(line)
                if m:
                    dep_ids = [d.strip() for d in m.group(1)[1:-1].split(",") if d.strip()]
                    if dep_ids:
                        out.append("dep_rationale:")
                        out.extend(f"  - {dep_id}: fixture rationale for R14 tests" for dep_id in dep_ids)
                    else:
                        out.append("dep_rationale: []")
                    inserted = True
        assert inserted, f"{name}: no deps: field found to derive dep_rationale from"
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")


# The matching-pair quote-strip line the corpus cites twice (T-001.md:57,
# against compose-brief.py:64 and check-provenance.py:74). Built by
# concatenation rather than an escaped literal so the quoting is legible;
# verified byte-for-byte against the real compose-brief.py:64 while writing
# this suite.
MATCH_LINE = (
    "        if len(val) >= 2 and val[0] == val[-1] and val[0] in "
    + '"' + "\\" + '"' + "'" + '"' + ":"
)


def build_fixture_repo_root(root):
    """A pinned stand-in for the repo root, holding only what the corpus
    actually needs. compose-brief.py and check-provenance.py carry the
    cited snippet on the exact line the corpus cites (:64 and :74)
    regardless of what the live copies say today; conventions.md is pinned
    the same way for its :65 citations. check-build.sh and
    check-diff-scope.py are executable stubs, since R5 never runs them—it
    only checks X_OK and, for check-build.sh, that the quoted inner command
    parses—so their bodies don't need to do anything.

    Returns the line number of the fixture's "## Prose Voice" heading, which
    M2 redirects a citation onto.
    """
    scripts_dir = os.path.join(root, ".agent-guild", "scripts")
    os.makedirs(scripts_dir)
    wm_dir = os.path.join(root, "_working-memory")
    os.makedirs(wm_dir)

    write_exec(os.path.join(scripts_dir, "check-build.sh"), "#!/usr/bin/env bash\nexit 0\n")
    write_exec(
        os.path.join(scripts_dir, "check-diff-scope.py"),
        "#!/usr/bin/env python3\nimport sys\nsys.exit(0)\n",
    )

    # compose-brief.py: line 64 pinned to the cited snippet. Filler lines
    # avoid a leading '#'—R3's heading check is scoped to .md targets, but
    # there's no reason to hand a stray edge case a chance to misfire here.
    cb_lines = [f"x_{i} = None  # filler" for i in range(1, 64)]
    cb_lines.append(MATCH_LINE)  # line 64
    cb_lines += [f"x_{i} = None  # filler" for i in range(65, 70)]
    write_lines(os.path.join(scripts_dir, "compose-brief.py"), cb_lines)

    # check-provenance.py: same snippet, pinned at line 74.
    cp_lines = [f"x_{i} = None  # filler" for i in range(1, 74)]
    cp_lines.append(MATCH_LINE)  # line 74
    cp_lines += [f"x_{i} = None  # filler" for i in range(75, 80)]
    write_lines(os.path.join(scripts_dir, "check-provenance.py"), cp_lines)

    # conventions.md: the Prose Voice bullet pinned at line 65 (what every
    # unmutated "conventions.md:65" citation in the corpus resolves to), with
    # a real heading earlier in the file for M2 to redirect onto.
    conv_lines = [f"<!-- filler {i} -->" for i in range(1, 60)]
    prose_heading_line = 60
    conv_lines.append("## Prose Voice (docs and comments)")  # line 60
    conv_lines += [f"<!-- filler {i} -->" for i in range(61, 65)]
    conv_lines.append(
        "- Em dashes chain directly to the text on both sides—like this—never "
        "wrapped in spaces. Don't hard-wrap prose lines; let the display wrap. "
        "Headings are Title Case. Comments explain the why, not the what."
    )  # line 65
    conv_lines += [f"<!-- filler {i} -->" for i in range(66, 70)]
    write_lines(os.path.join(wm_dir, "conventions.md"), conv_lines)

    return prose_heading_line


MINIMAL_CONSTITUTION = """# Constitution: CLI fixture

## Clauses

### C-1: trivial clause
- **text**: The output file exists and is non-empty.
- **check**: checker-judgment: confirm the output file exists and has content.
- **severity**: minor
- **failing example**: the output file is empty or missing.

## Protected content

- none.

## Non-goals

- none.
"""


def write_synthetic_state(d, tasks):
    """A minimal state dir: MINIMAL_CONSTITUTION plus one task file per
    entry in `tasks`, each `{"id", "artifacts", "deps"}`. For the build
    rules (R8, R16), where what matters is which paths a task claims and
    who depends on whom, and the corpus is the wrong instrument because
    its own build graph is the thing under test elsewhere. No `owns`, so
    R13/R14/R15 have nothing to say about these fixtures."""
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "tasks"))
    write_lines(os.path.join(state, "constitution.md"), MINIMAL_CONSTITUTION.splitlines())
    for t in tasks:
        artifacts_block = "\n".join(f"  - {a}" for a in t["artifacts"])
        write_lines(
            os.path.join(state, "tasks", f"{t['id']}.md"),
            f"""---
id: {t['id']}
title: Synthetic {t['id']}
spec: .agent-guild/state/spec.md#one
clauses: [C-1]
executor: worker-standard
executor_model: sonnet
checker: checker-judgment
check_method: >-
  C-1: checker-judgment: confirm the output file exists and has content.
status: pending
retries: 0
max_retries: 2
deps: [{', '.join(t.get('deps', []))}]
escalations: []
artifacts:
{artifacts_block}
---

## Spec excerpt

Writes {', '.join(t['artifacts'])}.
""".splitlines(),
        )
    return state


def raw_shell_constitution(check_line):
    return f"""# Constitution: R4 fixture

## Clauses

### C-1: build succeeds
- **text**: The build passes.
- **check**: {check_line}
- **severity**: minor
- **failing example**: the build never runs.

## Protected content

- none.

## Non-goals

- none.
"""


# --------------------------------------------------------------- CLI basics
print("CLI basics")

rc, out, err = run_linter("--self-test")
check("--self-test: exit 0", rc == 0, f"rc={rc} err={err}")

with tempfile.TemporaryDirectory() as d:
    missing_state = os.path.join(d, "does-not-exist")
    rc, out, err = run_linter(missing_state, "--repo-root", d, "--audit-id", "CON-audit")
    check("missing state dir: exit 3, not 1", rc == 3, f"rc={rc} err={err}")

with tempfile.TemporaryDirectory() as d:
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "tasks"))
    write_lines(os.path.join(state, "constitution.md"), MINIMAL_CONSTITUTION.splitlines())
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
    check("empty tasks/, DEC-audit: exit 1", rc == 1, f"rc={rc} err={err}")

    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "CON-audit")
    check("same empty tasks/, CON-audit: exit 0, not 1", rc == 0, f"rc={rc} err={err}")

# ------------------------------------------------------- R4: #121's criterion
print("R4: inline shell in a check field (#121)")

with tempfile.TemporaryDirectory() as d:
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "tasks"))
    write_lines(
        os.path.join(state, "constitution.md"),
        raw_shell_constitution("bash -c 'pytest && echo ok'").splitlines(),
    )
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "CON-audit")
    check("bash -c wrapping a shell block: exit 1", rc == 1, f"rc={rc} err={err}")
    check("bash -c wrapping a shell block: R4 named", rule_hit(err, "R4"), f"err={err!r}")
    check("bash -c wrapping a shell block: no traceback", "Traceback" not in err, f"err={err!r}")

with tempfile.TemporaryDirectory() as d:
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "tasks"))
    write_lines(
        os.path.join(state, "constitution.md"),
        raw_shell_constitution("pytest && echo ok").splitlines(),
    )
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "CON-audit")
    check("raw pipeline, no .agent-guild/scripts/ prefix: exit 1", rc == 1, f"rc={rc} err={err}")
    check("raw pipeline: R4 named", rule_hit(err, "R4"), f"err={err!r}")

# The other side of #121's line: a shell one-liner handed to the sanctioned
# runner is NOT the defect. Every check-build.sh invocation in the corpus
# (constitution C-1/C-3, T-002, T-003's two check-build.sh segments) is
# exactly that shape, so the base corpus pass below—run unmutated—is the
# proof this side stays green. T-003.md:13 in particular wraps a bespoke
# one-liner this way and DEC-r4 passed it.


def preamble_task(preamble_line):
    return f"""---
id: T-001
title: Preamble fixture
spec: .agent-guild/state/spec.md#one
clauses: [C-1]
executor: worker-standard
executor_model: sonnet
checker: checker-judgment
check_method: >-
  {preamble_line}
  C-1: checker-judgment: confirm the output file exists and has content.
status: pending
retries: 0
max_retries: 2
deps: []
escalations: []
artifacts:
  - out.txt
---

## Spec excerpt

Fixture body.
"""


# A #132 adversarial finding: R4's preamble scan used to fire on ANY
# mention of a script path ahead of a C-N: segment, not just one shaped
# like an invocation—blocking a check_method that merely names a suite for
# context (T-003's real preamble does exactly this: "The suite lives in
# .agent-guild/scripts/test_ledger_append.py. Run these three commands...").
print("R4: bare script mention in the preamble is not the #121 evasion")

with tempfile.TemporaryDirectory() as d:
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "tasks"))
    write_lines(os.path.join(state, "constitution.md"), MINIMAL_CONSTITUTION.splitlines())
    write_lines(
        os.path.join(state, "tasks", "T-001.md"),
        preamble_task(
            "The suite lives in .agent-guild/scripts/test_thing.py. Run these commands in order."
        ).splitlines(),
    )
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
    check("bare mention, not invocation-shaped: exit 0", rc == 0, f"rc={rc} err={err}")

# The evasion itself has to stay caught: a preamble that OPENS with the
# script path reads as a command line, not prose naming it for context.
with tempfile.TemporaryDirectory() as d:
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "tasks"))
    write_lines(os.path.join(state, "constitution.md"), MINIMAL_CONSTITUTION.splitlines())
    write_lines(
        os.path.join(state, "tasks", "T-001.md"),
        preamble_task(
            ".agent-guild/scripts/sneaky.sh --all handles everything, so nothing below matters."
        ).splitlines(),
    )
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
    check("invocation-shaped preamble: exit 1", rc == 1, f"rc={rc} err={err}")
    check("invocation-shaped preamble: R4 named", rule_hit(err, "R4"), f"err={err!r}")

# --------------------------------------------- corpus: baseline + mutations
if not os.path.isdir(ARCHIVE_DIR):
    print(f"note: corpus archive not found at {ARCHIVE_DIR} — skipping corpus-based "
          f"cases. This suite ships into user projects; the archive under state/ does "
          f"not, so the skip is expected there.")
else:
    with tempfile.TemporaryDirectory() as fixture_root:
        prose_heading_line = build_fixture_repo_root(fixture_root)

        # ------------------------------------------------------- corpus: baseline
        print("corpus: the shipped #117 state (DEC-audit-r4 PASS)")

        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
            # This single exit-0 also carries two things called out in the plan
            # that don't get their own case: R9 doesn't fire on any of T-007's
            # four load-bearing sentences (including "an absent fact is a FAIL,
            # never a pass carrying a finding"—the very fix M4 below reverts),
            # and every check-build.sh-wrapped shell block in the corpus passes
            # R4 (the other side of the #121 test above).
            check("unmutated corpus: exit 0", rc == 0, f"rc={rc} err={err}")

        # ---------------------------------------------------------- M1 (R2)
        # DEC-r0's D5: a citation stale by six lines (compose-brief.py:64 was
        # :58 by the time the auditor checked it).
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-001.md"),
                ".agent-guild/scripts/compose-brief.py:64",
                ".agent-guild/scripts/compose-brief.py:58",
                "M1",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("M1 stale code citation: exit 1", rc == 1, f"rc={rc} err={err}")
                check("M1: R2 named", rule_hit(err, "R2"), f"err={err!r}")
                check("M1: no traceback", "Traceback" not in err, f"err={err!r}")

        # ---------------------------------------------------------- M2 (R3)
        # DEC-r2's D12: a citation landing on a heading rather than the prose
        # it meant to anchor.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-007.md"),
                "`_working-memory/conventions.md:65`",
                f"`_working-memory/conventions.md:{prose_heading_line}`",
                "M2",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("M2 citation lands on a heading: exit 1", rc == 1, f"rc={rc} err={err}")
                check("M2: R3 named", rule_hit(err, "R3"), f"err={err!r}")
                check("M2: no traceback", "Traceback" not in err, f"err={err!r}")

        # --------------------------------------------------------- M3 (R10)
        # W3, by class rather than by instance: this fixture is invented,
        # but it exercises the same defect shape W3 was—a count word
        # disagreeing with what follows it. W3 itself (C-9 naming a file by
        # role rather than by path) isn't something R10 can parse directly;
        # the template's "list what you name" note is the other half of
        # that fix.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-006.md"),
                "record three findings",
                "record four findings",
                "M3",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("M3 count disagrees with its list: exit 1", rc == 1, f"rc={rc} err={err}")
                check("M3: R10 named", rule_hit(err, "R10"), f"err={err!r}")
                check("M3: no traceback", "Traceback" not in err, f"err={err!r}")

        # ---------------------------------------------------------- M4 (R9)
        # DEC-r3's D13: T-007's check_method restoring the pass-and-report
        # instruction is the actual defect this job exists to fix. This is
        # the pair test for R9's veto set—the unmutated corpus already
        # proved the four load-bearing sentences don't fire (see baseline
        # above); this proves the real defect still does.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-007.md"),
                "On C-6 or C-9, an absent fact is a FAIL, never a pass carrying a finding. For C-9",
                "On C-6 or C-9, an absent fact is the upstream task's defect: pass this task on "
                "that clause and file the gap as a major finding. For C-9",
                "M4",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("M4 pass-while-major instruction: exit 1", rc == 1, f"rc={rc} err={err}")
                check("M4: R9 named", rule_hit(err, "R9"), f"err={err!r}")
                check("M4: no traceback", "Traceback" not in err, f"err={err!r}")

        # ---------------------------------------------------------- M5 (R8)
        # DEC-r0's D1: a terminal task that isn't actually terminal. Drops
        # T-007, not T-005—T-005 stays in T-003's transitive closure via
        # T-007, so dropping it wouldn't fire this rule at all.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-003.md"),
                "deps: [T-001, T-002, T-004, T-005, T-006, T-007]",
                "deps: [T-001, T-002, T-004, T-005, T-006]",
                "M5",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("M5 terminal task not terminal: exit 1", rc == 1, f"rc={rc} err={err}")
                check("M5: R8 named", rule_hit(err, "R8"), f"err={err!r}")
                check("M5: no traceback", "Traceback" not in err, f"err={err!r}")

        # -------------------------------------------------------- M6 (R12')
        # DEC-r1's D9: the "eleven" that survived the sweep—a count that
        # disagrees with the same fact stated in a different task's prose.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-004.md"),
                "Ten rows record",
                "Eleven rows record",
                "M6",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("M6 count disagrees across artifacts: exit 1", rc == 1, f"rc={rc} err={err}")
                check("M6: R12 named", rule_hit(err, "R12"), f"err={err!r}")
                check("M6: no traceback", "Traceback" not in err, f"err={err!r}")

        # ------------------------------------------- P1 (R2, #132 adversarial)
        # An unrelated code aside sitting earlier in the SAME region used to
        # become the anchor for every citation in it, regardless of which
        # sentence either one was in—so a totally unrelated snippet could
        # veto a citation it has nothing to do with. T-001's real citation
        # (compose-brief.py:64, quoting the quote-stripping line) must stay
        # correct after the aside is inserted ahead of it.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-001.md"),
                "You need only `ref`.",
                "A totally unrelated aside: `for line in sorted(paths, key=len): pass` is how "
                "we iterate. You need only `ref`.",
                "P1",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("P1 unrelated code span leaves the real citation alone: exit 0", rc == 0, f"rc={rc} err={err}")

        # ------------------------------------------- P2 (R9, #132 adversarial)
        # The veto list used to fire on "not"/"no"/etc. ANYWHERE in the
        # sentence, so a genuine violation phrased with the negation next to
        # something OTHER than "pass" read as vetoed. This is arguably the
        # most natural way to write the defect R9 exists to catch.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-007.md"),
                "On C-6 or C-9, an absent fact is a FAIL, never a pass carrying a finding.",
                "If a named fact is not present, pass this task and file the gap as a major finding.",
                "P2",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("P2 negation not governing pass no longer vetoes: exit 1", rc == 1, f"rc={rc} err={err}")
                check("P2: R9 named", rule_hit(err, "R9"), f"err={err!r}")
                check("P2: no traceback", "Traceback" not in err, f"err={err!r}")

        # ------------------------------------------ P3 (R10, #132 adversarial)
        # A number before a colon that isn't a count of the following list—
        # an issue id, here—used to be compared against the list length
        # anyway, deadlocking a job on a coincidence. T-006's real, correct
        # "three findings" must stay silent with an issue number added.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-006.md"),
                "record three findings",
                "record three findings, filed against issue 27,",
                "P3",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("P3 issue number beside a correct count: exit 0", rc == 0, f"rc={rc} err={err}")

        # ------------------------------------------ P4 (R10, #132 adversarial)
        # Only the LAST number on the line used to be checked, so a wrong
        # count word earlier on the line hid behind an unrelated number that
        # happened to agree with the list by coincidence.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-006.md"),
                "record three findings",
                "record four findings, cross-checked against 3 sources",
                "P4",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("P4 wrong early count no longer hidden by a coincidental match: exit 1", rc == 1, f"rc={rc} err={err}")
                check("P4: R10 named", rule_hit(err, "R10"), f"err={err!r}")
                check("P4: no traceback", "Traceback" not in err, f"err={err!r}")

        # -------------------------------------------------- R15: owns shape (#162)
        # A one-task fixture rather than the corpus, because what's under
        # test is a single entry's spelling and the corpus has no bad ones.
        # Each case names the whole entry back to the reader, since "your
        # owns is malformed" without the offending string is a scavenger
        # hunt through a decomposition.
        print("R15: owns shape (#162)")

        def write_owns_fixture(state, owns_entries):
            os.makedirs(os.path.join(state, "tasks"))
            write_lines(
                os.path.join(state, "constitution.md"), MINIMAL_CONSTITUTION.splitlines()
            )
            owns_block = "\n".join(f"  - {e}" for e in owns_entries)
            write_lines(
                os.path.join(state, "tasks", "T-001.md"),
                f"""---
id: T-001
title: Sole task
spec: .agent-guild/state/spec.md#one
clauses: [C-1]
executor: worker-standard
executor_model: sonnet
checker: checker-judgment
check_method: >-
  C-1: checker-judgment: confirm the output file exists and has content.
status: pending
retries: 0
max_retries: 2
deps: []
dep_rationale: []
escalations: []
artifacts:
  - out.txt
owns:
{owns_block}
---

## Spec excerpt

Produces out.txt.
""".splitlines(),
            )

        for entry, label in [
            ("./out.txt", "'./' prefix"),
            ("/abs/out.txt", "absolute path"),
            ("../sibling/out.txt", "'..' segment"),
            ("src//out.txt", "empty segment"),
            ("src\\\\out.txt", "backslash separator"),
            ('""', "empty entry"),
        ]:
            with tempfile.TemporaryDirectory() as d:
                state = os.path.join(d, "state")
                write_owns_fixture(state, [entry])
                rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
                check(f"R15 {label}: exit 1", rc == 1, f"rc={rc} err={err}")
                check(f"R15 {label}: R15 named", rule_hit(err, "R15"), f"err={err!r}")
                check(f"R15 {label}: task named", "T-001" in err, f"err={err!r}")
                check(f"R15 {label}: no traceback", "Traceback" not in err, f"err={err!r}")

        # The two spellings #162 demonstrated. Both need the entry to exist
        # on disk for the shape to be provably wrong, which is why R15 takes
        # repo_root and ready-set.py (which has none) can't catch this pair.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            os.makedirs(os.path.join(d, "src", "lib"))
            write_owns_fixture(state, ["src/lib"])
            rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
            check("R15 directory without trailing slash: exit 1", rc == 1, f"rc={rc} err={err}")
            check("R15 directory without trailing slash: entry quoted back", "src/lib" in err, err)
            check("R15 directory without trailing slash: R15 named", rule_hit(err, "R15"), f"err={err!r}")

        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            os.makedirs(os.path.join(d, "src"))
            write_lines(os.path.join(d, "src", "a.py"), ["x = 1"])
            write_owns_fixture(state, ["src/a.py/"])
            rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
            check("R15 file with trailing slash: exit 1", rc == 1, f"rc={rc} err={err}")
            check("R15 file with trailing slash: R15 named", rule_hit(err, "R15"), f"err={err!r}")

        # Owning a file the task hasn't created yet is the normal case, so
        # existence is never what R15 asks about.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            write_owns_fixture(state, ["src/not-yet-written.py", "docs/generated/"])
            rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
            check("R15 entries naming paths that don't exist yet: exit 0", rc == 0, f"rc={rc} err={err}")

        # R13 has to catch the same pair the wave does, on the strings alone
        # and with neither path on disk. Two well-formed entries, one
        # directory, and R15 has nothing to say about either of them.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            os.makedirs(os.path.join(state, "tasks"))
            write_lines(os.path.join(state, "constitution.md"), MINIMAL_CONSTITUTION.splitlines())
            for tid, entry in (("T-001", "src/lib"), ("T-002", "src/lib/")):
                write_lines(
                    os.path.join(state, "tasks", f"{tid}.md"),
                    f"""---
id: {tid}
title: Task {tid}
spec: .agent-guild/state/spec.md#one
clauses: [C-1]
executor: worker-standard
executor_model: sonnet
checker: checker-judgment
check_method: >-
  C-1: checker-judgment: confirm the output file exists and has content.
status: pending
retries: 0
max_retries: 2
deps: []
dep_rationale: []
escalations: []
artifacts:
  - out.txt
owns:
  - {entry}
---

## Spec excerpt

Writes under src/lib.
""".splitlines(),
                )
            rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
            check("'src/lib' vs 'src/lib/' with neither on disk: exit 1", rc == 1, f"rc={rc} err={err}")
            check("'src/lib' vs 'src/lib/': R13 named, not R15", rule_hit(err, "R13"), f"err={err!r}")

        # The migration decision (#162): `owns` stays optional, so a corpus
        # that predates the field is not retroactively in violation. The
        # unmutated corpus below carries no `owns:` at all.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
            check("R15 corpus with no owns field anywhere: exit 0", rc == 0, f"rc={rc} err={err}")

        # -------------------------------------------------- R13: ownership overlap (#133)
        # `owns` postdates this corpus, so add_owns() has to inject it before
        # R13 has anything to check. Every real overlap in the corpus—T-001
        # and T-006/T-007 sharing the schema, T-006 and T-007 sharing both
        # the schema and docs/vendor-ledger.md, T-005 and T-007 sharing the
        # retrospective skill, T-003 and T-007 sharing the generated-tree
        # prefixes—already has a direct dep edge, so the corpus with owns
        # added should pass cleanly on its own. add_dep_rationale() also
        # runs here (#125): every task add_owns() gives an `owns` list now
        # owes R14 a rationale for each of its own `deps`, so an exit-0
        # baseline needs both fields injected, not just `owns`.
        print("R13: ownership overlap (#133)")

        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            add_owns(state)
            add_dep_rationale(state)
            rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
            check("corpus + owns: exit 0", rc == 0, f"rc={rc} err={err}")

        # T-006 and T-007 both own the schema and docs/vendor-ledger.md.
        # T-007's dep on T-006 is the only path connecting them—drop it and
        # nothing else does, so R13 has to catch the gap. R13 runs before
        # R14 in rule order, so this fires regardless of dep_rationale;
        # added anyway to keep this fixture's shape matching the baseline.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            add_owns(state)
            add_dep_rationale(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-007.md"),
                "deps: [T-001, T-004, T-005, T-006]",
                "deps: [T-001, T-004, T-005]",
                "R13",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("T-007's dep on T-006 dropped: exit 1", rc == 1, f"rc={rc} err={err}")
                check("T-007 dep dropped: R13 named", rule_hit(err, "R13"), f"err={err!r}")
                check(
                    "T-007 dep dropped: both task ids named",
                    "T-006" in err and "T-007" in err,
                    err,
                )
                check("T-007 dep dropped: no traceback", "Traceback" not in err, f"err={err!r}")

        # -------------------------------------------------- R14: dep rationale (#125)
        # `dep_rationale` postdates this corpus too, so add_dep_rationale()
        # injects it the same way add_owns() injects `owns`. Every task that
        # add_owns() gives an `owns` list also picks up a rationale for each
        # of its own `deps` here, so the corpus with both added should pass
        # cleanly on its own—the mechanical half R14 checks (the two lists
        # line up one to one) is true by construction.
        print("R14: dep rationale (#125)")

        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            add_owns(state)
            add_dep_rationale(state)
            rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
            check("corpus + owns + dep_rationale: exit 0", rc == 0, f"rc={rc} err={err}")

        # T-002 depends on T-001 but its rationale is retargeted at T-999—a
        # dep with no matching rationale at all now.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            add_owns(state)
            add_dep_rationale(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-002.md"),
                "  - T-001: fixture rationale for R14 tests",
                "  - T-999: fixture rationale for R14 tests",
                "R14-missing",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("T-002's rationale for T-001 removed: exit 1", rc == 1, f"rc={rc} err={err}")
                check("T-002 rationale removed: R14 named", rule_hit(err, "R14"), f"err={err!r}")
                check(
                    "T-002 rationale removed: both task and dep named",
                    "T-002" in err and "T-001" in err,
                    err,
                )
                check("T-002 rationale removed: no traceback", "Traceback" not in err, f"err={err!r}")

        # T-002's real dep (T-001) keeps its rationale; a second entry is
        # added naming T-006, which T-002 never declares as a dep at all.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            copy_corpus_state(state)
            add_owns(state)
            add_dep_rationale(state)
            ok = mutate(
                os.path.join(state, "tasks", "T-002.md"),
                "  - T-001: fixture rationale for R14 tests",
                "  - T-001: fixture rationale for R14 tests\n"
                "  - T-006: rationale for a dep this task never declares",
                "R14-extra",
            )
            if ok:
                rc, out, err = run_linter(state, "--repo-root", fixture_root, "--audit-id", "DEC-audit")
                check("T-002's rationale names an undeclared dep: exit 1", rc == 1, f"rc={rc} err={err}")
                check("T-002 undeclared dep: R14 named", rule_hit(err, "R14"), f"err={err!r}")
                check(
                    "T-002 undeclared dep: both task and dep named",
                    "T-002" in err and "T-006" in err,
                    err,
                )
                check("T-002 undeclared dep: no traceback", "Traceback" not in err, f"err={err!r}")

        # A task with no `owns` at all owes R14 nothing, even with a `deps`
        # id and no `dep_rationale` field in sight—the opt-in scoping (#125,
        # same shape as R13's #133). A minimal two-task fixture, not the
        # corpus, since every corpus task already carries `owns` once
        # add_owns() runs and this case needs one that deliberately doesn't.
        with tempfile.TemporaryDirectory() as d:
            state = os.path.join(d, "state")
            os.makedirs(os.path.join(state, "tasks"))
            write_lines(os.path.join(state, "constitution.md"), MINIMAL_CONSTITUTION.splitlines())
            write_lines(
                os.path.join(state, "tasks", "T-001.md"),
                """---
id: T-001
title: Upstream task
spec: .agent-guild/state/spec.md#one
clauses: [C-1]
executor: worker-standard
executor_model: sonnet
checker: checker-judgment
check_method: >-
  C-1: checker-judgment: confirm the output file exists and has content.
status: pending
retries: 0
max_retries: 2
deps: []
escalations: []
artifacts:
  - out.txt
owns:
  - out.txt
---

## Spec excerpt

Produces out.txt.
""".splitlines(),
            )
            write_lines(
                os.path.join(state, "tasks", "T-002.md"),
                """---
id: T-002
title: Downstream task with no owns
spec: .agent-guild/state/spec.md#two
clauses: [C-1]
executor: worker-standard
executor_model: sonnet
checker: checker-judgment
check_method: >-
  C-1: checker-judgment: confirm the output file exists and has content.
status: pending
retries: 0
max_retries: 2
deps: [T-001]
escalations: []
artifacts: []
---

## Spec excerpt

Reads out.txt but writes nothing, so it declares no owns and no
dep_rationale.
""".splitlines(),
            )
            rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
            check("owns-less task with a dep and no rationale: exit 0", rc == 0, f"rc={rc} err={err}")

# ------------------------------------ generated trees: the marketplace files
# Both marketplace files are build-plugin.py outputs, and neither sits under
# `plugin/`, `plugins/`, or `.claude/`. While they were missing from
# GENERATED_TREE_PREFIXES, a task whose only generated artifact was one of
# them read as a task that regenerates nothing, and R8 went quiet on the
# whole job: an illegal decomposition lints clean. Each marketplace file gets
# a fire-then-pass pair, since the passing half on its own goes green against
# the old prefix list too and would prove nothing.
print("generated trees: a marketplace file counts as a regeneration")

for marketplace in (".claude-plugin/marketplace.json", ".agents/plugins/marketplace.json"):
    with tempfile.TemporaryDirectory() as d:
        state = write_synthetic_state(d, [
            {"id": "T-001", "artifacts": ["guild-core/roles/worker-bulk.md"]},
            {"id": "T-002", "artifacts": [marketplace]},  # no dep on T-001
        ])
        rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
        check(f"{marketplace} regenerated before the edit it captures: exit 1", rc == 1, f"rc={rc} err={err}")
        check(f"{marketplace}: R8 named", rule_hit(err, "R8"), f"err={err!r}")

    with tempfile.TemporaryDirectory() as d:
        state = write_synthetic_state(d, [
            {"id": "T-001", "artifacts": ["guild-core/roles/worker-bulk.md"]},
            {"id": "T-002", "artifacts": [marketplace], "deps": ["T-001"]},
        ])
        rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
        check(f"{marketplace} regenerated downstream of the edit: exit 0", rc == 0, f"rc={rc} err={err}")

# ------------------------------------------- R16: build serialization (#164)
# The case that reproduces today: two tasks editing disjoint paths under
# guild-core/. Nothing about their file ownership overlaps, so the wave
# dispatches both, and both then have to run build-plugin.py over the same
# output trees. R16 refuses the decomposition until one task owns the
# regeneration.
print("R16: build serialization (#164)")

GUILD_CORE_A = "guild-core/roles/auditor.md"
GUILD_CORE_B = "guild-core/workflows/decompose/SKILL.md"

with tempfile.TemporaryDirectory() as d:
    state = write_synthetic_state(d, [
        {"id": "T-001", "artifacts": [GUILD_CORE_A]},
        {"id": "T-002", "artifacts": [GUILD_CORE_B]},
    ])
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
    check("R16 two build-input editors and no regenerator: exit 1", rc == 1, f"rc={rc} err={err}")
    check("R16 no regenerator: R16 named", rule_hit(err, "R16"), f"err={err!r}")
    check("R16 no regenerator: both editors named", "T-001" in err and "T-002" in err, err)
    check("R16 no regenerator: no traceback", "Traceback" not in err, f"err={err!r}")

# The fix the rule is asking for: one terminal task, downstream of both
# edits, declaring the generated trees. Both editors still share a wave;
# the regenerator waits on its deps, which is where the serialization the
# issue asked for becomes visible in the wave's own output.
with tempfile.TemporaryDirectory() as d:
    state = write_synthetic_state(d, [
        {"id": "T-001", "artifacts": [GUILD_CORE_A]},
        {"id": "T-002", "artifacts": [GUILD_CORE_B]},
        {"id": "T-003", "artifacts": ["plugin/", "plugins/", ".claude/"],
         "deps": ["T-001", "T-002"]},
    ])
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
    check("R16 one terminal regenerator downstream of both: exit 0", rc == 0, f"rc={rc} err={err}")

# Two regenerators with no dep path between them. R8 passes this, because
# some generated task (T-004) is downstream of everything—which is why R8
# alone was never enough.
with tempfile.TemporaryDirectory() as d:
    state = write_synthetic_state(d, [
        {"id": "T-001", "artifacts": [GUILD_CORE_A]},
        {"id": "T-002", "artifacts": ["plugin/"], "deps": ["T-001"]},
        {"id": "T-003", "artifacts": ["plugins/"], "deps": ["T-001"]},
        {"id": "T-004", "artifacts": [".claude/"], "deps": ["T-002", "T-003"]},
    ])
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
    check("R16 two unordered regenerators: exit 1", rc == 1, f"rc={rc} err={err}")
    check("R16 two unordered regenerators: R16 named, not R8", rule_hit(err, "R16"), f"err={err!r}")
    check("R16 two unordered regenerators: both named", "T-002" in err and "T-003" in err, err)

with tempfile.TemporaryDirectory() as d:
    state = write_synthetic_state(d, [
        {"id": "T-001", "artifacts": [GUILD_CORE_A]},
        {"id": "T-002", "artifacts": ["plugin/"], "deps": ["T-001"]},
        {"id": "T-003", "artifacts": ["plugins/", ".claude/"], "deps": ["T-002"]},
    ])
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
    check("R16 two regenerators on a dep path: exit 0", rc == 0, f"rc={rc} err={err}")

# A job that touches no build input owes nothing to the build step.
with tempfile.TemporaryDirectory() as d:
    state = write_synthetic_state(d, [
        {"id": "T-001", "artifacts": ["docs/some-guide.md"]},
        {"id": "T-002", "artifacts": ["README.md"]},
    ])
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "DEC-audit")
    check("R16 no build inputs anywhere in the job: exit 0", rc == 0, f"rc={rc} err={err}")

# CON-audit has no tasks to serialize.
with tempfile.TemporaryDirectory() as d:
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "tasks"))
    write_lines(os.path.join(state, "constitution.md"), MINIMAL_CONSTITUTION.splitlines())
    rc, out, err = run_linter(state, "--repo-root", d, "--audit-id", "CON-audit")
    check("R16 CON-audit with an empty tasks/: exit 0", rc == 0, f"rc={rc} err={err}")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
