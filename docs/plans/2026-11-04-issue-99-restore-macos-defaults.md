# Restore Captured macOS Defaults Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close #99 by adding `run_onchange_after_restore-macos-defaults.sh.tmpl`, which writes `dot_config/macos-defaults.captured` onto the machine, touching only keys whose live value differs.

**Architecture:** One new chezmoi `run_onchange_after_` script. Its header hashes the captured file, so chezmoi reruns it whenever a `chezmoi apply`/`update` changes that file. At runtime it reads the captured file from `{{ .chezmoi.sourceDir }}` (so tests can render it against a temp source holding a fixture), compares each `domain key type value` line to `defaults read`, writes the differences, restarts the apps whose domains changed, and names refused keys in a summary. It exits 0 every time. The name sorts after `configure-macos`, so chezmoi runs it after the one-shot baseline and captured values win.

**Tech Stack:** bash 3.2 (`/bin/bash`), chezmoi templates, `.chezmoitemplates/sh-ui.sh` step vocabulary, bats.

**Read first:** `AGENTS.md` (test commands), `tests/helpers.bash:1-25` (why test bodies avoid `[[ ]]`, and why `assert_contains` is the assertion form `tests/mutation-check.sh` can invert), `tests/macos-defaults.bats:1-31` and `:86-108` (temp-plist domains and `source_only_run`), `run_onchange_configure-raycast.sh.tmpl` (the shape this script copies).

**Facts verified on this machine (2026-11-04), so don't re-derive them:**

- `defaults read` prints a bool as `1`/`0`, but `defaults write -bool 1` is rejected with the usage text and a non-zero exit. `-bool` accepts only `true|false|yes|no`. The captured file holds `1`/`0`, so the script must map them.
- `defaults read <domain> <missing-key>` exits 1.
- An absolute path to a `.plist` file works as a domain for both `read` and `write`, which is how `tests/macos-defaults.bats` stays off real preferences.
- chezmoi runs `after` scripts in target-name order. `configure-macos.sh` sorts before `restore-macos-defaults.sh`. Task 1 asserts this from a real `chezmoi apply`, not from the names.

**Never** let a test reach the real `defaults` with a real domain (`com.apple.*`, `NSGlobalDomain`). Real `defaults` gets only `$PLIST` paths. Any case using a real domain name stubs `defaults` completely.

---

### Task 1: The script exists and chezmoi runs it after the baseline

**Files:**
- Create: `run_onchange_after_restore-macos-defaults.sh.tmpl`
- Test: `tests/macos-defaults.bats` (append)

**Step 1: Write the failing test**

Append to `tests/macos-defaults.bats`:

```bash
# ---- restore (#99) ----

# chezmoi's run order is the consumer here, so this runs a real apply against a temp
# source holding stand-ins named like the two real scripts, and reads back the order
# they actually ran in. The two [ -f ] lines tie the stand-ins to names the repo holds.
@test "restore runs after configure-macos in chezmoi's own apply order" {
	command -v chezmoi >/dev/null || skip "chezmoi not on PATH"
	[ -f "$SRC/run_once_after_configure-macos.sh" ]
	[ -f "$SRC/run_onchange_after_restore-macos-defaults.sh.tmpl" ]
	local src="$BATS_TEST_TMPDIR/order-src" log="$BATS_TEST_TMPDIR/order.log"
	mkdir -p "$src"
	printf '#!/bin/sh\necho configure >>"%s"\n' "$log" >"$src/run_once_after_configure-macos.sh"
	printf '#!/bin/sh\necho restore >>"%s"\n' "$log" >"$src/run_onchange_after_restore-macos-defaults.sh.tmpl"
	run source_only_run "$src" apply --no-tty
	[ "$status" -eq 0 ]
	assert_contains "|configure restore |" "|$(tr '\n' ' ' <"$log")|"
}
```

**Step 2: Run it and confirm it fails**

Run: `bats tests/macos-defaults.bats -f "apply order"`
Expected: FAIL, because the second `[ -f ]` finds no restore script.

**Step 3: Create the script skeleton**

