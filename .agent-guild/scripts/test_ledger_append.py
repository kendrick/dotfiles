#!/usr/bin/env python3
"""Fixture-based tests for ledger-append.py. No repo state touched: every
ledger lives in a fresh temp dir, and the script runs as a subprocess so
these tests exercise the real CLI contract (exit codes, stderr messages,
file contents) rather than calling internals directly — matching
test_verdict_tools.py's approach for validate-verdict.py.

Run: python3 .agent-guild/scripts/test_ledger_append.py
"""
import json
import os
import subprocess
import sys
import tempfile

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
LEDGER_APPEND = os.path.join(SCRIPTS_DIR, "ledger-append.py")

passed = failed = 0


def check(label, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


def run(*argv):
    proc = subprocess.run(
        [sys.executable, LEDGER_APPEND, *argv], capture_output=True, text=True
    )
    return proc.returncode, proc.stdout, proc.stderr


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines()


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

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
