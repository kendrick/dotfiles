# Age-Key Hidden op Prompt (#74) Implementation Plan

**Goal:** When 1Password still isn't ready after the wait, `run_before_provision-age-key.sh.tmpl` settles `✗ age key  1Password would not answer` in bounded time, and `op` never starts its own interactive sign-in from inside the script.

**Tech Stack:** bash 3.2, chezmoi templates, bats, `tests/support/pty-run.py`.

---

## Context

Issue #74. At `:81` the script runs `op read "$OP_REF" 2>/dev/null` whether or not `op_ready` passed. With no account configured and stdin on a tty, `op` 2.40.0 asks `Do you want to add an account manually now? [Y/n]` on `/dev/tty`. Enter means yes, and its next prompt (`Enter your sign-in address`) goes to stderr, which `2>/dev/null` discards, so the apply hangs on a blank line. Measured: with stdin on `/dev/null`, `op read` exits 1 at once with no prompt, and `op account list --format=json` (the `op_ready` probe at `:65`) never prompts.

## Decisions

These are settled. Implement them as written.

1. **Detach stdin from `op read` only when `op_ready` fails.** At `:81`, when `op_ready` passes, keep today's call byte for byte, so the working Touch ID path is untouched. When it fails, run `op read "$OP_REF" </dev/null 2>/dev/null`. `op` then can't prompt, and a read that can still succeed without the desktop integration still gets its chance. Re-probe with `op_ready` at that point rather than caching the result from `:69`, because the wait may have ended with the integration switched on. Don't skip `op read` outright when `op_ready` fails.
2. **No other behavior changes.** The failure branch at `:86-89` already prints the right guidance and stays as is. `WAIT_TIMEOUT` stays 600.
3. **Comment the WHY above the call:** `op` prompts on the tty when no account is set up, and its follow-up prompt goes to stderr, which this line discards, so the run would wait on a question nobody can see (#74).
4. **New test file `tests/age-key.bats`,** registered in `ALL_FILES` at `tests/mutation-check.sh:89`, with the comment at `:78` updated to name it (#74). This lane owns the only edit to `tests/mutation-check.sh` in the wave with #45 and #67.

## Task: fix and cover the op read call

**Files:** run_before_provision-age-key.sh.tmpl, tests/age-key.bats, tests/mutation-check.sh

### Test harness

Render the script the way `tests/prerequisites.bats` `setup()` does, with `chezmoi execute-template --source "$(ui_src)" --config "$(ui_fixture_config)" --destination …`, and confirm the rendered `KEY_PATH=` line points under a temp dir the test controls. Fail setup if it doesn't. Rewrite fixed paths in the rendered copy using the idiom in `_working-memory/conventions.md` (rewrite the one assignment, fail setup unless exactly the expected lines changed):

- `WAIT_TIMEOUT=600` becomes `WAIT_TIMEOUT=2`.
- The `/opt/homebrew/bin/brew` probe at `:39` points at a nonexistent path, so the real Homebrew `shellenv` can't put the real `op` ahead of the stub.

Stubs on `PATH="$stubs:/usr/bin:/bin"`:

- `op`: `account list` prints the contents of `$OP_ACCOUNTS` (a file the case writes, `[]` or `[{"url":"my.1password.com"}]`). `read` appends `read tty=<yes|no>` to `$OP_LOG`, testing `[ -t 0 ]`. When stdin is a tty and accounts are empty, it writes `Do you want to add an account manually now? [Y/n] ` to `/dev/tty` and blocks reading stdin, which is what `op` was measured to do. When accounts are present, it prints `AGE-SECRET-KEY-1FIXTURE` and exits 0. Otherwise it exits 1.
- `open` and `brew` exit 0 and do nothing.

Drive the attended cases with `tests/support/pty-run.py --stdin-from-tty --timeout 20`. Exit 199 means the run hung.

### Cases

Settle each expected value from the issue's Expected section, not from the new code.

1. **Attended, not ready, wait times out.** Accounts `[]`. The run exits before pty-run's timeout (not 199). Its output contains `1Password would not answer`. `$OP_LOG` contains no `read tty=yes` line. The key file doesn't exist. This case must be red against the pre-fix template, where the run hits exit 199.
2. **Attended, ready (falsifier).** Accounts present. The run settles `fetched from 1Password`, and the key file contains `AGE-SECRET-KEY-1FIXTURE`. A fix that skips `op read` whenever stdin is a tty, or skips it outright, fails here.
3. **Non-interactive, not ready.** Plain `bash` with stdin from `/dev/null`, accounts `[]`. The run exits 0 (the script is best-effort with no `set -e`), the output contains `1Password would not answer`, and `$OP_LOG` has no `read tty=yes`.
4. **Already provisioned.** The key file is pre-seeded with an `AGE-SECRET-KEY-1` line. The output contains `already provisioned`, and `$OP_LOG` doesn't exist.

## Verification

- `bats tests/age-key.bats` passes. Case 1 fails against the template at the plan's base commit, either confirmed in a scratch copy or recorded as a red run before the edit.
- `bash tests/mutation-check.sh tests/age-key.bats` reports every site killed.
- `bats tests/` exits 0.

## Out of Scope

- The Touch ID prompt `op read` raises when the integration is on, which is expected.
- Any `op account add` or sign-in flow driven from this script.
- The 600-second wait length.
- `_working-memory/conventions.md`. Other lanes in the wave may touch it, so this lane leaves it alone.
