#!/usr/bin/env python3
"""Append one line to the vendor call ledger. This is the only way a courier
should ever write to the ledger — the whole point is that no courier
hand-formats JSONL, so every line is schema-conforming and every nullable
field is genuinely null rather than a guessed zero.

    .agent-guild/scripts/ledger-append.py \\
        --task-id T-007 --vendor codex --model gpt-5.5 \\
        --started-at 2026-07-22T18:00:00Z --duration-ms 41200 --exit-code 0 \\
        --tokens-in 1200 --tokens-out 340 --cost-usd 0.02 \\
        --artifacts a.py b.py --quota-event

`--tokens-in`, `--tokens-out`, and `--cost-usd` default to null when omitted
— never write a fabricated 0 for a figure the vendor didn't report.
`--artifacts` is required but may take zero values for an empty list (the
field itself must always be present). `--brief PATH` computes `brief_tokens`
as that file's byte size divided by 4 and records `tokenizer` as
"heuristic-bytes/4" (a stdlib stand-in — no tiktoken, per the kit's
stdlib-only rule); without `--brief`, both stay null.

The assembled line is validated against vendor-call.schema.json BEFORE the
ledger file is touched. Once valid, exactly one newline-terminated JSON line
is appended to .agent-guild/state/log/vendor-calls.jsonl (or `--ledger PATH`),
creating the directory and file on demand. This script never reads,
rewrites, or repairs existing ledger content — even a ledger with an earlier
malformed line (a courier killed mid-write, say) gets a clean append and
nothing else, so one bad line never blocks the next.

Exit codes: 0 success; 1 invalid input — a schema violation, or a --brief
file that can't be read — stderr names the problem as `ledger-append: <path>:
<reason>`, ledger file untouched. (Missing/mistyped CLI flags are rejected by
argparse itself, also without touching the ledger.)

Stdlib only, so the kit stays copy-in portable. Re-implements, rather than
imports, the conservative JSON Schema keyword walk (type, properties,
required, items, enum, additionalProperties) that validate-verdict.py
already carries for the verdict schema — a second small copy is cheaper than
coupling this script's behavior to changes made for a different schema.
"""
import argparse
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "schemas", "vendor-call.schema.json")
)
DEFAULT_LEDGER = os.path.join(
    os.getcwd(), ".agent-guild", "state", "log", "vendor-calls.jsonl"
)


def _type_name(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def _matches_type(value, expected):
    actual = _type_name(value)
    if expected == "number":
        # JSON Schema's "number" subsumes integers (mirrors
        # validate-verdict.py's identical rule for the same reason).
        return actual in ("number", "integer")
    return actual == expected


def schema_violation(instance, schema, path=""):
    """Return (json_path, reason) for the first thing about `instance` that
    fails `schema`, or None if it conforms. Walks type -> enum -> object
    (required, additionalProperties, properties) -> array (items)."""
    types = schema.get("type")
    if types is not None:
        expected = types if isinstance(types, list) else [types]
        if not any(_matches_type(instance, t) for t in expected):
            want = " or ".join(expected)
            return (
                path or "$",
                f"expected type {want}, got {_type_name(instance)} ({instance!r})",
            )

    if "enum" in schema and instance not in schema["enum"]:
        allowed = ", ".join(repr(v) for v in schema["enum"])
        return path or "$", f"must be one of [{allowed}], got {instance!r}"

    if isinstance(instance, dict) and (
        "properties" in schema or "required" in schema or types == "object"
    ):
        for key in schema.get("required", []):
            if key not in instance:
                return (f"{path}.{key}" if path else key), "required field missing"
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extra = sorted(set(instance) - set(properties))
            if extra:
                return path or "$", f"additional properties not allowed: {extra}"
        for key, subschema in properties.items():
            if key in instance:
                violation = schema_violation(
                    instance[key], subschema, f"{path}.{key}" if path else key
                )
                if violation:
                    return violation

    if isinstance(instance, list) and "items" in schema:
        items_schema = schema["items"]
        for i, item in enumerate(instance):
            violation = schema_violation(item, items_schema, f"{path}[{i}]")
            if violation:
                return violation

    return None


def load_schema(schema_path=SCHEMA_PATH):
    with open(schema_path, encoding="utf-8") as f:
        return json.load(f)


def build_line(args):
    """Assemble the ledger line dict from parsed CLI args. Returns
    (line, None) or (None, error_message) — a --brief file that can't be
    stat'd is the one way this step itself can fail."""
    brief_tokens = None
    tokenizer = None
    if args.brief is not None:
        try:
            brief_tokens = os.path.getsize(args.brief) // 4
        except OSError as e:
            return None, f"--brief {args.brief}: {e}"
        tokenizer = "heuristic-bytes/4"

    line = {
        "task_id": args.task_id,
        "vendor": args.vendor,
        "model": args.model,
        "started_at": args.started_at,
        "duration_ms": args.duration_ms,
        "exit_code": args.exit_code,
        "tokens_in": args.tokens_in,
        "tokens_out": args.tokens_out,
        "cost_usd": args.cost_usd,
        "brief_tokens": brief_tokens,
        "tokenizer": tokenizer,
        "artifacts": args.artifacts,
        "quota_event": args.quota_event,
    }
    return line, None


def append_line(line, ledger_path):
    """Append `line` to `ledger_path` as one newline-terminated JSON line,
    creating the directory and file on demand. Deliberately never opens the
    file for reading first: append-only means append-only, even when the
    file already holds a malformed line that would trip a reader — this
    call must not be the thing that notices or touches that line."""
    ledger_dir = os.path.dirname(ledger_path)
    if ledger_dir:
        os.makedirs(ledger_dir, exist_ok=True)
    with open(ledger_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(line) + "\n")


def parse_args(argv=None):
    ap = argparse.ArgumentParser(
        description="Validate and append one line to the vendor call ledger."
    )
    ap.add_argument("--task-id", required=True)
    ap.add_argument("--vendor", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--started-at", required=True, help="ISO-8601 UTC, e.g. 2026-07-22T18:00:00Z")
    ap.add_argument("--duration-ms", required=True, type=int)
    ap.add_argument("--exit-code", required=True, type=int)
    ap.add_argument("--tokens-in", type=int, default=None, help="omit for null (vendor didn't report)")
    ap.add_argument("--tokens-out", type=int, default=None, help="omit for null (vendor didn't report)")
    ap.add_argument("--cost-usd", type=float, default=None, help="omit for null (vendor didn't report)")
    ap.add_argument(
        "--artifacts",
        nargs="*",
        required=True,
        metavar="PATH",
        help="files verified on disk after the call; pass with no PATHs for an empty list",
    )
    ap.add_argument("--quota-event", action="store_true", default=False)
    ap.add_argument("--brief", default=None, metavar="PATH", help="brief file; sets brief_tokens to bytes/4 and tokenizer to heuristic-bytes/4")
    ap.add_argument("--ledger", default=DEFAULT_LEDGER, metavar="PATH", help="ledger file (default: .agent-guild/state/log/vendor-calls.jsonl)")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)

    line, err = build_line(args)
    if err is not None:
        sys.stderr.write(f"ledger-append: {err}\n")
        return 1

    schema = load_schema()
    violation = schema_violation(line, schema)
    if violation:
        json_path, reason = violation
        sys.stderr.write(f"ledger-append: {json_path}: {reason}\n")
        return 1

    append_line(line, args.ledger)
    print(f"OK: appended to {args.ledger}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
