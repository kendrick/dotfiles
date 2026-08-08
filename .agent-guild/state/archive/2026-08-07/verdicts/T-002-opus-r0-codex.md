---
task: T-002
checker: checker-courier
vendor: openai
model: gpt-5.6-terra
verdict: FAIL
checked_at: 2026-08-07T19:14:02Z
duration_ms: None
cost_usd: None
---

<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py
from the verdict JSON, the record of record. Edit the JSON and
re-render instead. -->

## Per-clause results

| clause | severity | description | evidence |
| ------ | -------- | ------------ | -------- |
| B-2 | blocker | The Homebrew degenerate failure summary names no failing Brewfile item, violating the per-item naming requirement. | When brew exits non-zero without matching a parsed entry, it emits: "Homebrew ran and exited $bundle_status without naming a failed entry. Its output is above." Raw output above it cannot replace the script's own named-item summary. |

## Diagnosis

- **B-2** (blocker): The Homebrew degenerate failure summary names no failing Brewfile item, violating the per-item naming requirement.
  evidence: When brew exits non-zero without matching a parsed entry, it emits: "Homebrew ran and exited $bundle_status without naming a failed entry. Its output is above." Raw output above it cannot replace the script's own named-item summary.