`run_onchange_after_restore-macos-defaults.sh.tmpl`:

```bash
#!/bin/bash
# chezmoi:template:left-delimiter="{{" right-delimiter="}}"
# Captured defaults hash: {{ include "dot_config/macos-defaults.captured" | sha256sum }}
# Re-runs whenever the capture changes, which on this machine means a `chezmoi update`
# brought another Mac's values, or a fresh machine's first apply.
#
# The write half of #66's capture. Named to sort after configure-macos because chezmoi
# runs after-scripts by target name: captured values have to land on top of that
# script's one-shot baseline, not under it.
#
# Preference writes, not files.
#
# teardown:none
#
# No `set -e`, same reason as configure-macos: one key macOS refuses must not
# abort the rest.

{{ template "sh-ui.sh" . }}

ui_trap_exit

captured="{{ joinPath .chezmoi.sourceDir "dot_config" "macos-defaults.captured" }}"

ui_require defaults "macos defaults" "defaults not found"
[ -r "$captured" ] || { step_warn "macos defaults" "no capture"; exit 0; }

exit 0
```

**Step 4: Run it and confirm it passes**

Run: `bats tests/macos-defaults.bats -f "apply order"`
Expected: PASS

**Step 5: Commit**

```bash
git add run_onchange_after_restore-macos-defaults.sh.tmpl tests/macos-defaults.bats
git commit -m "feat(macos): add restore script for captured defaults, ordered after the baseline (#99)"
```

---

### Task 2: Write keys whose live value differs

**Files:**
- Modify: `run_onchange_after_restore-macos-defaults.sh.tmpl`
- Test: `tests/macos-defaults.bats`

**Step 1: Add the render helper and pass-through stub, then the failing test**

Add these helpers to `tests/macos-defaults.bats`, right after `source_only_run`:

```bash
# Renders the restore script against a temp source whose capture is $1. The script reads
# the capture from .chezmoi.sourceDir at runtime, so the fixture is what it acts on.
# The real $HOME is kept for the render only; chezmoi needs its config to start.
REAL_HOME="$HOME"
render_restore() {
	local src="$BATS_TEST_TMPDIR/restore-src" out="$BATS_TEST_TMPDIR/restore.sh"
	mkdir -p "$src/dot_config"
	cp -R "$SRC/.chezmoitemplates" "$src/"
	cp "$1" "$src/dot_config/macos-defaults.captured"
	HOME="$REAL_HOME" chezmoi execute-template --source "$src" \
		<"$SRC/run_onchange_after_restore-macos-defaults.sh.tmpl" >"$out"
	echo "$out"
}

# Logs every write, then hands the call to the real defaults, so the plist under
# $BATS_TEST_TMPDIR really changes and the assertion reads it back with defaults itself.
stub_defaults_passthrough() {
	STUBS="$BATS_TEST_TMPDIR/stubs"
	export DEFAULTS_LOG="$BATS_TEST_TMPDIR/defaults-writes.log"
	mkdir -p "$STUBS"
	: >"$DEFAULTS_LOG"
	cat >"$STUBS/defaults" <<'STUB'
#!/usr/bin/env bash
[ "$1" = write ] && echo "$@" >>"$DEFAULTS_LOG"
exec /usr/bin/defaults "$@"
STUB
	chmod +x "$STUBS/defaults"
}
```

Add `CAP="$BATS_TEST_TMPDIR/capture"` to `setup()`.

The test:

```bash
@test "restore writes each differing captured key, as defaults reads it back" {
	defaults write "$PLIST" k1 -bool false
	defaults write "$PLIST" k2 -string old
	printf '%s\n' "$PLIST k1 bool 1" "$PLIST k2 string new value" >"$CAP"
	script="$(render_restore "$CAP")"
	stub_defaults_passthrough
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "|1|" "|$(defaults read "$PLIST" k1)|"
	assert_contains "|new value|" "|$(defaults read "$PLIST" k2)|"
}
```

The bool case is the one that matters. A script that passes the captured `1` straight to `-bool` fails it, because `defaults` rejects the write and k1 stays `0`.

