#!/usr/bin/env python3
"""The standard scoped-diff check: fail loud if the working tree touches a
path outside an explicit allowlist.

Nearly every guild constitution carries a "the job's diff touches only these
paths" clause. Hand-rolled as judgment prose, it's opus-tier spend on a
listing rule, re-phrased—and occasionally mis-phrased—per job. This makes it
mechanical, so the clause routes to checker-deterministic (haiku) instead.

    .agent-guild/scripts/check-diff-scope.py ALLOWED... [--ignore PATH]...

ALLOWED arguments: an exact file path, or a directory prefix if the argument
ends with `/` (covers everything under it, e.g. `plugin/` covers
`plugin/hooks/hooks.json`).

--ignore PATH, repeatable: a known user-owned path (typically untracked)
excluded from judgment—the honest escape hatch for files the job legitimately
didn't create but shouldn't be held to the allowlist either.

Paths under `.agent-guild/state/` are always permitted (job bookkeeping the
kit itself writes) and need no allowlist entry.

Run from the repo root, like the kit's other scripts—git's relative paths
only line up against ALLOWED/--ignore arguments when cwd is the toplevel.

The path set is the union of `git status --porcelain` and
`git diff --name-only`. Rename syntax (`old -> new`, which `git status`
emits for a detected rename) resolves to the new path—a rename that lands
back in scope shouldn't trip the check on its own history.

Exit codes: 0 every changed path is in scope, one `OK:` line to stdout; 1 one
or more paths are out of scope, each named on stderr as
`check-diff-scope: out of scope: <path>`; 3 usage/infra error (not a git
repo, or a git command itself failed).

Stdlib only, so the kit stays copy-in portable.
"""
import argparse
import subprocess
import sys


def _resolve_rename(raw):
    """A git status/diff path token, with rename syntax ('old -> new')
    resolved to just the new path—scope is about where the file ends up,
    not what it used to be called."""
    if " -> " in raw:
        return raw.split(" -> ", 1)[1]
    return raw


def _parse_porcelain(text):
    """Parse `git status --porcelain` (v1) output. Each line is a 2-char
    XY status, a space, then a path (or 'orig -> new' for a detected
    rename/copy)—so the path always starts at index 3."""
    paths = []
    for line in text.splitlines():
        if not line:
            continue
        paths.append(_resolve_rename(line[3:]))
    return paths


def _parse_name_only(text):
    """Parse `git diff --name-only` output: one path per line. Rename
    syntax isn't normally emitted here, but resolving it too costs nothing
    and keeps both parsers honest about the same contract."""
    return [_resolve_rename(line) for line in text.splitlines() if line]


def _in_git_repo():
    proc = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        capture_output=True,
        text=True,
    )
    return proc.returncode == 0 and proc.stdout.strip() == "true"


def _run_git(*args):
    return subprocess.run(
        ["git", *args], capture_output=True, text=True, check=True
    ).stdout


def collect_changed_paths():
    """Union of `git status --porcelain` and `git diff --name-only`,
    deduplicated, order preserved (first-seen wins)—stable output makes the
    OK:/offender lines reproducible run to run.

    --untracked-files=all is not optional: git's default collapses a wholly
    new directory into a single `dir/` entry instead of listing the files
    inside it, which would silently defeat directory-prefix matching (and
    the .agent-guild/state/ carve-out) the moment a job's first file in a
    new directory lands."""
    paths = _parse_porcelain(_run_git("status", "--porcelain", "--untracked-files=all"))
    paths += _parse_name_only(_run_git("diff", "--name-only"))
    seen = set()
    unique = []
    for p in paths:
        if p not in seen:
            seen.add(p)
            unique.append(p)
    return unique


def in_scope(path, allowed_files, allowed_dirs, ignored):
    if path in allowed_files:
        return True
    if path in ignored:
        return True
    if path.startswith(".agent-guild/state/"):
        return True
    for prefix in allowed_dirs:
        if path.startswith(prefix):
            return True
    return False


def main(argv=None):
    ap = argparse.ArgumentParser(
        description=(
            "Fail if the working tree's diff touches a path outside an "
            "explicit allowlist."
        )
    )
    ap.add_argument(
        "allowed",
        nargs="*",
        metavar="ALLOWED",
        help="an exact file path, or a directory prefix ending in '/'",
    )
    ap.add_argument(
        "--ignore",
        action="append",
        default=[],
        metavar="PATH",
        help="a known user-owned path to exclude from judgment (repeatable)",
    )
    args = ap.parse_args(argv)

    if not _in_git_repo():
        sys.stderr.write("check-diff-scope: not inside a git repository\n")
        return 3

    allowed_files = {p for p in args.allowed if not p.endswith("/")}
    allowed_dirs = tuple(p for p in args.allowed if p.endswith("/"))
    ignored = set(args.ignore)

    try:
        paths = collect_changed_paths()
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"check-diff-scope: git command failed: {e}\n")
        return 3

    offenders = [
        p for p in paths if not in_scope(p, allowed_files, allowed_dirs, ignored)
    ]

    if offenders:
        for p in offenders:
            sys.stderr.write(f"check-diff-scope: out of scope: {p}\n")
        return 1

    print(f"OK: {len(paths)} path(s) in scope")
    return 0


if __name__ == "__main__":
    sys.exit(main())
