---
task: T-001
checker: checker-courier
vendor: openai
model: gpt-5.6-terra
verdict: FAIL
checked_at: 2026-08-08T00:00:00Z
duration_ms: None
cost_usd: None
---

<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py
from the verdict JSON, the record of record. Edit the JSON and
re-render instead. -->

## Per-clause results

| clause | severity | description | evidence |
| ------ | -------- | ------------ | -------- |
| B-3 | blocker | The supplied evidence supports B-3's shared-helper, removal, and discriminating-probe requirements. | Definition count is 2; all seven named pre-existing .bats files are listed by the load check; install-failures.bats has no matching local definition; helper probe reports both cases `not ok` while the otherwise-equivalent bare `[[ ]]` probe reports both `ok`, demonstrating the intended propagation distinction. |
| B-1 | blocker | The supplied B-1 evidence is insufficient because it checks only tests/helpers.bash rather than the entire guarded surface. | Provided command/output cover `tests/helpers.bash` only; no command output is supplied for `tests/*.bats` or `tests/mutation-check.sh`, which are required by B-1. |

## Diagnosis

- **B-3** (blocker): The supplied evidence supports B-3's shared-helper, removal, and discriminating-probe requirements.
  evidence: Definition count is 2; all seven named pre-existing .bats files are listed by the load check; install-failures.bats has no matching local definition; helper probe reports both cases `not ok` while the otherwise-equivalent bare `[[ ]]` probe reports both `ok`, demonstrating the intended propagation distinction.
- **B-1** (blocker): The supplied B-1 evidence is insufficient because it checks only tests/helpers.bash rather than the entire guarded surface.
  evidence: Provided command/output cover `tests/helpers.bash` only; no command output is supplied for `tests/*.bats` or `tests/mutation-check.sh`, which are required by B-1.
