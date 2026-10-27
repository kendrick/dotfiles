# Installer Refused Count (#84) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** The VS Code installer's `N of M refused` summary and the list under it count and name only extension installs that `code` rejected; a profile that failed to register shows up only in the existing "Couldn't register these with VS Code" message.

**Architecture:** One-line removal in the profile decision loop of `run_onchange_install-vscode-extensions.sh.tmpl`, plus its comment, covered by two new bats cases and one adjusted case in `tests/install-failures.bats`.

**Tech Stack:** bash 3.2, chezmoi templates, bats.

---

## Context

Issue #84. In the decision loop (`run_onchange_install-vscode-extensions.sh.tmpl:185-199` at 499398c), the `else` branch for a profile `register_profile` couldn't register runs `failed+=("profile $p")`, then `pending+=("$p")` and `unregistrable+=("$p")`. `failed` feeds both `step_warn "vscode ext" "${#failed[@]} of $ext_total refused"` and the `printf '  %s\n' "${failed[@]}"` list under "VS Code ran, but could not install these extensions". `ext_total` is computed after the loop from `ready` only, so a registration failure adds to the numerator and never the denominator. With `storage.json` broken and every install succeeding, the summary reads `3 of 26 refused` and lists `profile docs`, `profile embedded`, `profile web`.

The pending block further down already prints `Couldn't register these with VS Code (the errors are above). Fix what they name, then run 'chezmoi apply' again to create: ${unregistrable[*]}`, which is the correct place for them.

## Decisions

These are settled. Implement them as written.

1. **Delete `failed+=("profile $p")`.** Keep `pending+=("$p")` and `unregistrable+=("$p")` exactly as they are: the pending marker is what reruns the installer once `storage.json` is fixed (#81), and `unregistrable` drives the message that names them.
2. **Rewrite the comment above that branch** so it no longer says "as well as failed". It should say why the profile goes in `pending`: the marker is the only thing that makes a later apply rerun this script once `storage.json` is fixed, and the "Couldn't register" message below names it, so the refused count stays a count of extensions.
3. **No other wording changes.** The refused line, the "could not install" heading, the pending warning and the "Couldn't register" message keep their text. The exit status stays 0.
4. **Never hardcode the default-list size** in a test. Derive it with `vscode_ids "$SRC/dot_config/vscode-extensions.txt" | wc -l | tr -d ' '`, so a list edit doesn't break the cases.

## Task 1: Failing tests

**Files:**
tests/install-failures.bats

Add both cases directly after `@test "install-vscode-extensions: a profile that fails to register is named and left pending"` (about `:745`). They use the file's existing helpers: `render_script`, `vscode_write_storage`, `vscode_ids`, `vscode_profiles`, `stub_code_logging` (whose `FAIL_ID` refuses one id, and only inside `FAIL_PROFILE` when that's set; unset means the default profile's install), and `assert_contains` / `assert_not_contains`.

**Step 1: Write the two cases**

```bash
@test "install-vscode-extensions: when only registrations fail, the summary counts no refused extensions" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	total="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | wc -l | tr -d ' ')"
	vscode_write_storage '{bad'
	stub_code_logging
	PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_not_contains "refused"
	assert_not_contains "could not install these extensions"
	assert_contains "$total installed"
	assert_contains "Couldn't register these with VS Code"
}

# Falsifier for the fix: a real refusal alongside failed registrations still counts, and
# only the refused id is listed. Hiding the refused line whenever a registration fails, or
# still counting the profiles, both fail here.
@test "install-vscode-extensions: a refused id beside failed registrations counts alone" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	total="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | wc -l | tr -d ' ')"
	id="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | head -1)"
	vscode_write_storage '{bad'
	stub_code_logging
	FAIL_ID="$id" PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "1 of $total refused"
	assert_contains "  $id"
	assert_not_contains "  profile "
}
```

**Step 2: Run them and confirm they fail for the right reason**

Run: `bats --filter 'only registrations fail|beside failed registrations' tests/install-failures.bats`
Expected: both FAIL. The first fails on `assert_not_contains "refused"` (the output has `3 of <total> refused`). The second fails on `assert_contains "1 of $total refused"` (the output has `4 of <total> refused`). Any other failure means the harness is wrong; fix the test before going on.

## Task 2: Fix and adjust the existing case

**Files:**
run_onchange_install-vscode-extensions.sh.tmpl
tests/install-failures.bats

**Step 1: Apply Decisions 1 and 2** in the decision loop's `else` branch.

**Step 2: Adjust the existing case** `a profile that fails to register is named and left pending`. Replace its loop

```bash
	for p in $(vscode_profiles); do
		assert_contains "  profile $p"
	done
```

with one assertion on the line that now names them, in the order the installer walks them (glob order, which `vscode_profiles` also uses):

```bash
	assert_contains "run 'chezmoi apply' again to create: $(vscode_profiles | tr '\n' ' ' | sed 's/ $//')"
	assert_not_contains "  profile "
```

Leave its `status`, `Couldn't register these`, `Quit VS Code`, marker and `--profile` assertions as they are.

**Step 3: Run the file**

Run: `bats tests/install-failures.bats`
Expected: every case passes, including the two new ones and both `real chezmoi apply registers ...` cases, unchanged. Those two prove the pending marker still drives the retry.

**Step 4: Run the full suite**

Run: `TMPDIR=$(mktemp -d /tmp/v84.XXXX) bats tests/`
Expected: 0 not ok. It takes about 25 minutes, so run it in the background.

**Step 5: Commit**

```bash
git add run_onchange_install-vscode-extensions.sh.tmpl tests/install-failures.bats
git commit -m "fix(vscode): stop counting failed profile registrations as refused extensions (#84)"
```

The message body says why: the refused ratio mixed registrations into a count of installs, and the "Couldn't register" message already names those profiles.

## Verification

- The two new cases fail against 499398c and pass after the fix.
- `bats tests/install-failures.bats` and `bats tests/` exit 0.
- `git diff 499398c -- run_onchange_install-vscode-extensions.sh.tmpl` shows only the deleted `failed+=` line and the rewritten comment.

## Out of Scope

- #83's retry fingerprint and #82's shared-extensions check, which touch the same file later.
- `tests/mutation-check.sh`. `tests/install-failures.bats` is excluded there by name, and this lane adds no new test file.
- README and `_working-memory/`. Neither describes the refused summary.
