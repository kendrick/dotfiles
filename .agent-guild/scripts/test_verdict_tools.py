#!/usr/bin/env python3
"""Fixture-based tests for validate-verdict.py and render-verdict.py. No
repo state touched: every fixture is a JSON file written fresh into a temp
dir, and both scripts are run as subprocesses so these tests exercise the
real CLI contract (exit codes, stderr messages) rather than calling
internals directly.

Run: python3 .agent-guild/scripts/test_verdict_tools.py
"""
import json
import os
import subprocess
import sys
import tempfile

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
VALIDATE = os.path.join(SCRIPTS_DIR, "validate-verdict.py")
RENDER = os.path.join(SCRIPTS_DIR, "render-verdict.py")

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


def write_json(tmpdir, name, data):
    path = os.path.join(tmpdir, name)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f)
    return path


def run_validate(*argv):
    proc = subprocess.run(
        [sys.executable, VALIDATE, *argv], capture_output=True, text=True
    )
    return proc.returncode, proc.stdout, proc.stderr


def run_render(*argv):
    proc = subprocess.run(
        [sys.executable, RENDER, *argv], capture_output=True, text=True
    )
    return proc.returncode, proc.stdout, proc.stderr


PASS_VERDICT = {
    "task_id": "T-001",
    "checker": "checker-deterministic",
    "vendor": "anthropic",
    "model": "claude-haiku-4",
    "verdict": "pass",
    "findings": [],
    "timestamp": "2026-07-22T18:00:00Z",
    "duration_ms": 1200,
    "cost_usd": 0.02,
}

FAIL_VERDICT = {
    "task_id": "T-002",
    "checker": "checker-judgment",
    "vendor": "anthropic",
    "model": "claude-opus-4",
    "verdict": "fail",
    "findings": [
        {
            "clause_id": "C-1",
            "severity": "blocker",
            "description": "schema missing required field task_id",
            "evidence": ".agent-guild/schemas/verdict.schema.json:10",
        }
    ],
    "timestamp": "2026-07-22T18:05:00Z",
    "duration_ms": 4300,
    "cost_usd": 0.11,
}

# The live probe output from issue #2 — the first real call against
# --output-schema, which 400'd on the pre-fix schema ("'required' is
# required ... Missing 'duration_ms'"). Kept as a raw string, not a dict fed
# through json.dump, so the fixture is the exact bytes that round-tripped
# clean from gpt-5.6-terra, not a reformatted lookalike.
PROBE_JSON_RAW = (
    '{"task_id":"T-000","checker":"checker-judgment-codex","vendor":"openai",'
    '"model":"gpt-5.6-terra","verdict":"pass","findings":[],'
    '"timestamp":"2026-07-24T04:00:00Z","duration_ms":null,"cost_usd":null}'
)

GOLDEN_MARKDOWN = (
    "---\n"
    "task: T-002\n"
    "checker: checker-judgment\n"
    "vendor: anthropic\n"
    "model: claude-opus-4\n"
    "verdict: FAIL\n"
    "checked_at: 2026-07-22T18:05:00Z\n"
    "duration_ms: 4300\n"
    "cost_usd: 0.11\n"
    "---\n"
    "\n"
    "<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py\n"
    "from the verdict JSON, the record of record. Edit the JSON and\n"
    "re-render instead. -->\n"
    "\n"
    "## Per-clause results\n"
    "\n"
    "| clause | severity | description | evidence |\n"
    "| ------ | -------- | ------------ | -------- |\n"
    "| C-1 | blocker | schema missing required field task_id | .agent-guild/schemas/verdict.schema.json:10 |\n"
    "\n"
    "## Diagnosis\n"
    "\n"
    "- **C-1** (blocker): schema missing required field task_id\n"
    "  evidence: .agent-guild/schemas/verdict.schema.json:10\n"
)

# ------------------------------------------------------------- conforming verdicts
print("conforming verdicts")

with tempfile.TemporaryDirectory() as d:
    path = write_json(d, "pass.json", PASS_VERDICT)
    rc, out, err = run_validate(path)
    check("pass verdict: exit 0", rc == 0, f"rc={rc} err={err}")
    check("pass verdict: stdout confirms OK", out.startswith("OK:"), f"out={out!r}")

with tempfile.TemporaryDirectory() as d:
    path = write_json(d, "fail.json", FAIL_VERDICT)
    rc, out, err = run_validate(path)
    check("fail verdict with one evidence-backed finding: exit 0", rc == 0, f"rc={rc} err={err}")

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "probe.json")
    with open(path, "w", encoding="utf-8") as f:
        f.write(PROBE_JSON_RAW)
    rc, out, err = run_validate(path)
    check("issue #2 probe JSON validates clean: exit 0", rc == 0, f"rc={rc} err={err}")

# --------------------------------------------------------- strict-mode nullable fields
print("strict-mode nullable fields (duration_ms, cost_usd)")

