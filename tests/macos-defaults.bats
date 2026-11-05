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
	CAP="$BATS_TEST_TMPDIR/capture"
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

@test "a failed append aborts the capture, keeps the previous file, and leaves no temp file" {
	mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/out"
	# The second read makes the temp file unwritable before answering, so the second key's append
	# fails while the first key's already landed: a truncated capture the mv must never install.
	cat >"$BATS_TEST_TMPDIR/bin/defaults" <<STUB
#!/bin/sh
echo x >>"$BATS_TEST_TMPDIR/calls"
if [ "\$(wc -l <"$BATS_TEST_TMPDIR/calls")" -ge 2 ]; then
	chmod a-w "$BATS_TEST_TMPDIR"/out/captured.*
fi
echo 1
STUB
	chmod +x "$BATS_TEST_TMPDIR/bin/defaults"
	printf '%s\n' "$PLIST k1 int" "$PLIST k2 int" >"$LIST"
	printf '%s\n' "$PLIST k1 int 7" "$PLIST k2 int 8" "$PLIST k3 int 9" >"$BATS_TEST_TMPDIR/out/captured"
	cp "$BATS_TEST_TMPDIR/out/captured" "$BATS_TEST_TMPDIR/before"
	run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" --capture-macos-defaults "$LIST" "$BATS_TEST_TMPDIR/out/captured"
	[ "$status" -ne 0 ]
	assert_contains "==> macos-defaults: can't write" "$output"
	cmp "$BATS_TEST_TMPDIR/before" "$BATS_TEST_TMPDIR/out/captured"
	[ -z "$(ls "$BATS_TEST_TMPDIR/out" | grep '^captured\.' || true)" ]
}

@test "fd exhaustion never installs a capture shorter than the allowlist" {
	mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/out"
	# bash 3.2 ends a while loop silently when a here-string redirect can't get an fd, so this
	# limit once left one line where three had been. Either every key lands or the run fails
	# with the previous file untouched; a shorter file with rc=0 is the defect.
	printf '#!/bin/sh\necho 1\n' >"$BATS_TEST_TMPDIR/bin/defaults"
	chmod +x "$BATS_TEST_TMPDIR/bin/defaults"
	printf '%s\n' "$PLIST k1 int" "$PLIST k2 int" "$PLIST k3 int" >"$LIST"
	printf '%s\n' "$PLIST k1 int 7" "$PLIST k2 int 8" "$PLIST k3 int 9" >"$BATS_TEST_TMPDIR/out/captured"
	cp "$BATS_TEST_TMPDIR/out/captured" "$BATS_TEST_TMPDIR/before"
	run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" /bin/bash -c 'ulimit -n 11; exec /bin/bash "$0" --capture-macos-defaults "$1" "$2"' "$SCRIPT" "$LIST" "$BATS_TEST_TMPDIR/out/captured"
	if [ "$status" -eq 0 ]; then
		[ "$(grep -c . "$BATS_TEST_TMPDIR/out/captured")" -eq 3 ]
		for k in k1 k2 k3; do
			grep -Fxq -- "$PLIST $k int $("$BATS_TEST_TMPDIR/bin/defaults" read "$PLIST" $k)" "$BATS_TEST_TMPDIR/out/captured"
		done
	else
		cmp "$BATS_TEST_TMPDIR/before" "$BATS_TEST_TMPDIR/out/captured"
	fi
	[ -z "$(ls "$BATS_TEST_TMPDIR/out" | grep '^captured\.' || true)" ]
}

@test "an empty allowlist installs an empty capture" {
	mkdir -p "$BATS_TEST_TMPDIR/out"
	: >"$LIST"
	printf '%s\n' "$PLIST k1 int 7" >"$BATS_TEST_TMPDIR/out/captured"
	run "$SCRIPT" --capture-macos-defaults "$LIST" "$BATS_TEST_TMPDIR/out/captured"
	[ "$status" -eq 0 ]
	[ ! -s "$BATS_TEST_TMPDIR/out/captured" ]
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

@test "editing one captured value changes the rendered restore script" {
	printf '%s\n' "$PLIST k1 bool 1" >"$CAP"
	cp "$(render_restore "$CAP")" "$BATS_TEST_TMPDIR/before.sh"
	printf '%s\n' "$PLIST k1 bool 0" >"$CAP"
	run cmp -s "$BATS_TEST_TMPDIR/before.sh" "$(render_restore "$CAP")"
	[ "$status" -ne 0 ]
	assert_contains "macos-defaults.captured" "$(head -5 "$SRC/run_onchange_after_restore-macos-defaults.sh.tmpl")"
}
