#!/usr/bin/env python3
"""Run the fixed Claude CLI boundary for a Codex-hosted second opinion.

The prompt arrives on stdin and must already contain the Task-ID, brief,
artifact contents, and locally collected evidence. This runner never asks the
far side to read a repository path or execute a command. It invokes one pinned
Claude model with no tools, no MCP servers, plan permissions, no persistence,
a closed child stdin, and an isolated temporary cwd.

Stdout is one JSON outcome for the read-only courier to return to its parent:

    {
      "status": "verdict" | "quota",
      "verdict": <validated verdict object> | null,
      "ledger": <arguments for ledger-append.py>,
      "attempts": 1 | 2,
      "diagnostic": <string> | null
    }

Malformed structured output is retried once. Missing CLI access,
authentication and other process failures, repeated malformed output, and the
wall-clock bound produce a schema-conforming blocked second opinion. A quota
signal produces no verdict; the parent records the ledger line before creating
state/exhausted/claude.
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
MODEL = "claude-haiku-4-5-20251001"
DEFAULT_TIMEOUT_SECONDS = 120.0

# Both lanes share these; see _courier_lib for why the 429 boundary is the
# part worth stating once.
CourierError = _courier_lib.CourierError
QUOTA_RE = _courier_lib.QUOTA_RE
AUTH_RE = _courier_lib.AUTH_RE
VALIDATOR = _courier_lib.load_validator(VALIDATOR_PATH)
_utc_now = _courier_lib.utc_now
_number = _courier_lib.number


def _adapted_schema():
    try:
        with open(SCHEMA_PATH, encoding="utf-8") as stream:
            schema = json.load(stream)
    except (OSError, json.JSONDecodeError) as error:
        raise CourierError(
            f"cannot read canonical verdict schema {SCHEMA_PATH}: {error}"
        ) from error
    if not isinstance(schema, dict):
        raise CourierError(
            f"canonical verdict schema {SCHEMA_PATH} is not an object"
        )
    adapted = dict(schema)
    adapted.pop("$schema", None)
    return adapted


def _command(prompt):
    schema = json.dumps(
        _adapted_schema(), separators=(",", ":"), ensure_ascii=False
    )
    return [
        "claude",
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
        schema,
        prompt,
    ]


def _run_once(prompt, timeout_seconds):
    if shutil.which("claude") is None:
        return {
            "returncode": 127,
            "stdout": "",
            "stderr": "`claude` CLI not found on PATH",
            "timed_out": False,
            "missing": True,
        }

    with tempfile.TemporaryDirectory(
        prefix="agent-guild-claude-courier-"
    ) as isolated_cwd:
        try:
            process = subprocess.run(
                _command(prompt),
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
            }
        except subprocess.TimeoutExpired as error:
            stdout = error.stdout or ""
            stderr = error.stderr or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode("utf-8", errors="replace")
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", errors="replace")
            return {
                "returncode": 124,
                "stdout": stdout,
                "stderr": stderr,
                "timed_out": True,
                "missing": False,
            }
        except FileNotFoundError:
            return {
                "returncode": 127,
                "stdout": "",
                "stderr": "`claude` CLI not found on PATH",
                "timed_out": False,
                "missing": True,
            }


def _raw_evidence(call):
    parts = []
    if call["stdout"].strip():
        parts.append("stdout:\n" + call["stdout"].strip())
    if call["stderr"].strip():
        parts.append("stderr:\n" + call["stderr"].strip())
    return "\n\n".join(parts) or "The Claude CLI returned no output."


def _parse_envelope(call):
    raw = call["stdout"].strip()
    if not raw:
        return None, "Claude CLI stdout was empty"
    try:
        envelope = json.loads(raw)
    except json.JSONDecodeError as error:
        return None, f"Claude CLI stdout was not JSON: {error}"
    if not isinstance(envelope, dict):
        return None, "Claude CLI JSON envelope was not an object"
    return envelope, None


def _prose_surfaces(call, envelope):
    # stdout carries the serialized JSON envelope, so scanning it as text
    # reads numeric fields like duration_ms as if they were prose—the
    # bug #69 exists to fix. Only stderr (always) and result (only on an
    # API-error envelope) are prose surfaces worth pattern-matching.
    # They're joined with a separator, not concatenated raw, so a digit
    # trailing one surface can never complete "429" with a digit leading
    # the other.
    surfaces = [call["stderr"]]
    if (
        isinstance(envelope, dict)
        and envelope.get("terminal_reason") == "api_error"
    ):
        surfaces.append(str(envelope.get("result", "")))
    return "\n".join(surfaces)


def _is_quota(call, envelope):
    # Structural signal outranks wording: a real 429 status classifies as
    # quota even outside the errorish gate (e.g. a "completed" envelope
    # whose api_error_status still reports the retry-exhausted 429 #52
    # never observed but the fallback guards against).
    if isinstance(envelope, dict) and envelope.get("api_error_status") == 429:
        return True
    errorish = call["returncode"] != 0 or (
        isinstance(envelope, dict) and envelope.get("is_error") is True
    )
    if not errorish:
        return False
    return bool(QUOTA_RE.search(_prose_surfaces(call, envelope)))


def _is_auth_denial(call, envelope):
    """Only called from inside the errorish gate, and only after quota has
    already been ruled out, so the caller owns both of those conditions."""
    return bool(AUTH_RE.search(_prose_surfaces(call, envelope)))


def _validate_structured_output(envelope, task_id):
    if envelope.get("type") != "result":
        return None, "Claude CLI envelope type was not 'result'"
    if envelope.get("subtype") != "success":
        return None, "Claude CLI envelope subtype was not 'success'"
    if envelope.get("is_error") is not False:
        return None, "Claude CLI envelope did not report is_error: false"
    if envelope.get("terminal_reason") != "completed":
        return None, "Claude CLI envelope did not terminate as completed"
    verdict = envelope.get("structured_output")
    if not isinstance(verdict, dict):
        return None, "Claude CLI envelope omitted object structured_output"

    violation = VALIDATOR.schema_violation(
        verdict, VALIDATOR.load_schema()[0]
    )
    if violation is None:
        violation = VALIDATOR.semantic_violation(verdict)
    if violation is not None:
        path, reason = violation
        return None, f"structured_output failed verdict validation at {path}: {reason}"

    # `model` is absent from this list on purpose. The far side knows which
    # task it judged, which role it was filling, and whose API answered; it
    # does not know its own name, it is only repeating one it was handed. The
    # codex lane lost a sound judgment to that distinction (#142), so identity
    # is stamped below rather than demanded here.
    expected_identity = {
        "task_id": task_id,
        "checker": "checker-courier",
        "vendor": "anthropic",
    }
    for key, expected in expected_identity.items():
        if verdict.get(key) != expected:
            return (
                None,
                f"structured_output {key} was {verdict.get(key)!r}, "
                f"expected {expected!r}",
            )
    verdict["model"] = MODEL

    # This check survives the change above, because it is not a self-report:
    # modelUsage is the CLI's own accounting of which model it billed, which
    # is exactly the vendor-structural evidence the codex lane turned out not
    # to have.
    model_usage = envelope.get("modelUsage")
    if isinstance(model_usage, dict) and model_usage:
        unexpected = sorted(set(model_usage) - {MODEL})
        if unexpected or MODEL not in model_usage:
            return (
                None,
                "Claude CLI modelUsage did not identify only the pinned "
                f"model {MODEL!r}: {sorted(model_usage)!r}",
            )
    return verdict, None


def _usage(envelope):
    usage = envelope.get("usage")
    usage = usage if isinstance(usage, dict) else {}
    tokens_in = _number(usage.get("input_tokens"), int)
    tokens_out = _number(usage.get("output_tokens"), int)
    cost_usd = _number(envelope.get("total_cost_usd"), (int, float))

    model_usage = envelope.get("modelUsage")
    selected = (
        model_usage.get(MODEL)
        if isinstance(model_usage, dict)
        and isinstance(model_usage.get(MODEL), dict)
        else {}
    )
    if tokens_in is None:
        tokens_in = _number(selected.get("inputTokens"), int)
    if tokens_out is None:
        tokens_out = _number(selected.get("outputTokens"), int)
    if cost_usd is None:
        cost_usd = _number(selected.get("costUSD"), (int, float))
    return tokens_in, tokens_out, cost_usd


def _blocked_verdict(task_id, description, evidence):
    return _courier_lib.blocked_verdict(
        VALIDATOR, task_id, "checker-courier", "anthropic", MODEL,
        description, evidence,
    )


def _discarded_entries(attempt_records):
    """One `--discarded`-shaped object per non-final attempt, oldest first,
    built from each attempt's own duration and usage rather than the
    crossing's cumulative figures (#116, mirrored from codex-courier.py).
    Empty when nothing was retried."""
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


def _ledger(
    task_id,
    started_at,
    duration_ms,
    call,
    envelope=None,
    quota_event=False,
    usage_totals=None,
    discarded=None,
):
    if usage_totals is not None:
        tokens_in, tokens_out, cost_usd = usage_totals
    elif isinstance(envelope, dict):
        tokens_in, tokens_out, cost_usd = _usage(envelope)
    else:
        tokens_in = tokens_out = cost_usd = None
    return _courier_lib.ledger_record(
        task_id, "claude", MODEL, started_at, duration_ms,
        call["returncode"], tokens_in, tokens_out, cost_usd, quota_event,
        # Never invented for a quota bailout, even when an earlier attempt
        # was itself discarded first: a quota abandonment stays
        # distinguishable from a retried crossing (#116), so callers on that
        # path simply never pass this.
        discarded=discarded or None,
    )


def run_courier(task_id, prompt, timeout_seconds=DEFAULT_TIMEOUT_SECONDS):
    started_at = _utc_now()
    started_clock = time.monotonic()
    attempts = 0
    last_call = None
    last_envelope = None
    malformed_reason = None
    usage_totals = [None, None, None]
    attempt_records = []

    for attempt in range(2):
        attempts = attempt + 1
        attempt_clock = time.monotonic()
        call = _run_once(prompt, timeout_seconds)
        last_call = call
        envelope, envelope_error = _parse_envelope(call)
        last_envelope = envelope
        attempt_tokens_in = attempt_tokens_out = None
        if isinstance(envelope, dict):
            reported = _usage(envelope)
            attempt_tokens_in, attempt_tokens_out, _attempt_cost = reported
            for index, value in enumerate(reported):
                if value is None:
                    continue
                prior = usage_totals[index]
                usage_totals[index] = value if prior is None else prior + value

        # This attempt's own elapsed time, not the crossing's cumulative
        # clock: a discarded attempt's duration_ms has to say how long THAT
        # call took, or the retry looks free (#116).
        attempt_records.append({
            "reason": None,
            "duration_ms": max(
                0, int((time.monotonic() - attempt_clock) * 1000)
            ),
            "exit_code": call["returncode"],
            "tokens_in": attempt_tokens_in,
            "tokens_out": attempt_tokens_out,
        })

        duration_ms = max(
            0, int((time.monotonic() - started_clock) * 1000)
        )
        if _is_quota(call, envelope):
            return {
                "status": "quota",
                "verdict": None,
                "ledger": _ledger(
                    task_id,
                    started_at,
                    duration_ms,
                    call,
                    envelope,
                    quota_event=True,
                    usage_totals=usage_totals,
                ),
                "attempts": attempts,
                "diagnostic": _raw_evidence(call),
            }

        if call["missing"]:
            description = "`claude` CLI not found; the Claude lane was unavailable"
            break
        if call["timed_out"]:
            description = (
                f"Claude CLI timed out after {timeout_seconds:g} seconds"
            )
            # Silence on both streams for the whole wall clock is the
            # signature of a sandbox with no egress: the CLI retries a
            # transport failure rather than erroring out, so it dies at the
            # bound with nothing to report. Verified 2026-08-10 in a Codex
            # session where DNS did not resolve at all (#92).
            if not call["stdout"].strip() and not call["stderr"].strip():
                description += (
                    ", producing no output on either stream. Check network "
                    "egress first: a sandboxed session with no DNS looks "
                    "exactly like this. `curl -sS -m 10 "
                    "https://api.anthropic.com/v1/messages` fails in "
                    "milliseconds when egress is blocked. On Codex, set "
                    "sandbox_workspace_write.network_access = true."
                )
            break
        if call["returncode"] != 0 or (
            isinstance(envelope, dict) and envelope.get("is_error") is True
        ):
            if _is_auth_denial(call, envelope):
                # "exited 1" once sent a session hunting a login problem that
                # didn't exist. The CLI was logged in; the sandbox was what it
                # couldn't get past (#92). Name the cause here so the blocked
                # verdict reads without that detour.
                description = (
                    "Claude CLI could not authenticate; the lane never "
                    "reached the far side. On macOS the CLI reads its "
                    "credentials from the login keychain, which a sandboxed "
                    "Codex session cannot open, so a terminal that is logged "
                    "in still fails here. Run `claude setup-token` outside "
                    "the sandbox and pass the token it prints to the courier's "
                    "session as CLAUDE_CODE_OAUTH_TOKEN. That is the first of "
                    "two requirements; the sandbox also needs network egress, "
                    "or the credential resolves and the call then hangs until "
                    "the wall clock."
                )
            else:
                description = (
                    f"Claude CLI exited {call['returncode']} before producing "
                    "a verdict"
                )
            break
        if envelope_error is not None:
            malformed_reason = envelope_error
        else:
            verdict, malformed_reason = _validate_structured_output(
                envelope, task_id
            )
            if malformed_reason is None:
                return {
                    "status": "verdict",
                    "verdict": verdict,
                    "ledger": _ledger(
                        task_id,
                        started_at,
                        duration_ms,
                        call,
                        envelope,
                        usage_totals=usage_totals,
                        discarded=_discarded_entries(attempt_records),
                    ),
                    "attempts": attempts,
                    "diagnostic": None,
                }
        if attempt == 0:
            attempt_records[-1]["reason"] = malformed_reason
            continue
        description = (
            "Claude structured_output remained invalid after one retry: "
            + malformed_reason
        )
        break

    if last_call is None:
        raise CourierError("Claude courier made no classified attempt")
    duration_ms = max(0, int((time.monotonic() - started_clock) * 1000))
    evidence = _raw_evidence(last_call)
    return {
        "status": "verdict",
        "verdict": _blocked_verdict(task_id, description, evidence),
        "ledger": _ledger(
            task_id,
            started_at,
            duration_ms,
            last_call,
            last_envelope,
            usage_totals=usage_totals,
            discarded=_discarded_entries(attempt_records),
        ),
        "attempts": attempts,
        "diagnostic": evidence,
    }


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Run the fixed Claude CLI second-opinion boundary."
    )
    parser.add_argument("--task-id", required=True)
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
        "claude-courier", args.task_id, args.timeout_seconds, prompt
    )
    if invalid:
        sys.stderr.write(invalid + "\n")
        return 2

    try:
        outcome = run_courier(
            args.task_id, prompt, timeout_seconds=args.timeout_seconds
        )
    except (CourierError, OSError, ValueError) as error:
        sys.stderr.write(f"claude-courier: {error}\n")
        return 2
    json.dump(outcome, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
