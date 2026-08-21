#!/usr/bin/env python3
"""Hold a constitution clause's declared baseline to what its check actually
does against the CURRENT working tree.

A clause may carry `- **baseline**: red | green` alongside its
`- **check**:` line. Red means the check is expected to FAIL against the
tree as the job finds it—the clause asserts a property the job hasn't built
yet. Green means expected to PASS—the clause forbids something, or guards a
suite that already passes. This script runs every clause whose check
classifies as a script invocation, against the tree at --repo-root right
now, and holds the exit code to the declaration:

    .agent-guild/scripts/check-baselines.py [state-dir] [--repo-root DIR]
                                             [--timeout SECONDS] [--dry-run]

STATE defaults to `.agent-guild/state`, matching check-job-spec.py.
`--repo-root` (default `.`) is the cwd every check runs in.

Meaningful before work begins, at Phase 0 / CON-audit r0: a red clause
whose check already exits 0 is #141's own defect in miniature—a check that
passes on the untouched tree proves nothing once a worker builds toward
it—caught mechanically here instead of by an auditor reading the
constitution by eye. A green clause whose check exits nonzero is a broken
invocation, caught before any worker is ever dispatched against it. Run
again after workers have built, a red clause may legitimately have turned
green by then; the auditor reading the report knows which phase it's
reading, this script doesn't need to.

WARNING: this script executes arbitrary shell text authored by whoever
wrote the constitution's `- **check**:` line, unsandboxed, against the tree
at --repo-root. It exists to be run by a human or by the auditor from their
own session—never wired into a hook or CI job that runs against a real
constitution unattended.

--dry-run classifies every clause and prints its disposition without
executing anything; always exits 0.

Stdlib only, so the kit stays copy-in portable. Loads `parse_constitution`
and `classify_check_text` from check-job-spec.py, in this script's own
directory, via the `_load_module` importlib idiom (see that script's own
docstring)—the same parser the constitution's other consumers use, not a
lookalike that could read a `- **baseline**:` field differently than the
document's own author meant it. The `baseline` field itself is read
straight off `Clause.block_text` with a small regex here rather than
through the `Clause.baseline` attribute R19 added, so this script still
runs against a payload whose check-job-spec.py predates the field—hand-
refreshed kits mix vintages (#183), and a crash here would read as "the
baselines are fine" to anyone who only saw the audit go quiet.

Exit codes: 1 if any clause's check contradicts its declared baseline (a
proven violation outranks an unproven one); else 3 if any check could not
be run at all (an invocation exiting the kit's own could-not-run code, a
timeout, a baseline value that's neither `red` nor `green`, or infra
failure before any clause ran—the import failed, or state/constitution.md
couldn't be read); else 0. A baseline value outside {red, green} is
defense in depth, not the real gate: check-job-spec.py's own linter is
what's meant to fail a constitution shaped that way before this script
ever sees it. --dry-run always exits 0.
"""
import argparse
import importlib.util
import os
import re
import subprocess
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


# Same per-line field shape check-job-spec.py's CLAUSE_FIELD_RE uses,
# filtered here to just the `baseline` field. Reading it straight off
# block_text keeps this script honest against whatever check-job-spec.py's
# own parser considers a clause block, rather than trusting a second parse
# of the same text to agree.
FIELD_LINE_RE = re.compile(r"^- \*\*([a-zA-Z ]+)\*\*:\s?(.*)$")


def clause_baseline(clause):
    """The clause's declared baseline, lowercased and stripped—None if the
    clause carries no `- **baseline**:` line at all. First matching line
    wins, mirroring how parse_constitution reads every other field."""
    for line in clause.block_text.split("\n"):
        m = FIELD_LINE_RE.match(line.strip())
        if m and m.group(1).strip().lower() == "baseline":
            return m.group(2).strip().lower()
    return None


