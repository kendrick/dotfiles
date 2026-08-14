"""The parts of a courier lane that are the same in both directions.

There are two courier runners, one per lane, and they share almost nothing at
the seams: the Claude CLI answers with a JSON envelope on stdout, `codex exec`
with a JSONL event stream plus a separate `-o` file; usage sits at the envelope
top level on one and inside `turn.completed` on the other. Trying to drive both
from one parameterized engine produces a dispatch table with one caller per
branch, so the runners stay separate and only the genuinely common pieces live
here.

What is common is worth centralizing, because #84 was filed over three couriers
that shared no code and behaved three different ways. The quota and auth
boundaries in particular: `(?<![\\w.])429(?![\\w.])` is guarding against a
`duration_ms` of 4290 reading as a rate limit (#69), and that guard should be
stated once rather than retyped per lane.

The leading underscore marks this as an import target, not something to run.
"""
import importlib.util
import json
import os
import re
from datetime import datetime, timezone


QUOTA_RE = re.compile(
    r"(?:rate[ -]?limit|quota|usage[ -]?limit|spend(?:ing)?[ -]?cap"
    r"|(?<![\w.])429(?![\w.]))",
    re.IGNORECASE,
)
# Same 401 boundary guard as QUOTA_RE's 429, for the same reason.
AUTH_RE = re.compile(
    r"(?:not logged in|please run /login|invalid api key"
    r"|authentication (?:failed|required)|unauthorized"
    r"|(?<![\w.])401(?![\w.]))",
    re.IGNORECASE,
)

TASK_ID_RE = re.compile(r"T-\d+")


class CourierError(Exception):
    """The local courier boundary cannot produce a classified outcome."""


def utc_now():
    """Whole seconds. One archived ledger row carries microseconds where the
    other seventeen don't, which costs nothing until a collector sorts or
    compares these as text (#117)."""
    stamp = datetime.now(timezone.utc).replace(microsecond=0)
    return stamp.isoformat().replace("+00:00", "Z")


def number(value, expected_type):
    """A bool is an int in Python, and `True` tokens would be a lie in the
    ledger, so reject it before the isinstance check can accept it."""
    if isinstance(value, bool):
        return None
    return value if isinstance(value, expected_type) else None


def load_validator(validator_path):
    """Import `validate-verdict.py` despite the hyphen in its name. Both
    runners defer every schema and semantic rule to that one file rather than
    re-deriving conformance, so there is exactly one answer to "is this a
    valid verdict"."""
    spec = importlib.util.spec_from_file_location(
        "agent_guild_validate_verdict", validator_path
    )
    if spec is None or spec.loader is None:
        raise CourierError(
            f"cannot load verdict validator from {validator_path}"
        )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def blocked_verdict(validator, task_id, checker, vendor, model, description,
                    evidence):
    """A schema-conforming `blocked` second opinion, self-validated before it
    is handed back. A courier that emitted an invalid blocked verdict would
    fail the return gate with a message about the verdict rather than about
    the lane failure that actually happened, which is a long way to walk to
    find a missing CLI."""
    verdict = {
        "task_id": task_id,
        "checker": checker,
        "vendor": vendor,
        "model": model,
        "verdict": "blocked",
        "findings": [
            {
                "clause_id": "external-lane",
                "severity": "blocker",
                "description": description,
                "evidence": evidence,
            }
        ],
        "timestamp": utc_now(),
        "duration_ms": None,
        "cost_usd": None,
    }
    schema, schema_error = validator.load_schema()
    if schema_error:
        raise CourierError(schema_error)
    violation = validator.schema_violation(verdict, schema)
    if violation is None:
        violation = validator.semantic_violation(verdict)
    if violation is not None:
        path, reason = violation
        raise CourierError(
            f"internally generated blocked verdict is invalid at {path}: {reason}"
        )
    return verdict


def ledger_record(task_id, vendor, model, started_at, duration_ms, exit_code,
                  tokens_in=None, tokens_out=None, cost_usd=None,
                  quota_event=False, discarded=None):
    """One crossing, one row. `vendor` is the LANE name here, not the
    provider; the verdict's own `vendor` field carries the provider. The two
    disagreeing is what made the #100 archive's rows unreadable.

    `discarded` stays out of the dict entirely when the caller passes
    nothing, rather than landing as `None` or `[]`: codex-courier.py never
    passes it (it routes per-attempt figures straight to `_append_ledger`
    instead, per #116), and the Codex-host parent that validates
    claude-courier.py's returned payload checks this key set by exact
    equality, so an always-present key would break that lane's callers
    (T-009)."""
    record = {
        "task_id": task_id,
        "vendor": vendor,
        "model": model,
        "started_at": started_at,
        "duration_ms": duration_ms,
        "exit_code": exit_code,
        "tokens_in": tokens_in,
        "tokens_out": tokens_out,
        "cost_usd": cost_usd,
        "quota_event": quota_event,
    }
    if discarded is not None:
        record["discarded"] = discarded
    return record


def validate_courier_args(script_name, task_id, timeout_seconds, prompt):
    """The guards every courier owes before it spends a vendor call. Returns
    an error string for stderr, or None to proceed.

    The Task-ID check earns its place: a prompt that doesn't name the task is
    a prompt assembled for some other crossing, and the far side has no way to
    notice."""
    if not re.fullmatch(TASK_ID_RE, task_id or ""):
        return f"{script_name}: --task-id must have the form T-NNN"
    if timeout_seconds <= 0:
        return f"{script_name}: --timeout-seconds must be positive"
    if not (prompt or "").strip():
        return f"{script_name}: prompt stdin is empty"
    if not re.search(rf"\bTask-ID:\s*{re.escape(task_id)}\b", prompt,
                     re.IGNORECASE):
        return f"{script_name}: prompt does not carry Task-ID: {task_id}"
    return None


def parse_jsonl(text):
    """Every line that parses as a JSON object, in order, skipping the rest.

    A CLI is free to print a banner or a warning into a stream it also uses
    for JSONL, and one unparseable line must not poison the whole stream.
    """
    events = []
    for line in (text or "").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if isinstance(event, dict):
            events.append(event)
    return events


def repo_relative(path, root):
    """A ledger artifact path, relative to the project root, or None if the
    file isn't there. Ten rows in one archived ledger carry absolute paths
    under a home directory that doesn't exist on this machine (#47), which
    records nothing at all."""
    if not path:
        return None
    absolute = path if os.path.isabs(path) else os.path.join(root, path)
    if not os.path.exists(absolute):
        return None
    try:
        return os.path.relpath(absolute, root)
    except ValueError:
        return None
