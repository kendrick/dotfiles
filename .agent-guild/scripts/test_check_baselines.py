#!/usr/bin/env python3
"""Fixture-based tests for check-baselines.py (#182). Every fixture is a
scratch state dir plus a scratch repo root in a fresh temp dir, and the
script runs as a subprocess so these tests exercise the real CLI contract
(exit codes, stdout/stderr)—matching test_check_diff_scope.py's approach.

check-baselines.py imports check-job-spec.py from its own directory
(SCRIPT_DIR), so this suite only works when the two ship side by side—the
real `.agent-guild/scripts/` layout. During drafting, that means a copy of
check-job-spec.py has to sit alongside this test file before running it.

Run: python3 .agent-guild/scripts/test_check_baselines.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(SCRIPTS_DIR, "check-baselines.py")
# Resolves to .agent-guild/state/archive/2026-08-11-issue-141 once this file
# ships at .agent-guild/scripts/—computed relative to this file's own
# directory rather than hardcoded, so the fixture works from any checkout.
ARCHIVE_141_DIR = os.path.join(SCRIPTS_DIR, os.pardir, "state", "archive", "2026-08-11-issue-141")

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


def write_exec(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(path, 0o755)


def build_fixture_repo_root(root):
    """A scratch repo root holding just what a fixture clause's check
    needs: an executable check-build.sh stub that runs its quoted argument
    through `bash -c` and propagates the exit code. Every fixture clause's
    check text is a check-build.sh invocation, the same shape real
    constitutions use. Unlike the real check-build.sh, this stub skips
    logging entirely—nothing here reads state/log/, and one line keeps the
    fixture's own behavior obvious to a reader."""
    repo_root = os.path.join(root, "repo")
    scripts_dir = os.path.join(repo_root, ".agent-guild", "scripts")
    os.makedirs(scripts_dir)
    write_exec(
        os.path.join(scripts_dir, "check-build.sh"),
        '#!/usr/bin/env bash\nbash -c "$1"\nexit $?\n',
    )
    return repo_root


def cb(cmd):
    """A fixture clause's check text: a check-build.sh invocation quoting
    `cmd`, the shape every real constitution's script-checked clause uses."""
    return f".agent-guild/scripts/check-build.sh '{cmd}'"


def constitution(clauses):
    """A minimal-but-valid constitution.md: title, job-weight line, one
    `### C-N:` block per entry in `clauses`, then a `## Non-goals`
    section—so the last-clause-swallows-trailing-sections history
    (check-job-spec.py's own corpus was bitten by this once) can't leak
    into what parse_constitution reads back out here. Each entry is a dict
    with `id` and `check`, plus optional `name`, `text`, and `baseline`."""
    lines = [
        "# Constitution: check-baselines.py fixture",
        "",
        "**Job weight**: deep, synthetic fixture",
        "",
        "## Clauses",
        "",
    ]
    for c in clauses:
        lines.append(f"### {c['id']}: {c.get('name', 'fixture clause')}")
        lines.append(f"- **text**: {c.get('text', 'Fixture clause text.')}")
        lines.append(f"- **check**: {c['check']}")
        lines.append("- **severity**: major")
        if "baseline" in c:
            lines.append(f"- **baseline**: {c['baseline']}")
        lines.append("- **failing example**: n/a, this is a fixture.")
        lines.append("")
    lines.append("## Non-goals")
    lines.append("")
    lines.append("- Nothing else is in scope for this fixture.")
    lines.append("")
    return "\n".join(lines)


def write_state(root, clauses):
    state_dir = os.path.join(root, "state")
    os.makedirs(state_dir)
    with open(os.path.join(state_dir, "constitution.md"), "w", encoding="utf-8") as f:
        f.write(constitution(clauses))
    return state_dir


def run_script(state_dir, repo_root, *extra_args):
    proc = subprocess.run(
        [sys.executable, SCRIPT, state_dir, "--repo-root", repo_root, *extra_args],
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


# --------------------------------------------------------- 1. green passes
print("green baseline, check passes: exit 0")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [{"id": "C-1", "check": cb("true"), "baseline": "green"}])
    rc, out, err = run_script(state_dir, repo_root)
    check("green-pass: exit 0", rc == 0, f"rc={rc} out={out!r} err={err!r}")
    check("green-pass: summary says ran 1", "ran 1" in out, out)
    check("green-pass: no traceback", "Traceback" not in err, err)

