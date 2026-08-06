#!/usr/bin/env python3
"""Fixture-based tests for check-diff-scope.py. Every fixture is a scratch
git repo in a fresh temp dir, and the script runs as a subprocess so these
tests exercise the real CLI contract (exit codes, stderr messages)—matching
test_ledger_append.py's approach for ledger-append.py.

Run: python3 .agent-guild/scripts/test_check_diff_scope.py
"""
import os
import subprocess
import sys
import tempfile

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(SCRIPTS_DIR, "check-diff-scope.py")

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


def init_repo(d):
    """Turn an existing empty temp dir into a scratch git repo with one
    committed file, so `git status` and `git diff` both have a real
    baseline (a repo with zero commits makes a staged rename behave
    oddly)."""
    subprocess.run(["git", "init", "-q"], cwd=d, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=d, check=True)
    subprocess.run(["git", "config", "user.name", "Test"], cwd=d, check=True)
    write(d, "README.md", "seed\n")
    subprocess.run(["git", "add", "."], cwd=d, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=d, check=True)


def write(d, rel, content="x\n"):
    path = os.path.join(d, rel)
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


def run_script(d, *argv):
    proc = subprocess.run(
        [sys.executable, SCRIPT, *argv], cwd=d, capture_output=True, text=True
    )
    return proc.returncode, proc.stdout, proc.stderr


# ---------------------------------------------------- 1. allowed-only tree
print("allowed-only dirty tree exits 0")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, "foo.py")
    rc, out, err = run_script(d, "foo.py")
    check("allowed-only: exit 0", rc == 0, f"rc={rc} err={err}")
    check("allowed-only: OK line on stdout", out.startswith("OK:"), out)

# ------------------------------------------------- 2. one out-of-scope path
print("one out-of-scope path exits nonzero and names it")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, "foo.py")
    write(d, "bar.py")
    rc, out, err = run_script(d, "foo.py")
    check("out-of-scope: nonzero exit", rc != 0, f"rc={rc}")
    check("out-of-scope: offender named on stderr", "bar.py" in err, err)
    check(
        "out-of-scope: allowed path not named as an offender",
        "out of scope: foo.py" not in err,
        err,
    )

# --------------------------------------- 3. state/ and --ignore never flagged
print("state/ and --ignore paths are never flagged")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, os.path.join(".agent-guild", "state", "tasks", "T-001.md"))
    write(d, "scratch-notes.txt")
    rc, out, err = run_script(d, "foo.py", "--ignore", "scratch-notes.txt")
    check("state/ + --ignore only: exit 0", rc == 0, f"rc={rc} err={err}")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, os.path.join(".agent-guild", "state", "tasks", "T-001.md"))
    write(d, "bar.py")  # genuinely out of scope, to prove state/ isn't a blanket pass
    rc, out, err = run_script(d, "foo.py")
    check("state/ doesn't mask a real offender: nonzero exit", rc != 0, f"rc={rc}")
    check("state/ doesn't mask a real offender: bar.py named", "bar.py" in err, err)
    check(
        "state/ path itself not named as an offender",
        ".agent-guild/state/tasks/T-001.md" not in err,
        err,
    )

# --------------------------------------- 4. directory-prefix argument
print("a dir/ prefix argument covers nested files")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, os.path.join("plugin", "hooks", "hooks.json"))
    rc, out, err = run_script(d, "plugin/")
    check("dir-prefix: nested file exits 0", rc == 0, f"rc={rc} err={err}")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    # A lookalike top-level name must NOT match the "plugin/" prefix—
    # startswith("plugin/") requires the trailing slash boundary.
    write(d, os.path.join("plugin-extra", "file.py"))
    rc, out, err = run_script(d, "plugin/")
    check("dir-prefix: lookalike sibling dir is not swallowed", rc != 0, f"rc={rc}")
    check("dir-prefix: lookalike offender named", "plugin-extra/file.py" in err, err)

# --------------------------------------------------------- 5. rename syntax
print("rename syntax ('old -> new') resolves to the new path")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, "old.py")
    subprocess.run(["git", "add", "old.py"], cwd=d, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "add old.py"], cwd=d, check=True)
    subprocess.run(["git", "mv", "old.py", "new.py"], cwd=d, check=True)
    rc, out, err = run_script(d, "old.py", "new.py")
    check("rename within allowlist: exit 0", rc == 0, f"rc={rc} err={err}")
    check(
        "rename within allowlist: no arrow-string leaked into stderr",
        "->" not in err,
        err,
    )

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, "old.py")
    subprocess.run(["git", "add", "old.py"], cwd=d, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "add old.py"], cwd=d, check=True)
    subprocess.run(["git", "mv", "old.py", "new_bad.py"], cwd=d, check=True)
    rc, out, err = run_script(d, "old.py")
    check("rename out of allowlist: nonzero exit", rc != 0, f"rc={rc}")
    check(
        "rename out of allowlist: new path named, not the arrow string",
        "new_bad.py" in err,
        err,
    )
    check(
        "rename out of allowlist: raw arrow syntax not dumped verbatim",
        "old.py -> new_bad.py" not in err,
        err,
    )

# ---------------------------------------------------- bonus: not a git repo
print("not a git repo: clear message, exit 3")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-nogit-") as d:
    rc, out, err = run_script(d, "foo.py")
    check("not-a-git-repo: exit 3", rc == 3, f"rc={rc}")
    check(
        "not-a-git-repo: message uses the check-diff-scope: prefix",
        "check-diff-scope:" in err,
        err,
    )

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