**Step 2: Run it and confirm it fails**

Run: `bats tests/macos-defaults.bats -f "differing"`
Expected: FAIL, because k1 still reads `0`.

**Step 3: Implement the loop**

In the script, replace the final `exit 0` with:

```bash
step_begin "macos defaults"

written=0
refused=()
changed_domains=()

# The capture is `domain key type value`, and the value is whatever `defaults read`
# printed, spaces included, so it goes last. read -r's final variable takes the rest.
while read -r d k t v; do
  case "$d" in '' | '#'*) continue ;; esac
  # A key absent here reads as a failure, which counts as differing: the capture has a
  # value and the machine doesn't.
  if live="$(defaults read "$d" "$k" 2>/dev/null </dev/null)" && [ "$live" = "$v" ]; then
    continue
  fi
  arg="$v"
  # `defaults read` prints bools as 1/0, but `write -bool` takes only true/false/yes/no
  # and rejects 1 with its usage text.
  if [ "$t" = bool ]; then
    case "$v" in 1) arg=true ;; 0) arg=false ;; esac
  fi
  if step_run defaults write "$d" "$k" -"$t" "$arg" </dev/null; then
    written=$((written + 1))
    changed_domains+=("$d")
  else
    refused+=("$d $k")
  fi
done <"$captured"

step_ok "macos defaults" "$written written"
exit 0
```

**Step 4: Run it and confirm it passes**

Run: `bats tests/macos-defaults.bats -f "differing"`
Expected: PASS

**Step 5: Commit**

```bash
git add run_onchange_after_restore-macos-defaults.sh.tmpl tests/macos-defaults.bats
git commit -m "feat(macos): write captured keys that differ from the live value (#99)"
```

---

### Task 3: Leave matching and uncaptured keys alone

**Files:**
- Test: `tests/macos-defaults.bats`

Task 2's code should already pass this. The test pins the changed-only rule: perturb the live value of a captured key and the write count moves, perturb a key outside the capture and it stays put.

**Step 1: Write the test**

```bash
@test "restore writes nothing when live matches the capture, and only the perturbed key after" {
	defaults write "$PLIST" k1 -bool true
	defaults write "$PLIST" local -string mine
	printf '%s\n' "$PLIST k1 bool 1" >"$CAP"
	script="$(render_restore "$CAP")"
	stub_defaults_passthrough
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_not_contains "write" "$(cat "$DEFAULTS_LOG")"

	defaults write "$PLIST" local -string changed
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	assert_not_contains "write" "$(cat "$DEFAULTS_LOG")"

	defaults write "$PLIST" k1 -bool false
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	assert_contains "|1|" "|$(grep -c '^write' "$DEFAULTS_LOG")|"
	assert_contains "|changed|" "|$(defaults read "$PLIST" local)|"
}
```

**Step 2: Run it**

Run: `bats tests/macos-defaults.bats -f "matches the capture"`
Expected: PASS. If it fails, the comparison in Task 2's loop is wrong, so fix the loop, not the test.

**Step 3: Commit**

```bash
git add tests/macos-defaults.bats
git commit -m "test(macos): pin restore's changed-only rule (#99)"
```

---

### Task 4: Restart only the apps whose domains changed

**Files:**
- Modify: `run_onchange_after_restore-macos-defaults.sh.tmpl`
- Test: `tests/macos-defaults.bats`

**Step 1: Add the fake-store stub, then the failing test**

This case uses real domain names, so `defaults` is fully fake and never reaches the real binary.

