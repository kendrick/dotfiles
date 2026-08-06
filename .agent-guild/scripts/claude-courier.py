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
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "schemas", "verdict.schema.json")
)
VALIDATOR_PATH = os.path.join(SCRIPT_DIR, "validate-verdict.py")
MODEL = "claude-haiku-4-5-20251001"
DEFAULT_TIMEOUT_SECONDS = 120.0
QUOTA_RE = re.compile(
    r"(?:rate[ -]?limit|quota|usage[ -]?limit|spend(?:ing)?[ -]?cap"
    r"|(?<![\w.])429(?![\w.]))",
    re.IGNORECASE,
)


class CourierError(Exception):
    """The local courier boundary cannot produce a classified outcome."""


def _load_validator():
    spec = importlib.util.spec_from_file_location(
        "agent_guild_validate_verdict", VALIDATOR_PATH
    )
    if spec is None or spec.loader is None:
        raise CourierError(
            f"cannot load verdict validator from {VALIDATOR_PATH}"
        )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


VALIDATOR = _load_validator()


def _utc_now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


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
    # stdout carries the serialized JSON envelope, so scanning it as text
    # reads numeric fields like duration_ms as if they were prose — the
    # bug this task exists to fix. Only stderr (always) and result (only
    # on an API-error envelope) are prose surfaces worth pattern-matching.
    # They're joined with a separator, not concatenated raw, so a digit
    # trailing one surface can never complete "429" with a digit leading
    # the other.
    surfaces = [call["stderr"]]
    if (
        isinstance(envelope, dict)
        and envelope.get("terminal_reason") == "api_error"
    ):
        surfaces.append(str(envelope.get("result", "")))
    text = "\n".join(surfaces)
    return bool(QUOTA_RE.search(text))


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

    expected_identity = {
        "task_id": task_id,
        "checker": "checker-courier",
        "vendor": "anthropic",
        "model": MODEL,
    }
    for key, expected in expected_identity.items():
        if verdict.get(key) != expected:
            return (
                None,
                f"structured_output {key} was {verdict.get(key)!r}, "
                f"expected {expected!r}",
            )

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


def _number(value, expected_type):
    if isinstance(value, bool):
        return None
    return value if isinstance(value, expected_type) else None


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
    verdict = {
        "task_id": task_id,
        "checker": "checker-courier",
        "vendor": "anthropic",
        "model": MODEL,
        "verdict": "blocked",
        "findings": [
            {
                "clause_id": "external-lane",
                "severity": "blocker",
                "description": description,
                "evidence": evidence,
            }
        ],
        "timestamp": _utc_now(),
        "duration_ms": None,
        "cost_usd": None,
    }
    schema, schema_error = VALIDATOR.load_schema()
    if schema_error:
        raise CourierError(schema_error)
    violation = VALIDATOR.schema_violation(verdict, schema)
    if violation is None:
        violation = VALIDATOR.semantic_violation(verdict)
    if violation is not None:
        path, reason = violation
        raise CourierError(
            f"internally generated blocked verdict is invalid at {path}: {reason}"
        )
    return verdict


def _ledger(
    task_id,
    started_at,
    duration_ms,
    call,
    envelope=None,
    quota_event=False,
    usage_totals=None,
):
    if usage_totals is not None:
        tokens_in, tokens_out, cost_usd = usage_totals
    elif isinstance(envelope, dict):
        tokens_in, tokens_out, cost_usd = _usage(envelope)
    else:
        tokens_in = tokens_out = cost_usd = None
    return {
        "task_id": task_id,
        "vendor": "claude",
        "model": MODEL,
        "started_at": started_at,
        "duration_ms": duration_ms,
        "exit_code": call["returncode"],
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "cost_usd": cost_usd,
        "quota_event": quota_event,
    }


def run_courier(task_id, prompt, timeout_seconds=DEFAULT_TIMEOUT_SECONDS):
    started_at = _utc_now()
    started_clock = time.monotonic()
    attempts = 0
    last_call = None
    last_envelope = None
    malformed_reason = None
    usage_totals = [None, None, None]

    for attempt in range(2):
        attempts = attempt + 1
        call = _run_once(prompt, timeout_seconds)
        last_call = call
        envelope, envelope_error = _parse_envelope(call)
        last_envelope = envelope
        if isinstance(envelope, dict):
            reported = _usage(envelope)
            for index, value in enumerate(reported):
                if value is None:
                    continue
                prior = usage_totals[index]
                usage_totals[index] = value if prior is None else prior + value

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
            break
        if call["returncode"] != 0 or (
            isinstance(envelope, dict) and envelope.get("is_error") is True
        ):
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
                    ),
                    "attempts": attempts,
                    "diagnostic": None,
                }
        if attempt == 0:
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
    if not re.fullmatch(r"T-\d+", args.task_id):
        sys.stderr.write(
            "claude-courier: --task-id must have the form T-NNN\n"
        )
        return 2
    if args.timeout_seconds <= 0:
        sys.stderr.write(
            "claude-courier: --timeout-seconds must be positive\n"
        )
        return 2
    if not prompt.strip():
        sys.stderr.write("claude-courier: prompt stdin is empty\n")
        return 2
    if not re.search(
        rf"\bTask-ID:\s*{re.escape(args.task_id)}\b",
        prompt,
        re.IGNORECASE,
    ):
        sys.stderr.write(
            f"claude-courier: prompt does not carry Task-ID: {args.task_id}\n"
        )
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
