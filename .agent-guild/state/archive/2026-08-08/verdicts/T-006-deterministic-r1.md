---
task: T-006
checker: checker-deterministic
vendor: anthropic
model: claude-haiku-4-5-20251001
verdict: PASS
checked_at: 2026-08-08T19:47:19.432137Z
duration_ms: None
cost_usd: None
---

<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py
from the verdict JSON, the record of record. Edit the JSON and
re-render instead. -->

## Per-clause results

| clause | severity | description | evidence |
| ------ | -------- | ------------ | -------- |
| V-1 | blocker | Guard detects bare [[ or (( statements at line start in all three file kinds. | Part 2 plantings 1–4: Planting bare [[ ]] at line start in tests/jsonc.bats, tests/helpers.bash, and tests/mutation-check.sh; planting bare (( )) at line start — all caused bats --formatter tap tests/lint.bats to report 'not ok 1'. Exit code 0 on unplanted suite. |
| V-1 | blocker | Guard detects bare [[ or (( statements after command separators and keywords. | Part 2 plantings 5–7: Planting 'true; [[ 1 -eq 2 ]]' (with space after semicolon), 'if true; then [[ 1 -eq 2 ]]; fi', and 'true && [[ 1 -eq 2 ]]' in tests/jsonc.bats — all caused bats --formatter tap to report 'not ok 1'. |
| V-1 | blocker | Guard does not flag [[ ]] when it is a condition (if/while/until/elif). | Part 3 precision tests: Planting 'if [[ 1 -eq 1 ]]; then true; fi' and 'while [[ -n "$x" ]]; do true; done' in tests/jsonc.bats — both caused bats --formatter tap to report 'ok 1'. Also verified: mutation-check.sh lines 168, 172, 287 contain 'if [[ ... ]]' conditions; bats tests/ exits 0 at 120 cases, proving these lines are not flagged. |
| V-1 | blocker | Guard does not flag [[ ]] inside comments, grep patterns, or character classes. | lint.bats contains multiple comments quoting [[ patterns (lines 4, 13, 20, 22, 40, 44–49); helpers.bash contains explanatory comments (lines 2, 5, 7, 9); bats tests/ exits 0, confirming no false positives on comments or patterns. Character classes [[:space:]] in font.bats:462, packages.bats:107 and grep -oE patterns are not flagged. |
| V-1 | blocker | Guard does not flag its own source code. | /usr/bin/grep -nE '^[[:space:]]*(\\[\\[\|\\(\\()' tests/lint.bats exits 1 with no output, confirming the guard's pattern text is not matched. |
| B-1 | blocker | Guard pattern matches all three file kinds on the guarded surface. | Part 2 plantings 1–3 confirm guard detects bare [[ in each of tests/*.bats (jsonc.bats), tests/helpers.bash, and tests/mutation-check.sh. |
| B-1 | blocker | Guard exits 1 with no output when no bare compound is found. | /usr/bin/grep -nE '^[[:space:]]*(\\[\\[\|\\(\\()' tests/lint.bats exits 1. Unplanted suite: bats tests/lint.bats exits 0 (passes), bats tests/ exits 0 at 120 cases (all green). |
| B-1 | blocker | Known acceptable limitation: bare [[ without space after semicolon (non-idiomatic form) is not caught. | Orchestrator ruling (task file, line 105–112) accepted 'true;[[ ]]' (no space) as uncaught but acceptable because it is non-idiomatic and a formatter normalizes it away. The spaced form 'true; [[ ]]' is caught by planting 5. |