# ----------------------------------------------------- 2. green violation
print("green baseline, check fails: violation, exit 1")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [{"id": "C-1", "check": cb("false"), "baseline": "green"}])
    rc, out, err = run_script(state_dir, repo_root)
    check("green-fail: exit 1", rc == 1, f"rc={rc} out={out!r} err={err!r}")
    check("green-fail: stderr names C-1", "C-1" in err, err)
    check("green-fail: stderr names green", "green" in err, err)
    check("green-fail: no traceback", "Traceback" not in err, err)

# -------------------------------------------------------------- 3. red ok
print("red baseline, check fails: exit 0")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [{"id": "C-1", "check": cb("false"), "baseline": "red"}])
    rc, out, err = run_script(state_dir, repo_root)
    check("red-ok: exit 0", rc == 0, f"rc={rc} out={out!r} err={err!r}")
    check("red-ok: no traceback", "Traceback" not in err, err)

# ------------------------------------------------------- 4. red violation
print("red baseline, check passes: violation, exit 1")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [{"id": "C-1", "check": cb("true"), "baseline": "red"}])
    rc, out, err = run_script(state_dir, repo_root)
    check("red-fail: exit 1", rc == 1, f"rc={rc} out={out!r} err={err!r}")
    check("red-fail: stderr names C-1", "C-1" in err, err)
    check("red-fail: stderr names red", "red" in err, err)
    check("red-fail: stderr carries 'already holds'", "already holds" in err, err)

# ------------------------------------------------------- 5. mixed 4-clause
print("mixed doc, one of each: both violations named, ran counts all 4")

MIXED_CLAUSES = [
    {"id": "C-1", "check": cb("true"), "baseline": "green"},   # pass
    {"id": "C-2", "check": cb("false"), "baseline": "green"},  # violation
    {"id": "C-3", "check": cb("false"), "baseline": "red"},    # pass
    {"id": "C-4", "check": cb("true"), "baseline": "red"},     # violation
]

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, MIXED_CLAUSES)
    rc, out, err = run_script(state_dir, repo_root)
    check("mixed: exit 1", rc == 1, f"rc={rc} out={out!r} err={err!r}")
    check("mixed: C-2 named", "C-2" in err, err)
    check("mixed: C-4 named", "C-4" in err, err)
    check("mixed: summary counts ran 4", "ran 4" in out, out)
    check("mixed: no traceback", "Traceback" not in err, err)

# ------------------------------------------------ 6. judgment + no-baseline
print("judgment clause and no-baseline clause: both skipped, exit 0")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [
        {"id": "C-1", "check": "checker-judgment: reads well"},
        {"id": "C-2", "check": cb("true")},  # no baseline field at all
    ])
    rc, out, err = run_script(state_dir, repo_root)
    check("skip-mix: exit 0", rc == 0, f"rc={rc} out={out!r} err={err!r}")
    check(
        "skip-mix: summary says skipped 2 (1 judgment, 1 no-baseline)",
        "skipped 2 (1 judgment, 1 no-baseline)" in out,
        out,
    )
    check("skip-mix: no traceback", "Traceback" not in err, err)

# ------------------------------------------------- 7. baseline value amber
print("baseline value neither red nor green: could-not-run, exit 3")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [{"id": "C-1", "check": cb("true"), "baseline": "amber"}])
    rc, out, err = run_script(state_dir, repo_root)
    check("amber: exit 3", rc == 3, f"rc={rc} out={out!r} err={err!r}")
    check("amber: stderr names C-1", "C-1" in err, err)
    check("amber: stderr names amber", "amber" in err, err)
    check("amber: no traceback", "Traceback" not in err, err)

# ---------------------------------------------------- 8. check exits 3
print("check exits 3 with baseline red: could-not-run, exit 3")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [{"id": "C-1", "check": cb("exit 3"), "baseline": "red"}])
    rc, out, err = run_script(state_dir, repo_root)
    check("exit3: exit 3", rc == 3, f"rc={rc} out={out!r} err={err!r}")
    check("exit3: stderr says could not run", "could not run" in err, err)
    check("exit3: stderr names the exit code", "exited 3" in err, err)
    check("exit3: no traceback", "Traceback" not in err, err)

