#!/usr/bin/env python3
"""Behavioral tests for the fixed `codex exec` second-opinion boundary.

The fake `codex` executable is the only double: it stands in for the remote,
authenticated CLI while the real runner builds the command, closes stdin,
isolates cwd, parses the event stream, establishes identity, validates the
verdict, retries malformed output, classifies failures, and persists.

The case that matters most is `echo_mismatch`. It is #100's T-004 replayed:
the far side returns a substantive `fail` and echoes the wrong model name, and
the crossing must keep the judgment. The second most important is
`timeout_with_output`, where a valid verdict sits on disk from a process we
killed and must not be believed.

Run: python3 .agent-guild/scripts/test_codex_courier.py
"""
import json
import os
import stat
import subprocess
import sys
import tempfile
import textwrap


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(SCRIPT_DIR, "codex-courier.py")
SCHEMA = os.path.join(
    os.path.dirname(SCRIPT_DIR), "schemas", "verdict.schema.json"
)
MODEL = "gpt-5.6-terra"

passed = failed = 0


def check(label, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  ok   {label}")
    else:
        failed += 1
        print(f"  FAIL {label}  {detail}")


FAKE_CODEX = textwrap.dedent(
    """\
    #!/usr/bin/env python3
    import json
    import os
    import sys
    import time

    mode = os.environ["FAKE_CODEX_MODE"]
    task_id = os.environ["FAKE_CODEX_TASK_ID"]
    calls_path = os.environ["FAKE_CODEX_CALLS"]
    count_path = os.environ["FAKE_CODEX_COUNT"]

    try:
        with open(count_path, encoding="utf-8") as stream:
            count = int(stream.read()) + 1
    except (OSError, ValueError):
        count = 1
    with open(count_path, "w", encoding="utf-8") as stream:
        stream.write(str(count))

    argv = sys.argv[1:]
    out_path = None
    if "-o" in argv:
        out_path = argv[argv.index("-o") + 1]

    try:
        with open(calls_path, encoding="utf-8") as stream:
            calls = json.load(stream)
    except (OSError, json.JSONDecodeError):
        calls = []
    calls.append({
        "argv": argv,
        "stdin": sys.stdin.read(),
        "cwd": os.getcwd(),
    })
    with open(calls_path, "w", encoding="utf-8") as stream:
        json.dump(calls, stream)

    def verdict(**overrides):
        base = {
            "task_id": task_id,
            "checker": "checker-courier",
            "vendor": "openai",
            "model": "gpt-5.6-terra",
            "verdict": "pass",
            "findings": [],
            "timestamp": "2026-08-11T18:00:00Z",
            "duration_ms": None,
            "cost_usd": None,
        }
        base.update(overrides)
        return base

    def emit(events, out=None):
        for event in events:
            sys.stdout.write(json.dumps(event) + "\\n")
        if out is not None and out_path:
            with open(out_path, "w", encoding="utf-8") as stream:
                json.dump(out, stream)

    OK_EVENTS = [
        {"type": "thread.started", "thread_id": "t-1"},
        {"type": "turn.started"},
        {"type": "item.completed",
         "item": {"id": "item_0", "type": "agent_message", "text": "{}"}},
        {"type": "turn.completed", "usage": {
            "input_tokens": 101, "cached_input_tokens": 40,
            "cache_write_input_tokens": 0, "output_tokens": 23,
            "reasoning_output_tokens": 0}},
    ]

    def failed_turn(message, exit_code=1):
        emit([
            {"type": "thread.started", "thread_id": "t-1"},
            {"type": "turn.started"},
            {"type": "error", "message": message},
            {"type": "turn.failed", "error": {"message": message}},
        ])
        raise SystemExit(exit_code)

    FAIL_FINDINGS = [
        {"clause_id": "C-7", "severity": "major",
         "description": "first major defect", "evidence": "line 12"},
        {"clause_id": "C-7", "severity": "major",
         "description": "second major defect", "evidence": "line 40"},
        {"clause_id": "C-7", "severity": "info",
         "description": "first note", "evidence": "line 3"},
        {"clause_id": "C-7", "severity": "info",
         "description": "second note", "evidence": "line 9"},
    ]

    if mode == "timeout":
        # Write a perfectly valid verdict, then outlive the wall clock. The
        # runner must not read this file.
        if out_path:
            with open(out_path, "w", encoding="utf-8") as stream:
                json.dump(verdict(), stream)
        sys.stdout.write(json.dumps(OK_EVENTS[0]) + "\\n")
        sys.stdout.flush()
        time.sleep(5)
    elif mode == "quota_structural":
        failed_turn(json.dumps({
            "type": "error", "status": 429,
            "error": {"type": "rate_limit_error", "message": "slow down"}}))
    elif mode == "quota_wording":
        sys.stderr.write("Rate limit exceeded for your plan")
        failed_turn("the vendor refused")
    elif mode == "quota_token_lookalike":
        # usage numerics live on stdout, which must never be scanned as prose
        emit(OK_EVENTS[:3] + [{"type": "turn.completed", "usage": {
            "input_tokens": 429, "output_tokens": 4290}}], verdict())
    elif mode == "quota_request_id":
        sys.stderr.write("failed on req_01Hx429fk2")
        failed_turn("the vendor refused")
    elif mode == "quota_in_message":
        # a successful turn whose model text mentions rate limits is not
        # exhaustion
        emit(OK_EVENTS[:2] + [
            {"type": "item.completed", "item": {
                "id": "item_0", "type": "agent_message",
                "text": "I considered the rate limit and quota clauses."}},
            OK_EVENTS[3],
        ], verdict())
    elif mode == "auth":
        sys.stderr.write("Not logged in. Please run codex login")
        failed_turn("unauthorized")
    elif mode == "bad_model":
        failed_turn(json.dumps({
            "type": "error", "status": 400,
            "error": {"type": "invalid_request_error",
                      "message": "model is not supported"}}))
    elif mode == "malformed" or (mode == "malformed_once" and count == 1):
        emit(OK_EVENTS[:3] + [{"type": "turn.completed", "usage": {
            "input_tokens": 7, "output_tokens": 3}}])
        if out_path:
            with open(out_path, "w", encoding="utf-8") as stream:
                stream.write("NOT_JSON")
    elif mode == "malformed_quotes":
        # #106's own payload shape, and a different failure from `NOT_JSON`
        # above: this one is well-formed right up to a string value carrying
        # raw double quotes, so the decoder gets 242 characters in before it
        # gives up. Truncating there and keeping what parsed is exactly the
        # bug #106 reported.
        emit(OK_EVENTS[:3] + [{"type": "turn.completed", "usage": {
            "input_tokens": 7, "output_tokens": 3}}])
        if out_path:
            body = json.dumps(verdict(
                verdict="fail",
                findings=[{"clause_id": "C-1", "severity": "major",
                           "description": "the brief quotes itself",
                           "evidence": "EMBEDDED"}],
            )).replace("EMBEDDED", 'the brief says "C-1 must pass" at line 2')
            with open(out_path, "w", encoding="utf-8") as stream:
                stream.write(body)
    elif mode == "echo_mismatch":
        emit(OK_EVENTS, verdict(model="gpt-5.6", verdict="fail",
                                findings=FAIL_FINDINGS))
    elif mode == "echo_foreign":
        emit(OK_EVENTS, verdict(model="gpt-4o"))
    elif mode == "wrong_task":
        emit(OK_EVENTS, verdict(task_id="T-999"))
    elif mode == "wrong_vendor":
        emit(OK_EVENTS, verdict(vendor="anthropic"))
    elif mode == "stream_reports_model":
        emit([{"type": "thread.started", "thread_id": "t-1", "model": "gpt-9"}]
             + OK_EVENTS[1:], verdict())
    elif mode == "no_output_file":
        # answered, wrote no file: the agent_message is the fallback
        emit(OK_EVENTS[:2] + [
            {"type": "item.completed", "item": {
                "id": "item_0", "type": "agent_message",
                "text": json.dumps(verdict())}},
            OK_EVENTS[3],
        ])
    else:
        emit(OK_EVENTS, verdict())
    """
)


def make_project(root):
    for part in (("state", "log"), ("state", "verdicts"), ("state", "briefs")):
        os.makedirs(os.path.join(root, ".agent-guild", *part), exist_ok=True)
    brief = os.path.join(root, ".agent-guild", "state", "briefs", "T-054.md")
    with open(brief, "w", encoding="utf-8") as stream:
        stream.write("## Brief\nC-1 must pass.\n")
    return brief


def run_courier(mode, task_id="T-054", timeout=None, with_cli=True,
                persist=False, keep_raw=None, extra=()):
    temp = tempfile.TemporaryDirectory(prefix="codex-courier-test-")
    fake = os.path.join(temp.name, "codex")
    calls = os.path.join(temp.name, "calls.json")
    count = os.path.join(temp.name, "count")
    project = os.path.join(temp.name, "project")
    brief = make_project(project)
    with open(fake, "w", encoding="utf-8") as stream:
        stream.write(FAKE_CODEX)
    os.chmod(fake, os.stat(fake).st_mode | stat.S_IXUSR)

    env = os.environ.copy()
    if with_cli:
        env["PATH"] = temp.name + os.pathsep + env.get("PATH", "")
    else:
        env["PATH"] = temp.name
        os.remove(fake)
    env.update({
        "FAKE_CODEX_MODE": mode,
        "FAKE_CODEX_TASK_ID": task_id,
        "FAKE_CODEX_CALLS": calls,
        "FAKE_CODEX_COUNT": count,
    })

    command = [sys.executable, SCRIPT, "--task-id", task_id,
               "--project-root", project]
    if timeout is not None:
        command += ["--timeout-seconds", str(timeout)]
    if persist:
        command += ["--tier", "sonnet", "--retries", "0", "--brief", brief]
    if keep_raw:
        command += ["--keep-raw", keep_raw]
    command += list(extra)

    prompt = (
        f"Task-ID: {task_id}\n\n"
        "## Brief\nC-1 must pass.\n\n"
        "## Artifact\nresult.txt: OK\n\n"
        "## Evidence\nlocal check exited 0."
    )
    process = subprocess.run(
        command, input=prompt, capture_output=True, text=True, env=env,
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
    return temp, process, outcome, call_records, project


def ledger_lines(project):
    path = os.path.join(
        project, ".agent-guild", "state", "log", "vendor-calls.jsonl"
    )
    try:
        with open(path, encoding="utf-8") as stream:
            return [json.loads(line) for line in stream if line.strip()]
    except OSError:
        return []


print("codex-courier.py")

temp, process, outcome, calls, project = run_courier("success")
try:
    check(
        "a conforming response becomes a validated codex-lane verdict",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "pass"
        and outcome["verdict"]["vendor"] == "openai"
        and outcome["verdict"]["model"] == MODEL
        and outcome["ledger"]["vendor"] == "codex"
        and outcome["ledger"]["model"] == MODEL
        and outcome["ledger"]["tokens_in"] == 101
        and outcome["ledger"]["tokens_out"] == 23
        and outcome["ledger"]["cost_usd"] is None
        and outcome["attempts"] == 1,
        f"rc={process.returncode} stdout={process.stdout!r} stderr={process.stderr!r}",
    )

    check(
        "cached_input_tokens is reported separately, never folded into tokens_in",
        outcome is not None and outcome["ledger"]["tokens_in"] == 101,
        f"tokens_in={outcome and outcome['ledger']['tokens_in']}",
    )

    argv = calls[0]["argv"] if calls else []
    expected = ["exec", "--skip-git-repo-check", "-s", "read-only",
                "--ephemeral", "--ignore-user-config", "--json",
                "-m", MODEL, "--output-schema", SCHEMA]
    check(
        "the lane command is fixed, pinned, and sandboxed",
        argv[:len(expected)] == expected,
        f"argv={argv!r}",
    )
    check(
        "the -o path is absolute and the prompt is the final argument",
        "-o" in argv
        and os.path.isabs(argv[argv.index("-o") + 1])
        and argv[-1].startswith("Task-ID: T-054"),
        f"argv={argv!r}",
    )
    check(
        "child stdin is closed and cwd is isolated from the project",
        calls and calls[0]["stdin"] == ""
        and not os.path.exists(
            os.path.join(calls[0]["cwd"], ".agent-guild")
        ),
        f"stdin={calls and calls[0]['stdin']!r} cwd={calls and calls[0]['cwd']!r}",
    )
    check(
        "an exact echo records a match and needs no annotation",
        outcome is not None
        and outcome["identity"]["echo_matched"] is True
        and outcome["identity"]["model_source"] == "requested"
        and outcome["identity"]["echoed_model"] == MODEL
        and outcome["verdict"]["findings"] == [],
        f"identity={outcome and outcome['identity']!r}",
    )
finally:
    temp.cleanup()

# ---------------------------------------------------------------- #142 core
temp, process, outcome, calls, project = run_courier(
    "echo_mismatch", persist=True
)
try:
    verdict = outcome["verdict"] if outcome else {}
    vendor_findings = [
        f for f in verdict.get("findings", []) if f["clause_id"] == "C-7"
    ]
    runner_findings = [
        f for f in verdict.get("findings", [])
        if f["clause_id"] == "external-lane"
    ]
    check(
        "#142: a mis-echoed model keeps the judgment instead of blocking it",
        process.returncode == 0
        and outcome is not None
        and outcome["status"] == "verdict"
        and verdict.get("verdict") == "fail"
        and len(vendor_findings) == 4
        and sum(1 for f in vendor_findings if f["severity"] == "major") == 2,
        f"stdout={process.stdout!r} stderr={process.stderr!r}",
    )
    check(
        "#142: the verdict carries the model the lane ran, not the one echoed",
        outcome is not None
        and verdict.get("model") == MODEL
        and outcome["identity"]["echoed_model"] == "gpt-5.6"
        and outcome["identity"]["echo_matched"] is False,
        f"model={verdict.get('model')!r} identity={outcome and outcome['identity']!r}",
    )
    check(
        "#142: the divergence is recorded as one info finding by the runner",
        len(runner_findings) == 1
        and runner_findings[0]["severity"] == "info"
        and "gpt-5.6" in runner_findings[0]["description"]
        and MODEL in runner_findings[0]["description"],
        f"runner_findings={runner_findings!r}",
    )
    raw = outcome["persisted"]["raw_path"] if outcome and outcome.get("persisted") else None
    check(
        "#142: the raw response is retained and the finding points at it",
        raw is not None
        and os.path.exists(os.path.join(project, raw))
        and raw in runner_findings[0]["evidence"],
        f"raw={raw!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, project = run_courier("echo_foreign")
try:
    check(
        "a foreign family name diverges the same way a truncation does",
        outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["model"] == MODEL
        and outcome["identity"]["echoed_model"] == "gpt-4o"
        and outcome["identity"]["echo_matched"] is False,
        f"identity={outcome and outcome['identity']!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, project = run_courier("stream_reports_model")
try:
    check(
        "a stream that reports a different model than -m is a real fault",
        outcome is not None
        and outcome["verdict"]["verdict"] == "blocked"
        and "gpt-9" in outcome["verdict"]["findings"][0]["description"]
        and MODEL in outcome["verdict"]["findings"][0]["description"],
        f"outcome={outcome!r}",
    )
finally:
    temp.cleanup()

# ------------------------------------------------------- identity, elsewhere
for mode, field in (("wrong_task", "task_id"), ("wrong_vendor", "vendor")):
    temp, process, outcome, calls, project = run_courier(mode)
    try:
        check(
            f"a wrong {field} is still refused outright, after one retry",
            outcome is not None
            and outcome["verdict"]["verdict"] == "blocked"
            and field in outcome["verdict"]["findings"][0]["description"]
            and len(calls) == 2,
            f"outcome={outcome!r} calls={len(calls)}",
        )
    finally:
        temp.cleanup()

# --------------------------------------------------------------- the #84 core
temp, process, outcome, calls, project = run_courier(
    "timeout", timeout=1, persist=True
)
try:
    verdict = outcome["verdict"] if outcome else {}
    check(
        "#84: a verdict left by a killed process is never salvaged",
        process.returncode == 0
        and verdict.get("verdict") == "blocked"
        and outcome["ledger"]["exit_code"] == 124
        and "timed out" in verdict["findings"][0]["description"],
        f"stdout={process.stdout!r} stderr={process.stderr!r}",
    )
    check(
        "#84: a timed-out crossing still leaves exactly one ledger line",
        len(ledger_lines(project)) == 1
        and ledger_lines(project)[0]["exit_code"] == 124
        and ledger_lines(project)[0]["vendor"] == "codex",
        f"ledger={ledger_lines(project)!r}",
    )
finally:
    temp.cleanup()

# ------------------------------------------------------------------- retries
temp, process, outcome, calls, project = run_courier(
    "malformed_once", persist=True
)
try:
    check(
        "malformed output is retried once and the retry is accepted",
        outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "pass"
        and outcome["attempts"] == 2
        and len(calls) == 2,
        f"outcome={outcome!r}",
    )
    check(
        "a retried crossing sums both attempts into one ledger line",
        len(ledger_lines(project)) == 1
        and ledger_lines(project)[0]["tokens_in"] == 108
        and ledger_lines(project)[0]["tokens_out"] == 26,
        f"ledger={ledger_lines(project)!r}",
    )
    check(
        "a retry retains the raw response under the default policy",
        outcome["persisted"]["raw_path"] is not None
        and os.path.exists(
            os.path.join(project, outcome["persisted"]["raw_path"])
        ),
        f"persisted={outcome['persisted']!r}",
    )
    row = ledger_lines(project)[0]
    discarded = row.get("discarded") or []
    entry = discarded[0] if discarded else {}
    check(
        "#116: a retried crossing's ledger row carries attempts and one discarded entry",
        row.get("attempts") == 2 and len(discarded) == 1,
        f"row={row!r}",
    )
    check(
        "#116: the discarded entry names the first attempt's own validation "
        "failure and that attempt's own token usage",
        str(entry.get("reason", "")).startswith("codex output was not JSON")
        and entry.get("tokens_in") == 7
        and entry.get("tokens_out") == 3
        and entry.get("exit_code") == 0,
        f"discarded={discarded!r}",
    )
    check(
        "#116: the discarded entry's duration is its own attempt's, not the "
        "row's cumulative clock",
        entry.get("duration_ms") != row.get("duration_ms"),
        f"discarded_duration={entry.get('duration_ms')!r} "
        f"row_duration={row.get('duration_ms')!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, project = run_courier("malformed", persist=True)
try:
    check(
        "twice-malformed output becomes a blocked verdict quoting the raw text",
        outcome is not None
        and outcome["verdict"]["verdict"] == "blocked"
        and outcome["attempts"] == 2
        and "NOT_JSON" in outcome["verdict"]["findings"][0]["evidence"],
        f"outcome={outcome!r}",
    )
    row = ledger_lines(project)[0]
    discarded = row.get("discarded") or []
    entry = discarded[0] if discarded else {}
    check(
        "#116: a blocked crossing still discloses the first attempt it discarded",
        row.get("attempts") == 2
        and len(discarded) == 1
        and str(entry.get("reason", "")).startswith("codex output was not JSON")
        and entry.get("duration_ms") != row.get("duration_ms"),
        f"row={row!r}",
    )
finally:
    temp.cleanup()

# ------------------------------------------------------------------ #106
# `NOT_JSON` above fails at character one. #106's report was the harder shape:
# a payload that parses most of the way and then truncates mid-string, which is
# the case where "caught" and "silently accepted a prefix" look alike.
temp, process, outcome, calls, project = run_courier(
    "malformed_quotes", persist=True
)
try:
    persisted = outcome["persisted"] if outcome else {}
    stem_path = os.path.join(project, persisted.get("verdict_path") or "x")
    raw_path = os.path.join(project, persisted.get("raw_path") or "x")
    try:
        with open(stem_path, encoding="utf-8") as stream:
            at_stem = json.load(stream)
    except (OSError, json.JSONDecodeError):
        at_stem = None
    try:
        with open(raw_path, encoding="utf-8") as stream:
            raw_entries = [json.loads(line) for line in stream if line.strip()]
    except (OSError, json.JSONDecodeError):
        raw_entries = []
    validated = subprocess.run(
        [sys.executable, os.path.join(SCRIPT_DIR, "validate-verdict.py"),
         stem_path],
        capture_output=True, text=True,
    )
    blocking = (outcome["verdict"]["findings"][0] if outcome else {})

    check(
        "#106: a value carrying raw double quotes is caught, not truncated",
        outcome is not None
        and outcome["verdict"]["verdict"] == "blocked"
        and "was not JSON" in blocking["description"]
        and "Expecting ',' delimiter" in blocking["description"],
        f"outcome={outcome!r}",
    )
    check(
        "#106: the embedded-quote payload is retried exactly once, then stops",
        outcome is not None and outcome["attempts"] == 2 and len(calls) == 2,
        f"attempts={outcome and outcome['attempts']} calls={len(calls)}",
    )
    check(
        "#106: what reaches the lane stem passes the canonical validator",
        validated.returncode == 0
        and at_stem is not None
        and at_stem["verdict"] == "blocked"
        and at_stem["task_id"] == "T-054",
        f"rc={validated.returncode} stderr={validated.stderr!r} stem={at_stem!r}",
    )
    check(
        "#106: both discarded attempts are retained verbatim, quotes and all",
        len(raw_entries) == 2
        and all('"C-1 must pass"' in entry["output_file"]
                for entry in raw_entries)
        and '"C-1 must pass"' in blocking["evidence"],
        f"raw_path={persisted.get('raw_path')!r} entries={len(raw_entries)}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, project = run_courier("no_output_file")
try:
    check(
        "a completed turn that wrote no -o file falls back to its agent message",
        outcome is not None
        and outcome["status"] == "verdict"
        and outcome["verdict"]["verdict"] == "pass",
        f"outcome={outcome!r}",
    )
finally:
    temp.cleanup()

# ------------------------------------------------------------ lane failures
temp, process, outcome, calls, project = run_courier("auth")
try:
    check(
        "an auth denial blocks without retrying and names `codex login`",
        outcome is not None
        and outcome["verdict"]["verdict"] == "blocked"
        and "codex login" in outcome["verdict"]["findings"][0]["description"]
        and len(calls) == 1,
        f"outcome={outcome!r} calls={len(calls)}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, project = run_courier("bad_model")
try:
    check(
        "a rejected model blocks and reports the vendor's own status code",
        outcome is not None
        and outcome["verdict"]["verdict"] == "blocked"
        and "400" in outcome["verdict"]["findings"][0]["description"],
        f"outcome={outcome!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, project = run_courier("success", with_cli=False)
try:
    check(
        "a missing codex CLI blocks without attempting a call",
        outcome is not None
        and outcome["verdict"]["verdict"] == "blocked"
        and outcome["ledger"]["exit_code"] == 127
        and calls == [],
        f"outcome={outcome!r} calls={calls!r}",
    )
finally:
    temp.cleanup()

# --------------------------------------------------------------------- quota
for mode, label in (
    ("quota_structural", "a nested 429 status classifies as quota"),
    ("quota_wording", "rate-limit wording on stderr classifies as quota"),
):
    temp, process, outcome, calls, project = run_courier(mode, persist=True)
    try:
        sentinel = os.path.join(project, ".agent-guild", "state", "exhausted", "codex")
        lines = ledger_lines(project)
        check(
            label,
            outcome is not None
            and outcome["status"] == "quota"
            and outcome["verdict"] is None
            and outcome["ledger"]["quota_event"] is True,
            f"outcome={outcome!r}",
        )
        check(
            f"{mode}: the ledger line is written before the sentinel exists",
            len(lines) == 1
            and lines[0]["quota_event"] is True
            and lines[0]["artifacts"] == []
            and os.path.exists(sentinel),
            f"ledger={lines!r} sentinel={os.path.exists(sentinel)}",
        )
        check(
            f"{mode}: no verdict is written for an exhausted lane",
            not os.path.exists(os.path.join(
                project, ".agent-guild", "state", "verdicts",
                "T-054-sonnet-r0-codex.json")),
            "a verdict was written alongside the sentinel",
        )
        check(
            f"#116 {mode}: a quota abandonment still carries attempts but "
            "invents no discarded entry",
            lines[0].get("attempts") == 1 and "discarded" not in lines[0],
            f"line={lines[0]!r}",
        )
    finally:
        temp.cleanup()

for mode, label in (
    ("quota_token_lookalike",
     "usage numerics on stdout never read as a rate limit"),
    ("quota_request_id",
     "a request id containing 429 never reads as a rate limit"),
    ("quota_in_message",
     "a model discussing rate limits is not an exhausted lane"),
):
    temp, process, outcome, calls, project = run_courier(mode)
    try:
        check(
            label,
            outcome is not None and outcome["status"] != "quota",
            f"outcome={outcome!r}",
        )
    finally:
        temp.cleanup()

# --------------------------------------------------------------- persistence
temp, process, outcome, calls, project = run_courier("success", persist=True)
try:
    persisted = outcome["persisted"] if outcome else {}
    verdict_path = os.path.join(project, persisted.get("verdict_path") or "x")
    rendered_path = os.path.join(project, persisted.get("rendered_path") or "x")
    lines = ledger_lines(project)
    check(
        "the runner writes the lane-suffixed verdict and its rendered sibling",
        persisted.get("verdict_path")
        == ".agent-guild/state/verdicts/T-054-sonnet-r0-codex.json"
        and os.path.exists(verdict_path)
        and os.path.exists(rendered_path),
        f"persisted={persisted!r}",
    )
    validated = subprocess.run(
        [sys.executable, os.path.join(SCRIPT_DIR, "validate-verdict.py"),
         verdict_path],
        capture_output=True, text=True,
    )
    check(
        "the persisted verdict passes the canonical validator",
        validated.returncode == 0,
        f"rc={validated.returncode} stderr={validated.stderr!r}",
    )
    check(
        "the runner appends exactly one ledger line, with the lane as vendor",
        len(lines) == 1
        and lines[0]["vendor"] == "codex"
        and lines[0]["model"] == MODEL
        and lines[0]["quota_event"] is False
        and lines[0]["brief_tokens"] is not None,
        f"ledger={lines!r}",
    )
    check(
        "ledger artifacts are repo-relative and present on disk",
        lines
        and lines[0]["artifacts"]
        and all(not os.path.isabs(p) for p in lines[0]["artifacts"])
        and all(os.path.exists(os.path.join(project, p))
                for p in lines[0]["artifacts"]),
        f"artifacts={lines and lines[0]['artifacts']!r}",
    )
    check(
        "a clean crossing keeps no raw response under the default policy",
        persisted.get("raw_path") is None,
        f"raw_path={persisted.get('raw_path')!r}",
    )
    check(
        "#116: a single-attempt crossing carries attempts but invents no "
        "discarded entry",
        lines[0].get("attempts") == 1 and "discarded" not in lines[0],
        f"line={lines[0]!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, project = run_courier(
    "success", persist=True, keep_raw="always"
)
try:
    check(
        "--keep-raw always retains a clean crossing too",
        outcome["persisted"]["raw_path"] is not None
        and os.path.exists(
            os.path.join(project, outcome["persisted"]["raw_path"])
        ),
        f"persisted={outcome['persisted']!r}",
    )
finally:
    temp.cleanup()

temp, process, outcome, calls, project = run_courier("success")
try:
    check(
        "probe mode returns an outcome and persists nothing",
        outcome is not None
        and outcome["persisted"] is None
        and ledger_lines(project) == []
        and os.listdir(
            os.path.join(project, ".agent-guild", "state", "verdicts")) == [],
        f"outcome={outcome!r}",
    )
finally:
    temp.cleanup()

# ----------------------------------------------------------------- arguments
temp, process, outcome, calls, project = run_courier(
    "success", extra=["--tier", "sonnet"]
)
try:
    check(
        "half a stem is refused before any vendor call",
        process.returncode == 2
        and "--tier and --retries" in process.stderr
        and calls == [],
        f"rc={process.returncode} stderr={process.stderr!r}",
    )
finally:
    temp.cleanup()

temp = tempfile.TemporaryDirectory(prefix="codex-courier-test-")
try:
    mismatched = subprocess.run(
        [sys.executable, SCRIPT, "--task-id", "T-054"],
        input="no task id here\n", capture_output=True, text=True,
    )
    check(
        "a prompt that doesn't name the task is refused before any call",
        mismatched.returncode == 2
        and "does not carry Task-ID: T-054" in mismatched.stderr,
        f"rc={mismatched.returncode} stderr={mismatched.stderr!r}",
    )
finally:
    temp.cleanup()

print()
print(f"{passed} passed, {failed} failed")
raise SystemExit(1 if failed else 0)
