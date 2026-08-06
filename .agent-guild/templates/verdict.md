<!--
GENERATED FILE—do not hand-write this shape. A checker's verdict of record
is JSON (schema: .agent-guild/schemas/verdict.schema.json), written to
state/verdicts/T-NNN-<tier>-r<retries>.json and validated with
.agent-guild/scripts/validate-verdict.py. This .md file is produced from
that JSON by .agent-guild/scripts/render-verdict.py — never fill it in by
hand. What follows is a worked example showing the exact shape the renderer
emits, kept here so the shape stays reviewable without running the tools:
frontmatter carrying the verdict's identity fields, a per-clause results
table, and a Diagnosis section that appears only when `verdict: FAIL`.

`blocked` is not a third flavor of pass/fail—it carries the guild's old
ERROR semantics: the check itself couldn't complete (script crashed, tool
unreachable, vendor quota hit), doesn't count against the worker's retry
budget, and gets fixed-then-re-dispatched rather than reworked.
-->

---
task: T-000
checker: checker-judgment
vendor: anthropic
model: claude-opus-4
verdict: FAIL
checked_at: 2026-01-01T00:00:00Z
---

<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py from the
verdict JSON, the record of record. Edit the JSON and re-render instead. -->

## Per-clause results

| clause | severity | description | evidence |
| ------ | -------- | ------------ | -------- |
| C-1 | blocker | fails to check for a missing schema file | .agent-guild/scripts/validate-verdict.py:42 |

## Diagnosis

- **C-1** (blocker): fails to check for a missing schema file
  evidence: .agent-guild/scripts/validate-verdict.py:42
