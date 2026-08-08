---
source: github-issue
ref: kendrick/dotfiles#21
issue: 21
title: A failing [[ ]] doesn't fail its bats test, so 24 assertions may be checking nothing
fetched_at: 2026-08-08T15:06:08Z
---

# A failing [[ ]] doesn't fail its bats test, so 24 assertions may be checking nothing

## Steps to Reproduce

On any machine where `/bin/bash` is 3.2 (every stock macOS), from a clean checkout:

```bash
cat > /tmp/probe.bats <<'EOF'
@test "failing [[ ]] mid-body, then a passing command" {
	[[ 1 -eq 2 ]]
	echo "reached"
}

@test "failing grep mid-body, then a passing command" {
	echo needle | grep -qF haystack
	echo "reached"
}
EOF
bats --formatter tap /tmp/probe.bats
```

Both cases contain an assertion that is false. Both then run a command that succeeds.

## Observed vs. Expected

**Observed:** the `[[ ]]` case reports `ok`. Only the `grep` case fails.

```text
1..2
ok 1 failing [[ ]] mid-body, then a passing command
not ok 2 failing grep mid-body, then a passing command
# (in test file /tmp/probe.bats, line 7)
#   `echo needle | grep -qF haystack' failed
```

**Expected:** both report `not ok`. A false assertion should fail its test wherever it sits in the body.

## Error Output

The bug is an absence of output, so the underlying shell behavior is the useful evidence:

```console
$ /bin/bash -c 'set -e; f() { [[ 1 -eq 2 ]]; echo reached; }; f; echo "exit=$?"'
reached
exit=0

$ /bin/bash -c 'set -e; f() { echo first; [[ 1 -eq 2 ]]; }; f; echo REACHED'
first
                                    # exits 1, correct

$ /bin/bash -c 'set -e; f() { echo needle | grep -qF haystack; echo reached; }; f'
                                    # exits 1, correct
```

Under bash 3.2, a failing `[[ ]]` inside a function under `set -e` aborts only when it is the function's last statement. Anywhere else its failure is discarded. `grep` in the identical position propagates correctly, so this is specific to the `[[ ]]` compound rather than to errexit generally.

## Exposure

bats decides pass or fail from the test body's exit status. A false `[[ ]]` followed by any successful command therefore yields a green test with a failed assertion inside it, so the suite reports coverage it does not have.

Counted across the suite:

| file | `[[ ]]` assertions | in the vulnerable position |
| --- | --- | --- |
| `tests/doctor.bats` | 20 | 9 |
| `tests/font.bats` | 12 | 6 |
| `tests/apps.bats` | 11 | 4 |
| `tests/licensed-fonts.bats` | 5 | 2 |
| `tests/packages.bats` | 4 | 3 |
| `tests/jsonc.bats` | 2 | 0 |
| `tests/install-failures.bats` | 0 | 0 |
| **total** | **54** | **24** |

"Vulnerable position" means a further statement follows the assertion inside its block. The other 30 are safe today only because nothing comes after them. Appending one line to any of those blocks silently disarms the assertion above it, and nothing would catch that.

This surfaced during the #17 job. A draft of `tests/install-failures.bats` had an early failing assertion masked by a later passing one, and it was caught only because that file is required to fail against the pre-fix scripts. A suite that only ever runs green cannot reveal this. `install-failures.bats` uses `grep -qF` and `case` helpers as a result. The rest of the suite needs the same treatment.

## Acceptance Criteria

- [ ] No `.bats` file under `tests/` asserts with a bare `[[ ]]`. All 54 are replaced with a helper whose failure propagates from any position (`grep -qF`, `case`, or equivalent), following the `assert_contains` and `assert_not_contains` pattern already in `tests/install-failures.bats`.
- [ ] A check fails the suite if a bare `[[` assertion is reintroduced, so the 30 currently-safe-by-position cases cannot quietly become live later.
- [ ] The probe above reports `not ok` for both cases once converted helpers are used in place of `[[ ]]`.
- [ ] Every converted assertion still fails when its condition is false. Verify by inverting each one and confirming the test goes red. A conversion that silently always passes is the same bug wearing better syntax.
- [ ] `bats tests/` exits 0 with no case deleted or skipped. Per-file counts stay at or above: apps 18, doctor 11, font 44, install-failures 15, jsonc 9, licensed-fonts 7, packages 13.

## Verification

```bash
bats tests/          # exits 0, 117 cases, none skipped
```

Takes about 36s. It hangs on machines where `fzf` is installed unless #17's `tests/apps.bats` fix is present.

## Environment

- `/bin/bash` 3.2.57(1)-release (arm64-apple-darwin23), the shell bats runs test bodies under
- Bats 1.14.0
- macOS 14.4.1

The repo already treats bash 3.2 as a hard constraint; `_working-memory/conventions.md` carries the existing rules for it, and this belongs alongside them.

## Non-Goals

- **Requiring bash 4+ for the suite.** `/bin/bash` is 3.2 on every stock macOS and the scripts under test run under it. Testing on a different shell than production would trade this bug for a worse one.
- **Auditing whether any assertion is currently masking a real failure.** Worth knowing, but it is a separate question from making the mechanism sound, and the fix does not depend on the answer.
- **Changing what the assertions check.** This is a mechanical conversion of how a condition is expressed, not a review of whether the condition is right.
