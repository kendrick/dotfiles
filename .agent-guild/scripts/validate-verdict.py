#!/usr/bin/env python3
"""Validate a checker verdict JSON file against verdict.schema.json, plus the
two semantic rules a structured-output-safe schema can't express itself
(no if/then): a `fail` verdict must carry at least one finding, and every
finding's `evidence` must be non-empty.

    .agent-guild/scripts/validate-verdict.py FILE

The schema stays a plain, externally-validatable draft 2020-12 document (see
.agent-guild/schemas/verdict.schema.json); this script re-implements just the
conservative keyword subset that schema is documented to use (type,
properties, required, items, enum, additionalProperties) rather than pulling
in a generic JSON Schema engine, so the kit stays stdlib-only and copy-in
portable.

Exit codes: 0 conforming; 1 the file violates the schema or a semantic rule
(malformed JSON, a missing/mistyped required field, a bad enum value, a fail
verdict with zero findings, a finding with empty evidence) — stderr names the
failing JSON path, e.g. `findings[0].evidence`; 3 infra error (file or
schema unreadable).
"""
import argparse
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "schemas", "verdict.schema.json")
)


def load_schema(schema_path=SCHEMA_PATH):
    """(schema_dict, None) or (None, error_message)."""
    try:
        with open(schema_path, encoding="utf-8") as f:
            raw = f.read()
    except OSError as e:
        return None, f"cannot read schema {schema_path}: {e}"
    try:
        return json.loads(raw), None
    except json.JSONDecodeError as e:
        return None, f"schema {schema_path} is malformed JSON: {e}"


def load_verdict(path):
    """(data, None) on success, or (None, (kind, json_path, reason))."""
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
    except OSError as e:
        return None, ("infra", path, f"cannot read file: {e}")
    try:
        return json.loads(raw), None
    except json.JSONDecodeError as e:
        return None, ("content", path, f"malformed JSON: {e}")


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
        # JSON Schema's "number" subsumes integers; ours never emits bare
        # "integer" where a plain "number" instance (e.g. 1.0) is meant.
        return actual in ("number", "integer")
    return actual == expected


def _join(path, key):
    return key if not path else f"{path}.{key}"


def _index(path, i):
    return f"{path}[{i}]"


def schema_violation(instance, schema, path=""):
    """Return (json_path, reason) for the first thing about `instance` that
    fails `schema`, or None if it conforms. Walks type -> enum -> object
    (required, additionalProperties, properties) -> array (items), in that
    order, so the reported path is always the first field worth fixing."""
    types = schema.get("type")
    if types is not None:
        # `type` can be a list, e.g. ["integer", "null"] — that's how
        # verdict.schema.json marks duration_ms/cost_usd nullable while still
        # listing them in `required` (OpenAI's strict structured-output mode
        # rejects a schema that leaves any property out of `required`, so
        # "optional" has to be expressed as a nullable type instead).
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
                return _join(path, key), "required field missing"
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extra = sorted(set(instance) - set(properties))
            if extra:
                return path or "$", f"additional properties not allowed: {extra}"
        for key, subschema in properties.items():
            if key in instance:
                violation = schema_violation(instance[key], subschema, _join(path, key))
                if violation:
                    return violation

    if isinstance(instance, list) and "items" in schema:
        items_schema = schema["items"]
        for i, item in enumerate(instance):
            violation = schema_violation(item, items_schema, _index(path, i))
            if violation:
                return violation

    return None


def semantic_violation(data):
    """The two rules a conditional would express if the schema could use
    one. Returns (json_path, reason) or None. Assumes `data` already passed
    schema_violation — callers are expected to check schema first."""
    findings = data.get("findings", [])
    if data.get("verdict") == "fail" and len(findings) == 0:
        return "findings", "verdict is 'fail' but findings is empty; a fail verdict must carry at least one finding"
    for i, finding in enumerate(findings):
        evidence = finding.get("evidence")
        if not isinstance(evidence, str) or not evidence.strip():
            return _index("findings", i) + ".evidence", "evidence must be a non-empty string"
    return None


def validate(path):
    """Validate the verdict JSON file at `path`. Returns a dict:
    {ok, kind, path, reason, data} — `kind` is "infra" or "content" on
    failure, None on success; `data` is the parsed JSON when parsing got
    that far (None on a load failure), so callers like render-verdict.py can
    reuse it without re-reading the file."""
    schema, err = load_schema()
    if err:
        return {"ok": False, "kind": "infra", "path": SCHEMA_PATH, "reason": err, "data": None}

    data, load_err = load_verdict(path)
    if load_err:
        kind, json_path, reason = load_err
        return {"ok": False, "kind": kind, "path": json_path, "reason": reason, "data": None}

    violation = schema_violation(data, schema)
    if violation:
        json_path, reason = violation
        return {"ok": False, "kind": "content", "path": json_path, "reason": reason, "data": data}

    violation = semantic_violation(data)
    if violation:
        json_path, reason = violation
        return {"ok": False, "kind": "content", "path": json_path, "reason": reason, "data": data}

    return {"ok": True, "kind": None, "path": None, "reason": None, "data": data}


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Validate a checker verdict JSON file against verdict.schema.json "
        "plus the two semantic rules the schema can't express."
    )
    ap.add_argument("file", help="path to a verdict JSON file, e.g. state/verdicts/T-001-sonnet-r0.json")
    args = ap.parse_args(argv)

    result = validate(args.file)
    if not result["ok"]:
        sys.stderr.write(f"validate-verdict: {result['path']}: {result['reason']}\n")
        return 3 if result["kind"] == "infra" else 1

    print(f"OK: {args.file} is a conforming verdict")
    return 0


if __name__ == "__main__":
    sys.exit(main())
