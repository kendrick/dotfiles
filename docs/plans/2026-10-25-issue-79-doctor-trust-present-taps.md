# Doctor Trusts Present Taps (#79) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `dotfiles-doctor --fix` runs `brew trust --tap` for every enabled tap, whether or not it's already tapped, and runs `brew tap` only for the absent ones.

**Architecture:** Reorder one loop in the `--fix` path of `dot_local/bin/executable_dotfiles-doctor` so the already-tapped check skips only the `new_taps` append. Cover it in `tests/doctor.bats`, including one existing assertion that the fix would otherwise break.

**Tech Stack:** bash 3.2 under `set -euo pipefail`, jq, bats.

---

## Context

Issue #79. In the enabled-taps loop (`executable_dotfiles-doctor:405-413` at 499398c), `grep -qxF "$tap" <<<"$tapped" && continue` runs before the tap joins `tap_list`, the list the trust loop walks (`:420` for the prompt, `:446` for the run). A present tap is never trusted, so Homebrew 6 refuses its casks on every `--fix`. The issue body has the failing case, the expected behavior and the full Done-when list. Implement against it.

## Decisions

These are settled. Implement them as written.

1. **Loop shape:** every enabled tap joins `tap_list` (keeping the existing dedupe `case`), and only an absent one joins `new_taps`. Nothing else in the `--fix` path changes, so the `-- will run:` block shows a `brew trust --tap` line for a present tap and no `brew tap` line for it.
2. **Fix an assertion the issue missed.** The existing case "doctor --fix does not tap an enabled tap that is already tapped" (`tests/doctor.bats:868`) asserts `assert_not_contains "tap acme/fixture-tap" "$(cat "$BREW_LOG")"`. After the fix, `$BREW_LOG` holds `trust --tap acme/fixture-tap`, which contains that substring, so the case fails even though its intent still holds. Replace that one assertion with a whole-line check that no `brew tap` call ran: `[ "$(grep -cx 'tap acme/fixture-tap' "$BREW_LOG")" -eq 0 ]`. First confirm the stub's log format by reading `stub_brew_state` (one line per call, args without `brew`). Keep the case's other assertions.
3. **Audit the other tap cases for the same substring trap.** Any `assert_not_contains` on `tap <name>` against `$BREW_LOG` in a case where that tap is now trusted gets the same whole-line treatment. Leave a case alone when the trust can't happen in it, for example "declined" or "nothing missing", where no trust runs.
4. **Comment the WHY** in one line above the `continue`: a present tap still needs trusting, because one added before Homebrew 6 was never trusted (#79).

## Task 1: Failing tests

**Files:**
tests/doctor.bats

**Step 1:** Add the issue's case "doctor --fix trusts an enabled tap that is already tapped" at the end of the `--fix` cases.

**Step 2:** Add the falsifier from the issue's Done-when list: "doctor --fix does not trust a present tap from a disabled bundle". It uses `write_taps "acme/other-tap:dev"` and `echo acme/other-tap >"$BREW_STATE/tap"`, and checks for no `trust --tap acme/other-tap` line in `$BREW_LOG`, using the whole-line form from Decision 2. A fix that trusts every present tap instead of every enabled one fails it.

**Step 3:** Run `bats --filter 'tap' tests/doctor.bats`.
Expected: the new trust case fails on its first `assert_contains`, and every other tap case passes.

## Task 2: Fix

**Files:**
dot_local/bin/executable_dotfiles-doctor
tests/doctor.bats

**Step 1:** Apply Decisions 1 and 4.

**Step 2:** Apply Decisions 2 and 3.

**Step 3:** Run `bats tests/doctor.bats`. Expected: all pass.

**Step 4:** Run `bash tests/mutation-check.sh tests/doctor.bats`. Expected: every site killed.

**Step 5:** Run `TMPDIR=$(mktemp -d /tmp/v79.XXXX) bats tests/` in the background. Expected: 0 not ok.

**Step 6:** Commit both files: `fix(doctor): trust every enabled tap in --fix, not only absent ones (#79)`. The body says why: Homebrew 6 refuses untrusted taps, and a tap added before it is present but untrusted.

## Verification

- The new trust case fails at the plan's base commit and passes after the fix.
- The falsifier passes before and after.
- `bats tests/doctor.bats`, the mutation check and `bats tests/` all pass.

## Out of Scope

- Trusting taps from plain `dotfiles-doctor` without `--fix`.
- `run_onchange_install-packages.sh.tmpl`'s own trust step.
- The VS Code section of the doctor, which #85 changes in a later wave.