```bash
# Reads answer from $FAKE_LIVE ("domain key value" lines) and writes are only logged.
# For cases that need real domain names, which must never reach real preferences.
# $REFUSE_KEY, when set, makes a write of that key fail the way defaults does.
stub_defaults_fake() {
	STUBS="$BATS_TEST_TMPDIR/stubs"
	export DEFAULTS_LOG="$BATS_TEST_TMPDIR/defaults-writes.log" FAKE_LIVE="$BATS_TEST_TMPDIR/live"
	export KILLALL_LOG="$BATS_TEST_TMPDIR/killall.log"
	mkdir -p "$STUBS"
	: >"$DEFAULTS_LOG"
	: >"$KILLALL_LOG"
	cat >"$STUBS/defaults" <<'STUB'
#!/usr/bin/env bash
case "$1" in
read) awk -v d="$2" -v k="$3" '$1 == d && $2 == k { sub(/^[^ ]+ [^ ]+ /, ""); print; f = 1 } END { exit !f }' "$FAKE_LIVE" ;;
write)
	if [ -n "${REFUSE_KEY:-}" ] && [ "$3" = "$REFUSE_KEY" ]; then
		echo "fake defaults: refused $3" >&2
		exit 1
	fi
	echo "$@" >>"$DEFAULTS_LOG" ;;
*) exit 1 ;;
esac
STUB
	printf '#!/usr/bin/env bash\necho "$@" >>"$KILLALL_LOG"\n' >"$STUBS/killall"
	chmod +x "$STUBS/defaults" "$STUBS/killall"
}
```

The test:

```bash
@test "restore restarts only the apps whose domains got a write" {
	stub_defaults_fake
	printf '%s\n' "com.apple.finder FXPreferredViewStyle Nlsv" "com.apple.dock show-recents 0" \
		"NSGlobalDomain AppleKeyboardUIMode 0" >"$FAKE_LIVE"
	printf '%s\n' "com.apple.finder FXPreferredViewStyle string clmv" "com.apple.dock show-recents bool 0" \
		"NSGlobalDomain AppleKeyboardUIMode int 3" >"$CAP"
	script="$(render_restore "$CAP")"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "|Finder|" "|$(tr '\n' '|' <"$KILLALL_LOG")"
	assert_not_contains "Dock" "$(cat "$KILLALL_LOG")"
	assert_contains "|1|" "|$(wc -l <"$KILLALL_LOG" | tr -d ' ')|"
}
```

The Dock line matches the live value, so Dock gets no write and no restart. NSGlobalDomain gets a write but maps to no app.

**Step 2: Run it and confirm it fails**

Run: `bats tests/macos-defaults.bats -f "restarts only"`
Expected: FAIL, because nothing calls `killall` yet.

**Step 3: Implement**

In the script, between the loop's `done <"$captured"` and `step_ok`:

```bash
# Finder, the Dock and the screenshot service cache their prefs and only read a write
# after a restart. Anything else picks it up on its own or at next login.
apps=()
if [ "${#changed_domains[@]}" -gt 0 ]; then
  for d in "${changed_domains[@]}"; do
    case "$d" in
    com.apple.finder) app=Finder ;;
    com.apple.dock) app=Dock ;;
    com.apple.screencapture) app=SystemUIServer ;;
    *) continue ;;
    esac
    case " ${apps[*]-} " in *" $app "*) ;; *) apps+=("$app") ;; esac
  done
fi
if [ "${#apps[@]}" -gt 0 ]; then
  for app in "${apps[@]}"; do
    # Exits 1 when the app isn't running, which is fine: it reads the new value at launch.
    killall "$app" 2>/dev/null || :
  done
fi
```

The count guards are there because bash 3.2 mishandles empty-array expansion (see the note in `run_onchange_configure-raycast.sh.tmpl`).

**Step 4: Run it and confirm it passes**

Run: `bats tests/macos-defaults.bats -f "restarts only"`
Expected: PASS

**Step 5: Commit**

```bash
git add run_onchange_after_restore-macos-defaults.sh.tmpl tests/macos-defaults.bats
git commit -m "feat(macos): restart only the apps whose captured prefs changed (#99)"
```

---

### Task 5: Name refused keys and keep going

**Files:**
- Modify: `run_onchange_after_restore-macos-defaults.sh.tmpl`
- Test: `tests/macos-defaults.bats`

**Step 1: Write the failing test**

