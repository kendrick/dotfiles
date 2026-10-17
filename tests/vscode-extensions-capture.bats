#!/usr/bin/env bats
#
# Capture used to overwrite the tracked extension list with one machine's install set, so
# the last machine to sync won and removals kept coming back (#75). These cases pin the
# merge rule from the issue's Done-when: (list ∪ installed) − removed, removed wins, and
# a machine that lacks an extension never drops it.
#
# Every case runs the real helper (and, for the wrapper, the real functions.zsh) as a
# subprocess against a throwaway source dir, with `chezmoi` and `code` stubbed on PATH
# under a synthetic $HOME. Assertions read the files as written, which is what the
# installer's `include` reads.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
HELPER="$SRC/dot_local/bin/executable_vscode-extensions-capture"
LIST_HEADER='# VS Code extensions to install
# Edit this list and run `chezmoi apply` to sync.'

setup() {
	unset XDG_CONFIG_HOME XDG_CACHE_HOME
	unset LIST_RC
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export CALL_LOG="$BATS_TEST_TMPDIR/code-calls.log"
	export INSTALLED="$BATS_TEST_TMPDIR/installed.txt"
	export CHEZMOI_SRC="$BATS_TEST_TMPDIR/source"
	# The helper locks under $TMPDIR, so each case gets its own lock rather than racing the
	# real one or a sibling case.
	export LOCK_TMP="$BATS_TEST_TMPDIR/tmp"
	LOCK="$LOCK_TMP/vscode-extensions-capture.$(id -u).lock"
	HOLDER=""
	mkdir -p "$HOME" "$STUBS" "$CHEZMOI_SRC/dot_config" "$LOCK_TMP"
	: >"$CALL_LOG"
	: >"$INSTALLED"
	LIST="$CHEZMOI_SRC/dot_config/vscode-extensions.txt"
	REMOVED="$CHEZMOI_SRC/dot_config/vscode-extensions-removed.txt"

	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
[ "\$1" = "source-path" ] && { echo "$CHEZMOI_SRC"; exit 0; }
exit 1
STUB
	chmod +x "$STUBS/chezmoi"
	stub_code 0
	ln -s "$HELPER" "$STUBS/vscode-extensions-capture"
}

# A failing case can leave a chmod 000 fixture bats can't delete, or a lock holder alive.
teardown() {
	chmod -R u+rw "$CHEZMOI_SRC" 2>/dev/null || true
	if [ -n "$HOLDER" ]; then
		# Reaping it here keeps bash's "Terminated" notice out of the TAP stream.
		{ kill "$HOLDER" && wait "$HOLDER"; } 2>/dev/null || true
	fi
}

# hold_lock: take the helper's lock on behalf of a live background process. fd 3 is closed
# so bats doesn't wait on the sleep before reporting.
hold_lock() {
	sleep 60 3>&- &
	HOLDER=$!
	ln -s "$HOLDER" "$LOCK"
}

# Answers --list-extensions from $INSTALLED and logs every call, so a case can prove what
# the helper asked of VS Code. A nonzero rc models a refused uninstall; LIST_RC models a
# broken `--list-extensions`.
stub_code() {
	local rc="${1:-0}"
	cat >"$STUBS/code" <<STUB
#!/usr/bin/env bash
echo "\$*" >>"$CALL_LOG"
if [ "\$1" = "--list-extensions" ]; then cat "$INSTALLED"; exit \${LIST_RC:-0}; fi
exit $rc
STUB
	chmod +x "$STUBS/code"
}

