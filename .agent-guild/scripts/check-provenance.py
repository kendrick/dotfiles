#!/usr/bin/env python3
"""Validate the provenance header the `/job` intake skill writes at the top of
.agent-guild/state/spec.md.

The header is flat-key YAML frontmatter:

    ---
    source: github-issue | file | url
    ref: <owner/repo#N | path | URL>
    issue: <N>                # required when source is github-issue; absent otherwise
    title: <issue title>      # required when source is github-issue
    fetched_at: <ISO-8601 UTC, e.g. 2026-07-14T18:00:00Z>
    ---

    .agent-guild/scripts/check-provenance.py <spec.md> [--issue N]
    .agent-guild/scripts/check-provenance.py --self-test

Exit 0 only when: `source`, `ref`, `fetched_at` are present; `source` is one of
the three allowed values; `fetched_at` parses as ISO-8601 UTC; when
`source: github-issue`, `issue` and `title` are present and `issue` is
consistent with the `#N` in `ref`; and, with `--issue N`, the recorded `issue`
equals N.

On failure, exits nonzero and prints a diagnostic line to stderr naming the
first violated rule (e.g. `provenance: fetched_at missing`)—a bare nonzero
exit with no message is itself a defect.

--self-test runs an embedded fixture battery (temp files, nothing checked
into the repo) and exits 0 only if every fixture behaves as documented,
including that each failing fixture's diagnostic names the rule it violates.

Exit codes: 0 valid; 1 the header violates a rule (content failure); 3
usage/infra error (bad args, file unreadable, no frontmatter at all).

Stdlib only, so the kit stays copy-in portable. Deliberately standalone: does
not import from .agent-guild/hooks/, even though _lib.py has a similar tiny
frontmatter parser to crib from.
"""
import argparse
import re
import subprocess
import sys
import tempfile
from datetime import datetime

ALLOWED_SOURCES = ("github-issue", "file", "url")

# Matches the example format exactly (2026-07-14T18:00:00Z), with optional
# fractional seconds. Requires the trailing Z: the contract calls for
# ISO-8601 *UTC*, not any offset.
ISO_UTC_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$")

REF_ISSUE_RE = re.compile(r"#(\d+)")


def parse_frontmatter(text):
    """Parse the leading `--- ... ---` block into a flat {key: value} dict.
    Returns None if the file has no frontmatter header at all (no leading
    `---` line, or the block is never closed). Deliberately minimal—this
    contract only has scalar keys, no lists or nesting."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    fm = {}
    closed = False
    for line in lines[1:]:
        if line.strip() == "---":
            closed = True
            break
        m = re.match(r"^([A-Za-z0-9_]+):\s*(.*)$", line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        fm[key] = val
    if not closed:
        return None
    return fm


def parse_iso_utc(s):
    """Return a datetime if s matches ISO-8601 UTC, else None."""
    if not ISO_UTC_RE.match(s):
        return None
    body = s[:-1]  # strip trailing Z
    fmt = "%Y-%m-%dT%H:%M:%S.%f" if "." in body else "%Y-%m-%dT%H:%M:%S"
    try:
        return datetime.strptime(body, fmt)
    except ValueError:
        return None


def validate(fm, issue_arg):
    """Check a parsed frontmatter dict against the contract. Returns
    (ok, message). message is None on success, else the diagnostic line for
    the FIRST rule violated—callers should stop at the first failure rather
    than pile on unrelated complaints."""
    source = (fm.get("source") or "").strip()
    ref = (fm.get("ref") or "").strip()
    fetched_at = (fm.get("fetched_at") or "").strip()
    issue = (fm.get("issue") or "").strip()
    title = (fm.get("title") or "").strip()

    if not source:
        return False, "provenance: source missing"
    if not ref:
        return False, "provenance: ref missing"
    if not fetched_at:
        return False, "provenance: fetched_at missing"

    if source not in ALLOWED_SOURCES:
        return False, (
            f"provenance: source invalid: {source!r} "
            f"(must be one of: {', '.join(ALLOWED_SOURCES)})"
        )

    if parse_iso_utc(fetched_at) is None:
        return False, (
            f"provenance: fetched_at malformed: {fetched_at!r} "
            "(expected ISO-8601 UTC, e.g. 2026-07-14T18:00:00Z)"
        )

    if source == "github-issue":
        if not issue:
            return False, "provenance: issue missing (required when source: github-issue)"
        if not title:
            return False, "provenance: title missing (required when source: github-issue)"
        if not issue.isdigit():
            return False, f"provenance: issue not numeric: {issue!r}"
        ref_m = REF_ISSUE_RE.search(ref)
        if not ref_m:
            return False, "provenance: ref missing #N (required when source: github-issue)"
        if ref_m.group(1) != issue:
            return False, (
                f"provenance: issue/ref mismatch: issue={issue} "
                f"but ref has #{ref_m.group(1)}"
            )

    if issue_arg is not None:
        if issue != str(issue_arg):
            return False, (
                f"provenance: --issue mismatch: recorded issue={issue or '(none)'} "
                f"but --issue {issue_arg} was given"
            )

    return True, None


def check_file(path, issue_arg):
    """Read, parse, and validate a spec file. Returns a process exit code,
    printing the diagnostic (failure) or an OK line (success) as a side
    effect—mirrors the other .agent-guild/scripts/check-*.py CLIs."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        sys.stderr.write(f"provenance: cannot read {path}: {e}\n")
        return 3

    fm = parse_frontmatter(text)
    if fm is None:
        sys.stderr.write("provenance: no YAML frontmatter header found\n")
        return 3

    ok, message = validate(fm, issue_arg)
    if not ok:
        sys.stderr.write(message + "\n")
        return 1
    print(f"OK: provenance header valid ({path})")
    return 0


