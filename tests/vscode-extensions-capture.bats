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
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export CALL_LOG="$BATS_TEST_TMPDIR/code-calls.log"
	export INSTALLED="$BATS_TEST_TMPDIR/installed.txt"
	export CHEZMOI_SRC="$BATS_TEST_TMPDIR/source"
	mkdir -p "$HOME" "$STUBS" "$CHEZMOI_SRC/dot_config"
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

# Answers --list-extensions from $INSTALLED and logs every call, so a case can prove what
# the helper asked of VS Code. A nonzero rc models a refused uninstall.
stub_code() {
	local rc="${1:-0}"
	cat >"$STUBS/code" <<STUB
#!/usr/bin/env bash
echo "\$*" >>"$CALL_LOG"
if [ "\$1" = "--list-extensions" ]; then cat "$INSTALLED"; exit 0; fi
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
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER" "$@"
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
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER"
	[ "$status" -eq 0 ]
	assert_contains "code CLI not found, skipping"
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
	PATH="$STUBS:/usr/bin:/bin" run zsh -c "source '$SRC/dot_config/zsh/functions.zsh'; code $*"
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

# ---- static checks ----

@test "sync and wrapper no longer list extensions themselves" {
	[ "$(grep -c 'list-extensions' "$SRC/dot_local/bin/executable_dotfiles-sync")" -eq 0 ]
	[ "$(grep -c 'list-extensions' "$SRC/dot_config/zsh/functions.zsh")" -eq 0 ]
}

@test "the seeded removed file holds exactly the seven ids and none is in the list" {
	expected='adamerose.markdown-wysiwyg
bierner.markdown-preview-github-styles
ms-azuretools.vscode-docker
ms-vscode-remote.remote-wsl
ms-vsliveshare.vsliveshare
webhint.vscode-webhint
xyc.vscode-mdx-preview'
	[ "$(ids "$SRC/dot_config/vscode-extensions-removed.txt")" = "$expected" ]
	run grep -qxFf <(printf '%s\n' "$expected") "$SRC/dot_config/vscode-extensions.txt"
	[ "$status" -eq 1 ]
}

@test ".chezmoiignore keeps the removed file source-only" {
	grep -qxF '.config/vscode-extensions-removed.txt' "$SRC/.chezmoiignore"
}
