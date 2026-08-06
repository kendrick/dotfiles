#!/usr/bin/env python3
"""Behavioral tests for the fixed Claude CLI second-opinion boundary.

The fake `claude` executable is the only double: it stands in for the remote,
authenticated CLI while the real courier runner builds the command, closes
stdin, isolates cwd, adapts the schema, parses the result envelope, validates
the verdict, retries malformed output, and classifies failures.

Run: python3 .agent-guild/scripts/test_claude_courier.py
"""
import json
import os
import stat
import subprocess
import sys
import tempfile
import textwrap


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(SCRIPT_DIR, "claude-courier.py")
SCHEMA = os.path.join(
    os.path.dirname(SCRIPT_DIR), "schemas", "verdict.schema.json"
)
MODEL = "claude-haiku-4-5-20251001"

passed = failed = 0


def check(label, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


FAKE_CLAUDE = textwrap.dedent(
    """\
    #!/usr/bin/env python3
    import json
    import os
    import sys
    import time

    # C-10's table, rows (a) through (p): each maps a row's cells (exit
    # code, envelope fields the row names, stderr) to a fixed fake-CLI
    # mode. A row with no envelope at all (k) carries None; the fake CLI
    # then prints non-JSON stdout so the courier parses no envelope.
    ROWS = {
        "a": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "Not logged in · Please run /login",
            "duration_ms": 14290,
        }, ""),
        "b": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "Request rejected (500) · retry after 14290 ms",
        }, ""),
        "c": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "No further detail.",
        }, "Rate limit exceeded"),
        "d": (0, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "aborted_streaming",
            "result": "model text mentioning rate limits and quota",
        }, ""),
        "e": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "No further detail.",
        }, "attempt 3/11 · elapsed 14290 ms, 0.429 s, 429.15 s, trace_429_ok"),
        "f": (0, {
            "is_error": False,
            "api_error_status": None,
            "terminal_reason": "completed",
            "result": "No further detail.",
        }, "Rate limit exceeded"),
        "g": (0, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "No further detail.",
        }, "monthly quota exhausted"),
        "h": (1, {
            "is_error": False,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "spending cap reached for your plan",
        }, ""),
        "i": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "aborted_streaming",
            "result": "No further detail.",
        }, "Rate limit exceeded"),
        "j": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "No further detail.",
        }, "HTTP 429"),
        "k": (1, None, "Rate limit exceeded"),
        "l": (0, {
            "is_error": False,
            "api_error_status": 429,
            "terminal_reason": "completed",
            "result": "No further detail.",
        }, ""),
        "m": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "No further detail.",
        }, "usage limit reached for your plan"),
        "n": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "No further detail.",
        }, "the request was rate-limited"),
        "o": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "29 requests still queued, worker 4",
        }, "29 tasks queued behind worker 4"),
        "p": (1, {
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "No further detail.",
        }, "req_01Hx429fk2 failed"),
    }

    mode = os.environ["FAKE_CLAUDE_MODE"]
    task_id = os.environ["FAKE_CLAUDE_TASK_ID"]
    calls_path = os.environ["FAKE_CLAUDE_CALLS"]
    count_path = os.environ["FAKE_CLAUDE_COUNT"]
    try:
        with open(count_path, encoding="utf-8") as stream:
            count = int(stream.read()) + 1
    except (OSError, ValueError):
        count = 1
    with open(count_path, "w", encoding="utf-8") as stream:
        stream.write(str(count))

    try:
        with open(calls_path, encoding="utf-8") as stream:
            calls = json.load(stream)
    except (OSError, json.JSONDecodeError):
        calls = []
    calls.append({
        "argv": sys.argv[1:],
        "stdin": sys.stdin.read(),
        "cwd": os.getcwd(),
    })
    with open(calls_path, "w", encoding="utf-8") as stream:
        json.dump(calls, stream)

    verdict = {
        "task_id": task_id,
        "checker": "checker-courier",
        "vendor": "anthropic",
        "model": "claude-haiku-4-5-20251001",
        "verdict": "pass",
        "findings": [],
        "timestamp": "2026-07-26T18:00:00Z",
        "duration_ms": None,
        "cost_usd": None,
    }
    success = {
        "type": "result",
        "subtype": "success",
        "is_error": False,
        "terminal_reason": "completed",
        "result": json.dumps(verdict),
        "structured_output": verdict,
        "usage": {"input_tokens": 101, "output_tokens": 23},
        "modelUsage": {
            "claude-haiku-4-5-20251001": {
                "inputTokens": 101,
                "outputTokens": 23,
                "costUSD": 0.0042,
            }
        },
        "total_cost_usd": 0.0042,
    }

    if mode == "timeout":
        time.sleep(2)
    elif mode == "quota":
        print(json.dumps({
            "type": "result",
            "subtype": "error_during_execution",
            "is_error": True,
            "api_error_status": 429,
            "terminal_reason": "api_error",
            "result": "API Error: Request rejected (429) · Rate limit exceeded",
        }))
        raise SystemExit(1)
    elif mode == "auth":
        print(json.dumps({
            "type": "result",
            "subtype": "error_during_execution",
            "is_error": True,
            "api_error_status": None,
            "terminal_reason": "api_error",
            "result": "Not logged in · Please run /login",
        }))
        raise SystemExit(1)
    elif mode == "invalid_model":
        print(json.dumps({
            "type": "result",
            "subtype": "error_during_execution",
            "is_error": True,
            "api_error_status": 404,
            "terminal_reason": "api_error",
            "result": "Model not found: claude-haiku-4-5-20251001",
        }))
        raise SystemExit(1)
    elif mode == "malformed" or (mode == "malformed_once" and count == 1):
        print(json.dumps({
            "type": "result",
            "subtype": "success",
            "is_error": False,
            "terminal_reason": "completed",
            "result": "NOT_JSON",
            "usage": {"input_tokens": 7, "output_tokens": 3},
            "modelUsage": {
                "claude-haiku-4-5-20251001": {
                    "inputTokens": 7,
                    "outputTokens": 3,
                    "costUSD": 0.001,
                }
            },
            "total_cost_usd": 0.001,
        }))
    elif mode == "wrong_identity":
        success["structured_output"]["task_id"] = "T-999"
        print(json.dumps(success))
    elif mode.startswith("row_"):
        exit_code, envelope, stderr_text = ROWS[mode[len("row_"):]]
        if stderr_text:
            sys.stderr.write(stderr_text)
        if envelope is None:
            sys.stdout.write("boom: no JSON envelope produced")
        else:
            sys.stdout.write(json.dumps(envelope))
        raise SystemExit(exit_code)
    else:
        print(json.dumps(success))
    """
)


def run_courier(mode, task_id="T-054", timeout=None, with_cli=True):
    temp = tempfile.TemporaryDirectory(prefix="claude-courier-test-")
    fake = os.path.join(temp.name, "claude")
    calls = os.path.join(temp.name, "calls.json")
    count = os.path.join(temp.name, "count")
    with open(fake, "w", encoding="utf-8") as stream:
        stream.write(FAKE_CLAUDE)
    os.chmod(fake, os.stat(fake).st_mode | stat.S_IXUSR)

    env = os.environ.copy()
    if with_cli:
        env["PATH"] = temp.name + os.pathsep + env.get("PATH", "")
    else:
        env["PATH"] = temp.name
        os.remove(fake)
    env.update(
        {
            "FAKE_CLAUDE_MODE": mode,
            "FAKE_CLAUDE_TASK_ID": task_id,
            "FAKE_CLAUDE_CALLS": calls,
            "FAKE_CLAUDE_COUNT": count,
        }
    )
    command = [sys.executable, SCRIPT, "--task-id", task_id]
    if timeout is not None:
        command.extend(["--timeout-seconds", str(timeout)])
    prompt = (
        f"Task-ID: {task_id}\n\n"
        "## Brief\nC-1 must pass.\n\n"
        "## Artifact\nresult.txt: OK\n\n"
        "## Evidence\nlocal check exited 0."
    )
    process = subprocess.run(
        command,
        input=prompt,
        capture_output=True,
        text=True,
        env=env,
    )
    try:
        outcome = json.loads(process.stdout)
    except json.JSONDecodeError:
        outcome = None
    try:
        with open(calls, encoding="utf-8") as stream:
            call_records = json.load(stream)
    except (OSError, json.JSONDecodeError):
        call_records = []
    return temp, process, outcome, call_records, prompt


print("claude-courier.py")

temp, process, outcome, calls, prompt = run_courier("success")
try:
    check(
        "successful structured_output becomes a validated Claude-lane verdict",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "pass"
        and outcome["verdict"]["vendor"] == "anthropic"
        and outcome["verdict"]["model"] == MODEL
        and outcome["ledger"]["vendor"] == "claude"
        and outcome["ledger"]["tokens_in"] == 101
        and outcome["ledger"]["tokens_out"] == 23
        and outcome["ledger"]["cost_usd"] == 0.0042
        and outcome["attempts"] == 1,
        f"rc={process.returncode} stdout={process.stdout!r} stderr={process.stderr!r}",
    )

    argv = calls[0]["argv"] if calls else []
    expected_flags = [
        "-p",
        "--safe-mode",
        "--no-session-persistence",
        "--strict-mcp-config",
        "--mcp-config",
        '{"mcpServers":{}}',
        "--tools",
        "",
        "--permission-mode",
        "plan",
        "--prompt-suggestions",
        "false",
        "--model",
        MODEL,
        "--output-format",
        "json",
        "--json-schema",
    ]
    check(
        "the Claude command is fixed, isolated, receives inline evidence, and has closed stdin",
        argv[: len(expected_flags)] == expected_flags
        and argv[-1] == prompt
        and calls[0]["stdin"] == ""
        and not os.path.exists(
            os.path.join(calls[0]["cwd"], ".agent-guild")
        ),
        repr(calls),
    )

    try:
        adapted = json.loads(argv[-2])
        with open(SCHEMA, encoding="utf-8") as stream:
            canonical = json.load(stream)
        canonical.pop("$schema")
        schema_ok = adapted == canonical and "$schema" not in adapted
    except (IndexError, json.JSONDecodeError, OSError) as error:
        schema_ok = False
        adapted = repr(error)
    check(
        "the Claude schema adapter removes only the top-level $schema declaration",
        schema_ok,
        repr(adapted),
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, _prompt = run_courier("malformed_once")
try:
    check(
        "missing structured_output retries once before accepting a valid response",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "pass"
        and outcome["attempts"] == 2
        and outcome["ledger"]["tokens_in"] == 108
        and outcome["ledger"]["tokens_out"] == 26
        and outcome["ledger"]["cost_usd"] == 0.0052
        and len(calls) == 2,
        f"rc={process.returncode} outcome={outcome!r} calls={calls!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, _prompt = run_courier("malformed")
try:
    check(
        "two malformed responses become a blocked second opinion without repair",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "blocked"
        and "structured_output" in outcome["verdict"]["findings"][0]["description"]
        and "NOT_JSON" in outcome["verdict"]["findings"][0]["evidence"]
        and outcome["attempts"] == 2
        and len(calls) == 2,
        f"rc={process.returncode} outcome={outcome!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, _prompt = run_courier("auth")
try:
    check(
        "authentication failure is a recorded blocked opinion and is not retried",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "blocked"
        and "Not logged in" in outcome["verdict"]["findings"][0]["evidence"]
        and outcome["ledger"]["exit_code"] == 1
        and outcome["attempts"] == 1
        and len(calls) == 1,
        f"rc={process.returncode} outcome={outcome!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, _prompt = run_courier("quota")
try:
    check(
        "structured 429 is a quota outcome with no verdict and no retry",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "quota"
        and outcome["verdict"] is None
        and outcome["ledger"]["quota_event"] is True
        and outcome["attempts"] == 1
        and len(calls) == 1,
        f"rc={process.returncode} outcome={outcome!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, _prompt = run_courier(
    "timeout", timeout=0.05
)
try:
    check(
        "the courier-owned wall-clock bound returns a blocked opinion",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "blocked"
        and "timed out" in outcome["verdict"]["findings"][0]["description"]
        and outcome["attempts"] == 1
        and outcome["ledger"]["exit_code"] == 124,
        f"rc={process.returncode} outcome={outcome!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, _prompt = run_courier(
    "success", with_cli=False
)
try:
    check(
        "missing Claude CLI returns a blocked opinion without attempting a command",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "blocked"
        and "not found" in outcome["verdict"]["findings"][0]["description"]
        and outcome["ledger"]["exit_code"] == 127
        and calls == [],
        f"rc={process.returncode} outcome={outcome!r} stderr={process.stderr!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, _prompt = run_courier("wrong_identity")
try:
    check(
        "a schema-valid verdict with the wrong identity is rejected after one retry",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "blocked"
        and "task_id" in outcome["verdict"]["findings"][0]["description"]
        and outcome["attempts"] == 2
        and len(calls) == 2,
        f"rc={process.returncode} outcome={outcome!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, _prompt = run_courier("invalid_model")
try:
    check(
        "an invalid/unavailable model (api_error_status 404) is a blocked "
        "opinion, not quota",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "blocked"
        and outcome["ledger"]["exit_code"] == 1
        and outcome["attempts"] == 1
        and len(calls) == 1,
        f"rc={process.returncode} outcome={outcome!r}",
    )
finally:
    temp.cleanup()

# C-10's table, rows (a) through (p): each row is the sole catcher of one
# specific way to misread a failed CLI call as lane exhaustion. `expect_quota`
# names the row's one graded cell — status "quota" vs a verdict outcome,
# which by construction is "not quota".
C10_ROWS = [
    ("a", False, "auth failure is not exhaustion, whatever digits ride along"),
    ("b", False, "the 429 boundary holds inside result"),
    ("c", True, "stderr is scanned in addition to result"),
    ("d", False, "result is not scanned off api_error; a bounded stdout scan would fail this"),
    ("e", False, "all four digit/decimal/underscore adjacency shapes in one stderr"),
    ("f", False, "the errorish gate is retained"),
    ("g", True, "the is_error gate limb alone suffices; the quota alternative survives"),
    ("h", True, "the returncode gate limb alone suffices; result is scanned; spending cap survives"),
    ("i", True, "stderr is scanned regardless of terminal_reason"),
    ("j", True, "the boundary does not over-narrow a genuine standalone 429"),
    ("k", True, "stderr is read when the envelope is absent or not a dict"),
    ("l", True, "the structural test runs before the gate"),
    ("m", True, "a non-rate-limit alternative, lowercase, survives"),
    ("n", True, "hyphenated and suffixed wording survives"),
    ("o", False, "the two surfaces are joined so neither lends digits to the other"),
    ("p", False, "alphanumeric adjacency, which a digit-only boundary misses"),
]

for letter, expect_quota, pin in C10_ROWS:
    temp, process, outcome, calls, _prompt = run_courier(f"row_{letter}")
    try:
        if expect_quota:
            condition = (
                process.returncode == 0
                and outcome is not None
                and outcome["status"] == "quota"
                and outcome["verdict"] is None
                and outcome["ledger"]["quota_event"] is True
            )
        else:
            condition = (
                process.returncode == 0
                and outcome is not None
                and outcome["status"] == "verdict"
            )
        check(
            f"C-10 row ({letter}): "
            f"{'quota' if expect_quota else 'not quota'} — {pin}",
            condition,
            f"rc={process.returncode} outcome={outcome!r}",
        )
    finally:
        temp.cleanup()

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
