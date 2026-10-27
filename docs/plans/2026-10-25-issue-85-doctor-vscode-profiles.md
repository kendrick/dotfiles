# Doctor VS Code Profiles (#85) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `dotfiles-doctor` reports VS Code extension drift for every tracked profile (`web`, `embedded`, `docs`), comparing each registered profile against the default list plus its own list, and says plainly when a profile isn't created yet or can't be checked.

**Architecture:** Extend the `== VS Code extensions ==` section of `dot_local/bin/executable_dotfiles-doctor` with a per-profile loop after the existing default comparison, reading the registered-profile roster from `storage.json` the way `executable_vscode-extensions-update` does. Cover it in `tests/doctor.bats` with a profile-aware `code` stub.

**Tech Stack:** bash 3.2 under `set -euo pipefail`, jq, bats.

---

## Context

Issue #85. #81 split VS Code extensions into the default list `dot_config/vscode-extensions.txt` and per-profile lists `dot_config/vscode-profiles/<name>.txt`. The doctor's VS Code section (`executable_dotfiles-doctor:42-57` at 499398c) still runs a bare `code --list-extensions` and compares it with the default list alone, so drift inside a profile never shows up.

Facts this plan relies on, checked at 499398c:

- A profile's expected set is the default list plus its own list. The installer installs both into every profile (`_working-memory/dataContracts.md`, "VS Code profiles (#45)").
- A tracked profile is `dot_config/vscode-profiles/<name>.txt` whose name matches `[a-z0-9-]+` and doesn't end in `-removed`. The installer, capture and the `code()` wrapper all use this rule.
- The CLI can't list profiles. `executable_vscode-extensions-update:53-64` reads the roster from `$HOME/Library/Application Support/Code/User/globalStorage/storage.json` with `jq -r '(.userDataProfiles // [])[] | select((.location // "") | startswith("builtin/") | not) | .name'`. A file that exists but won't parse is a failure, distinct from an absent file.
- macOS ships `/usr/bin/jq`. A case that hides jq can't just narrow PATH to `/usr/bin:/bin`.
- `tests/doctor.bats` points `HOME` at a temp dir and stubs `chezmoi source-path` to `$FIXTURE`, so a fixture `storage.json` under `$HOME/Library/...` and a fixture `$FIXTURE/dot_config/vscode-profiles/` are what the doctor reads. Its `code` stub is created in `setup()` (about `:62-63`) and prints `fixture.extension`.
- `tests/doctor.bats` is in `ALL_FILES` in `tests/mutation-check.sh`, so new cases must assert with `assert_contains` / `assert_not_contains`, the way the file's other cases do.

## Decisions

These are settled. Implement them as written.

1. **The default comparison is unchanged,** byte for byte, including its two `-- ` lines and their wording.
2. **Then one block per tracked profile,** in glob order, after the default's two lists and before the existing `else`. Untracked registered profiles (hand-made ones, `builtin/` ones) are ignored.
3. **The roster is read once, before the loop,** with the update helper's jq filter, and these outcomes:
   - No tracked profiles: print nothing extra.
   - jq missing: `-- profiles skipped: jq not found`
   - `storage.json` absent: `-- profiles skipped: no storage.json, VS Code has never run here`
   - `storage.json` exists but jq fails on it: `-- profiles skipped: cannot read storage.json`
   - In all three, the default comparison above still runs and the doctor still exits as it does today.
4. **A tracked profile the roster doesn't name** prints one line and runs no `code` call for it: `-- <name> profile: not created yet (quit VS Code, then run chezmoi apply)`
5. **A registered profile** gets the default section's two comparisons against `sort` of (default list ∪ `<name>.txt`), with these headings:
   - `-- <name> profile, here but not in your dotfiles (remove it, or capture with dotfiles-sync):`
   - `-- <name> profile, in your dotfiles but not installed (install with code --profile <name>; apply won't retry until a list changes):`
   Ids are listed the same way as the default section: one per line, four-space indent. Lowercase both sides with `tr A-Z a-z` before `sort`. The CLI prints lowercase ids today, but the lists are hand-edited and capture already matches ids case-insensitively (`grep -i`), so a mixed-case list line must not read as drift.
6. **A failing `code --list-extensions --profile <name>`** prints `    ! code --list-extensions --profile <name> failed` and moves on to the next profile. Guard it so `set -e` can't end the run.
7. **Comment the WHY once,** above the loop: profiles are separate extension sets since #45, the default comparison can't see them, and the roster comes from `storage.json` because the CLI can't list profiles.
8. **Docs:** in `_working-memory/dataContracts.md`, add one sentence to the "VS Code profiles (#45)" paragraph saying that `dotfiles-doctor` compares each registered tracked profile against the default list plus its own, and names an unregistered one as not created yet.

## Task 1: Test harness and failing cases

**Files:**
tests/doctor.bats

**Step 1: Add helpers** near the top, after `homebrew_section`:

```bash
vscode_section() {
	bash "$SCRIPT" 2>&1 | sed -n '/== VS Code extensions ==/,/^$/p'
}

vscode_storage_file() {
	echo "$HOME/Library/Application Support/Code/User/globalStorage/storage.json"
}

# Registers the named profiles the way the installer does.
write_vscode_storage() {
	local json='{"userDataProfiles":[' sep="" p
	for p in "$@"; do
		json="$json$sep{\"location\":\"chezmoi-$p\",\"name\":\"$p\"}"
		sep=","
	done
	mkdir -p "$(dirname "$(vscode_storage_file)")"
	printf '%s]}\n' "$json" >"$(vscode_storage_file)"
}

# Answers --list-extensions per profile from $FIXTURE/installed/<name>.txt
# (default.txt with no --profile), and logs every call.
stub_code_profiles() {
	mkdir -p "$FIXTURE/installed"
	export CODE_LOG="$BATS_TEST_TMPDIR/code.log"
	: >"$CODE_LOG"
	cat >"$STUBS/code" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$CODE_LOG"
p=default
[ "${2:-}" = "--profile" ] && p="$3"
[ -n "${FAIL_PROFILE:-}" ] && [ "$p" = "$FAIL_PROFILE" ] && exit 1
cat "$FIXTURE/installed/$p.txt" 2>/dev/null
exit 0
STUB
	chmod +x "$STUBS/code"
}
```

Each profile case then writes `$FIXTURE/dot_config/vscode-profiles/{web,docs}.txt`, `$FIXTURE/installed/{default,web,docs}.txt`, and calls `write_vscode_storage` with the registered names. Keep `fixture.extension` as the one default-list id from `setup()`, and add `web.only` to `web.txt`.

**Step 2: Write the cases.** Settle every expected value from the issue's Done-when list and the Decisions above, not from the code you're about to write.

1. **Missing profile-only id.** `web` registered; `installed/web.txt` holds `fixture.extension` only. The section contains `-- web profile, in your dotfiles but not installed` followed by `    web.only`.
2. **Falsifier, union of all lists.** `web` and `docs` registered; `docs.txt` holds `docs.only`; `installed/docs.txt` holds `fixture.extension` and `docs.only`, with no `web.only`. Nothing under `docs` names `web.only`. A check against the union of every list fails this. To assert per profile, extract the lines from the first `-- docs profile` heading up to the next heading that isn't a `docs` one (an `awk` flag toggled on `/^-- /` lines does it), and assert on that.
3. **Falsifier, own list only.** `web` registered; `installed/web.txt` holds `web.only` but not `fixture.extension`. The `web` "not installed" block names `fixture.extension`. A check against the profile's own list alone fails this.
4. **Untracked extra.** `web` registered; `installed/web.txt` holds `fixture.extension`, `web.only`, and `stray.ext`. The `web` "here but not in your dotfiles" block names `stray.ext`.
5. **Unregistered.** `web.txt` exists, and `storage.json` registers nothing (`write_vscode_storage` with no args). The section contains `-- web profile: not created yet`, and `$CODE_LOG` has no line containing `--profile`.
6. **jq hidden.** With a profile tracked and registered, build a PATH that has no jq anywhere: a dir of symlinks to every entry of `/usr/bin` and `/bin` except `jq`, as `tests/vscode-extensions-capture.bats` does in its no-jq case (about `:770-780`), not the hand-picked list at `tests/install-failures.bats:578-583`. Assert `[ ! -e "$tools/jq" ]` first. Run with `PATH="$STUBS:$tools"`. The section contains `-- profiles skipped: jq not found`, and the default comparison lines are still present.
7. **Unreadable storage.json.** Write `{bad` to the storage file. The section contains `-- profiles skipped: cannot read storage.json`.
8. **Case-insensitive match.** `installed/web.txt` holds `Fixture.Extension` and `web.only`. Neither `web` block names either id.
9. **Failing CLI for one profile.** `web` and `docs` registered, `FAIL_PROFILE=web`. The section contains `! code --list-extensions --profile web failed` and still prints the `docs` blocks. Status is 0.

**Step 3: Run them**

Run: `bats --filter 'profile' tests/doctor.bats`
Expected: every new case fails, except 6 and 7, which may pass by accident because the current section prints no profile lines. Their `assert_contains` on the skipped line must fail. If one passes, its assertion is wrong.

## Task 2: Implement

**Files:**
dot_local/bin/executable_dotfiles-doctor
tests/doctor.bats
_working-memory/dataContracts.md

**Step 1: Implement Decisions 2–7** inside the `if command -v code` branch of the VS Code section, after the default's second `comm`.

- Collect tracked names with a glob over `$SRC/dot_config/vscode-profiles/*.txt`, keeping a name only if it matches the shape rule. Guard an empty glob, since bash 3.2 leaves the pattern in place.
- Under `set -euo pipefail`, capture every command that can fail (`jq`, `code`, a `grep -v` that may match nothing) with `|| rc=$?` or an `if`, never bare. The setup comment in `tests/doctor.bats` about `grep -v` exiting 1 is the trap here.
- Membership in the roster is an exact, case-sensitive name match, since VS Code profile names are case-sensitive.

**Step 2: Apply Decision 8** to `_working-memory/dataContracts.md`.

**Step 3: Run the file**

Run: `bats tests/doctor.bats`
Expected: every case passes, old and new.

**Step 4: Mutation check**

Run: `bash tests/mutation-check.sh tests/doctor.bats`
Expected: every site killed.

**Step 5: Full suite**

Run: `TMPDIR=$(mktemp -d /tmp/v85.XXXX) bats tests/`
Expected: 0 not ok. It takes about 25 minutes, so run it in the background.

**Step 6: Commit**

```bash
git add dot_local/bin/executable_dotfiles-doctor tests/doctor.bats _working-memory/dataContracts.md
git commit -m "feat(doctor): report VS Code extension drift per tracked profile (#85)"
```

The message body says why: since #45 the default comparison can't see the `web`, `embedded` and `docs` profiles.

## Verification

- The new cases fail against 499398c and pass after the change.
- `bats tests/doctor.bats`, `bash tests/mutation-check.sh tests/doctor.bats` and `bats tests/` all pass.
- On a real machine with the profiles registered, `dotfiles-doctor` prints a block for each of `docs`, `embedded` and `web`, and no line for the `Agents` builtin profile.

## Out of Scope

- The theme-registry check further down, which still reads only the default list.
- `--fix` installing missing profile extensions.
- Hand-made profiles with no tracked list.
- `run_onchange_install-vscode-extensions.sh.tmpl` and `tests/install-failures.bats`, which #84 owns in this wave.
- README. Its `dotfiles-doctor` row already says "installed-but-untracked, tracked-but-not-installed", which now covers profiles too.