# --- self-test --------------------------------------------------------------

_VALID = """---
source: github-issue
ref: acme/widgets#42
issue: 42
title: Widgets sometimes explode
fetched_at: 2026-07-14T18:00:00Z
---

# Widgets sometimes explode

body text here.
"""

_MISSING_FETCHED_AT = """---
source: github-issue
ref: acme/widgets#42
issue: 42
title: Widgets sometimes explode
---

body.
"""

_MALFORMED_TIMESTAMP = """---
source: github-issue
ref: acme/widgets#42
issue: 42
title: Widgets sometimes explode
fetched_at: yesterday
---

body.
"""

_MISSING_ISSUE = """---
source: github-issue
ref: acme/widgets#42
title: Widgets sometimes explode
fetched_at: 2026-07-14T18:00:00Z
---

body.
"""

# Fixtures: (name, content, extra_argv, expect_ok, needle-required-on-failure)
_FIXTURES = [
    ("valid github-issue header", _VALID, [], True, None),
    ("missing fetched_at", _MISSING_FETCHED_AT, [], False, "fetched_at missing"),
    ("malformed timestamp", _MALFORMED_TIMESTAMP, [], False, "fetched_at malformed"),
    ("github-issue without issue", _MISSING_ISSUE, [], False, "issue missing"),
    ("--issue N mismatch", _VALID, ["--issue", "99"], False, "--issue mismatch"),
]


def self_test():
    failures = []
    for name, content, extra_argv, expect_ok, needle in _FIXTURES:
        with tempfile.NamedTemporaryFile(
            "w", suffix=".md", prefix="check-provenance-fixture-", delete=False
        ) as f:
            f.write(content)
            tmp_path = f.name

        proc = subprocess.run(
            [sys.executable, __file__, tmp_path, *extra_argv],
            capture_output=True,
            text=True,
        )
        got_ok = proc.returncode == 0
        combined = proc.stdout + proc.stderr

        if got_ok != expect_ok:
            failures.append(
                f"{name}: expected {'pass' if expect_ok else 'fail'}, got "
                f"exit {proc.returncode} (stdout={proc.stdout!r} stderr={proc.stderr!r})"
            )
            continue

        if not expect_ok:
            if not combined.strip():
                failures.append(f"{name}: failed with NO diagnostic message at all")
                continue
            if "provenance:" not in combined:
                failures.append(
                    f"{name}: diagnostic did not use the 'provenance:' prefix "
                    f"(got {combined!r})"
                )
                continue
            if needle not in combined:
                failures.append(
                    f"{name}: diagnostic did not name the violated rule "
                    f"(expected {needle!r} in {combined!r})"
                )
                continue

    if failures:
        sys.stderr.write("SELF-TEST FAILED:\n")
        for m in failures:
            sys.stderr.write(f"  - {m}\n")
        return 1

    print(f"OK: self-test passed ({len(_FIXTURES)} fixtures)")
    return 0


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("spec", nargs="?", help="path to spec.md")
    ap.add_argument("--issue", type=int, default=None)
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args()

    if args.self_test:
        return self_test()

    if not args.spec:
        sys.stderr.write("usage: check-provenance.py <spec.md> [--issue N]\n")
        return 3

    return check_file(args.spec, args.issue)


if __name__ == "__main__":
    sys.exit(main())
