#!/usr/bin/env bats

# Tests for cfd and cff (#34): pure-copy Finder path helpers in
# dot_config/zsh/functions.zsh.
#
# Both functions shell out to osascript (to ask Finder for paths) and pbcopy
# (to set the clipboard). Real runs would need a GUI session and automation
# permission, so both are stubbed on $PATH. The osascript stub dispatches on
# the script text it's handed—"insertion location" vs "selection"—and its
# output comes from env vars each test exports. The pbcopy stub writes its
# stdin to a file byte for byte, which is what lets the no-trailing-newline
# criteria be checked for real rather than through a $(...) that would strip
# the very newline under test.
#
# These are zsh functions, so the tests run them through the real zsh: source
# the functions file, call the function. No other file in the suite touches a
# .zsh file yet, so this is the precedent.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
FUNCS="$SRC/dot_config/zsh/functions.zsh"

# Resolve zsh before setup() narrows PATH to the stub dir. || true because
# helpers load under errexit.
REAL_ZSH="$(command -v zsh || true)"

setup() {
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	mkdir -p "$STUBS"

	export OSA_LOG="$BATS_TEST_TMPDIR/osascript.log"
	: >"$OSA_LOG"
	export PBCOPY_FILE="$BATS_TEST_TMPDIR/clipboard"

	write_stubs

	export PATH="$STUBS:/usr/bin:/bin"
}

write_stubs() {
	# Dispatch on the script text, not argv position, so the stub keeps
	# working if the functions ever switch between one -e and many.
	cat >"$STUBS/osascript" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OSA_LOG"
if [ -n "$STUB_OSA_FAIL" ]; then
	echo "execution error: Not authorized to send Apple events to Finder. (-1743)" >&2
	exit 1
fi
case "$*" in
	*"insertion location"*)
		printf '%s\n' "$STUB_FINDER_DIR"
		;;
	*selection*)
		# Real osascript prints the script result plus a newline; an
		# empty selection yields an empty result, so a bare newline.
		printf '%s\n' "$STUB_FINDER_SELECTION"
		;;
	*)
		echo "osascript stub: unrecognised script: $*" >&2
		exit 64
		;;
esac
STUB

	cat >"$STUBS/pbcopy" <<'STUB'
#!/usr/bin/env bash
cat >"$PBCOPY_FILE"
STUB

	chmod +x "$STUBS/osascript" "$STUBS/pbcopy"
}

# The clipboard file's exact bytes, with a sentinel appended so command
# substitution can't strip a trailing newline before we look for one.
clipboard_bytes() {
	cat "$PBCOPY_FILE"
	printf x
}

@test "finder-copy: cfd copies the front window directory with no trailing newline and echoes it" {
	export STUB_FINDER_DIR="/Users/example/Projects/demo"

	run "$REAL_ZSH" -c "source '$FUNCS'; cfd"

	[ "$status" -eq 0 ]
	assert_contains "/Users/example/Projects/demo"
	[ "$(clipboard_bytes)" = "/Users/example/Projects/demox" ]
}

@test "finder-copy: cff with one selected item copies its path with no trailing newline" {
	export STUB_FINDER_SELECTION="/Users/example/Projects/demo/README.md"

	run "$REAL_ZSH" -c "source '$FUNCS'; cff"

	[ "$status" -eq 0 ]
	assert_contains "/Users/example/Projects/demo/README.md"
	[ "$(clipboard_bytes)" = "/Users/example/Projects/demo/README.mdx" ]
}

@test "finder-copy: cff with multiple items copies newline-separated paths in Finder order" {
	# Deliberately not sorted: order must be Finder's, not lexical.
	export STUB_FINDER_SELECTION="/Users/example/b.txt
/Users/example/a.txt"

	run "$REAL_ZSH" -c "source '$FUNCS'; cff"

	[ "$status" -eq 0 ]
	[ "$(clipboard_bytes)" = "/Users/example/b.txt
/Users/example/a.txtx" ]
}

@test "finder-copy: cff with an empty selection copies the window directory like cfd" {
	export STUB_FINDER_SELECTION=""
	export STUB_FINDER_DIR="/Users/example/Projects/demo"

	run "$REAL_ZSH" -c "source '$FUNCS'; cff"

	[ "$status" -eq 0 ]
	assert_contains "/Users/example/Projects/demo"
	[ "$(clipboard_bytes)" = "/Users/example/Projects/demox" ]
}

@test "finder-copy: cfd leaves PWD and OLDPWD untouched" {
	export STUB_FINDER_DIR="/Users/example/Projects/demo"
	mkdir -p "$BATS_TEST_TMPDIR/dir-a" "$BATS_TEST_TMPDIR/dir-b"

	run "$REAL_ZSH" -c "cd '$BATS_TEST_TMPDIR/dir-a'; cd '$BATS_TEST_TMPDIR/dir-b'; source '$FUNCS'; cfd >/dev/null; print -r -- \"\$PWD|\$OLDPWD\""

	[ "$status" -eq 0 ]
	assert_contains "$BATS_TEST_TMPDIR/dir-b|$BATS_TEST_TMPDIR/dir-a"
}

@test "finder-copy: cff leaves PWD and OLDPWD untouched" {
	export STUB_FINDER_SELECTION="/Users/example/file.txt"
	mkdir -p "$BATS_TEST_TMPDIR/dir-a" "$BATS_TEST_TMPDIR/dir-b"

	run "$REAL_ZSH" -c "cd '$BATS_TEST_TMPDIR/dir-a'; cd '$BATS_TEST_TMPDIR/dir-b'; source '$FUNCS'; cff >/dev/null; print -r -- \"\$PWD|\$OLDPWD\""

	[ "$status" -eq 0 ]
	assert_contains "$BATS_TEST_TMPDIR/dir-b|$BATS_TEST_TMPDIR/dir-a"
}

@test "finder-copy: cfd returns nonzero and leaves the clipboard alone when osascript fails" {
	export STUB_OSA_FAIL=1
	printf 'previous clipboard contents' >"$PBCOPY_FILE"

	run "$REAL_ZSH" -c "source '$FUNCS'; cfd"

	[ "$status" -ne 0 ]
	[ "$(clipboard_bytes)" = "previous clipboard contentsx" ]
}

@test "finder-copy: cff returns nonzero and leaves the clipboard alone when osascript fails" {
	export STUB_OSA_FAIL=1
	printf 'previous clipboard contents' >"$PBCOPY_FILE"

	run "$REAL_ZSH" -c "source '$FUNCS'; cff"

	[ "$status" -ne 0 ]
	[ "$(clipboard_bytes)" = "previous clipboard contentsx" ]
}