# --------------------------------------- 9. violation + could-not-run
print("violation and could-not-run together: violation outranks, exit 1")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [
        {"id": "C-1", "check": cb("false"), "baseline": "green"},   # violation
        {"id": "C-2", "check": cb("exit 3"), "baseline": "red"},    # could-not-run
    ])
    rc, out, err = run_script(state_dir, repo_root)
    check("combo: exit 1 (violation outranks)", rc == 1, f"rc={rc} out={out!r} err={err!r}")
    check("combo: violation line present", "C-1" in err and "green" in err, err)
    check("combo: could-not-run line present", "C-2" in err and "could not run" in err, err)

# ------------------------------------------------------------- 10. timeout
print("--timeout 1 against a 5-second sleep: could-not-run, exit 3")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [{"id": "C-1", "check": cb("sleep 5"), "baseline": "red"}])
    rc, out, err = run_script(state_dir, repo_root, "--timeout", "1")
    check("timeout: exit 3", rc == 3, f"rc={rc} out={out!r} err={err!r}")
    check("timeout: stderr mentions timeout", "timeout" in err.lower() or "timed out" in err.lower(), err)
    check("timeout: no traceback", "Traceback" not in err, err)

# --------------------------------------------------------- 11. dry run
print("--dry-run: classifies without executing anything")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = write_state(root, [
        {"id": "C-1", "check": cb("touch case11-marker && true"), "baseline": "green"},
        {"id": "C-2", "check": "checker-judgment: reads well"},
        {"id": "C-3", "check": cb("true")},  # no baseline
        {"id": "C-4", "check": cb("false"), "baseline": "red"},
    ])
    rc, out, err = run_script(state_dir, repo_root, "--dry-run")
    check("dry-run: exit 0", rc == 0, f"rc={rc} out={out!r} err={err!r}")
    check("dry-run: C-1 would run", "C-1 would run" in out, out)
    check("dry-run: C-4 would run", "C-4 would run" in out, out)
    check("dry-run: C-2 skip", "C-2 skip" in out, out)
    check("dry-run: C-3 skip", "C-3 skip" in out, out)
    check(
        "dry-run: nothing executed, marker file absent",
        not os.path.exists(os.path.join(repo_root, "case11-marker")),
        f"repo_root listing: {os.listdir(repo_root)}",
    )
    check("dry-run: no traceback", "Traceback" not in err, err)

# ---------------------------------------------------- 12. missing constitution
print("missing constitution.md: exit 3, prefixed message")

with tempfile.TemporaryDirectory(prefix="check-baselines-fixture-") as root:
    repo_root = build_fixture_repo_root(root)
    state_dir = os.path.join(root, "state")
    os.makedirs(state_dir)  # constitution.md deliberately absent
    rc, out, err = run_script(state_dir, repo_root)
    check("missing-constitution: exit 3", rc == 3, f"rc={rc} out={out!r} err={err!r}")
    check("missing-constitution: prefixed message", "check-baselines: " in err, err)
    check("missing-constitution: no traceback", "Traceback" not in err, err)

# ------------------------------------------------- 13. archive replay (#141)
if not os.path.isdir(ARCHIVE_141_DIR):
    print(f"skip: archive fixture not found at {ARCHIVE_141_DIR}")
else:
    print("archive replay: issue-141 constitution classifies exactly as measured")

    with tempfile.TemporaryDirectory(prefix="check-baselines-archive-") as root:
        repo_root = build_fixture_repo_root(root)
        state_dir = os.path.join(root, "state")
        os.makedirs(state_dir)
        shutil.copy(
            os.path.join(ARCHIVE_141_DIR, "constitution.md"),
            os.path.join(state_dir, "constitution.md"),
        )
        rc, out, err = run_script(state_dir, repo_root, "--dry-run")
        check("archive-141: exit 0", rc == 0, f"rc={rc} out={out!r} err={err!r}")
        check("archive-141: would run 0", "would run 0" in out, out)
        check(
            "archive-141: skipped 9 (5 judgment, 4 no-baseline)",
            "skipped 9 (5 judgment, 4 no-baseline)" in out,
            out,
        )
        for cid in ["C-1", "C-2", "C-5", "C-8", "C-9"]:
            check(f"archive-141: {cid} classified judgment", f"{cid} skip (judgment)" in out, out)
        for cid in ["C-3", "C-4", "C-6", "C-7"]:
            check(f"archive-141: {cid} classified no-baseline", f"{cid} skip (no-baseline)" in out, out)
        check("archive-141: no traceback", "Traceback" not in err, err)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