# seed_list <ids...>: the tracked list, under its real header.
seed_list() {
	{
		printf '%s\n' "$LIST_HEADER"
		[ $# -eq 0 ] || printf '%s\n' "$@"
	} >"$LIST"
}

# seed_removed <ids...>: the removed file, under its real header.
seed_removed() {
	{
		echo '# VS Code extensions removed on purpose. Capture never adds these back.'
		echo '# Remove a line (or run `code --install-extension <id>`) to allow it again.'
		[ $# -eq 0 ] || printf '%s\n' "$@"
	} >"$REMOVED"
}

installed() {
	printf '%s\n' "$@" >"$INSTALLED"
}

# Ids only, one per line, so an assertion is not hostage to header wording.
ids() {
	grep -vE '^[[:space:]]*(#|$)' "$1" || true
}

capture() {
	TMPDIR="$LOCK_TMP" PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER" "$@"
}

# ---- the merge rule ----

@test "capture: a machine missing an extension does not drop it" {
	seed_list a b
	seed_removed
	installed a
	capture
	[ "$status" -eq 0 ]
	[ "$(ids "$LIST")" = "$(printf 'a\nb')" ]
}

@test "capture: removed wins over the local install set" {
	seed_list a
	seed_removed b
	installed a b c
	capture
	[ "$status" -eq 0 ]
	[ "$(ids "$LIST")" = "$(printf 'a\nc')" ]
}

@test "capture: falsifier, without the removed entry the same run keeps b" {
	seed_list a
	seed_removed
	installed a b c
	capture
	[ "$status" -eq 0 ]
	[ "$(ids "$LIST")" = "$(printf 'a\nb\nc')" ]
}

@test "capture: an id in the list and the removed file leaves the list" {
	seed_list a b
	seed_removed b
	capture
	[ "$status" -eq 0 ]
	[ "$(ids "$LIST")" = "a" ]
}

@test "capture: ids match case-insensitively" {
	seed_list a
	seed_removed Foo.Bar
	installed foo.bar
	capture
	[ "$status" -eq 0 ]
	[ "$(ids "$LIST")" = "a" ]
}

@test "capture: an absent removed file reads as empty" {
	seed_list a
	installed b
	capture
	[ "$status" -eq 0 ]
	[ "$(ids "$LIST")" = "$(printf 'a\nb')" ]
	[ ! -e "$REMOVED" ]
}

# ---- recording intent ----

@test "capture --removed: twice leaves the id once in the removed file and out of the list" {
	seed_list a b
	seed_removed
	installed a b
	capture --removed b
	[ "$status" -eq 0 ]
	capture --removed b
	[ "$status" -eq 0 ]
	[ "$(grep -cx 'b' "$REMOVED")" -eq 1 ]
	[ "$(ids "$LIST")" = "a" ]
}

@test "capture --removed: creates the removed file under its header when absent" {
	seed_list a
	installed a
	capture --removed b
	[ "$status" -eq 0 ]
	[ "$(sed -n 1p "$REMOVED")" = "# VS Code extensions removed on purpose. Capture never adds these back." ]
	[ "$(ids "$REMOVED")" = "b" ]
}

@test "capture --restored: takes the id out of the removed file and into the list" {
	seed_list a
	seed_removed b
	installed a b
	capture --restored b
	[ "$status" -eq 0 ]
	[ -z "$(ids "$REMOVED")" ]
	[ "$(ids "$LIST")" = "$(printf 'a\nb')" ]
}

# ---- write discipline ----

@test "capture: a merge that changes nothing leaves bytes and mtimes alone and prints no updated" {
	seed_list a b
	seed_removed c
	installed a
	touch -t 202001010000 "$LIST" "$REMOVED"
	cp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	m_list="$(stat -f %m "$LIST")"
	m_removed="$(stat -f %m "$REMOVED")"
	capture
	[ "$status" -eq 0 ]
	cmp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cmp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	[ "$(stat -f %m "$LIST")" = "$m_list" ]
	[ "$(stat -f %m "$REMOVED")" = "$m_removed" ]
	assert_not_contains "updated"
}

@test "capture: a merge that changes the list prints updated" {
	seed_list a
	installed a b
	capture
	[ "$status" -eq 0 ]
	assert_contains "updated"
}

@test "capture: the list's two header lines survive byte for byte" {
	seed_list a
	seed_removed
	installed a b
	capture
	[ "$status" -eq 0 ]
	[ "$(sed -n 1,2p "$LIST")" = "$LIST_HEADER" ]
}

# ---- edges ----

@test "capture: absent code CLI skips clean" {
	seed_list a
	rm "$STUBS/code"
	TMPDIR="$LOCK_TMP" PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER"
	[ "$status" -eq 0 ]
	[ "$output" = "code CLI not found, skipping" ]
}

@test "capture: a failing --list-extensions exits nonzero and leaves both files alone" {
	seed_list a
	seed_removed b
	cp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	LIST_RC=1 capture
	[ "$status" -ne 0 ]
	cmp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cmp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
}

@test "capture: a write that dies after mktemp leaves no temp file in the source tree" {
	seed_list a
	installed a b
	printf '#!/usr/bin/env bash\nexit 1\n' >"$STUBS/mv"
	chmod +x "$STUBS/mv"
	capture
	[ "$status" -ne 0 ]
	run find "$CHEZMOI_SRC/dot_config" -name '*.txt.*'
	[ -z "$output" ]
}

@test "capture: an unreadable list exits nonzero, names it, and writes neither file" {
	seed_list a
	seed_removed b
	installed a c
	cp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	chmod 000 "$LIST"
	capture --removed d
	chmod 644 "$LIST"
	[ "$status" -ne 0 ]
	[ "$output" = "vscode-extensions-capture: cannot read $LIST" ]
	cmp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cmp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
}

@test "capture: an unreadable removed file exits nonzero, names it, and writes neither file" {
	seed_list a
	seed_removed b
	installed a b c
	cp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	chmod 000 "$REMOVED"
	capture
	chmod 644 "$REMOVED"
	[ "$status" -ne 0 ]
	[ "$output" = "vscode-extensions-capture: cannot read $REMOVED" ]
	cmp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cmp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
}

@test "capture: SIGTERM between mktemp and mv leaves no temp file, no lock, and the list unchanged" {
	seed_list a
	seed_removed
	installed a b
	cp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	# The helper's only cmp runs after mktemp and before mv, as a direct child of its main shell.
	printf '#!/bin/bash\nkill -TERM $PPID\nsleep 1\nexit 1\n' >"$STUBS/cmp"
	chmod +x "$STUBS/cmp"
	capture
	[ "$status" -eq 143 ]
	run find "$CHEZMOI_SRC/dot_config" -name '*.txt.*'
	[ -z "$output" ]
	[ ! -e "$LOCK" ]
	/usr/bin/cmp "$LIST" "$BATS_TEST_TMPDIR/list.before"
}

# ---- the lock ----

@test "capture: a held lock holds --removed back until it is released" {
	seed_list a
	seed_removed
	installed a
	hold_lock
	(
		TMPDIR="$LOCK_TMP" PATH="$STUBS:/usr/bin:/bin" bash "$HELPER" --removed x >"$BATS_TEST_TMPDIR/out" 2>&1
		echo $? >"$BATS_TEST_TMPDIR/rc"
	) 3>&- &
	waiter=$!
	sleep 2
	[ ! -e "$BATS_TEST_TMPDIR/rc" ]
	[ -z "$(ids "$REMOVED")" ]
	rm -rf "$LOCK"
	wait "$waiter"
	[ "$(cat "$BATS_TEST_TMPDIR/rc")" = "0" ]
	[ "$(ids "$REMOVED")" = "x" ]
	[ ! -e "$LOCK" ]
}

@test "capture: a stale lock whose holder is dead does not wedge capture" {
	seed_list a
	seed_removed
	installed a
	sleep 0 &
	dead=$!
	wait "$dead"
	ln -s "$dead" "$LOCK"
	capture --removed x
	[ "$status" -eq 0 ]
	[ "$(ids "$REMOVED")" = "x" ]
	[ ! -e "$LOCK" ]
}

@test "capture: a lock held past the deadline exits nonzero and writes neither file" {
	seed_list a
	seed_removed
	installed a b
	cp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	hold_lock
	capture --removed x
	[ "$status" -ne 0 ]
	[ "$output" = "vscode-extensions-capture: $LOCK still held by pid $HOLDER after 10s" ]
	cmp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cmp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	[ "$(readlink "$LOCK")" = "$HOLDER" ]
}

# SIGKILL skips the EXIT trap, so this is the one lock the helper can leave behind: a link
# naming a dead pid. It has no state that names nobody.
@test "capture: a helper SIGKILLed while holding the lock doesn't wedge the next run" {
	seed_list a
	seed_removed
	installed a b
	printf '#!/bin/bash\nkill -KILL $PPID\nsleep 1\nexit 1\n' >"$STUBS/cmp"
	chmod +x "$STUBS/cmp"
	capture
	[ "$status" -eq 137 ]
	[ -L "$LOCK" ]
	rm "$STUBS/cmp"
	capture --removed x
	[ "$status" -eq 0 ]
	[ "$(ids "$REMOVED")" = "x" ]
	[ ! -e "$LOCK" ]
}

# Replays the stale-break race without two racers. The waiter's first readlink sees a dead
# pid, then the stub hands the lock to a live holder before the waiter can break it.
@test "capture: a lock that changes hands after the waiter read a dead pid isn't broken" {
	seed_list a
	seed_removed
	installed a b
	cp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	sleep 0 &
	dead=$!
	wait "$dead"
	ln -s "$dead" "$LOCK"
	sleep 60 3>&- &
	HOLDER=$!
	cat >"$STUBS/readlink" <<STUB
#!/bin/bash
out="\$(/usr/bin/readlink "\$@")"
if [ ! -e "$BATS_TEST_TMPDIR/swapped" ]; then
	: >"$BATS_TEST_TMPDIR/swapped"
	rm -f "$LOCK"
	ln -s "$HOLDER" "$LOCK"
fi
printf '%s\n' "\$out"
STUB
	chmod +x "$STUBS/readlink"
	capture --removed x
	[ -e "$BATS_TEST_TMPDIR/swapped" ]
	[ "$status" -ne 0 ]
	[ "$output" = "vscode-extensions-capture: $LOCK still held by pid $HOLDER after 10s" ]
	[ "$(/usr/bin/readlink "$LOCK")" = "$HOLDER" ]
	cmp "$LIST" "$BATS_TEST_TMPDIR/list.before"
	cmp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
}

@test "capture: an unknown flag exits 2" {
	capture --bogus
	[ "$status" -eq 2 ]
}

@test "capture: --removed without an id exits 2" {
	capture --removed
	[ "$status" -eq 2 ]
}

# ---- the code() wrapper ----

wrapper() {
	TMPDIR="$LOCK_TMP" PATH="$STUBS:/usr/bin:/bin" run zsh -c "source '$SRC/dot_config/zsh/functions.zsh'; code $*"
}

@test "wrapper: --uninstall-extension records the id as removed" {
	seed_list a b
	seed_removed
	installed a
	wrapper --uninstall-extension b
	[ "$status" -eq 0 ]
	[ "$(ids "$REMOVED")" = "b" ]
	[ "$(ids "$LIST")" = "a" ]
}

@test "wrapper: --uninstall-extension twice, then the list lacks the id" {
	seed_list a b
	seed_removed
	installed a b
	wrapper --uninstall-extension b
	wrapper --uninstall-extension b
	[ "$(grep -cx 'b' "$REMOVED")" -eq 1 ]
	[ "$(ids "$LIST")" = "a" ]
}

@test "wrapper: a failed uninstall records nothing and returns the code's status" {
	seed_list a b
	seed_removed
	installed a b
	stub_code 1
	cp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	wrapper --uninstall-extension b
	[ "$status" -eq 1 ]
	cmp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
}

@test "wrapper: --install-extension takes the id out of the removed file" {
	seed_list a
	seed_removed b
	installed a b
	wrapper --install-extension b
	[ "$status" -eq 0 ]
	[ -z "$(ids "$REMOVED")" ]
	[ "$(ids "$LIST")" = "$(printf 'a\nb')" ]
}

@test "wrapper: repeated flags each record their own id" {
	seed_list a b c
	seed_removed
	installed a
	wrapper --uninstall-extension b --uninstall-extension c
	[ "$status" -eq 0 ]
	[ "$(ids "$REMOVED")" = "$(printf 'b\nc')" ]
}

@test "wrapper: a version-pinned id is recorded bare" {
	seed_list a b
	seed_removed
	installed a b
	wrapper --uninstall-extension b@1.2.3
	[ "$status" -eq 0 ]
	[ "$(ids "$REMOVED")" = "b" ]
	seed_removed b
	installed a
	wrapper --install-extension b@1.2.3
	[ "$status" -eq 0 ]
	[ -z "$(ids "$REMOVED")" ]
}

@test "wrapper: a .vsix path records nothing" {
	seed_list a
	seed_removed b
	installed a
	cp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
	wrapper --install-extension ./x.vsix
	[ "$status" -eq 0 ]
	cmp "$REMOVED" "$BATS_TEST_TMPDIR/removed.before"
}

@test "wrapper: a missing helper is named on stderr and code's status is kept" {
	seed_list a
	seed_removed
	rm "$STUBS/vscode-extensions-capture"
	wrapper --uninstall-extension b
	[ "$status" -eq 0 ]
	assert_contains "vscode-extensions-capture not found"
}

@test "wrapper: a failing helper is named on stderr and code's status is kept" {
	seed_list a b
	seed_removed
	installed a b
	LIST_RC=1 wrapper --uninstall-extension b
	[ "$status" -eq 0 ]
	assert_contains "vscode-extensions-capture failed"
}

# ---- static checks ----

@test "sync and wrapper no longer list extensions themselves" {
	[ "$(grep -c 'list-extensions' "$SRC/dot_local/bin/executable_dotfiles-sync")" -eq 0 ]
	[ "$(grep -c 'list-extensions' "$SRC/dot_config/zsh/functions.zsh")" -eq 0 ]
}

# The exact seven ids are a one-time acceptance check done outside the suite: pinning
# them here would turn red the day someone runs `code --install-extension` on one.
@test "the removed file keeps its header, sorted unique ids, and none is in the list" {
	removed="$SRC/dot_config/vscode-extensions-removed.txt"
	[ "$(sed -n 1p "$removed")" = "# VS Code extensions removed on purpose. Capture never adds these back." ]
	[ "$(sed -n 2p "$removed")" = '# Remove a line (or run `code --install-extension <id>`) to allow it again.' ]
	[ "$(ids "$removed")" = "$(ids "$removed" | sort -f | awk '!seen[tolower($0)]++')" ]
	run grep -qixFf <(ids "$removed") "$SRC/dot_config/vscode-extensions.txt"
	[ "$status" -eq 1 ]
}

@test ".chezmoiignore keeps the removed file source-only" {
	grep -qxF '.config/vscode-extensions-removed.txt' "$SRC/.chezmoiignore"
}
