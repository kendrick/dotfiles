---
task: T-001
checker: checker-courier
vendor: openai
model: gpt-5.6-terra
verdict: FAIL
checked_at: 2026-08-06T00:00:00Z
duration_ms: None
cost_usd: None
---

<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py
from the verdict JSON, the record of record. Edit the JSON and
re-render instead. -->

## Per-clause results

| clause | severity | description | evidence |
| ------ | -------- | ------------ | -------- |
| V-2 | major | The supplied output proves the suite terminated but does not identify or demonstrate execution of the formerly hanging apps.bats case. | Suite output only shows final cases 100–102; no output names, source diff, or targeted invocation ties successful completion to the former apps.bats:256 case. |
| V-2 | major | The supplied scope evidence proves dot_local/ is unchanged but does not prove the fix is confined to tests/apps.bats. | `git diff --stat -- dot_local/` is empty, but no complete changed-path listing or diff is supplied; doctor.bats is stated to have concurrent changes. |

## Diagnosis

- **V-2** (major): The supplied output proves the suite terminated but does not identify or demonstrate execution of the formerly hanging apps.bats case.
  evidence: Suite output only shows final cases 100–102; no output names, source diff, or targeted invocation ties successful completion to the former apps.bats:256 case.
- **V-2** (major): The supplied scope evidence proves dot_local/ is unchanged but does not prove the fix is confined to tests/apps.bats.
  evidence: `git diff --stat -- dot_local/` is empty, but no complete changed-path listing or diff is supplied; doctor.bats is stated to have concurrent changes.
