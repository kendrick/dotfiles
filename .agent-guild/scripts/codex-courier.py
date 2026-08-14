#!/usr/bin/env python3
"""Run the fixed `codex exec` boundary for a Claude-hosted second opinion.

The prompt arrives on stdin and must already contain the Task-ID, brief,
artifact contents, and locally collected evidence. This runner never asks the
far side to read a repository path or execute a command. It invokes one pinned
model with no persistence, read-only sandboxing, a closed child stdin, and an
isolated temporary cwd.

The isolated cwd is not decoration. `-s read-only` blocks writes, not reads, so
a vendor started in the project root can shell out and read the very repository
it is supposed to be judging blind.

Stdout is one JSON outcome:

    {
      "status": "verdict" | "quota",
      "verdict": <validated verdict object> | null,
      "ledger": <arguments passed to ledger-append.py>,
      "attempts": 1 | 2,
      "diagnostic": <string> | null,
      "identity": {"model", "model_source", "echoed_model", "echo_matched"},
      "persisted": {...} | null
    }

With --tier and --retries the runner also persists: the lane-suffixed verdict,
its rendered sibling, and exactly one ledger line. That is deliberate. #84's
Done-when asks that a crossing append to the ledger "without the dispatching
session having to remember," which rules out any design where the agent runs
this and then runs something else. One ledger writer, and it is the thing that
made the call.

Malformed structured output is retried once. Missing CLI access, authentication
and other process failures, repeated malformed output, and the wall-clock bound
produce a schema-conforming blocked second opinion. A quota signal produces no
verdict; the ledger line is written before the exhaustion sentinel.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)
import _courier_lib  # noqa: E402  needs SCRIPT_DIR on the path first

SCHEMA_PATH = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "schemas", "verdict.schema.json")
)
VALIDATOR_PATH = os.path.join(SCRIPT_DIR, "validate-verdict.py")
RENDERER_PATH = os.path.join(SCRIPT_DIR, "render-verdict.py")
LEDGER_PATH = os.path.join(SCRIPT_DIR, "ledger-append.py")
DEFAULT_PROJECT_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, "..", ".."))

MODEL = "gpt-5.6-terra"
# The verdict's vendor is the provider; the ledger's vendor is the lane. They
# are different fields answering different questions, and the #100 archive has
# rows using each convention for the same lane.
VENDOR = "openai"
LANE = "codex"
DEFAULT_TIMEOUT_SECONDS = 120.0

CourierError = _courier_lib.CourierError
QUOTA_RE = _courier_lib.QUOTA_RE
AUTH_RE = _courier_lib.AUTH_RE
VALIDATOR = _courier_lib.load_validator(VALIDATOR_PATH)
_utc_now = _courier_lib.utc_now
_number = _courier_lib.number

# `claude setup-token` has no codex equivalent, so the remedy differs even
# though the failure reads the same.
CODEX_AUTH_HINT = (
    "codex could not authenticate; the lane never reached the far side. Run "
    "`codex login` in a normal terminal, and check that CODEX_HOME points at "
    "the directory holding those credentials if it is set. A sandboxed session "
    "that cannot open the credential store fails here even though the same "
    "account works interactively."
)


def _command(prompt, out_path, model):
    return [
        "codex", "exec",
        "--skip-git-repo-check",
        "-s", "read-only",
        "--ephemeral",
        # Without this the far side's model, reasoning effort, and provider all
        # come from a machine-local ~/.codex/config.toml. That file is the
        # reason "the pinned model" was a claim nobody could check (#142).
        "--ignore-user-config",
        "--json",
        "-m", model,
        "--output-schema", SCHEMA_PATH,
        "-o", out_path,
        prompt,
    ]


def _run_once(prompt, timeout_seconds, model):
    if shutil.which("codex") is None:
        return {
            "returncode": 127,
            "stdout": "",
            "stderr": "`codex` CLI not found on PATH",
            "timed_out": False,
            "missing": True,
            "out_text": "",
            "argv": [],
        }

    with tempfile.TemporaryDirectory(
        prefix="agent-guild-codex-courier-"
    ) as isolated_cwd:
        out_path = os.path.join(isolated_cwd, "verdict.json")
        argv = _command(prompt, out_path, model)
        try:
            process = subprocess.run(
                argv,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                cwd=isolated_cwd,
                timeout=timeout_seconds,
            )
            return {
                "returncode": process.returncode,
                "stdout": process.stdout,
                "stderr": process.stderr,
                "timed_out": False,
                "missing": False,
                "out_text": _read_output_file(out_path),
                "argv": argv,
            }
        except subprocess.TimeoutExpired as error:
            # The -o file is deliberately not read here. A verdict recovered
            # from a process we killed is not a second opinion, and the last
            # courier to try it reported PASS from a killed call and agreed
            # with a checker that had caught a blocker twice (#84).
            return {
                "returncode": 124,
                "stdout": _decoded(error.stdout),
                "stderr": _decoded(error.stderr),
                "timed_out": True,
                "missing": False,
                "out_text": "",
                "argv": argv,
            }
        except FileNotFoundError:
            return {
                "returncode": 127,
                "stdout": "",
                "stderr": "`codex` CLI not found on PATH",
                "timed_out": False,
                "missing": True,
                "out_text": "",
                "argv": argv,
            }


def _decoded(stream):
    if isinstance(stream, bytes):
        return stream.decode("utf-8", errors="replace")
    return stream or ""


def _read_output_file(path):
    try:
        with open(path, encoding="utf-8") as stream:
            return stream.read()
    except OSError:
        return ""


def _events(call):
    return _courier_lib.parse_jsonl(call["stdout"])


def _terminal(events):
    for event in reversed(events):
        if event.get("type") in ("turn.completed", "turn.failed"):
            return event
    return None


def _usage(events):
    """codex reports token counts on turn.completed and no cost at all, so
    cost_usd stays null. Null means unreported; never invent zero."""
    terminal = _terminal(events)
    usage = terminal.get("usage") if isinstance(terminal, dict) else None
    usage = usage if isinstance(usage, dict) else {}
    # cached_input_tokens is reported alongside input_tokens but is not added
    # into it. Report what the vendor reported.
    return (
        _number(usage.get("input_tokens"), int),
        _number(usage.get("output_tokens"), int),
        None,
    )


def _reported_model(events):
    """(model, source), or (None, None) when the stream says nothing.

    As of codex-cli 0.146.1 this finds nothing: probed across five live calls,
    `thread.started` carries only `thread_id` and `turn.completed` only
    `usage`, and no event anywhere carries a model. The lookup is written
    anyway because a stream that reports what it ran is strictly better
    evidence than a flag asserting what we asked for, and this is the one
    place that would need to change if codex starts reporting it.
    """
    for event in events:
        for key in ("model", "model_slug"):
            value = event.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip(), "event-stream"
        for container in ("thread", "turn", "session", "config"):
            nested = event.get(container)
            if isinstance(nested, dict):
                value = nested.get("model")
                if isinstance(value, str) and value.strip():
                    return value.strip(), "event-stream"
    return None, None


def _agent_message(events):
    text = None
    for event in events:
        if event.get("type") != "item.completed":
            continue
        item = event.get("item")
        if isinstance(item, dict) and item.get("type") == "agent_message":
            candidate = item.get("text")
            if isinstance(candidate, str):
                text = candidate
    return text


def _error_messages(events):
    """The prose surfaces codex puts an error on: a top-level error event and
    turn.failed's nested error. Both carry the message as a JSON *string*, so
    a status code arrives as text inside text."""
    messages = []
    for event in events:
        if event.get("type") == "error":
            message = event.get("message")
            if isinstance(message, str):
                messages.append(message)
        if event.get("type") == "turn.failed":
            error = event.get("error")
            if isinstance(error, dict) and isinstance(error.get("message"), str):
                messages.append(error["message"])
    return messages


def _reported_statuses(events):
    """HTTP-ish status codes dug out of those nested JSON strings. Structural
    evidence outranks wording, and on this lane the structure is one layer
    down: a rejected turn reports `{"type":"error","status":400,...}` as the
    text of turn.failed.error.message (verified live, #142)."""
    statuses = []
    for message in _error_messages(events):
        try:
            payload = json.loads(message)
        except (json.JSONDecodeError, ValueError):
            continue
        if not isinstance(payload, dict):
            continue
        for candidate in (payload, payload.get("error")):
            if isinstance(candidate, dict):
                status = candidate.get("status") or candidate.get("status_code")
                if isinstance(status, int) and not isinstance(status, bool):
                    statuses.append(status)
    return statuses


def _prose_surfaces(call, events):
    # stdout is JSONL carrying usage.input_tokens and similar numerics, so
    # scanning it whole would read a token count as a rate limit — the #69 bug
    # in codex clothing. Only stderr and the error events are prose. They are
    # joined with a separator, never concatenated, so a digit ending one
    # surface cannot complete "429" with a digit starting the next.
    return "\n".join([call["stderr"]] + _error_messages(events))


def _is_quota(call, events):
    if 429 in _reported_statuses(events):
        return True
    errorish = call["returncode"] != 0 or any(
        event.get("type") == "turn.failed" for event in events
    )
    if not errorish:
        return False
    return bool(QUOTA_RE.search(_prose_surfaces(call, events)))


def _is_auth_denial(call, events):
    """Only called from inside the errorish gate, and only after quota has
    already been ruled out, so the caller owns both of those conditions."""
    if 401 in _reported_statuses(events):
        return True
    return bool(AUTH_RE.search(_prose_surfaces(call, events)))


def _verdict_text(call, events):
    """The -o file is the contract. The agent message is a fallback for the
    case where codex answered but wrote no file, and only when the turn
    actually completed: salvaging text from a turn that failed or was killed
    is how a courier reports PASS on a call that never finished."""
    if call["out_text"].strip():
        return call["out_text"].strip()
    terminal = _terminal(events)
    completed = isinstance(terminal, dict) and terminal.get("type") == "turn.completed"
    if completed and call["returncode"] == 0:
        message = _agent_message(events)
        if message and message.strip():
            return message.strip()
    return ""


def _model_matches(echoed, resolved):
    """Exact, after trimming and case folding. Nothing else.

    A looser rule was tempting: `gpt-5.6` for `gpt-5.6-terra` is the far side
    shortening its own name rather than a different model answering, so
    treating a family truncation as a match would classify it correctly. But
    the classification isn't what this decides. Since the echo can no longer
    block a crossing, matching leniently buys nothing and costs the record:
    `gpt-5.6` is the precise string #142 was filed over, and a rule that calls
    it a match is a rule under which that incident leaves no trace.
    """
    if not isinstance(echoed, str) or not echoed.strip():
        return False
    return echoed.strip().lower() == (resolved or "").strip().lower()


def _validate_structured_output(text, task_id, resolved_model):
    """Returns (verdict, echoed_model, reason). The verdict comes back with
    `model` already stamped locally."""
    if not text:
        return None, None, "codex produced no structured verdict output"
    try:
        verdict = json.loads(text)
    except (json.JSONDecodeError, ValueError) as error:
        return None, None, f"codex output was not JSON: {error}"
    if not isinstance(verdict, dict):
        return None, None, "codex output was not a JSON object"

    echoed = verdict.get("model")
    echoed = echoed if isinstance(echoed, str) else None

    # Identity the far side genuinely knows: which task it judged, what role it
    # was filling, whose API answered. `model` is not on that list — a model
    # asked to write its own name is guessing, and this stamps the fact instead
    # of asking for it (#142).
    verdict["model"] = resolved_model

    violation = VALIDATOR.schema_violation(verdict, VALIDATOR.load_schema()[0])
    if violation is None:
        violation = VALIDATOR.semantic_violation(verdict)
    if violation is not None:
        path, reason = violation
        return None, echoed, f"codex output failed verdict validation at {path}: {reason}"

    expected = {
        "task_id": task_id,
        "checker": "checker-courier",
        "vendor": VENDOR,
    }
    for key, want in expected.items():
        if verdict.get(key) != want:
            return (
                None,
                echoed,
                f"codex output {key} was {verdict.get(key)!r}, expected {want!r}",
            )
    return verdict, echoed, None


def _note_divergence(verdict, echoed, resolved, source, raw_path):
    """One info finding, authored by the runner and attributed to it, so the
    substitution is visible in the artifact #34 actually reads."""
    where = raw_path or "the raw response was not retained for this crossing"
    verdict["findings"].append({
        "clause_id": "external-lane",
        "severity": "info",
        "description": (
            f"courier runner: the far side echoed model={echoed!r}; the lane "
            f"ran {resolved!r} (source: {source}). The judgment below is the "
            "vendor's, unchanged."
        ),
        "evidence": f"raw response: {where}",
    })


def _blocked_verdict(task_id, model, description, evidence):
    return _courier_lib.blocked_verdict(
        VALIDATOR, task_id, "checker-courier", VENDOR, model,
        description, evidence,
    )


def _raw_evidence(call):
    parts = []
    if call["stdout"].strip():
        parts.append("stdout:\n" + call["stdout"].strip())
    if call["stderr"].strip():
        parts.append("stderr:\n" + call["stderr"].strip())
    if call["out_text"].strip():
        parts.append("output file:\n" + call["out_text"].strip())
    return "\n\n".join(parts) or "The codex CLI returned no output."


def _discarded_entries(attempt_records):
    """One `--discarded` object per non-final attempt, oldest first, built
    from each attempt's own figures rather than the crossing's cumulative
    ones (#116). Empty when nothing was retried."""
    return [
        {
            "reason": record["reason"] or "no failure reason recorded",
            "duration_ms": record["duration_ms"],
            "exit_code": record["exit_code"],
            "tokens_in": record["tokens_in"],
            "tokens_out": record["tokens_out"],
        }
        for record in attempt_records[:-1]
    ]


def run_courier(task_id, prompt, timeout_seconds=DEFAULT_TIMEOUT_SECONDS,
                model=MODEL):
    started_at = _utc_now()
    started_clock = time.monotonic()
    attempts = 0
    last_call = None
    last_events = []
    malformed_reason = None
    echoed_model = None
    resolved_model = model
    model_source = "requested"
    usage_totals = [None, None, None]
    raw_attempts = []
    attempt_records = []

    for attempt in range(2):
        attempts = attempt + 1
        attempt_clock = time.monotonic()
        call = _run_once(prompt, timeout_seconds, model)
        last_call = call
        events = _events(call)
        last_events = events
        reported, source = _reported_model(events)
        if reported:
            resolved_model, model_source = reported, source

        # Read before the fold below, or this attempt's own cost is gone the
        # instant it merges into the crossing's cumulative totals (#116).
        attempt_tokens_in, attempt_tokens_out, attempt_cost = _usage(events)
        for index, value in enumerate(
            (attempt_tokens_in, attempt_tokens_out, attempt_cost)
        ):
            if value is None:
                continue
            prior = usage_totals[index]
            usage_totals[index] = value if prior is None else prior + value

        raw_attempts.append({
            "attempt": attempts,
            "argv": call["argv"],
            "returncode": call["returncode"],
            "timed_out": call["timed_out"],
            "stdout": call["stdout"],
            "stderr": call["stderr"],
            "output_file": call["out_text"],
        })

        attempt_records.append({
            "reason": None,
            "duration_ms": max(0, int((time.monotonic() - attempt_clock) * 1000)),
            "exit_code": call["returncode"],
            "tokens_in": attempt_tokens_in,
            "tokens_out": attempt_tokens_out,
        })

        duration_ms = max(0, int((time.monotonic() - started_clock) * 1000))

        if _is_quota(call, events):
            # A quota abandonment stays distinguishable from a retried
            # crossing: no discarded entry is invented for whatever happened
            # on an earlier attempt, quota or not (#116).
            return _outcome(
                "quota", None, task_id, LANE, resolved_model, started_at,
                duration_ms, call, usage_totals, attempts,
                _raw_evidence(call), True,
                echoed_model, model_source, None, raw_attempts, None,
            )

        if reported and reported != model:
            # The CLI ran something other than what we asked for. Unlike the
            # echoed name, this is a fact the CLI attested to, so it is a real
            # fault rather than a note.
            description = (
                f"codex reported running {reported!r} for a lane pinned to "
                f"{model!r}"
            )
            break
        if call["missing"]:
            description = "`codex` CLI not found; the codex lane was unavailable"
            break
        if call["timed_out"]:
            description = f"codex exec timed out after {timeout_seconds:g} seconds"
            if not call["stdout"].strip() and not call["stderr"].strip():
                description += (
                    ", producing no output on either stream. Check network "
                    "egress first: a sandboxed session with no DNS looks "
                    "exactly like this."
                )
            break
        errorish = call["returncode"] != 0 or any(
            event.get("type") == "turn.failed" for event in events
        )
        if errorish:
            if _is_auth_denial(call, events):
                description = CODEX_AUTH_HINT
            else:
                statuses = _reported_statuses(events)
                status_note = f" (vendor status {statuses[0]})" if statuses else ""
                description = (
                    f"codex exec exited {call['returncode']} before producing "
                    f"a verdict{status_note}"
                )
            break

        verdict, echoed, malformed_reason = _validate_structured_output(
            _verdict_text(call, events), task_id, resolved_model
        )
        if echoed is not None:
            echoed_model = echoed
        if malformed_reason is None:
            matched = _model_matches(echoed_model, resolved_model)
            return _outcome(
                "verdict", verdict, task_id, LANE, resolved_model, started_at,
                duration_ms, call, usage_totals, attempts, None, False,
                echoed_model, model_source, matched, raw_attempts,
                _discarded_entries(attempt_records),
            )
        if attempt == 0:
            attempt_records[-1]["reason"] = malformed_reason
            continue
        description = (
            "codex structured output remained invalid after one retry: "
            + malformed_reason
        )
        break

    if last_call is None:
        raise CourierError("codex courier made no classified attempt")
    duration_ms = max(0, int((time.monotonic() - started_clock) * 1000))
    evidence = _raw_evidence(last_call)
    return _outcome(
        "verdict",
        _blocked_verdict(task_id, resolved_model, description, evidence),
        task_id, LANE, resolved_model, started_at, duration_ms, last_call,
        usage_totals, attempts, evidence, False,
        echoed_model, model_source,
        _model_matches(echoed_model, resolved_model) if echoed_model else None,
        raw_attempts,
        _discarded_entries(attempt_records),
    )


def _outcome(status, verdict, task_id, lane, model, started_at, duration_ms,
             call, usage_totals, attempts, diagnostic, quota_event,
             echoed_model, model_source, echo_matched, raw_attempts,
             discarded):
    tokens_in, tokens_out, cost_usd = usage_totals
    return {
        "status": status,
        "verdict": verdict,
        # `ledger_record` builds the shape the Codex-host parent validates
        # the claude courier's payload against key for key, so the per-
        # attempt figures ride separately in `_discarded` instead of
        # widening it (#116; T-009 owns widening it for the claude lane).
        "ledger": _courier_lib.ledger_record(
            task_id, lane, model, started_at, duration_ms,
            call["returncode"], tokens_in, tokens_out, cost_usd, quota_event,
        ),
        "attempts": attempts,
        "diagnostic": diagnostic,
        "identity": {
            "model": model,
            "model_source": model_source,
            "echoed_model": echoed_model,
            "echo_matched": echo_matched,
        },
        "raw_attempts": raw_attempts,
        # Internal only, stripped in main() before the outcome reaches
        # stdout: the return contract and the raw-attempts log are both
        # published artifacts, and neither one's shape changes for this.
        "_discarded": discarded,
    }


def _should_keep_raw(outcome, policy):
    if policy == "always":
        return True
    if policy == "never":
        return False
    return bool(
        outcome["diagnostic"]
        or outcome["identity"]["echo_matched"] is False
        or outcome["attempts"] > 1
    )


def _persist(outcome, task_id, tier, retries, project_root, brief, keep_raw):
    """Verdict, rendered sibling, then the ledger. On quota the ledger line
    comes before the sentinel, always: a sentinel with no line explaining it is
    unaccounted exhaustion, and the reverse order is a two-step that a prompt
    following agent gets backwards under pressure."""
    stem = f"{task_id}-{tier}-r{retries}-{LANE}"
    state = os.path.join(project_root, ".agent-guild", "state")
    record = {
        "verdict_path": None, "rendered_path": None, "raw_path": None,
        "ledger_appended": False, "sentinel_path": None,
    }

    raw_path = None
    if _should_keep_raw(outcome, keep_raw):
        raw_dir = os.path.join(state, "log", "courier-raw")
        os.makedirs(raw_dir, exist_ok=True)
        raw_path = os.path.join(raw_dir, f"{stem}.jsonl")
        with open(raw_path, "w", encoding="utf-8") as stream:
            for entry in outcome["raw_attempts"]:
                entry = dict(entry, identity=outcome["identity"])
                stream.write(json.dumps(entry, ensure_ascii=False) + "\n")
        record["raw_path"] = os.path.relpath(raw_path, project_root)

    artifacts = []
    if outcome["status"] == "verdict":
        verdict = outcome["verdict"]
        if outcome["identity"]["echo_matched"] is False:
            _note_divergence(
                verdict,
                outcome["identity"]["echoed_model"],
                outcome["identity"]["model"],
                outcome["identity"]["model_source"],
                record["raw_path"],
            )
        verdicts_dir = os.path.join(state, "verdicts")
        os.makedirs(verdicts_dir, exist_ok=True)
        verdict_path = os.path.join(verdicts_dir, f"{stem}.json")
        with open(verdict_path, "w", encoding="utf-8") as stream:
            json.dump(verdict, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        record["verdict_path"] = os.path.relpath(verdict_path, project_root)

        rendered_path = os.path.join(verdicts_dir, f"{stem}.md")
        rendered = subprocess.run(
            [sys.executable, RENDERER_PATH, verdict_path, "--out", rendered_path],
            capture_output=True, text=True, cwd=project_root,
        )
        if rendered.returncode != 0:
            raise CourierError(
                f"render-verdict.py exited {rendered.returncode}: "
                f"{rendered.stderr.strip()}"
            )
        record["rendered_path"] = os.path.relpath(rendered_path, project_root)
        artifacts = [record["verdict_path"], record["rendered_path"]]

    _append_ledger(
        outcome["ledger"], artifacts, project_root, brief,
        outcome["attempts"], outcome["_discarded"],
    )
    record["ledger_appended"] = True

    if outcome["status"] == "quota":
        exhausted_dir = os.path.join(state, "exhausted")
        os.makedirs(exhausted_dir, exist_ok=True)
        sentinel = os.path.join(exhausted_dir, LANE)
        with open(sentinel, "w", encoding="utf-8") as stream:
            stream.write(
                f"{LANE} lane reported exhaustion at {outcome['ledger']['started_at']}\n"
            )
        record["sentinel_path"] = os.path.relpath(sentinel, project_root)
    return record


def _append_ledger(ledger, artifacts, project_root, brief, attempts, discarded):
    argv = [
        sys.executable, LEDGER_PATH,
        "--task-id", ledger["task_id"],
        "--vendor", ledger["vendor"],
        "--model", ledger["model"],
        "--started-at", ledger["started_at"],
        "--duration-ms", str(ledger["duration_ms"]),
        "--exit-code", str(ledger["exit_code"]),
    ]
    if ledger["tokens_in"] is not None:
        argv += ["--tokens-in", str(ledger["tokens_in"])]
    if ledger["tokens_out"] is not None:
        argv += ["--tokens-out", str(ledger["tokens_out"])]
    if ledger["quota_event"]:
        argv += ["--quota-event"]
    if brief:
        argv += ["--brief", brief]
    argv += ["--attempts", str(attempts)]
    for entry in discarded or []:
        argv += ["--discarded", json.dumps(entry)]
    # Repo-relative and verified on disk. Ten rows in one archived ledger name
    # absolute paths under a home directory that does not exist here (#47).
    verified = [
        rel for rel in (
            _courier_lib.repo_relative(path, project_root) for path in artifacts
        ) if rel
    ]
    argv += ["--artifacts"] + verified
    # cwd is the project root, not the isolated temp dir: ledger-append.py
    # resolves both the default ledger path and spec.md's provenance ref
    # relative to cwd, so running it elsewhere silently drops `job`.
    result = subprocess.run(argv, capture_output=True, text=True, cwd=project_root)
    if result.returncode != 0:
        raise CourierError(
            f"ledger-append.py exited {result.returncode}: {result.stderr.strip()}"
        )


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Run the fixed codex exec second-opinion boundary."
    )
    parser.add_argument("--task-id", required=True)
    parser.add_argument("--tier", default=None,
                        help="executor tier; with --retries, selects persistence mode")
    parser.add_argument("--retries", default=None,
                        help="retry round; with --tier, selects persistence mode")
    parser.add_argument("--brief", default=None,
                        help="brief path, recorded as brief_tokens on the ledger row")
    parser.add_argument("--project-root", default=DEFAULT_PROJECT_ROOT)
    parser.add_argument("--model", default=MODEL)
    parser.add_argument("--keep-raw", default="onissue",
                        choices=("onissue", "always", "never"))
    parser.add_argument("--dry-run", action="store_true", default=False,
                        help="never write; print the outcome and exit")
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=DEFAULT_TIMEOUT_SECONDS,
        help=f"wall-clock bound per attempt (default: {DEFAULT_TIMEOUT_SECONDS:g})",
    )
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    prompt = sys.stdin.read()
    invalid = _courier_lib.validate_courier_args(
        "codex-courier", args.task_id, args.timeout_seconds, prompt
    )
    if invalid:
        sys.stderr.write(invalid + "\n")
        return 2
    # Half a stem is worse than none: it would name a verdict file for a retry
    # round nobody ran.
    if (args.tier is None) != (args.retries is None):
        sys.stderr.write(
            "codex-courier: --tier and --retries go together or not at all\n"
        )
        return 2
    if args.dry_run and args.tier is not None:
        sys.stderr.write(
            "codex-courier: --dry-run cannot persist; drop --tier/--retries\n"
        )
        return 2

    try:
        outcome = run_courier(
            args.task_id, prompt,
            timeout_seconds=args.timeout_seconds,
            model=args.model,
        )
        persisting = args.tier is not None and not args.dry_run
        outcome["persisted"] = _persist(
            outcome, args.task_id, args.tier, args.retries,
            args.project_root, args.brief, args.keep_raw,
        ) if persisting else None
    except (CourierError, OSError, ValueError) as error:
        sys.stderr.write(f"codex-courier: {error}\n")
        return 2
    published = {
        k: v for k, v in outcome.items() if k not in ("raw_attempts", "_discarded")
    }
    json.dump(published, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
