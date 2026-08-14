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

`--attempts N` records how many times a retried crossing was attempted
before this row's own result. `--discarded JSON` is repeatable, one JSON
object per discarded attempt (`{"reason": ..., "duration_ms": ..., "exit_code":
..., "tokens_in": ..., "tokens_out": ...}`), oldest attempt first. Both are
optional and, unlike the nullable fields above, are left out of the line
entirely when omitted — the same spelling `job` uses — because a retry does
not turn one crossing into two rows, and every row written before #116
carries neither key. A discarded attempt whose own token figures the vendor
never reported writes `null` for them, the same rule the top-level fields
follow, never a fabricated `0`.

Every `--artifacts` value that resolves under the repo root (`os.getcwd()`,
same base as `DEFAULT_LEDGER`) is rewritten to a repo-relative path before
the line is validated — an absolute path under the root is a path that
stops resolving the moment the row is read from anywhere else. A value
already relative is left alone, and a value that resolves outside the root
is written exactly as given rather than as a `../` chain, which would
resolve nowhere but this one working directory. This is a backstop, not a
replacement for `_courier_lib.repo_relative`'s existence-checking pre-pass:
it relativizes whether or not a file sits at the path.

`job` names the guild run a call belongs to, so two runs' rows stay
distinguishable after `.agent-guild/state/` is wiped between them. It's
resolved in this order and no other:

1. `--job VALUE`, when passed.
2. Otherwise, the `ref` field from `.agent-guild/state/spec.md`'s
   provenance header, read from the current working directory. That's the
   same assumption `DEFAULT_LEDGER` already makes, and deliberately not
   this script's own location: the script gets copied into other projects,
   where a script-relative path would find this repo's spec while
   appending to that project's ledger.
3. Otherwise, the key is left out of the line entirely. There's no null
   spelling for it—a row either names its job or it doesn't.

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
import re
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SCHEMA_PATH = os.path.normpath(
    os.path.join(SCRIPT_DIR, "..", "schemas", "vendor-call.schema.json")
)
DEFAULT_LEDGER = os.path.join(
    os.getcwd(), ".agent-guild", "state", "log", "vendor-calls.jsonl"
)
# Same cwd assumption as DEFAULT_LEDGER, not SCRIPT_DIR: this script is
# copied into other projects, and a script-relative path would find this
# repo's spec.md while appending to that project's ledger.
SPEC_PATH = os.path.join(os.getcwd(), ".agent-guild", "state", "spec.md")

FM_REF_RE = re.compile(r"^ref:\s*(.*)$")


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


def derive_job(spec_path=SPEC_PATH):
    """Return the `ref` value from spec_path's provenance frontmatter, or
    None if the file is missing or carries no `ref:` line. Only reads the
    leading `--- ... ---` block, matching the header the /job intake skill
    writes — see check-provenance.py for the fuller version of this parser."""
    try:
        with open(spec_path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return None

    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = FM_REF_RE.match(line)
        if not m:
            continue
        val = m.group(1).strip()
        # At most one matching quote pair — never str.strip("'\""), which
        # trims any number of quote characters regardless of balance (#127).
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        return val or None
    return None


def relativize_artifact(path, root):
    """Rewrite one --artifacts value to be relative to `root` if it resolves
    under it; otherwise return it untouched (#47).

    A value that is already relative is left alone outright — it never
    reaches the absolute-path branch below, so there's no risk of a
    `sub/../a.py`-shaped input round-tripping through normpath into a
    different-looking string that still means the same file. An absolute
    value outside `root` is returned exactly as given: relpath() would
    happily emit a `../` chain (an artifact under /var/folders/... becomes
    `../../../var/folders/...`), and that chain resolves nowhere but the one
    working directory it was computed from. Deliberately not
    existence-gated, unlike `_courier_lib.repo_relative` — a path under the
    root is relativized whether or not a file sits there, because this is a
    backstop for every caller that isn't that helper's own pre-pass.
    """
    if not path or not os.path.isabs(path):
        return path
    normalized = os.path.normpath(path)
    root_norm = os.path.normpath(root)
    if normalized == root_norm or normalized.startswith(root_norm + os.sep):
        return os.path.relpath(normalized, root_norm)
    return path


def relativize_artifacts(artifacts, root):
    return [relativize_artifact(a, root) for a in artifacts]


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

    # --job wins outright; otherwise fall back to spec.md's provenance ref;
    # otherwise the key is left out entirely — never written as null.
    job = args.job if args.job is not None else derive_job()
    if job is not None:
        line["job"] = job

    # Same posture as job: a retry does not turn one crossing into two rows,
    # so an omitted --attempts/--discarded leaves the key out entirely rather
    # than writing a default — attempts is typed plain integer, not nullable,
    # so a written-but-empty value has no valid spelling anyway.
    if args.attempts is not None:
        line["attempts"] = args.attempts
    if args.discarded is not None:
        line["discarded"] = args.discarded

    return line, None


def append_line(line, ledger_path):
    """Append `line` to `ledger_path` as one newline-terminated JSON line,
    creating the directory and file on demand. Deliberately never opens the
    file for reading first: append-only means append-only, even when the
    file already holds a malformed line that would trip a reader — this
    call must not be the thing that notices or touches that line.

    Concurrent since waves (#164): a wave can have several couriers in
    flight, each writing its own row here, and this is the file #34 drew its
    conclusions from, so a torn row costs more than a lost log line would.
    Safe by deliberate reliance on O_APPEND (what "a" mode opens with) plus
    one write(2) per row: a ledger row runs a few hundred bytes today, well
    under PIPE_BUF, and the kernel won't interleave two writes that size. A
    row that ever outgrows PIPE_BUF voids that, so keep them small. No lock:
    fcntl would buy nothing here and cost NFS failure modes."""
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
    ap.add_argument("--attempts", type=int, default=None, help="how many times the crossing was attempted; omit for a single-attempt row")
    ap.add_argument(
        "--discarded",
        action="append",
        type=json.loads,
        default=None,
        metavar="JSON",
        help="one JSON object per discarded attempt, repeatable, oldest first; omit for none",
    )
    ap.add_argument(
        "--job",
        default=None,
        metavar="VALUE",
        help="job this call belongs to; defaults to spec.md's provenance ref, then omitted",
    )
    ap.add_argument("--brief", default=None, metavar="PATH", help="brief file; sets brief_tokens to bytes/4 and tokenizer to heuristic-bytes/4")
    ap.add_argument("--ledger", default=DEFAULT_LEDGER, metavar="PATH", help="ledger file (default: .agent-guild/state/log/vendor-calls.jsonl)")
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    # Runs before build_line/schema_violation: a path the schema has already
    # accepted is a path the ledger has already committed to (#47).
    args.artifacts = relativize_artifacts(args.artifacts, os.getcwd())

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
