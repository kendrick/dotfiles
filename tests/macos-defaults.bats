#!/usr/bin/env bats
#
# The macOS defaults capture (#66). Every case registers an absolute plist path under
# $BATS_TEST_TMPDIR as its domain, which `defaults` accepts, so no case reads or writes
# real preferences. Captured values are compared with what `defaults read` returns for the
# same key, never with a literal or a value the script computed.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/dot_local/bin/executable_dotfiles-sync"

setup() {
	PLIST="$BATS_TEST_TMPDIR/test.plist"
	LIST="$BATS_TEST_TMPDIR/list.txt"
	OUT="$BATS_TEST_TMPDIR/captured"
}

# A read-only dir can't be removed by bats' own cleanup.
teardown() {
	chmod -R u+w "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

# The line the capture wrote for KEY, minus its "domain key type " prefix.
captured_value() {
	local line
	line="$(grep -F -- "$PLIST $1 " "$OUT")"
	line="${line#"$PLIST $1 "}"
	printf '%s' "${line#* }"
}

@test "round trip: captured values equal what defaults read returns" {
	defaults write "$PLIST" k1 -bool true
	defaults write "$PLIST" k2 -string hello
	printf '%s\n' "$PLIST k1 bool" "$PLIST k2 string" >"$LIST"
	run bash "$SCRIPT" --capture-macos-defaults "$LIST" "$OUT"
	[ "$status" -eq 0 ]
	[ "$(captured_value k1)" = "$(defaults read "$PLIST" k1)" ]
	assert_contains "$(defaults read "$PLIST" k2)" "$(captured_value k2)"
	[ "$(captured_value k2)" = "$(defaults read "$PLIST" k2)" ]
}

@test "a key absent from the allowlist never reaches the captured file" {
	defaults write "$PLIST" k1 -bool true
	defaults write "$PLIST" k3 -string secret
	printf '%s\n' "$PLIST k1 bool" >"$LIST"
	run bash "$SCRIPT" --capture-macos-defaults "$LIST" "$OUT"
	[ "$status" -eq 0 ]
	assert_contains "$PLIST k1 " "$(cat "$OUT")"
	assert_not_contains "k3" "$(cat "$OUT")"
	assert_not_contains "secret" "$(cat "$OUT")"
}

@test "an unreadable key is reported, skipped, and keeps its previous value" {
	defaults write "$PLIST" k1 -bool true
	printf '%s\n' "$PLIST gone int 7" >"$OUT"
	printf '%s\n' "$PLIST gone bool" "$PLIST never string" "$PLIST k1 bool" >"$LIST"
	run bash "$SCRIPT" --capture-macos-defaults "$LIST" "$OUT"
	[ "$status" -eq 0 ]
	assert_contains "unreadable $PLIST gone" "$output"
	assert_contains "unreadable $PLIST never" "$output"
	assert_contains "$PLIST gone int 7" "$(cat "$OUT")"
	assert_not_contains "$PLIST never" "$(cat "$OUT")"
	assert_contains "$PLIST k1 bool" "$(cat "$OUT")"
}

@test "capture is idempotent: a second run leaves the file byte-identical" {
	defaults write "$PLIST" k1 -bool true
	defaults write "$PLIST" k2 -string hello
	printf '%s\n' "$PLIST k1 bool" "$PLIST k2 string" >"$LIST"
	run bash "$SCRIPT" --capture-macos-defaults "$LIST" "$OUT"
	[ "$status" -eq 0 ]
	cp "$OUT" "$BATS_TEST_TMPDIR/first"
	assert_contains "$PLIST k2 string hello" "$(cat "$OUT")"
	run bash "$SCRIPT" --capture-macos-defaults "$LIST" "$OUT"
	[ "$status" -eq 0 ]
	cmp "$BATS_TEST_TMPDIR/first" "$OUT"
}

@test "the sync script reads defaults itself" {
	run grep -c 'defaults read' "$SCRIPT"
	[ "$output" -ge 1 ]
	assert_contains "defaults read" "$(grep 'defaults read' "$SCRIPT")"
}

# --exclude=encrypted because a bare dry run aborts at the first .age file (no encryption
# configured here), before it ever reaches .config, which would make the grep below pass
# vacuously. chezmoi run against HOME and config of its own, so no template in the source reaches the
# real age key or 1Password.
source_only_run() {
	local src="$1"
	mkdir -p "$BATS_TEST_TMPDIR/h"
	# .chezmoiignore reads machine_role, and chezmoi refuses to render it without one.
	printf '[data]\nmachine_role = "personal"\n' >"$BATS_TEST_TMPDIR/chezmoi.toml"
	( unset XDG_CONFIG_HOME XDG_CACHE_HOME; export HOME="$BATS_TEST_TMPDIR/h"
	  chezmoi "${@:2}" --config "$BATS_TEST_TMPDIR/chezmoi.toml" --source "$src" --destination "$BATS_TEST_TMPDIR/dest" 2>&1 )
}

@test "both macos-defaults files are source-only" {
	command -v chezmoi >/dev/null || skip "chezmoi not on PATH"
	run source_only_run "$SRC" managed
	[ "$status" -eq 0 ]
	assert_contains ".claude/CLAUDE.md" "$output"
	assert_not_contains ".config/macos-defaults.txt" "$output"
	assert_not_contains ".config/macos-defaults.captured" "$output"
	run bash -c "$(declare -f source_only_run); source_only_run \"\$1\" apply --dry-run --verbose --exclude=encrypted,scripts | grep -c macos-defaults" _ "$SRC"
	[ "$output" = "0" ]
}

@test "malformed allowlist lines are reported and skipped, valid ones still captured" {
	defaults write "$PLIST" k1 -bool true
	printf '%s\n' "# comment" "$PLIST bad badtype" "$PLIST k1 bool" "$PLIST four string extra" >"$LIST"
	run bash "$SCRIPT" --capture-macos-defaults "$LIST" "$OUT"
	[ "$status" -eq 0 ]
	assert_contains "skipping malformed line 2" "$output"
	assert_contains "skipping malformed line 4" "$output"
	assert_not_contains "badtype" "$(cat "$OUT")"
	assert_not_contains " four " "$(cat "$OUT")"
	assert_contains "$PLIST k1 bool" "$(cat "$OUT")"
}

@test "a killed capture leaves no temp file beside the output" {
	mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/out"
	# Kill only once the stub is reading: that is mid-capture, with the temp file live. Keying
	# on the temp file instead raced the trap setup under full-suite load.
	printf '#!/bin/sh\n: >"%s/reading"\nexec sleep 30\n' "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/bin/defaults"
	chmod +x "$BATS_TEST_TMPDIR/bin/defaults"
	printf '%s\n' "$PLIST k1 bool" >"$LIST"
	set -m
	PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" --capture-macos-defaults "$LIST" "$BATS_TEST_TMPDIR/out/captured" >/dev/null 2>&1 3>&- </dev/null &
	local pid=$!
	set +m
	local i=0
	while [ ! -e "$BATS_TEST_TMPDIR/reading" ]; do
		i=$((i + 1))
		[ "$i" -lt 200 ] || { kill -TERM -- "-$pid"; return 1; }
		sleep 0.05
	done
	assert_contains "captured." "$(ls "$BATS_TEST_TMPDIR/out")"
	kill -TERM -- "-$pid"
	wait "$pid" || true
	# $pid is the outer bash, which dies at once; the capture's subshell outlives it by a beat,
	# so poll. Under load that subshell can also finish the capture before its TERM trap runs
	# and leave a complete `captured`. That's harmless; a stray `captured.*` is what the
	# sync's `git add -A` would commit, so it's the only thing asserted absent.
	i=0
	while [ -n "$(ls "$BATS_TEST_TMPDIR/out" | grep '^captured\.' || true)" ] && [ "$i" -lt 100 ]; do
		i=$((i + 1))
		sleep 0.05
	done
	[ -z "$(ls "$BATS_TEST_TMPDIR/out" | grep '^captured\.' || true)" ]
}

# --- the sync's own phase wiring, against a throwaway source repo -------------------------

sync_stubs() {
	export HOME="$BATS_TEST_TMPDIR/home" REPO="$BATS_TEST_TMPDIR/repo" STUBS="$BATS_TEST_TMPDIR/stubs"
	unset XDG_CONFIG_HOME XDG_CACHE_HOME DOTFILES_AUTO_PUSH
	export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
	mkdir -p "$HOME" "$STUBS" "$REPO/dot_config"
	printf '#!/bin/sh\ncase "$1" in source-path) printf "%%s\\n" "$REPO" ;; *) exit 0 ;; esac\n' >"$STUBS/chezmoi"
	printf '#!/bin/sh\nexit 0\n' >"$STUBS/osascript"
	printf '#!/bin/sh\ncase "$*" in *+%%s*) echo 1767225600 ;; *) echo 2026-01-01 ;; esac\n' >"$STUBS/date"
	chmod +x "$STUBS"/*
	git init -q --bare "$BATS_TEST_TMPDIR/origin.git"
	git init -q "$REPO"
	printf '%s\n' "$PLIST k1 bool" >"$REPO/dot_config/macos-defaults.txt"
	git -C "$REPO" add -A
	git -C "$REPO" commit -q -m seed
	git -C "$REPO" branch -M main
	git -C "$REPO" remote add origin "$BATS_TEST_TMPDIR/origin.git"
	git -C "$REPO" push -q origin main
	git -C "$REPO" remote set-head origin main
	export PATH="$STUBS:/usr/bin:/bin"
}

@test "the sync commits the captured file, and the commit holds what defaults read returns" {
	defaults write "$PLIST" k1 -bool true
	sync_stubs
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	assert_contains "$PLIST k1 bool $(defaults read "$PLIST" k1)" "$(git -C "$REPO" show HEAD:dot_config/macos-defaults.captured)"
}

@test "a capture that cannot write does not fail the sync" {
	defaults write "$PLIST" k1 -bool true
	sync_stubs
	chmod 555 "$REPO/dot_config"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	assert_contains "macos-defaults: capture failed, continuing" "$output"
}

@test "captured lines follow allowlist order, and a delisted key is dropped" {
	defaults write "$PLIST" ka -string A
	defaults write "$PLIST" kb -string B
	printf '%s\n' "$PLIST kb string" "$PLIST ka string" >"$LIST"
	run bash "$SCRIPT" --capture-macos-defaults "$LIST" "$OUT"
	[ "$status" -eq 0 ]
	[ "$(sed -n 1p "$OUT" | cut -d' ' -f2)" = "kb" ]
	[ "$(sed -n 2p "$OUT" | cut -d' ' -f2)" = "ka" ]
	assert_contains "$PLIST ka " "$(cat "$OUT")"
	printf '%s\n' "$PLIST kb string" >"$LIST"
	run bash "$SCRIPT" --capture-macos-defaults "$LIST" "$OUT"
	[ "$status" -eq 0 ]
	assert_not_contains "$PLIST ka " "$(cat "$OUT")"
	assert_contains "$PLIST kb " "$(cat "$OUT")"
}
