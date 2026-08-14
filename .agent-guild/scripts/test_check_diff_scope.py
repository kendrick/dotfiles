#!/usr/bin/env python3
"""Fixture-based tests for check-diff-scope.py. Every fixture is a scratch
git repo in a fresh temp dir, and the script runs as a subprocess so these
tests exercise the real CLI contract (exit codes, stderr messages)—matching
test_ledger_append.py's approach for ledger-append.py.

Run: python3 .agent-guild/scripts/test_check_diff_scope.py
"""
import importlib.util
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

# ---------------------------------------- 6. reconstruction: T-007 writes plugin/
# The real #117 corpus's T-007 listed generated-tree copies (e.g.
# `plugin/skills/retrospective/SKILL.md`) among its `artifacts`, even
# though its spec never has it touch `plugin/`—only the terminal
# regeneration task (T-003) owns generated trees. Allowlist the five source
# files T-007's spec excerpt actually names and confirm a write under
# `plugin/` is caught as out of scope.
print("reconstruction: T-007's real scope catches a plugin/ write as out of scope")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, os.path.join(".agent-guild", "state", "commit-message.md"))
    write(d, os.path.join("plugin", "skills", "retrospective", "SKILL.md"))
    rc, out, err = run_script(
        d,
        ".agent-guild/state/commit-message.md",
        ".agent-guild/schemas/vendor-call.schema.json",
        ".agent-guild/scripts/ledger-append.py",
        "docs/vendor-ledger.md",
        "guild-core/workflows/retrospective/SKILL.md",
    )
    check("T-007-writes-plugin/: nonzero exit", rc != 0, f"rc={rc}")
    check(
        "T-007-writes-plugin/: offending path named",
        "plugin/skills/retrospective/SKILL.md" in err,
        err,
    )

# ---------------------------------- 7. an allowlist grant only flows down
# A directory grant says nothing about a file at a node ABOVE it. That's
# containment, and it is not the symmetric question two owners ask about
# each other, which is why in_scope has its own predicate. Written against
# the CLI because the distinction was briefly lost in a shared one.
print("a directory grant doesn't admit a file above it")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, "docs")  # a FILE at the node above the granted directory
    rc, out, err = run_script(d, "docs/generated/")
    check("a file at an ancestor of the granted directory: out of scope", rc == 1, f"rc={rc} err={err}")
    check("ancestor file: named as the offender", "out of scope: docs" in err, err)

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, "plugin")  # a file where the grant names a directory
    rc, out, err = run_script(d, "plugin/")
    check("a file at the granted directory's own node: out of scope", rc == 1, f"rc={rc} err={err}")

with tempfile.TemporaryDirectory(prefix="check-diff-scope-fixture-") as d:
    init_repo(d)
    write(d, os.path.join("docs", "generated", "api.md"))
    rc, out, err = run_script(d, "docs/generated/")
    check("a file inside the granted directory: in scope", rc == 0, f"rc={rc} err={err}")

# ------------------------------------------- 8. owns_entry_problem (#162)
# The one predicate here that isn't reachable through the CLI: R13 and
# ready-set.py both import it, so it gets tested in-process.
print("owns_entry_problem: the two shapes, and what isn't one of them")

_spec = importlib.util.spec_from_file_location("check_diff_scope_under_test", SCRIPT)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
owns_entry_problem = _mod.owns_entry_problem
paths_overlap = _mod.paths_overlap

for good in [
    "src/a.py",
    "src/",
    "a.py",
    "docs/guide/index.md",
    "plugin/",
    # Brackets are ordinary filename characters, and this is the most
    # common path shape in half the frameworks a copied-in kit will meet.
    # Refusing it would fail DEC-audit with no spelling the author could
    # write instead, so the glob check is `*` and `?` only.
    "app/[slug]/page.tsx",
    "app/[...catchall]/route.ts",
    "src/my file.py",
    "lib/a~backup.js",
]:
    check(f"well-formed entry {good!r}: no problem", owns_entry_problem(good) is None)

for bad, label in [
    ("./src/a.py", "'./' prefix"),
    ("/etc/passwd", "absolute"),
    ("../outside/a.py", "'..' segment"),
    ("src//a.py", "empty segment"),
    ("src\\a.py", "backslash"),
    (" src/a.py", "leading space"),
    ("", "empty string"),
    ("/", "bare slash"),
    ("src/*.py", "glob star"),
    ("src/a?.py", "glob question mark"),
    ("~/a.py", "home expansion"),
    ("$OUT/a.py", "variable expansion"),
    ("​src/a.py", "zero-width space"),
    (None, "not a string at all"),
]:
    check(f"malformed entry ({label}): a problem is reported", owns_entry_problem(bad) is not None)

# The three pairs #162 opened with, none of which may answer a silent False.
# Two of them are the same territory spelled differently, so overlap is the
# honest answer and no filesystem lookup is involved in giving it.
check(
    "'src/lib' vs 'src/lib/' overlap, whether or not src/lib exists yet",
    paths_overlap("src/lib", "src/lib/") is True,
)
check(
    "'src/foo/bar.py' vs 'src/foo' overlap: one contains the other",
    paths_overlap("src/foo/bar.py", "src/foo") is True,
)
# The third is a spelling no comparison can rescue, so it's refused instead.
check(
    "'./src/a.py' vs 'src/a.py' can't be reconciled by comparison...",
    paths_overlap("./src/a.py", "src/a.py") is False,
)
check(
    "...so the './' spelling is refused, with no filesystem lookup at all",
    owns_entry_problem("./src/a.py") is not None,
)
# A directory that already exists is still refused when spelled slashless,
# even though overlap now catches it: the entry is wrong on its own terms
# and the reader of the task file deserves to be told.
with tempfile.TemporaryDirectory() as d:
    os.makedirs(os.path.join(d, "src", "lib"))
    check(
        "an existing directory spelled without its slash: still malformed",
        owns_entry_problem("src/lib", d) is not None,
    )

# The lookalike sibling must survive the looser overlap rule: a parent
# relationship is tested at a separator, not by raw string prefix.
check(
    "'plugin/' does not swallow 'plugin-extra/file.py'",
    paths_overlap("plugin/", "plugin-extra/file.py") is False,
)
check(
    "'plugin/' does cover 'plugin/hooks/hooks.json'",
    paths_overlap("plugin/", "plugin/hooks/hooks.json") is True,
)
check(
    "two different files under one directory don't overlap",
    paths_overlap("src/a.py", "src/b.py") is False,
)

# Existence is never required: a task's job is often to create what it owns.
with tempfile.TemporaryDirectory() as d:
    check(
        "an entry naming a path that doesn't exist yet: no problem",
        owns_entry_problem("src/brand-new.py", d) is None,
    )

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