```bash
@test "restore names a refused key, still writes the rest, and exits 0" {
	stub_defaults_fake
	export REFUSE_KEY=FXPreferredViewStyle
	printf '%s\n' "com.apple.finder FXPreferredViewStyle Nlsv" "com.apple.dock show-recents 1" >"$FAKE_LIVE"
	printf '%s\n' "com.apple.finder FXPreferredViewStyle string clmv" "com.apple.dock show-recents bool 0" >"$CAP"
	script="$(render_restore "$CAP")"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "fake defaults: refused FXPreferredViewStyle"
	assert_contains "would not write these captured keys"
	assert_contains "  com.apple.finder FXPreferredViewStyle"
	assert_contains "write com.apple.dock show-recents -bool false" "$(cat "$DEFAULTS_LOG")"
}
```

**Step 2: Run it and confirm it fails**

Run: `bats tests/macos-defaults.bats -f "refused key"`
Expected: FAIL on the summary line.

**Step 3: Implement**

Replace `step_ok "macos defaults" "$written written"` with:

```bash
# Guarded on the count: bash 3.2 turns an empty array into one empty word.
if [ "${#refused[@]}" -gt 0 ]; then
  step_warn "macos defaults" "${#refused[@]} refused"
  echo "defaults would not write these captured keys (its errors are above):"
  printf '  %s\n' "${refused[@]}"
else
  step_ok "macos defaults" "$written written"
fi
```

The trailing `exit 0` stays. One refused key is no reason to fail the apply, and the next capture still holds the value.

**Step 4: Run it and confirm it passes**

Run: `bats tests/macos-defaults.bats -f "refused key"`
Expected: PASS

**Step 5: Commit**

```bash
git add run_onchange_after_restore-macos-defaults.sh.tmpl tests/macos-defaults.bats
git commit -m "feat(macos): name captured keys defaults refuses, keep applying the rest (#99)"
```

---

### Task 6: A changed capture changes the rendered script

**Files:**
- Test: `tests/macos-defaults.bats`

The script reads the capture at runtime, so the hash comment is the only thing in the rendered text that tracks the capture's contents. If the hash comment goes, chezmoi never reruns the script.

**Step 1: Write the test**

```bash
@test "editing one captured value changes the rendered restore script" {
	printf '%s\n' "$PLIST k1 bool 1" >"$CAP"
	cp "$(render_restore "$CAP")" "$BATS_TEST_TMPDIR/before.sh"
	printf '%s\n' "$PLIST k1 bool 0" >"$CAP"
	run cmp -s "$BATS_TEST_TMPDIR/before.sh" "$(render_restore "$CAP")"
	[ "$status" -ne 0 ]
	assert_contains "macos-defaults.captured" "$(head -5 "$SRC/run_onchange_after_restore-macos-defaults.sh.tmpl")"
}
```

**Step 2: Run it**

Run: `bats tests/macos-defaults.bats -f "rendered restore"`
Expected: PASS. Check that the test can fail: delete the hash line temporarily, confirm FAIL, then restore the line.

**Step 3: Commit**

```bash
git add tests/macos-defaults.bats
git commit -m "test(macos): pin restore's rerun-on-capture-change hash (#99)"
```

---

### Task 7: Full suite, mutation check, and the real-machine check

**Step 1:** Run `bats tests/`. Expected: all green, with no new skips other than the `chezmoi not on PATH` guard.

**Step 2:** Run `tests/mutation-check.sh`. Expected: in the `tests/macos-defaults.bats` row, every inverted assertion from Tasks 1–6 reports `not ok`. Read the per-file counts, not the total.

**Step 3:** Run `bats tests/doctor.bats`. dotfiles-doctor scans `# teardown:` tags across `run_*`, so confirm the new script's `teardown:none` reads cleanly.

**Step 4: Real machine.** Hand this step to Kendrick rather than running it yourself, since it changes live Finder prefs:

```bash
defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
chezmoi apply
defaults read com.apple.finder FXPreferredViewStyle   # expect: clmv
```

The first apply after merge runs the script, because chezmoi has never seen its hash.

**Step 5:** If `_working-memory/conventions.md` describes macOS defaults as capture-only, update that line through `/update-working-memory`, not by hand.
