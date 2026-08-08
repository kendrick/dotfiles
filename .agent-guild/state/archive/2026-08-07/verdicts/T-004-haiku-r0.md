---
task: T-004
checker: checker-deterministic
vendor: anthropic
model: claude-haiku-4-5-20251001
verdict: PASS
checked_at: 2026-08-06T21:00:00Z
duration_ms: None
cost_usd: None
---

<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py
from the verdict JSON, the record of record. Edit the JSON and
re-render instead. -->

## Per-clause results

| clause | severity | description | evidence |
| ------ | -------- | ------------ | -------- |
| V-3 | pass | The test case exists with the correct title at line 92 of tests/doctor.bats. | grep output: 92:@test "doctor: a tracked but uninstalled formula is reported" { |
| V-3 | pass | All 11 test cases pass at HEAD including the new case. | bats --formatter tap tests/doctor.bats output: 1..11 ok 1 doctor: a tracked but uninstalled formula is reported ok 2 says nothing when every declared cask is tracked ok 3 names the key, the half and the cask when the registry is missing one ok 4 a formula does not satisfy a cask dependency ok 5 matches the whole cask name, not a prefix of a longer one ok 6 a cask in a bundle this machine hasn't enabled is a gap ok 7 an empty list is fine on Tier C, which is fetched from 1Password ok 8 an empty list is a gap on a tier that installs from Homebrew ok 9 a half with no casks key at all is reported as undeclared ok 10 skips rather than dies when there is no registry to read ok 11 the repo's own font registry and package registry agree |
| V-3 | pass | Mutation test proves the new case exercises the claimed branch: it fails when lines 58-68 deleted from doctor, confirming the cp command was executed. | bats --formatter tap in /tmp/agc-t004-check2 with deleted doctor branch: not ok 1 doctor: a tracked but uninstalled formula is reported ok 2 says nothing when every declared cask is tracked ok 3 names the key, the half and the cask when the registry is missing one Tests 4-11 remain ok. Worktree successfully cleaned up. |
| V-3 | pass | Test case count is 11 (exceeds minimum of 10) and no skips were added in the diff. | grep -c '^@test' tests/doctor.bats = 11 git diff -- tests/doctor.bats \| grep -E '^\\+[[:space:]]*skip\\b' = 0 lines |
| V-3 | pass | No changes to dot_local/ directory, scope is respected. | git diff --stat -- dot_local/ = (empty output) |
