#!/usr/bin/env python3
"""Fixture-based tests for ledger-append.py. No repo state touched: every
ledger lives in a fresh temp dir, and the script runs as a subprocess so
these tests exercise the real CLI contract (exit codes, stderr messages,
file contents) rather than calling internals directly — matching
test_verdict_tools.py's approach for validate-verdict.py.

Run: python3 .agent-guild/scripts/test_ledger_append.py
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
LEDGER_APPEND = os.path.join(SCRIPTS_DIR, "ledger-append.py")
SCHEMA_PATH = os.path.normpath(
    os.path.join(SCRIPTS_DIR, "..", "schemas", "vendor-call.schema.json")
)

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


def run(*argv, cwd=None):
    proc = subprocess.run(
        [sys.executable, LEDGER_APPEND, *argv],
        capture_output=True,
        text=True,
        cwd=cwd,
    )
    return proc.returncode, proc.stdout, proc.stderr


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines()


def first_record(ledger):
    return json.loads(read_lines(ledger)[0])


def write_spec(root, ref):
    """Write a provenance-header spec.md at <root>/.agent-guild/state/spec.md,
    matching the frontmatter shape derive_job() parses. Job derivation reads
    spec.md relative to cwd, so this only means anything when the caller
    also runs the script with cwd=root."""
    state_dir = os.path.join(root, ".agent-guild", "state")
    os.makedirs(state_dir, exist_ok=True)
    spec_path = os.path.join(state_dir, "spec.md")
    with open(spec_path, "w", encoding="utf-8") as f:
        f.write(f"---\nref: {ref}\nsource: file\n---\n\n# Spec\n")
    return spec_path


BASE_ARGS = [
    "--task-id", "T-007",
    "--vendor", "codex",
    "--model", "gpt-5.5",
    "--started-at", "2026-07-22T18:00:00Z",
    "--duration-ms", "41200",
    "--exit-code", "0",
]

# ---------------------------------------------------------------- happy path
print("happy path")

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc, out, err = run(
        *BASE_ARGS,
        "--tokens-in", "1200",
        "--tokens-out", "340",
        "--cost-usd", "0.02",
        "--artifacts", "a.py", "b.py",
        "--quota-event",
        "--ledger", ledger,
    )
    check("happy path: exit 0", rc == 0, f"rc={rc} err={err}")
    lines = read_lines(ledger)
    check("happy path: one line written", len(lines) == 1, f"lines={lines}")
    record = json.loads(lines[0])
    check("happy path: task_id recorded", record["task_id"] == "T-007", record)
    check("happy path: tokens_in recorded", record["tokens_in"] == 1200, record)
    check("happy path: tokens_out recorded", record["tokens_out"] == 340, record)
    check("happy path: cost_usd recorded", record["cost_usd"] == 0.02, record)
    check("happy path: artifacts recorded", record["artifacts"] == ["a.py", "b.py"], record)
    check("happy path: quota_event true", record["quota_event"] is True, record)
    check("happy path: brief_tokens null (no --brief)", record["brief_tokens"] is None, record)
    check("happy path: tokenizer null (no --brief)", record["tokenizer"] is None, record)

# --------------------------------------------------------- nulls for omitted
print("nulls for omitted tokens/cost")

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc, out, err = run(*BASE_ARGS, "--artifacts", "--ledger", ledger)
    check("omitted tokens/cost: exit 0", rc == 0, f"rc={rc} err={err}")
    record = json.loads(read_lines(ledger)[0])
    check("omitted tokens_in is null", record["tokens_in"] is None, record)
    check("omitted tokens_out is null", record["tokens_out"] is None, record)
    check("omitted cost_usd is null", record["cost_usd"] is None, record)
    check("empty --artifacts is []", record["artifacts"] == [], record)
    check("quota_event defaults false", record["quota_event"] is False, record)

# --------------------------------------------------------------------- brief
print("--brief computes bytes/4")

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    brief_path = os.path.join(d, "brief.md")
    with open(brief_path, "w", encoding="utf-8") as f:
        f.write("x" * 40)  # 40 bytes -> 40 // 4 == 10 tokens
    rc, out, err = run(*BASE_ARGS, "--artifacts", "--brief", brief_path, "--ledger", ledger)
    check("--brief: exit 0", rc == 0, f"rc={rc} err={err}")
    record = json.loads(read_lines(ledger)[0])
    check("--brief: brief_tokens is bytes/4", record["brief_tokens"] == 10, record)
    check("--brief: tokenizer recorded", record["tokenizer"] == "heuristic-bytes/4", record)

# ------------------------------------------------- validation rejection cases
print("validation rejection (nonzero exit, file untouched)")

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    args_no_task_id = [a for a in BASE_ARGS if a not in ("--task-id", "T-007")]
    rc, out, err = run(*args_no_task_id, "--artifacts", "--ledger", ledger)
    check("missing required field (--task-id): nonzero exit", rc != 0, f"rc={rc}")
    check("missing required field: file untouched", not os.path.exists(ledger))

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc, out, err = run(*BASE_ARGS, "--duration-ms", "not-an-int", "--artifacts", "--ledger", ledger)
    check("wrong type (--duration-ms): nonzero exit", rc != 0, f"rc={rc}")
    check("wrong type: file untouched", not os.path.exists(ledger))

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc, out, err = run(*BASE_ARGS, "--ledger", ledger)  # no --artifacts at all
    check("artifacts absent: nonzero exit", rc != 0, f"rc={rc}")
    check("artifacts absent: file untouched", not os.path.exists(ledger))

# ---------------------------------------------------------- resilience: reader
print("resilience: reader identifies a malformed middle line by number, still parses the rest")

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    good_first = json.dumps({"task_id": "T-001", "note": "fine"})
    good_last = json.dumps({"task_id": "T-002", "note": "also fine"})
    with open(ledger, "w", encoding="utf-8") as f:
        f.write(good_first + "\n")
        f.write("{not valid json, killed mid-write\n")
        f.write(good_last + "\n")

    valid_records = []
    malformed_line_numbers = []
    with open(ledger, encoding="utf-8") as f:
        for lineno, raw in enumerate(f, start=1):
            raw = raw.rstrip("\n")
            if not raw:
                continue
            try:
                valid_records.append(json.loads(raw))
            except json.JSONDecodeError:
                malformed_line_numbers.append(lineno)

    check("reader: two valid records parsed", len(valid_records) == 2, valid_records)
    check("reader: valid records are the right ones", valid_records == [json.loads(good_first), json.loads(good_last)], valid_records)
    check("reader: malformed line identified by number (line 2)", malformed_line_numbers == [2], malformed_line_numbers)

# -------------------------------------------------- resilience: append past it
print("resilience: append succeeds cleanly onto a ledger with a malformed line")

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    with open(ledger, "w", encoding="utf-8") as f:
        f.write("{not valid json, killed mid-write\n")

    rc, out, err = run(*BASE_ARGS, "--artifacts", "clean.py", "--ledger", ledger)
    check("append past malformed line: exit 0", rc == 0, f"rc={rc} err={err}")

    lines = read_lines(ledger)
    check("append past malformed line: original malformed line untouched", lines[0] == "{not valid json, killed mid-write", lines)
    check("append past malformed line: exactly one new line appended", len(lines) == 2, lines)
    appended = json.loads(lines[1])
    check("append past malformed line: appended line parses and is correct", appended["artifacts"] == ["clean.py"], appended)

# ------------------------------------------------------- two sequential appends
print("two sequential appends yield two independently parseable lines")

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc1, out1, err1 = run(*BASE_ARGS, "--task-id", "T-101", "--artifacts", "--ledger", ledger)
    rc2, out2, err2 = run(*BASE_ARGS, "--task-id", "T-102", "--artifacts", "--ledger", ledger)
    check("first append: exit 0", rc1 == 0, f"rc={rc1} err={err1}")
    check("second append: exit 0", rc2 == 0, f"rc={rc2} err={err2}")

    lines = read_lines(ledger)
    check("two lines total", len(lines) == 2, lines)
    rec1 = json.loads(lines[0])
    rec2 = json.loads(lines[1])
    check("first line is T-101", rec1["task_id"] == "T-101", rec1)
    check("second line is T-102", rec2["task_id"] == "T-102", rec2)

# --------------------------------------------------- artifact path relativizing
print("artifacts: under-root absolute becomes relative, others untouched")

with tempfile.TemporaryDirectory() as d:
    # realpath: on macOS d starts under the /var symlink, but the subprocess's
    # os.getcwd() (the root the rewrite relativizes against) reports the
    # resolved /private/var path — comparing against the unresolved form
    # would make an under-root path look like it resolves outside the root.
    d = os.path.realpath(d)
    ledger = os.path.join(d, "vendor-calls.jsonl")
    under_root = os.path.join(d, "sub", "a.py")
    rc, out, err = run(
        *BASE_ARGS, "--artifacts", under_root, "--ledger", ledger, cwd=d
    )
    record = first_record(ledger) if rc == 0 and os.path.exists(ledger) else None
    check(
        "artifacts: under-root absolute becomes relative",
        record is not None and record.get("artifacts") == [os.path.join("sub", "a.py")],
        f"rc={rc} err={err} record={record}",
    )

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    # "./sub/a.py", not "sub/a.py": a normalize-then-relativize pass would
    # collapse the leading "./" and still land on the right file, which
    # would let this case pass even against code that dropped the
    # already-relative guard and ran every value through the general path.
    # The leading "./" only survives if relative values are truly skipped.
    rc, out, err = run(
        *BASE_ARGS, "--artifacts", "./sub/a.py", "--ledger", ledger, cwd=d
    )
    record = first_record(ledger) if rc == 0 and os.path.exists(ledger) else None
    check(
        "artifacts: already-relative path unchanged",
        record is not None and record.get("artifacts") == ["./sub/a.py"],
        f"rc={rc} err={err} record={record}",
    )

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    with tempfile.TemporaryDirectory() as outside:
        outside_path = os.path.join(outside, "b.py")
        rc, out, err = run(
            *BASE_ARGS, "--artifacts", outside_path, "--ledger", ledger, cwd=d
        )
        record = first_record(ledger) if rc == 0 and os.path.exists(ledger) else None
        artifacts = record.get("artifacts") if record else None
        check(
            "artifacts: outside-root absolute is byte-identical",
            artifacts == [outside_path],
            f"rc={rc} err={err} record={record}",
        )
        check(
            "artifacts: outside-root absolute carries no ../ chain",
            artifacts is not None and "../" not in artifacts[0],
            artifacts,
        )

# ------------------------------------------------------------------- job field
print("job: derivation, override, absence, legacy tolerance, distinguishability, schema")

with tempfile.TemporaryDirectory() as d:
    write_spec(d, "kendrick/agent-guild#117")
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc, out, err = run(*BASE_ARGS, "--artifacts", "--ledger", ledger, cwd=d)
    record = first_record(ledger) if rc == 0 and os.path.exists(ledger) else None
    check(
        "job: derived from provenance ref",
        record is not None and record.get("job") == "kendrick/agent-guild#117",
        f"rc={rc} err={err} record={record}",
    )

with tempfile.TemporaryDirectory() as d:
    write_spec(d, "kendrick/agent-guild#117")
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc, out, err = run(
        *BASE_ARGS, "--artifacts", "--ledger", ledger, "--job", "override/repo#9", cwd=d
    )
    record = first_record(ledger) if rc == 0 and os.path.exists(ledger) else None
    check(
        "job: flag overrides provenance",
        record is not None and record.get("job") == "override/repo#9",
        f"rc={rc} err={err} record={record}",
    )

with tempfile.TemporaryDirectory() as d:
    # No .agent-guild/state/spec.md anywhere under d. This repo's own root
    # (the suite's default cwd) has a real spec.md, so a fixture leaning on
    # that would pass without proving the no-provenance path works at all —
    # the temp dir with cwd pinned to it is the only honest way to exercise it.
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc, out, err = run(*BASE_ARGS, "--artifacts", "--ledger", ledger, cwd=d)
    record = first_record(ledger) if rc == 0 and os.path.exists(ledger) else None
    check(
        "job: absent when no spec exists",
        rc == 0 and record is not None and "job" not in record,
        f"rc={rc} err={err} record={record}",
    )

# Loaded via importlib rather than the subprocess route the rest of this file
# uses, because this case tests schema_violation()'s own tolerance for a
# hand-built legacy dict — not the CLI's derivation behavior, which the three
# cases above already cover. The constitution's C-4 check uses the identical
# load_schema()/schema_violation() import for the same reason.
_module_spec = importlib.util.spec_from_file_location("ledger_append", LEDGER_APPEND)
_ledger_append = importlib.util.module_from_spec(_module_spec)
_module_spec.loader.exec_module(_ledger_append)

LEGACY_ROW = {
    "task_id": "T-001",
    "vendor": "codex",
    "model": "gpt-5.5",
    "started_at": "2026-07-22T18:00:00Z",
    "duration_ms": 41200,
    "exit_code": 0,
    "tokens_in": None,
    "tokens_out": None,
    "cost_usd": None,
    "brief_tokens": None,
    "tokenizer": None,
    "artifacts": [],
    "quota_event": False,
    # No "job" key: the exact shape of every row written before #117 added
    # the field.
}
_amended_schema = _ledger_append.load_schema()
_violation = _ledger_append.schema_violation(LEGACY_ROW, _amended_schema)
check("job: legacy row without the key still validates", _violation is None, _violation)

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    rc1, out1, err1 = run(
        *BASE_ARGS, "--artifacts", "--ledger", ledger, "--job", "org/repo#1", cwd=d
    )
    rc2, out2, err2 = run(
        *BASE_ARGS, "--artifacts", "--ledger", ledger, "--job", "org/repo#2", cwd=d
    )
    lines = read_lines(ledger) if os.path.exists(ledger) else []
    rec1 = json.loads(lines[0]) if rc1 == 0 and len(lines) > 0 else None
    rec2 = json.loads(lines[1]) if rc2 == 0 and len(lines) > 1 else None
    check(
        "job: two jobs are distinguishable",
        rec1 is not None
        and rec2 is not None
        and rec1["task_id"] == rec2["task_id"] == "T-007"
        # Same --started-at on both calls (BASE_ARGS is shared, unmodified):
        # distinguishability has to come from job content, not from an
        # incidental timestamp difference between the two runs.
        and rec1["started_at"] == rec2["started_at"]
        and rec1["job"] == "org/repo#1"
        and rec2["job"] == "org/repo#2"
        and rec1["job"] != rec2["job"],
        f"rc1={rc1} rc2={rc2} rec1={rec1} rec2={rec2}",
    )

with open(SCHEMA_PATH, encoding="utf-8") as f:
    _schema = json.load(f)
_job_property = _schema.get("properties", {}).get("job")
check(
    "job: schema keeps the field optional",
    _job_property is not None
    and _job_property.get("type") == "string"
    and "job" not in _schema.get("required", []),
    _job_property,
)

# ------------------------------------------------ attempts and discarded (#116)
print("attempts and discarded")

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    discarded_entry = {
        "reason": "malformed JSON",
        "duration_ms": 900,
        "exit_code": 1,
        "tokens_in": 50,
        "tokens_out": None,
    }
    rc, out, err = run(
        *BASE_ARGS,
        "--artifacts",
        "--attempts", "2",
        "--discarded", json.dumps(discarded_entry),
        "--ledger", ledger,
    )
    check("attempts+discarded: exit 0", rc == 0, f"rc={rc} err={err}")
    record = first_record(ledger) if rc == 0 and os.path.exists(ledger) else None
    check(
        "attempts+discarded: attempts read back intact",
        record is not None and record.get("attempts") == 2,
        record,
    )
    check(
        "attempts+discarded: discarded entry reads back intact",
        record is not None and record.get("discarded") == [discarded_entry],
        record,
    )

with tempfile.TemporaryDirectory() as d:
    ledger = os.path.join(d, "vendor-calls.jsonl")
    discarded_no_usage = {
        "reason": "vendor reported no usage",
        "duration_ms": 500,
        "exit_code": 1,
        "tokens_in": None,
        "tokens_out": None,
    }
    rc, out, err = run(
        *BASE_ARGS,
        "--artifacts",
        "--discarded", json.dumps(discarded_no_usage),
        "--ledger", ledger,
    )
    check("discarded with unreported usage: exit 0", rc == 0, f"rc={rc} err={err}")
    record = first_record(ledger) if rc == 0 and os.path.exists(ledger) else None
    check(
        "discarded with unreported usage: tokens_in is null, not 0",
        record is not None and record["discarded"][0]["tokens_in"] is None,
        record,
    )
    check(
        "discarded with unreported usage: tokens_out is null, not 0",
        record is not None and record["discarded"][0]["tokens_out"] is None,
        record,
    )

# Direct schema check, not assumed: a row written before #116 carries neither
# key, and the archived-row guarantee is that it still validates against the
# amended schema. Reuses LEGACY_ROW/_amended_schema from the job check above
# for the same reason that check does — this catches the case where
# "attempts" or "discarded" is mistakenly added to `required`, which no row
# written before this change would satisfy.
_no_new_fields_violation = _ledger_append.schema_violation(LEGACY_ROW, _amended_schema)
check(
    "attempts/discarded: row carrying neither key still validates",
    _no_new_fields_violation is None,
    _no_new_fields_violation,
)

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
