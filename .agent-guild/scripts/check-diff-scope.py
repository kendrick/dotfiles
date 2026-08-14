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

There was once a `--task-file` flag that scoped the check to one task's own
`owns:` list, meant as the runtime half of #133. It never had a caller, and
#162 ruled it can't have a sound one: under a wave the working tree holds
every in-flight task's writes at once and nothing can attribute a write back
to the task that made it, so a per-task run flags its peers. What that flag
was reaching for is enforced where it can be proven instead—R13 and R15 at
lint time, and ready-set.py's refusal to group tasks it can't compare.

The path set is the union of `git status --porcelain` and
`git diff --name-only`. Rename syntax (`old -> new`, which `git status`
emits for a detected rename) resolves to the new path—a rename that lands
back in scope shouldn't trip the check on its own history.

Exit codes: 0 every changed path is in scope, one `OK:` line to stdout; 1 one
or more paths are out of scope, each named on stderr as
`check-diff-scope: out of scope: <path>`; 3 usage/infra error (not a git
repo, or a git command itself failed).

`paths_overlap(a, b)` below is the single home for "do these two ownership
paths overlap" semantics—check-job-spec.py's R13 ownership-overlap rule
imports it via the `_load_module` importlib idiom (see that script's own
docstring), rather than re-deriving the same exact/prefix logic a second
time. `owns_entry_problem(entry)` lives beside it for the same reason:
overlap is only meaningful between two entries that are actually one of
the two shapes, so the shape predicate belongs where the shapes are
defined. R15 and ready-set.py both import it.

Stdlib only, so the kit stays copy-in portable.
"""
import argparse
import os
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


def paths_overlap(a, b):
    """True if ownership paths `a` and `b` denote overlapping territory.
    Each is either an exact file path or a directory prefix ending in
    '/'—the same two shapes ALLOWED and `owns:` entries both take.

    The comparison is on the path itself, with the trailing slash treated
    as notation rather than as part of the name, so `src/lib` and
    `src/lib/` are the same territory spelled two ways. #162 found the
    earlier version answering False there: it compared a file claim
    against a directory claim, correctly for the shapes it was handed and
    uselessly for what the author meant, and two tasks writing one tree
    rode the same wave on the strength of that answer. R15 refuses the
    slashless spelling of a directory that already exists, but a task's
    whole job is often to create the tree it owns, and this predicate is
    the only thing standing between that case and a lost write.

    So: two paths overlap when they name the same node, or when either is
    a parent directory of the other. A trailing slash still carries
    meaning for anyone reading the file, and `plugin/` still does not
    swallow `plugin-extra/`, because a parent relationship is tested at a
    separator rather than by raw string prefix. `a` and `b` are
    interchangeable—the check is symmetric—which matters to a caller like
    R13 comparing two tasks' owns lists pairwise without caring which one
    it read first."""
    a_core = a.rstrip("/")
    b_core = b.rstrip("/")
    if a_core == b_core:
        return True
    return a_core.startswith(b_core + "/") or b_core.startswith(a_core + "/")


def owns_entry_problem(entry, repo_root=None):
    """A short reason an `owns:` entry is malformed, or None if it's one of
    the two shapes paths_overlap above understands.

    Shape is load-bearing rather than cosmetic. `paths_overlap` above
    answers "same territory?" for the two documented shapes; hand it a
    third thing and its answer is meaningless rather than wrong, and a
    meaningless "no overlap" is what puts two tasks on one file in the
    same wave (#162). Every check here catches a spelling that would
    produce one: `./src/a.py` never matches `src/a.py`, a glob never
    matches the files it was meant to stand for, an invisible character
    makes a path that matches nothing at all.

    Existence is never required—a task's whole job is often to create the
    file it owns. The repo_root checks fire only when the path DOES exist
    and its kind contradicts its spelling. Pass repo_root=None for the
    textual checks alone, which is what ready-set.py does to stay a pure
    function of the task files."""
    if not isinstance(entry, str):
        return f"not a string ({type(entry).__name__})"
    if not entry.strip():
        return "empty entry"
    if entry != entry.strip():
        return "leading or trailing whitespace"
    invisible = next((c for c in entry if c in "​‌‍﻿\xa0"), None)
    if invisible is not None:
        # Survives .strip(), reads as an ordinary path, matches nothing.
        # Usually arrived by paste rather than by typing.
        return f"invisible character U+{ord(invisible):04X}"
    if "\\" in entry:
        return "backslash; entries use '/' separators"
    # `*` and `?` only. Brackets are ordinary filename characters and
    # `app/[slug]/page.tsx` is the most common path shape in half the
    # frameworks a copied-in kit will meet; rejecting it would fail
    # DEC-audit with no spelling the author could fix.
    glob_char = next((c for c in entry if c in "*?"), None)
    if glob_char is not None:
        return (
            f"glob character {glob_char!r}; an entry is a literal path, and a "
            "pattern here would own nothing"
        )
    if entry.startswith("~") or entry.startswith("$"):
        return "shell expansion; entries are literal repo-relative paths"
    if entry.startswith("/"):
        return "absolute path; entries are repo-relative"
    core = entry[:-1] if entry.endswith("/") else entry
    if not core:
        return "bare '/'"
    parts = core.split("/")
    if "" in parts:
        return "empty path segment ('//')"
    if "." in parts:
        return "'.' segment; write the path without './'"
    if ".." in parts:
        return "'..' segment; entries stay inside the repo"
    if repo_root is not None:
        full = os.path.join(repo_root, core)
        if entry.endswith("/"):
            if os.path.isfile(full):
                return "ends with '/' but exists as a file"
        elif os.path.isdir(full):
            return "exists as a directory but lacks the trailing '/'"
    return None


def path_within(path, prefix):
    """True if `path` sits inside directory `prefix`, which ends in '/'.

    Containment, not overlap, and the difference is the whole reason this
    isn't paths_overlap. Overlap is symmetric because two owners collide
    whichever way you read the pair. A grant flows one way only: allowing
    `docs/generated/` says nothing about a file at `docs`, which is
    ABOVE the granted territory rather than inside it. Sharing the
    symmetric predicate here let exactly that through."""
    return path.startswith(prefix)


def in_scope(path, allowed_files, allowed_dirs, ignored):
    if path in allowed_files:
        return True
    if path in ignored:
        return True
    if path.startswith(".agent-guild/state/"):
        return True
    return any(path_within(path, prefix) for prefix in allowed_dirs)


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
