---
task: T-007
checker: checker-deterministic
vendor: anthropic
model: claude-haiku-4-5-20251001
verdict: PASS
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
| V-2 | blocker | Part 1: bash tests/mutation-check.sh exits 0, names 53 distinct file:line sites, and git status before/after identical | mutation-check: all 53 sites turned their case red when inverted --- summary, by file --- tests/apps.bats: 11 tests/doctor.bats: 20 tests/font.bats: 12 tests/jsonc.bats: 2 tests/licensed-fonts.bats: 5 tests/packages.bats: 3 total: 53 |
| V-2 | blocker | Part 1a: In scratch worktree, marker line appended to tests/jsonc.bats survived the script's restore, proving copy-aside restore not git checkout | Marker '# scratch marker' successfully appended to tests/jsonc.bats, script ran with scoped file, and marker persisted after completion. This confirms restore uses cp, not git checkout. |
| V-2 | blocker | Part 2: Site counts by file match specification exactly: apps 11, doctor 20, font 12, jsonc 2, licensed-fonts 5, packages 3 = 53 | --- summary, by file --- tests/apps.bats: 11 tests/doctor.bats: 20 tests/font.bats: 12 tests/jsonc.bats: 2 tests/licensed-fonts.bats: 5 tests/packages.bats: 3 total: 53 |
| V-2 | blocker | Part 3: Script correctly rejects unrecognized form (bare 'true') and exits non-zero | mutation-check: found a converted-assertion site in a form this script does not recognise: tests/jsonc.bats:63 mutation-check: recognised forms are assert_contains/assert_not_contains calls, and doctor.bats's undeclared/casks disjunction. Fix the site above or exclude it by name. Exit code: 1 |
| V-2 | blocker | Part 4: Script judges by TAP output, not exit status. With unterminated @test block, bats fails but mutated cases never appear in TAP; script correctly reports failure | site [1/2] tests/jsonc.bats:63 test="refuses a file with line comments rather than stripping them" -> DID NOT REPORT not ok — dead assertion or broken mutation site [2/2] tests/jsonc.bats:70 test="refuses a file with block comments rather than stripping them" -> DID NOT REPORT not ok — dead assertion or broken mutation mutation-check: one or more sites did not turn red — see FAILs above Exit code: 1 |
| B-1 | blocker | No bare [[ or (( as first non-whitespace token found anywhere in tests/mutation-check.sh | /usr/bin/grep -nE '^[[:space:]]*(\\[\\[\|\\(\\()' tests/mutation-check.sh exits 1 with no output (exit 1 is the passing case) |
