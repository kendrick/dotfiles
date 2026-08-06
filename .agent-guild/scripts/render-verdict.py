#!/usr/bin/env python3
"""Render a checker verdict JSON file to its Markdown sibling.

    .agent-guild/scripts/render-verdict.py FILE [--out PATH]

FILE is a verdict JSON file, e.g. `state/verdicts/T-001-sonnet-r0.json`.
Output defaults to the same path with `.json` swapped for `.md`; `--out`
writes to PATH instead. The rendered file follows the shape of
`.agent-guild/templates/verdict.md`.

JSON is the record of record; Markdown only ever exists as its rendering, so
this refuses to render a verdict that doesn't validate — a bad JSON file
must never produce a Markdown file that reads as trustworthy. Validation is
delegated to validate-verdict.py (loaded as a module via importlib, since a
hyphenated filename isn't import-able the normal way) rather than
reimplemented, so the two scripts can't drift apart on what "conforming"
means.

Exit codes: 0 rendered; 1 the verdict doesn't validate (validate-verdict.py's
message is forwarded verbatim); 3 infra error (schema/verdict unreadable, or
the output path can't be written).

Stdlib only, so the kit stays copy-in portable.
"""
import argparse
import importlib.util
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def _load_validator():
    spec = importlib.util.spec_from_file_location(
        "validate_verdict", os.path.join(SCRIPT_DIR, "validate-verdict.py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _cell(value):
    """Make `value` safe as one Markdown table cell: escape pipes/backslashes
    and collapse any embedded newlines so a multi-line evidence excerpt can't
    break the table structure."""
    s = " ".join(str(value).split())
    return s.replace("\\", "\\\\").replace("|", "\\|")


def render_markdown(data):
    """Pure function of the parsed, already-validated verdict `data` ->
    Markdown text, matching the shape of templates/verdict.md."""
    verdict_upper = data["verdict"].upper()

    lines = [
        "---",
        f"task: {data['task_id']}",
        f"checker: {data['checker']}",
        f"vendor: {data['vendor']}",
        f"model: {data['model']}",
        f"verdict: {verdict_upper}",
        f"checked_at: {data['timestamp']}",
    ]
    if "duration_ms" in data:
        lines.append(f"duration_ms: {data['duration_ms']}")
    if "cost_usd" in data:
        lines.append(f"cost_usd: {data['cost_usd']}")
    lines += [
        "---",
        "",
        "<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py",
        "from the verdict JSON, the record of record. Edit the JSON and",
        "re-render instead. -->",
        "",
        "## Per-clause results",
        "",
        "| clause | severity | description | evidence |",
        "| ------ | -------- | ------------ | -------- |",
    ]
    for finding in data["findings"]:
        lines.append(
            "| {} | {} | {} | {} |".format(
                _cell(finding["clause_id"]),
                _cell(finding["severity"]),
                _cell(finding["description"]),
                _cell(finding["evidence"]),
            )
        )

    if data["verdict"] == "fail":
        lines += ["", "## Diagnosis", ""]
        for finding in data["findings"]:
            lines.append(f"- **{finding['clause_id']}** ({finding['severity']}): {finding['description']}")
            lines.append(f"  evidence: {finding['evidence']}")

    lines.append("")
    return "\n".join(lines)


def default_out_path(json_path):
    root, ext = os.path.splitext(json_path)
    return root + ".md"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Validate a checker verdict JSON file, then render its Markdown sibling."
    )
    ap.add_argument("file", help="path to a verdict JSON file, e.g. state/verdicts/T-001-sonnet-r0.json")
    ap.add_argument("--out", default=None, help="output path (default: FILE with .json swapped for .md)")
    args = ap.parse_args(argv)

    validate_verdict = _load_validator()
    result = validate_verdict.validate(args.file)
    if not result["ok"]:
        sys.stderr.write(f"render-verdict: refusing to render: {result['path']}: {result['reason']}\n")
        return 3 if result["kind"] == "infra" else 1

    out_path = args.out or default_out_path(args.file)
    markdown = render_markdown(result["data"])
    try:
        out_dir = os.path.dirname(out_path)
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(markdown)
    except OSError as e:
        sys.stderr.write(f"render-verdict: cannot write {out_path}: {e}\n")
        return 3

    print(f"OK: rendered {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