with tempfile.TemporaryDirectory() as d:
    omits_duration = dict(PASS_VERDICT)
    del omits_duration["duration_ms"]
    path = write_json(d, "omits_duration.json", omits_duration)
    rc, out, err = run_validate(path)
    check("omitted duration_ms: nonzero exit", rc != 0, f"rc={rc}")
    check("omitted duration_ms: stderr names duration_ms", "duration_ms" in err, f"err={err!r}")

with tempfile.TemporaryDirectory() as d:
    null_duration = dict(PASS_VERDICT)
    null_duration["duration_ms"] = None
    path = write_json(d, "null_duration.json", null_duration)
    rc, out, err = run_validate(path)
    check("null duration_ms alone: exit 0", rc == 0, f"rc={rc} err={err}")

with tempfile.TemporaryDirectory() as d:
    null_cost = dict(PASS_VERDICT)
    null_cost["cost_usd"] = None
    path = write_json(d, "null_cost.json", null_cost)
    rc, out, err = run_validate(path)
    check("null cost_usd alone: exit 0", rc == 0, f"rc={rc} err={err}")

# ------------------------------------------------------------------ schema violations
print("schema violations (nonzero exit, failing path named)")

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "malformed.json")
    with open(path, "w", encoding="utf-8") as f:
        f.write("{not valid json")
    rc, out, err = run_validate(path)
    check("malformed JSON: nonzero exit", rc != 0, f"rc={rc}")
    check("malformed JSON: stderr names the file", path in err, f"err={err!r}")
    check("malformed JSON: no bare traceback", "Traceback" not in err, f"err={err!r}")

with tempfile.TemporaryDirectory() as d:
    missing_field = dict(PASS_VERDICT)
    del missing_field["checker"]
    path = write_json(d, "missing_field.json", missing_field)
    rc, out, err = run_validate(path)
    check("missing required field: nonzero exit", rc != 0, f"rc={rc}")
    check("missing required field: stderr names the field", "checker" in err, f"err={err!r}")

with tempfile.TemporaryDirectory() as d:
    mistyped_field = dict(PASS_VERDICT)
    mistyped_field["task_id"] = 1
    path = write_json(d, "mistyped_field.json", mistyped_field)
    rc, out, err = run_validate(path)
    check("mistyped required field: nonzero exit", rc != 0, f"rc={rc}")
    check("mistyped required field: stderr names the field", "task_id" in err, f"err={err!r}")

with tempfile.TemporaryDirectory() as d:
    bad_enum = dict(PASS_VERDICT)
    bad_enum["verdict"] = "maybe"
    path = write_json(d, "bad_enum.json", bad_enum)
    rc, out, err = run_validate(path)
    check("bad enum value: nonzero exit", rc != 0, f"rc={rc}")
    check("bad enum value: stderr names the field", "verdict" in err, f"err={err!r}")

# --------------------------------------------------------------- semantic violations
print("semantic violations (nonzero exit, failing path named)")

with tempfile.TemporaryDirectory() as d:
    fail_no_findings = dict(PASS_VERDICT)
    fail_no_findings["task_id"] = "T-003"
    fail_no_findings["verdict"] = "fail"
    fail_no_findings["findings"] = []
    path = write_json(d, "fail_no_findings.json", fail_no_findings)
    rc, out, err = run_validate(path)
    check("fail with zero findings: nonzero exit", rc != 0, f"rc={rc}")
    check("fail with zero findings: stderr names findings", "findings" in err, f"err={err!r}")

with tempfile.TemporaryDirectory() as d:
    no_evidence = json.loads(json.dumps(FAIL_VERDICT))
    no_evidence["findings"][0]["evidence"] = ""
    path = write_json(d, "no_evidence.json", no_evidence)
    rc, out, err = run_validate(path)
    check("finding without evidence: nonzero exit", rc != 0, f"rc={rc}")
    check(
        "finding without evidence: stderr names findings[0].evidence",
        "findings[0].evidence" in err,
        f"err={err!r}",
    )

# --------------------------------------------------------------------------- render
print("render")

with tempfile.TemporaryDirectory() as d:
    json_path = write_json(d, "T-002-opus-r0.json", FAIL_VERDICT)
    rc, out, err = run_render(json_path)
    check("golden render: exit 0", rc == 0, f"rc={rc} err={err}")
    md_path = os.path.join(d, "T-002-opus-r0.md")
    check("golden render: default output path used", os.path.exists(md_path))
    with open(md_path, encoding="utf-8") as f:
        rendered = f.read()
    check("golden render: exact Markdown match", rendered == GOLDEN_MARKDOWN, f"got:\n{rendered!r}")

with tempfile.TemporaryDirectory() as d:
    bad_enum = dict(PASS_VERDICT)
    bad_enum["verdict"] = "maybe"
    json_path = write_json(d, "bad.json", bad_enum)
    rc, out, err = run_render(json_path)
    check("render refuses a non-conforming verdict: nonzero exit", rc != 0, f"rc={rc}")
    check(
        "render refuses a non-conforming verdict: no .md written",
        not os.path.exists(os.path.join(d, "bad.md")),
    )

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