def run_check(invocation, repo_root, timeout):
    """("ok" | "timeout" | "error", returncode). returncode is None unless
    status is "ok".

    Deliberately `bash -c <invocation>` with nothing wrapped around it,
    never check-build.sh: a clause's check text is frequently ALREADY a
    check-build.sh invocation, so wrapping it a second time would
    double-log to state/log/ and hand the tree a different command than
    the one the constitution actually names."""
    try:
        proc = subprocess.run(
            ["bash", "-c", invocation],
            cwd=repo_root, capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return "timeout", None
    except OSError:
        return "error", None
    return "ok", proc.returncode


def clause_sort_key(cid):
    return int(cid[2:])


def evaluate(clauses, classify_check_text, repo_root, timeout, dry_run):
    """Walk every clause in id order, classify it, and either run its check
    or record why it was skipped. Returns a dict main() renders into
    output—kept separate from printing so the disposition logic reads (and
    is testable) without going through a subprocess.

    No first-wins short-circuit: a baseline sweep is a report on the whole
    constitution, not a gate deciding a single dispatch the way
    check-job-spec.py's rules are, so every applicable clause runs even
    after the first violation is already known.
    """
    result = {
        "dispositions": [],   # [(cid, label, detail)], clause order—for --dry-run
        "violations": [],     # [(cid, message)]
        "could_not_run": [],  # [(cid, message)]
        "ran_red": 0,
        "ran_green": 0,
        "skipped_judgment": 0,
        "skipped_no_baseline": 0,
        "skipped_unclassifiable": 0,
    }
    for cid in sorted(clauses, key=clause_sort_key):
        clause = clauses[cid]
        kind, _ = classify_check_text(clause.check_text)

        if kind == "judgment":
            result["skipped_judgment"] += 1
            result["dispositions"].append((cid, "skip", "judgment"))
            continue
        if kind is None:
            # Neither a script invocation nor checker-judgment:. R4
            # upstream in check-job-spec.py already fails a constitution
            # shaped this way, so a real DEC-audited job never reaches
            # this branch—kept as its own bucket, rather than folded into
            # judgment or no-baseline, so a caller can tell "nothing here"
            # from "the paperwork itself is broken."
            result["skipped_unclassifiable"] += 1
            result["dispositions"].append((cid, "skip", "unclassifiable"))
            continue

        baseline = clause_baseline(clause)
        if baseline is None:
            result["skipped_no_baseline"] += 1
            result["dispositions"].append((cid, "skip", "no-baseline"))
            continue
        if baseline not in ("red", "green"):
            msg = f"could not run—baseline is {baseline!r}, neither red nor green"
            result["could_not_run"].append((cid, msg))
            result["dispositions"].append(
                (cid, "could not run", f"baseline {baseline!r} is neither red nor green")
            )
            continue

        if dry_run:
            if baseline == "green":
                result["ran_green"] += 1
            else:
                result["ran_red"] += 1
            result["dispositions"].append((cid, "would run", f"baseline {baseline}"))
            continue

        status, rc = run_check(clause.check_text, repo_root, timeout)
        if status == "timeout":
            result["could_not_run"].append((cid, f"could not run—its check timed out after {timeout}s"))
            continue
        if status == "error":
            result["could_not_run"].append((cid, "could not run—could not start the check"))
            continue
        # Exit 3 is the kit's own "the check did not run" convention (see
        # check-build.sh, check-job-spec.py)—it proves nothing about
        # redness or greenness either way, so it's could-not-run in BOTH
        # directions rather than counted as a violation in either.
        if rc == 3:
            result["could_not_run"].append((cid, "could not run—its check exited 3"))
            continue

        if baseline == "green":
            result["ran_green"] += 1
            if rc != 0:
                result["violations"].append((cid, f"baseline green but its check exited {rc}"))
        else:
            result["ran_red"] += 1
            if rc == 0:
                result["violations"].append(
                    (cid, "baseline red but its check exited 0—the property it names already holds")
                )
    return result


def render_summary(result, dry_run):
    ran_total = result["ran_red"] + result["ran_green"]
    skipped_total = (
        result["skipped_judgment"] + result["skipped_no_baseline"] + result["skipped_unclassifiable"]
    )
    verb = "would run" if dry_run else "ran"
    parts = [f"{verb} {ran_total} ({result['ran_red']} red, {result['ran_green']} green)"]

    skip_bits = [f"{result['skipped_judgment']} judgment", f"{result['skipped_no_baseline']} no-baseline"]
    if result["skipped_unclassifiable"]:
        skip_bits.append(f"{result['skipped_unclassifiable']} unclassifiable")
    parts.append(f"skipped {skipped_total} ({', '.join(skip_bits)})")

    if result["could_not_run"]:
        parts.append(f"{len(result['could_not_run'])} could-not-run")

    return "check-baselines: " + ", ".join(parts)


def main():
    ap = argparse.ArgumentParser(
        description=(
            "Run each constitution clause's check against the current "
            "working tree and hold the exit code to the clause's declared "
            "baseline (red/green)."
        )
    )
    ap.add_argument("state", nargs="?", default=".agent-guild/state", help="path to the state directory")
    ap.add_argument("--repo-root", default=".", help="root the checks run in (default: cwd)")
    ap.add_argument("--timeout", type=int, default=300, help="per-check timeout in seconds (default: 300)")
    ap.add_argument(
        "--dry-run", action="store_true",
        help="classify every clause and print dispositions; execute nothing",
    )
    args = ap.parse_args()

    try:
        job_spec = _load_module("check_job_spec_for_baselines", "check-job-spec.py")
    except Exception as e:
        sys.stderr.write(f"check-baselines: cannot import check-job-spec.py: {e}\n")
        return 3

    constitution_path = os.path.join(args.state, "constitution.md")
    try:
        with open(constitution_path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        sys.stderr.write(f"check-baselines: cannot read {constitution_path}: {e}\n")
        return 3

    clauses = job_spec.parse_constitution(text)
    result = evaluate(clauses, job_spec.classify_check_text, args.repo_root, args.timeout, args.dry_run)

    if args.dry_run:
        for cid, label, detail in result["dispositions"]:
            print(f"check-baselines: {cid} {label} ({detail})")
        print(render_summary(result, dry_run=True))
        return 0

    for cid, msg in result["violations"]:
        sys.stderr.write(f"check-baselines: {cid} {msg}\n")
    for cid, msg in result["could_not_run"]:
        sys.stderr.write(f"check-baselines: {cid} {msg}\n")

    print(render_summary(result, dry_run=False))

    if result["violations"]:
        return 1
    if result["could_not_run"]:
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
