#!/usr/bin/env bats
#
# The display kit's own suite (GitHub #16). Ten cases, one per constitution
# clause that names a filter, each named so `--filter "^<token>:"` selects
# exactly one:
#
#   detector  stdout  animates  adoption  failure
#   sigint    fail-open  bash32  tty-scope  setsid-log
#
# The anchor is not decoration. `bats --filter` matches a regex against test
# NAMES, so a bare token is satisfied by any name containing it—an
# unanchored "stdout" selects three of these, because `detector`'s name ends
# "whether stdout is a tty" and `setsid-log`'s contains "write no ESC to
# stdout". Keep every token's own name unique under its anchor.
#
# Assertions are single-bracket or helper calls throughout, never a bare
# `[[ ]]`. Bash 3.2 does not abort on a failing `[[ ]]` under errexit unless
# it is the body's literal last statement, so the idiom a worker reaches for
# first—`[[ "$output" == *" ✓ "* ]]`—reports `ok` against a kit that
# defines no helpers at all. tests/lint.bats is what stops one coming back.

load 'helpers'

setup() {
	# Both are set on this machine, and a script honoring them goes straight
	# back to the real ~/.config and ~/.cache no matter what $HOME says.
	unset XDG_CONFIG_HOME
	unset XDG_CACHE_HOME
	mkdir -p "$BATS_TEST_TMPDIR/dest"
}

# ---- C-11: the kit runs under bash 3.2 at runtime, not just at parse time ---

# Asserts on what the helpers PRODUCE, never on the exit status of a script
# that calls them. Under `set -u` alone a missing helper is a non-fatal
# command-not-found, so a status-only case goes green against a kit defining
# none of the six—and the ten scripts share no shell regime (six set -e, one
# -uo pipefail, three nothing), so this cannot lean on errexit either.
@test "bash32: every helper runs and produces its line under /bin/bash 3.2" {
	local kit="$BATS_TEST_TMPDIR/sh-ui.sh"
	ui_render_kit "$kit"

	# set -eu is the strictest regime any caller imposes, and it is where
	# bash 3.2's unset-array trap lives: `${#a[@]}` raises `unbound variable`
	# when a is unset and evaluates to 0 when it is merely empty.
	run env -u NO_COLOR -u DOTFILES_NO_PROGRESS /bin/bash -c "
		set -eu
		. '$kit'
		ui_watching || true
		step_begin 'unit test'
		step_ok    'alpha'   'first detail'
		step_warn  'bravo'   'second detail'
		step_fail  'charlie' 'third detail'
		ui_finalize 0
	"

	[ "$status" -eq 0 ]
	# The settled-line shape C-4 requires: two spaces, one glyph, two spaces.
	[ "$(ui_count_matching '^  ✓  ')" -ge 1 ]
	[ "$(ui_count_matching '^  !  ')" -ge 1 ]
	[ "$(ui_count_matching '^  ✗  ')" -ge 1 ]
	assert_contains "alpha"
	assert_contains "bravo"
	assert_contains "charlie"
}

# ---- C-2: the bytes the kit writes to stdout carry no escape codes ---------

# Three modes, because the kit fails differently in each. The third is not
# hypothetical. It is C-7's first injection, and a straightforward kit fails it
# because bash 3.2 holds the bytes of a failed `printf … >&9` in its stdout
# buffer and flushes them to fd 1 when the redirection is undone.
@test "stdout: no ESC reaches fd 1 whether the tty is writable, absent, or broken" {
	local kit="$BATS_TEST_TMPDIR/sh-ui.sh" fx="$BATS_TEST_TMPDIR/fixture.sh"
	ui_render_kit "$kit"
	ui_write_animating_fixture "$fx" "$kit"
	local g
	g="$(ui_glyphs "$kit")"
	local d="$BATS_TEST_TMPDIR"

	# Mode 1—/dev/tty open and writable, fd 1 captured separately from it.
	# The separation is the whole measurement: under a pty, /dev/tty and a
	# forwarded stdout are the same stream.
	ui_pty --glyphs "$g" --stdout "$d/m1.out" --stderr "$d/m1.err" \
		--tty-capture "$d/m1.tty" --timeout 60 -- /bin/bash "$fx"
	[ "$(ui_esc_count "$d/m1.out")" -eq 0 ]
	# Not vacuous: the run really did animate, so fd 1 stayed clean while
	# escape codes were being written somewhere.
	[ "$(ui_esc_count "$d/m1.tty")" -gt 0 ]
	[ ! -s "$d/m1.err" ]

	# Mode 2—detached, no controlling terminal. The degradation contract:
	# plain lines, and no complaint about the terminal that isn't there.
	ui_pty --setsid --stdout "$d/m2.out" --stderr "$d/m2.err" --timeout 60 \
		-- /bin/bash "$fx"
	[ "$(ui_esc_count "$d/m2.out")" -eq 0 ]
	[ "$(ui_count_matching '^  ✓  ' "$(cat "$d/m2.out")")" -ge 1 ]
	assert_not_contains "/dev/tty" "$(cat "$d/m2.err")"

	# Mode 3—/dev/tty open but its writes failing, built by closing the pty
	# master mid-animation. The fixture carries `trap '' HUP` or it dies at
	# 129 before it can spill anything.
	ui_pty --glyphs "$g" --close-master-after-glyphs 2 --stdout "$d/m3.out" \
		--stderr "$d/m3.err" --tty-capture "$d/m3.tty" --timeout 60 \
		-- /bin/bash "$fx"
	[ "$(ui_esc_count "$d/m3.out")" -eq 0 ]

	# The erase, judged from the /dev/tty capture alone so the property needs
	# no interleaving of two separately captured streams: after the final
	# frame, nothing but the cursor restore, and no residual frame text
	# trailing the erase.
	local tail
	tail="$(LC_ALL=C tail -c 12 "$d/m1.tty" | od -An -c | tr -s ' ')"
	assert_contains "\\r 033 [ K 033 [ ? 2 5 h" "$tail"
}
