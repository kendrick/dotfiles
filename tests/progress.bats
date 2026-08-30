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

# ---- C-1: the detector asks whether a human is watching --------------------

# The venue is redirected-but-watched, and no other venue answers. Under a bare
# pty apply, and under setsid, `[ -t 1 ]`, `[ -t 2 ]`, and a /dev/tty open all
# agree, so a case run in either of those goes green against the exact
# detectors this forbids. Pinning fd 2 as well as fd 1 is what stops a
# relocation of the original bug to `[ -t 2 ]` from passing.
@test "detector: animation follows the terminal, not whether stdout is a tty" {
	local kit="$BATS_TEST_TMPDIR/sh-ui.sh"
	ui_render_kit "$kit"

	# No `-t 1` survives in executable code. A comment recording the removal
	# is not a violation, so comment lines come out first. This assertion
	# lives here because the clause gets exactly one case, and one homed
	# anywhere else is homed nowhere.
	[ "$(grep -vE '^[[:space:]]*#' "$kit" | grep -cE '\-t 1')" -eq 0 ]

	local v="$BATS_TEST_TMPDIR/watched"
	ui_apply_venue "$v" "$(ui_probe_body)"
	local g
	g="$(ui_glyphs "$kit")"

	# Watched: fd 1 and fd 2 are both files, and /dev/tty is still open. A
	# human piping or capturing an apply is standing right here.
	ui_apply "$v" --glyphs "$g" --stdout "$v/out" --stderr "$v/err" \
		--tty-capture "$v/tty" --timeout 90
	[ "$(ui_distinct_glyphs "$v/tty" "$g")" -ge 1 ]
	[ "$(ui_esc_count "$v/out")" -eq 0 ]

	# Blind: no controlling terminal, so plain lines and nothing else.
	local w="$BATS_TEST_TMPDIR/blind"
	ui_apply_venue "$w" "$(ui_probe_body)"
	ui_apply "$w" --setsid --stdout "$w/out" --stderr "$w/err" --timeout 90
	[ "$(ui_esc_count "$w/out")" -eq 0 ]
	[ "$(ui_distinct_glyphs "$w/out" "$g")" -eq 0 ]
	[ "$(ui_count_matching '^  ✓  ' "$(cat "$w/out")")" -ge 1 ]
}

# ---- C-3: the animation actually animates under a pty ----------------------

@test "animates: the frame advances rather than sitting on one glyph" {
	local kit="$BATS_TEST_TMPDIR/sh-ui.sh"
	ui_render_kit "$kit"
	local v="$BATS_TEST_TMPDIR/anim" g
	ui_apply_venue "$v" "$(ui_probe_body)"
	g="$(ui_glyphs "$kit")"

	# Redirecting the script's stdout is required, not tidiness: under a pty,
	# /dev/tty and chezmoi's forwarded stdout are the same stream, and a
	# combined capture cannot tell an animation on /dev/tty from one wrongly
	# drawn to stdout.
	ui_apply "$v" --glyphs "$g" --stdout "$v/out" --stderr "$v/err" \
		--tty-capture "$v/tty" --timeout 90

	[ "$(ui_distinct_glyphs "$v/tty" "$g")" -ge 2 ]
	# Each frame opens by returning to column 0, so a capture carrying two
	# distinct glyphs and fewer than two carriage returns has drawn them side
	# by side instead of over each other.
	[ "$(LC_ALL=C tr -cd '\r' <"$v/tty" | wc -c | tr -d ' ')" -ge 2 ]
}

# ---- C-7: a display fault never changes a script's exit status -------------

# Judged standalone under a pty, never under `chezmoi apply`. The first
# injection is why: the only way to make /dev/tty present-but-unwritable is
# closing the pty master, which SIGHUPs the whole group, so under an apply the
# same run reports 129 for chezmoi and 0 for the script. The noun this measures
# is the script's own status throughout.
#
# `stty size` reporting zero columns is C-7's sixth injection and is not here
# yet: the kit reads no terminal width, so the fault has nothing to land on. It
# arrives with the width work, which is what gives it something to break.
@test "fail-open: a broken display leaves the exit status exactly where it was" {
	local kit="$BATS_TEST_TMPDIR/sh-ui.sh" d="$BATS_TEST_TMPDIR"
	ui_render_kit "$kit"
	local g inj dir fx marker
	g="$(ui_glyphs "$kit")"

	for inj in none frames-unset frames-empty bar-nan; do
		for dir in ok fail; do
			fx="$d/fo-$inj-$dir.sh"
			ui_fail_open_fixture "$fx" "$kit" "$dir" "$inj"

			# The injection is asserted present on disk before anything is
			# asserted about the result. An injection that silently failed to
			# apply produces a clean run and reads as a pass.
			if [ "$inj" != "none" ]; then
				assert_contains "INJECT:$inj" "$(cat "$fx")"
			fi

			marker="$(ui_pty_status --glyphs "$g" --stdout "$d/o" \
				--stderr "$d/e" --tty-capture "$d/t" --timeout 60 \
				-- /bin/bash "$fx")"
			if [ "$dir" = "ok" ]; then
				[ "$marker" -eq 0 ]
			else
				[ "$marker" -eq 7 ]
			fi
		done
	done

	# Injection: /dev/tty present but its writes failing, built by closing the
	# master while the kit is actively drawing.
	for dir in ok fail; do
		fx="$d/fo-unwritable-$dir.sh"
		ui_fail_open_fixture "$fx" "$kit" "$dir" none
		marker="$(ui_pty_status --glyphs "$g" --close-master-after-glyphs 2 \
			--stdout "$d/o" --stderr "$d/e" --tty-capture "$d/t" \
			--timeout 60 -- /bin/bash "$fx")"
		if [ "$dir" = "ok" ]; then
			[ "$marker" -eq 0 ]
		else
			[ "$marker" -eq 7 ]
		fi
	done

	# Injection: /dev/tty failing to open at all. This is the one that covers
	# the plain branch; the others all live on the animated one, so without it
	# nothing tests the branch a detached run takes.
	for dir in ok fail; do
		fx="$d/fo-notty-$dir.sh"
		ui_fail_open_fixture "$fx" "$kit" "$dir" none
		marker="$(ui_pty_status --setsid --stdout "$d/o" --stderr "$d/e" \
			--timeout 60 -- /bin/bash "$fx")"
		if [ "$dir" = "ok" ]; then
			[ "$marker" -eq 0 ]
		else
			[ "$marker" -eq 7 ]
		fi
	done

	# The check demonstrates its own discrimination rather than assuming it: a
	# kit whose frame write is unguarded must fail the succeeding direction
	# under the unwritable injection. A check that cannot fail against the
	# clause's own failing example has not been verified, only assumed.
	local bad="$d/sh-ui-unguarded.sh"
	ui_unguarded_kit "$kit" "$bad"
	ui_fail_open_fixture "$d/fo-bad.sh" "$bad" ok none
	marker="$(ui_pty_status --glyphs "$g" --close-master-after-glyphs 2 \
		--stdout "$d/o" --stderr "$d/e" --tty-capture "$d/t" --timeout 60 \
		-- /bin/bash "$d/fo-bad.sh")"
	[ "$marker" -ne 0 ]
}
