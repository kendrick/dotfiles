# bash 3.2 — /bin/bash, what bats itself runs these test bodies under — has a
# genuine errexit bug: a failing `[[ ]]` does not abort the function unless it
# is the function's literal last statement, so any assertion before the last
# one in a multi-assertion @test silently stops gating anything. Confirmed by
# hand: `set -e; f() { [[ 1 -eq 2 ]]; echo reached; }; f` prints "reached" on
# this machine's /bin/bash. `(( ))` behaves identically, and a semicolon is no
# escape — `true; [[ 1 -eq 2 ]]; echo reached` prints it too, so the rule is
# about using either as a statement, not about where the line starts. Worst of
# all is a loop: `for i in 1 2 3; do [[ $i -ge 3 ]]; done` exits 0, so one
# passing iteration erases every failure before it, and no statement has to
# follow the assertion for that to happen. grep and case, used below,
# propagate from all of those positions.
assert_contains() {
	local needle="$1" haystack="${2-$output}"
	grep -qF -- "$needle" <<<"$haystack"
}

assert_not_contains() {
	local needle="$1" haystack="${2-$output}"
	case "$haystack" in
	*"$needle"*) return 1 ;;
	esac
}

# --- decision-table fixture machinery (constitution C-1/C-2/C-7's axes) ----
#
# Everything below builds and runs one target's worth of the guard's
# four-axis state (col1, src, live, ct — see constitution C-1) so the table
# case, the multi-target case, and the per-row anchor cases can all share one
# reading of what a row's fixture actually is, rather than five hand-rolled
# copies drifting apart from each other over time.

# `age`/`age-keygen` live in /opt/homebrew/bin, outside the stub PATH
# ("$STUBS:/usr/bin:/bin") setup() below installs for every test. Captured
# here, at file-source time, because `load 'helpers'` runs before setup() on
# every test bats spins up — this is the last point PATH still holds the
# real tool locations. Encrypted-path fixtures use these directly; the guard
# itself is never asked to shell out to age by anything in this file.
#
# `load 'helpers'` runs under errexit, so an unguarded `command -v` here
# would abort every bats file that loads this one on a machine without age
# installed, before a single case runs — including the ten pre-existing
# cases that never touch encryption at all. `|| true` keeps the file load
# alive; sg_age_setup below is what turns an empty result into a clean skip
# for the cases that actually need age, rather than a mass abort.
REAL_AGE="$(command -v age || true)"
REAL_AGE_KEYGEN="$(command -v age-keygen || true)"

# This repo's own chezmoi.toml points [age].identity at
# "$HOME/.config/chezmoi/key.txt" (confirmed against the real config on this
# machine). Encrypted fixtures adopt that same path under the test's
# redirected $HOME, since it's the one convention already load-bearing here
# rather than one invented for this suite alone.
sg_age_identity_path() {
	printf '%s' "$HOME/.config/chezmoi/key.txt"
}

# Generates one age identity for the whole case that calls it and leaves its
# recipient (public key) in $SG_AGE_RECIPIENT. One key per case is enough—
# a real machine has exactly one — and $SG_AGE_KEYFILE is what the no-key
# case removes to prove the fallback in C-5.
sg_age_setup() {
	if [ -z "$REAL_AGE" ] || [ -z "$REAL_AGE_KEYGEN" ]; then
		skip "age/age-keygen not installed on this machine"
	fi
	SG_AGE_KEYFILE="$(sg_age_identity_path)"
	mkdir -p "$(dirname "$SG_AGE_KEYFILE")"
	"$REAL_AGE_KEYGEN" -o "$SG_AGE_KEYFILE" 2>/dev/null
	SG_AGE_RECIPIENT="$("$REAL_AGE_KEYGEN" -y "$SG_AGE_KEYFILE")"
}

# Writes $2 (plaintext) to $3, encrypting through $SG_AGE_RECIPIENT first
# when $1 is 1. Every encrypted source file in this suite is built this way
# so the committed bytes are genuine age ciphertext, never plaintext with an
# ".age" name glued on — the whole point of the encrypted iteration is that
# a guard comparing raw bytes can't see through it.
sg_write_source_version() {
	local encrypted="$1" content="$2" dest="$3"
	if [ "$encrypted" -eq 1 ]; then
		SG_TMP_COUNTER=$((SG_TMP_COUNTER + 1))
		local plain_tmp="$BATS_TEST_TMPDIR/sg-plain-${SG_TMP_COUNTER}"
		printf '%s' "$content" >"$plain_tmp"
		"$REAL_AGE" -r "$SG_AGE_RECIPIENT" -o "$dest" "$plain_tmp"
		rm -f "$plain_tmp"
	else
		printf '%s' "$content" >"$dest"
	fi
}

# Deterministic body generator. Built with awk rather than bash string
# concatenation — measured at 50-95s for the 52-build table case the other
# way, since bash concatenation of multi-kilobyte bodies is dramatically
# slower than letting awk do it in one pass. $3 (label) is folded into every
# line, which is what keeps two different bodies from ever colliding on
# bytes even when their line count and padding happen to match.
sg_gen_body() {
	local lines="$1" pad="$2" label="$3"
	awk -v n="$lines" -v pad="$pad" -v label="$label" 'BEGIN {
		for (i = 0; i < n; i++) printf "%s line %06d\n", label, i
		if (pad > 0) {
			digits = "0123456789abcdef"
			out = ""
			while (length(out) < pad) out = out digits
			print substr(out, 1, pad)
		}
	}'
}

# Per-case counters reset at the top of every case that uses this machinery,
# so nonces (and therefore names and content) never repeat within one case
# without depending on state any earlier case left behind.
#
# Backed by files under $BATS_TEST_TMPDIR rather than plain shell variables,
# because every call site in sync-guard.bats reads the counter through a
# command substitution — `nonce="$(sg_next_nonce)"` — which runs the
# function in a subshell. A subshell's variable assignments die with it, so
# a bare `SG_NONCE_COUNTER=$((SG_NONCE_COUNTER + 1))` would increment a copy
# nobody outside that subshell ever sees, and every call would return the
# same first value forever. Filesystem state has no such scoping: a write
# from inside the subshell is visible to the next command substitution, and
# to the caller's own shell, the moment it happens.
sg_reset_state() {
	SG_TMP_COUNTER=0
	SG_COUNTER_DIR="$BATS_TEST_TMPDIR/sg-counters"
	mkdir -p "$SG_COUNTER_DIR"
	printf '0' >"$SG_COUNTER_DIR/nonce"
	printf '0' >"$SG_COUNTER_DIR/far"
	printf '0' >"$SG_COUNTER_DIR/near"
}

sg_next_nonce() {
	local n
	n=$(($(cat "$SG_COUNTER_DIR/nonce") + 1))
	printf '%s' "$n" >"$SG_COUNTER_DIR/nonce"
	printf '%s' "$n"
}

# Cycles through 3..30 (28 distinct values) without repeating within a
# case, stepping by 11 (coprime with 28) rather than by 1 so a handful of
# calls actually spans the whole range instead of clustering at the low
# end — the "far" stratum needs values spread across 3-30, not merely
# distinct values near 3.
sg_next_far_dist() {
	local c d
	c="$(cat "$SG_COUNTER_DIR/far")"
	d=$((3 + ((c * 11) % 28)))
	printf '%s' "$((c + 1))" >"$SG_COUNTER_DIR/far"
	printf '%s' "$d"
}

# Alternates 1 and 2 — the "near" stratum's two fixed distances.
sg_next_near_dist() {
	local c d
	c="$(cat "$SG_COUNTER_DIR/near")"
	d=$((1 + (c % 2)))
	printf '%s' "$((c + 1))" >"$SG_COUNTER_DIR/near"
	printf '%s' "$d"
}

# Builds one target's whole situation on disk — git history, live file,
# status row — to the four axes named, and leaves the result in
# $SG_HOME_REL (the target path, home-relative) and $SG_STATUS_LINE (the
# fully-formed `chezmoi status` row for it). Nothing here runs the guard or
# asserts anything; callers do that once they've assembled whichever targets
# one run needs.
#
# Args (all positional — bash 3.2 has no associative arrays):
#   1  leaf             bare filename component, may contain a space
#   2  depth            0-4 levels of source-path nesting
#   3  encrypted        0 or 1
#   4  col1             " " or "M" — chezmoi status column 1 (index 0)
#   5  src              clean|edited
#   6  live             head|near|far|none
#   7  ct               ahead|behind
#   8  dist             near/far distance; ignored for head/none
#   9  commit_epoch     HEAD commit time for this path (drives ct)
#  10  live_mtime_epoch live file's mtime (drives ct against commit_epoch)
#  11  src_mtime_epoch  source WORKING file's own mtime — a decoy the guard
#                       must not read; varied only to prove that
#  12  content_lines    body length of this build's content, in lines
#  13  content_bytes    padding bytes appended to the body
#  14  nonce            unique to this build; folded into every piece of
#                       content so no two builds' bytes ever collide and
#                       "none" can never coincide with a real commit
sg_prepare_target() {
	local leaf="$1" depth="$2" encrypted="$3" col1="$4" src="$5" live="$6" ct="$7" \
		dist="$8" commit_epoch="$9" live_mtime_epoch="${10}" src_mtime_epoch="${11}" \
		content_lines="${12}" content_bytes="${13}" nonce="${14}"

	local home_rel i
	if [ "$depth" -eq 0 ]; then
		home_rel=".${leaf}"
	else
		home_rel=".d${nonce}_1"
		i=2
		while [ "$i" -le "$depth" ]; do
			home_rel="${home_rel}/d${nonce}_${i}"
			i=$((i + 1))
		done
		home_rel="${home_rel}/${leaf}"
	fi

	local src_dir="" src_leaf src_rel
	if [ "$depth" -gt 0 ]; then
		src_dir="s${nonce}_1"
		i=2
		while [ "$i" -le "$depth" ]; do
			src_dir="${src_dir}/s${nonce}_${i}"
			i=$((i + 1))
		done
	fi
	if [ "$encrypted" -eq 1 ]; then
		src_leaf="encrypted_s${nonce}.age"
	else
		src_leaf="s${nonce}"
	fi
	if [ -n "$src_dir" ]; then
		src_rel="${src_dir}/${src_leaf}"
	else
		src_rel="${src_leaf}"
	fi

	local home_abs="$HOME/$home_rel" src_abs="$REPO/$src_rel"
	mkdir -p "$(dirname "$home_abs")"
	mkdir -p "$(dirname "$src_abs")"

	local head_body match_body=""
	head_body="$(sg_gen_body "$content_lines" "$content_bytes" "HEAD-${nonce}")"

	case "$live" in
	near | far)
		# $dist filler/match commits older than HEAD, so the match commit—
		# the one whose target state the live file below will hold — sits
		# exactly $dist commits behind HEAD in this path's own history.
		match_body="$(sg_gen_body "$content_lines" "$content_bytes" "MATCH-${nonce}")"
		local n=0 filler_epoch
		while [ "$n" -lt "$dist" ]; do
			if [ "$n" -eq 0 ]; then
				sg_write_source_version "$encrypted" "$match_body" "$src_abs"
			else
				sg_write_source_version "$encrypted" "$(sg_gen_body 3 5 "FILLER-${nonce}-${n}")" "$src_abs"
			fi
			filler_epoch=$((commit_epoch - (dist - n) * 86400))
			commit_at "$filler_epoch" "$src_rel"
			n=$((n + 1))
		done
		;;
	esac

	sg_write_source_version "$encrypted" "$head_body" "$src_abs"
	commit_at "$commit_epoch" "$src_rel"
	touch_at "$src_mtime_epoch" "$src_abs"

	local live_body
	case "$live" in
	head) live_body="$head_body" ;;
	near | far) live_body="$match_body" ;;
	none) live_body="$(sg_gen_body "$content_lines" "$content_bytes" "NONE-${nonce}")" ;;
	esac
	printf '%s' "$live_body" >"$home_abs"
	touch_at "$live_mtime_epoch" "$home_abs"

	# Every edited row in C-1's table is edited *after* HEAD is committed—
	# an uncommitted change sitting on top of real history, never the only
	# state a path has ever had.
	if [ "$src" = "edited" ]; then
		sg_write_source_version "$encrypted" "$(sg_gen_body "$content_lines" "$((content_bytes + 7))" "EDITED-${nonce}")" "$src_abs"
		touch_at "$src_mtime_epoch" "$src_abs"
	fi

	# The stub's source-path arm consults this before falling back to its
	# original dot_-prefix convention, so nested and encrypted fixtures never
	# have to fake that convention themselves — see write_stubs() below.
	printf '%s\t%s\n' "$home_rel" "$src_abs" >>"$SRC_MAP"

	SG_HOME_REL="$home_rel"
	SG_STATUS_LINE="${col1}M ${home_rel}"
}

# Truncates $READD_LOG (this run's only oracle — see file header) and runs
# the guard, leaving $status/$output the way bats' own `run` always does.
sg_run_guard() {
	: >"$READD_LOG"
	run bash "$SCRIPT"
}

sg_check_block() {
	local target="$1"
	[ "$status" -ne 0 ] || return 1
	assert_contains "        $target" || return 1
	[ ! -s "$READD_LOG" ] || return 1
}

sg_check_proceed() {
	[ "$status" -eq 0 ] || return 1
	assert_not_contains "these files have source commits this machine never applied" || return 1
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ] || return 1
}

# One target, one run, one assertion: builds the fixture the 14 positional
# args describe (same shape as sg_prepare_target), writes a status fixture
# holding just that target, runs the guard, and checks the $15th arg
# (BLOCK|PROCEED). Used by the table case and by every anchor case, so a
# single row is built exactly the same way everywhere it appears.
sg_build_row_and_check() {
	local required="${15}"
	sg_prepare_target "${@:1:14}"
	write_status "$SG_STATUS_LINE"
	sg_run_guard
	case "$required" in
	BLOCK) sg_check_block "$SG_HOME_REL" || return 1 ;;
	PROCEED) sg_check_proceed || return 1 ;;
	esac
}

# --- multi-target run assembly (constitution C-1's "one run, many targets") --
#
# One target's fixture, added to whichever run the caller is assembling
# rather than run on its own. Callers reset $STATUS_LINES, $BLOCK_TARGETS,
# and $PROCEED_TARGETS (plain indexed arrays — bash 3.2 has no associative
# ones) before the first call for a run, add every target the run needs,
# write one status fixture from $STATUS_LINES, and run the guard once.
sg_add_target() {
	local required="${15}"
	sg_prepare_target "${@:1:14}"
	STATUS_LINES+=("$SG_STATUS_LINE")
	if [ "$required" = "BLOCK" ]; then
		BLOCK_TARGETS+=("$SG_HOME_REL")
	else
		PROCEED_TARGETS+=("$SG_HOME_REL")
	fi
}

# Confirms the guard's refusal names exactly $BLOCK_TARGETS: every one of
# them present, none of $PROCEED_TARGETS present, and the block list's own
# line count matches — a target the guard silently dropped and a PROCEED
# target it wrongly caught would otherwise look the same to the first two
# checks alone.
sg_assert_multi_block_set() {
	local t got
	for t in "${BLOCK_TARGETS[@]}"; do
		assert_contains "        $t" || return 1
	done
	for t in "${PROCEED_TARGETS[@]}"; do
		assert_not_contains "        $t" || return 1
	done
	got="$(printf '%s\n' "$output" | grep -cE '^        \.')"
	[ "$got" -eq "${#BLOCK_TARGETS[@]}" ] || return 1
}

# --- progress-display harness (constitution C-1..C-14, GitHub #16) ----------
#
# Everything below serves tests/progress.bats. It lives here rather than in
# that file because tests/lint.bats scans this file too, so the bash 3.2
# assertion rules above apply to it and stay enforced.

# The repo root, resolved from BATS_TEST_DIRNAME rather than $PWD: a checker
# that copies this suite into a scratch worktree has to measure the copy, not
# whatever tree the process happens to be running from.
ui_src() {
	printf '%s' "${BATS_TEST_DIRNAME}/.."
}

# A chezmoi config carrying machine_role, written once per test into
# $BATS_TEST_TMPDIR and echoed back by path.
#
# Rendering under a synthetic $HOME without one fails outright with
# `map has no entry for key "machine_role"`, and that key decides the
# Brewfile's size. tests/packages.bats:30-43 is the same idea; this is the
# whole-script form of it.
ui_fixture_config() {
	local cfg="$BATS_TEST_TMPDIR/chezmoi.toml"
	if [ ! -f "$cfg" ]; then
		printf '[data]\n  machine_role = "work"\n' >"$cfg"
	fi
	printf '%s' "$cfg"
}

# Renders .chezmoitemplates/sh-ui.sh on its own, the way a run_ script's
# `{{ template "sh-ui.sh" . }}` include would.
#
# Every flag here is load-bearing. --source is what makes the include resolve
# at all: bare `execute-template` resolves its source dir from
# $HOME/.local/share/chezmoi, so under a synthetic $HOME it finds nothing and
# the include renders empty—the defect still live at
# tests/install-failures.bats:37. --config and --destination pin the other two
# resolution surfaces, because with XDG unset and $HOME real chezmoi still
# falls back through $HOME to the user's own ~/.config.
ui_render_kit() {
	local out="$1"
	env -u XDG_CONFIG_HOME -u XDG_CACHE_HOME \
		chezmoi execute-template \
		--source "$(ui_src)" \
		--config "$(ui_fixture_config)" \
		--destination "$BATS_TEST_TMPDIR/dest" \
		<<<'{{ template "sh-ui.sh" . }}' >"$out"
}

# Counts lines of $2 matching extended regex $1. Anchored assertions need a
# regex, and assert_contains hands its needle to `grep -qF`, so a settled
# line's shape (`^  ✓  `) cannot be expressed through it.
ui_count_matching() {
	printf '%s\n' "${2-$output}" | grep -cE "$1" || true
}

# Counts ESC (0x1b) bytes in a file. Bytes, not matching lines: `grep -c`
# answers a different question and reads as a pass on a file whose every
# escape sequence shares one line.
ui_esc_count() {
	LC_ALL=C tr -cd '\033' <"$1" | wc -c | tr -d ' '
}

# The pty driver. See tests/support/pty-run.py for what each mode measures.
ui_pty() {
	python3 "$(ui_src)/tests/support/pty-run.py" "$@"
}

# The kit's spinner glyphs, read out of the rendered kit rather than
# hardcoded, so a kit that changes its frames does not silently stop being
# measured. Passed to the pty driver as the thing it counts.
ui_glyphs() {
	local kit="$1"
	sed -n 's/^SPINNER_FRAMES=(\(.*\))$/\1/p' "$kit" | tr -d ' \n'
}

# A fixture that animates: it draws frames on /dev/tty for long enough that a
# harness can act on one, then settles. Every venue in this suite needs a
# script under test that is genuinely mid-animation, and `trap '' HUP` is what
# lets it survive the one injection built by closing the pty master.
ui_write_animating_fixture() {
	local path="$1" kit="$2" frames="${3:-12}"
	cat >"$path" <<FIXTURE
#!/bin/bash
set -eu
trap '' HUP
. '$kit'
step_begin 'work'
i=0
while [ "\$i" -lt $frames ]; do
	step_tick "\$i" $frames 'running'
	sleep 0.1
	i=\$((i + 1))
done
step_ok 'work' 'done'
FIXTURE
	chmod +x "$path"
}

# Builds a self-contained chezmoi source dir holding a copy of the kit and one
# run_ script, plus its own destination, home, and config.
#
# The kit is copied in rather than referenced because a `{{ template
# "sh-ui.sh" . }}` include resolves against the CONFIGURED source dir, not the
# file being rendered. A venue that points --source at a fixture and expects
# the repo's kit gets an empty include and a script that calls helpers nothing
# defined.
ui_apply_venue() {
	local v="$1" body="$2"
	mkdir -p "$v/src/.chezmoitemplates" "$v/dest" "$v/home"
	cp "$(ui_src)/.chezmoitemplates/sh-ui.sh" "$v/src/.chezmoitemplates/sh-ui.sh"
	{
		printf '#!/bin/bash\n'
		printf '{{ template "sh-ui.sh" . }}\n'
		printf '%s\n' "$body"
	} >"$v/src/run_onchange_probe.sh.tmpl"
	printf '[data]\n  machine_role = "work"\n' >"$v/chezmoi.toml"
}

# A run_ script body that animates long enough for a harness to act on a frame,
# then settles.
ui_probe_body() {
	local frames="${1:-15}"
	cat <<BODY
step_begin 'probe'
i=0
while [ "\$i" -lt $frames ]; do
	step_tick "\$i" $frames 'working'
	sleep 0.1
	i=\$((i + 1))
done
step_ok 'probe' 'done'
BODY
}

# Runs `chezmoi apply` against a venue, under whichever pty mode the caller
# names.
#
# Every flag and every unset here was measured. The three path flags bypass
# chezmoi's resolution entirely, which is the only deterministic way to keep a
# test off the user's live config: with XDG unset and $HOME real, chezmoi still
# falls back through $HOME to the same ~/.config. The env scrub is the backstop
# for what the SCRIPTS resolve on their own, and NVM_DIR is why it exists. The
# login shell exports it, so `${NVM_DIR:-$HOME/.nvm}` never takes its default
# and a synthetic home is ignored.
ui_apply() {
	local v="$1"
	shift
	(
		unset NVM_DIR HOMEBREW_PREFIX XDG_CONFIG_HOME XDG_CACHE_HOME
		unset NO_COLOR DOTFILES_NO_PROGRESS
		export HOME="$v/home"
		ui_pty "$@" -- chezmoi apply \
			--source "$v/src" --destination "$v/dest" --config "$v/chezmoi.toml"
	)
}

# How many of the kit's frame glyphs appear anywhere in a capture.
#
# Distinct glyphs, not total frames: a single static draw satisfies "escape
# codes were emitted" while showing a frozen character, which is
# indistinguishable from the hang this whole job exists to rule out.
ui_distinct_glyphs() {
	local cap="$1" g="$2" i=0 found=0
	while [ "$i" -lt "${#g}" ]; do
		if grep -qF -- "${g:$i:1}" "$cap"; then
			found=$((found + 1))
		fi
		i=$((i + 1))
	done
	printf '%s' "$found"
}

# Builds one script for the fail-open matrix: a direction (does the underlying
# work succeed or fail?) crossed with a display fault.
#
# In the failing direction the work's status has to reach the caller THROUGH a
# kit helper, as spin_on_log's wrapped job. A fixture that ends in a bare
# `exit 7` on its own tests nothing about the kit; it tests that `exit` works.
#
# `trap '' HUP` is required by the unwritable injection and harmless in the
# rest: the only way to make /dev/tty present-but-unwritable is closing the pty
# master, which raises SIGHUP on the whole foreground process group, and
# without the trap the script dies at 129 before it can spill anything.
ui_fail_open_fixture() {
	local path="$1" kit="$2" direction="$3" injection="$4"
	local inject='' sttydir
	case "$injection" in
	frames-unset) inject='unset SPINNER_FRAMES # INJECT:frames-unset' ;;
	frames-empty) inject='SPINNER_FRAMES=() # INJECT:frames-empty' ;;
	bar-nan) inject='progress_bar "not-a-number" >/dev/null # INJECT:bar-nan' ;;
	stty-zero)
		# The one injection that needs a binary rather than a variable, and the
		# only place in this suite where a shell utility is stubbed. It is an
		# injected fault here, not a venue: everywhere else `stty` resolves for
		# real, because a harness that replaces the shell's own utilities ends
		# up measuring a kit that cannot animate.
		sttydir="$(dirname "$path")/stty-zero"
		mkdir -p "$sttydir"
		printf '#!/bin/bash\necho "0 0"\n' >"$sttydir/stty"
		chmod +x "$sttydir/stty"
		inject="PATH=\"$sttydir:\$PATH\" # INJECT:stty-zero"
		;;
	esac

	local work='return 0'
	if [ "$direction" = "fail" ]; then
		work='return 7'
	fi

	cat >"$path" <<FIXTURE
#!/bin/bash
set -eu
trap '' HUP
. '$kit'
cleanup() {
	st=\$?
	ui_finalize "\$st"
}
trap cleanup EXIT
$inject
job() {
	sleep 1
	$work
}
log="\$(mktemp)"
step_begin 'work'
job >"\$log" 2>&1 &
spin_on_log \$! 'work' "\$log"
step_ok 'work' 'done'
FIXTURE
	chmod +x "$path"
}

# A kit whose frame write is unguarded, which is C-7's own failing example: a
# cosmetic write to a vanished tty takes the script down under errexit, and
# every package after that point goes uninstalled.
ui_unguarded_kit() {
	local src="$1" out="$2"
	sed 's|^  ( printf .*$|  printf "%s" "$1" >\&9|' "$src" >"$out"
	# Both halves of the guard have to be gone, not just the subshell. An
	# earlier version of this replacement left the trailing `|| true` in place
	# and produced a kit that still swallowed the failure, so the check it
	# feeds passed while proving nothing.
	grep -q '^  printf "%s" "\$1" >&9$' "$out"
	grep -vq '|| true' <(grep -A1 '^_ui_write()' "$out")
}

# ui_pty's exit status, without errexit eating the case first. bats runs test
# bodies under `set -e`, so a bare `ui_pty ...; st=$?` never reaches the
# assignment on any run that fails, which is exactly the run worth measuring.
ui_pty_status() {
	local st=0
	ui_pty "$@" || st=$?
	printf '%s' "$st"
}

# One field out of capture-shape.py's report, by name.
ui_shape() {
	local cap="$1" glyphs="$2" field="$3"
	python3 "$(ui_src)/tests/support/capture-shape.py" "$cap" "$glyphs" |
		tr ' ' '\n' | sed -n "s/^$field=//p"
}

# Does the capture end with the cursor restore, as real bytes rather than as
# the eight characters `\033[?25h`?
ui_ends_with_restore() {
	LC_ALL=C tail -c 6 "$1" | LC_ALL=C od -An -tx1 | tr -d ' \n' |
		grep -q '^1b5b3f323568$'
}

# A script that fails by one of four routes, each with its own way of reaching
# a non-zero exit, all of them going through the caller's EXIT trap.
#
# The trap captures $? as its literal first statement. That ordering is the
# whole point: install-prerequisites' real trap opens with `rm -f`, which
# always returns 0, so a finalizer reading $? after it would settle a failing
# script's line as a success.
ui_failure_fixture() {
	local path="$1" kit="$2" route="$3" work=''
	case "$route" in
	# The helper's own loop gives up. spin_until returns 1 on timeout, and
	# that status has to reach the caller rather than being swallowed.
	helper-loop) work='spin_until "waiting" 1 false' ;;
	# The work a helper wraps fails, and its status comes back through the
	# helper rather than around it.
	wrapped) work='job() { sleep 1; return 7; }
log="$(mktemp)"
job >"$log" 2>&1 &
spin_on_log $! "work" "$log"' ;;
	# A region no helper owns aborts under errexit. Six of the ten scripts
	# set -e, so a step settled as ✓ followed by an abort would otherwise
	# exit non-zero with a tick as its last word.
	bare-region) work='false' ;;
	explicit-exit) work='exit 5' ;;
	esac
	cat >"$path" <<FIXTURE
#!/bin/bash
set -eu
. '$kit'
cleanup() {
	st=\$?
	ui_finalize "\$st"
}
trap cleanup EXIT
step_begin 'work'
step_tick 1 3 'running'
step_tick 2 3 'running'
$work
step_ok 'work' 'done'
FIXTURE
	chmod +x "$path"
}

# C-6's failing example as a kit: the cursor is hidden once before the first
# frame and restored once after the last, so every frame drawn in between sits
# inside one open hide span. A clean run looks right and Ctrl-C during the
# two-minute package install leaves the user with no cursor until they run
# `reset`.
ui_hide_once_kit() {
	local src="$1" out="$2"
	# Written as generic substitutions rather than as whole-line matches. The
	# line-matching version stopped biting the moment the frame writers gained
	# their width trim, and a builder that silently produces an unmodified kit
	# hands the check a failing example that cannot fail. The greps below are
	# what turn that into a loud failure instead of a quiet pass.
	sed -e 's|${_UI_ERASE}${_UI_HIDE}|${_UI_ERASE}|g' \
		-e 's|)${_UI_SHOW}"|)"|g' \
		-e 's|^  _ui_measure$|  _ui_measure; [ -n "${_UI_HIDDEN:-}" ] \|\| { _ui_write "$_UI_HIDE"; _UI_HIDDEN=1; }|' \
		"$src" >"$out"
	[ "$(grep -c '\${_UI_ERASE}\${_UI_HIDE}' "$out")" -eq 0 ]
	grep -q '_UI_HIDDEN=1' "$out"
}

# --- the ten templated run_ scripts ----------------------------------------

ui_ten_scripts() {
	cat <<'LIST'
run_before_provision-age-key.sh.tmpl
run_once_before_install-prerequisites.sh.tmpl
run_onchange_after_fetch-licensed-fonts.sh.tmpl
run_onchange_after_install-claude-plugins.sh.tmpl
run_onchange_after_install-global-node-packages.sh.tmpl
run_onchange_after_load-launchagents.sh.tmpl
run_onchange_after_restore-agent-skills.sh.tmpl
run_onchange_configure-raycast.sh.tmpl
run_onchange_install-packages.sh.tmpl
run_onchange_install-vscode-extensions.sh.tmpl
LIST
}

# Stubs for every binary the ten drive as a tool, drawn by effect rather than
# by location.
#
# A binary is stubbed when its real invocation's effect leaves the harness:
# network, launchd, credentials, GUI and app state, package state. Two members
# were measured doing live damage from a passthrough PATH. `launchctl bootout`
# runs against the user's own auto-sync agent, and `defaults` sits on
# /usr/bin, reads like a system utility, and writes com.raycast.macos for real
# on every run.
#
# The shell's own utilities are never stubbed. `sleep`, `tr`, `grep`, `tail`,
# `sed`, `awk`, `stty`, `mktemp`, `cat`, and `date` resolve from /usr/bin:/bin,
# because a no-op `sleep` collapses the kit's frame loop and leaves the harness
# measuring a kit that cannot animate.
ui_write_stubs() {
	local v="$1" name
	mkdir -p "$v/stubs" "$v/clt/usr/bin"

	for name in npm pnpm npx claude code curl launchctl open osascript killall \
		defaults mas gh node corepack softwareupdate sudo pkgutil; do
		printf '#!/bin/bash\nexit 0\n' >"$v/stubs/$name"
		chmod +x "$v/stubs/$name"
	done

	# Present the Command Line Tools as installed. With have_clt false the
	# script falls through to `spin_until "Waiting for the install to finish"
	# 3600`, and a venue that closes every install route turns that bound into
	# an hour.
	: >"$v/clt/usr/bin/clang"
	: >"$v/clt/usr/bin/git"
	chmod +x "$v/clt/usr/bin/clang" "$v/clt/usr/bin/git"
	cat >"$v/stubs/xcode-select" <<STUB
#!/bin/bash
if [ "\$1" = "-p" ]; then
	echo "$v/clt"
	exit 0
fi
exit 0
STUB
	chmod +x "$v/stubs/xcode-select"

	# brew has to answer `command -v`, or install-prerequisites takes its miss
	# branch and runs Homebrew's installer off the network. `bundle` reads the
	# Brewfile from stdin and has to drain it.
	cat >"$v/stubs/brew" <<'STUB'
#!/bin/bash
case "$1" in
bundle)
	cat >/dev/null
	echo "Homebrew Bundle complete! 0 Brewfile dependencies now installed."
	;;
shellenv) : ;;
esac
exit 0
STUB
	chmod +x "$v/stubs/brew"

	# Signed out, which is the branch a harness can honestly take: the real
	# `op read` blocks on interactive auth for as long as you let it.
	cat >"$v/stubs/op" <<'STUB'
#!/bin/bash
case "$1" in
account) exit 1 ;;
esac
exit 1
STUB
	chmod +x "$v/stubs/op"
}

# Renders one of the ten into its own venue and returns that venue's path.
#
# Venue state is per script because one shared home is jointly unsatisfiable.
# provision-age-key needs a seeded key to take its early exit, since without
# one it sources brew's shellenv by absolute path and then blocks on real
# 1Password auth. install-claude-plugins needs that same path empty, because
# with a key present its render takes a decrypt branch no test config can
# serve and fails outright.
ui_ten_venue() {
	local root="$1" tmpl="$2"
	local v="$root/${tmpl%.sh.tmpl}"
	mkdir -p "$v/home" "$v/dest"
	printf '[data]\n  machine_role = "work"\n' >"$v/chezmoi.toml"
	ui_write_stubs "$v"

	if [ "$tmpl" = "run_before_provision-age-key.sh.tmpl" ]; then
		mkdir -p "$v/home/.config/chezmoi"
		printf 'AGE-SECRET-KEY-1TESTONLYNOTAREALKEY\n' \
			>"$v/home/.config/chezmoi/key.txt"
	fi

	(
		unset XDG_CONFIG_HOME XDG_CACHE_HOME
		HOME="$v/home" chezmoi execute-template \
			--source "$(ui_src)" --config "$v/chezmoi.toml" \
			--destination "$v/dest" <"$(ui_src)/$tmpl" >"$v/script.sh"
	)
	printf '%s' "$v"
}

# Runs a rendered script under its stubs.
#
# NVM_DIR and HOMEBREW_PREFIX are SET to venue paths rather than unset, and the
# difference is not cosmetic. Both scripts that consult them read
# `${HOMEBREW_PREFIX:-/opt/homebrew}`, so unsetting the variable hands the
# script the real Homebrew prefix, whose opt/nvm/nvm.sh exists on this machine.
# Sourcing it prepends real node ahead of the stubs and the run reaches a live
# `npm install -g`.
ui_run_ten() {
	local v="$1"
	shift
	(
		unset XDG_CONFIG_HOME XDG_CACHE_HOME NO_COLOR DOTFILES_NO_PROGRESS
		export HOME="$v/home"
		export NVM_DIR="$v/home/.nvm"
		export HOMEBREW_PREFIX="$v/home/.no-homebrew"
		export PATH="$v/stubs:/usr/bin:/bin"
		ui_pty "$@" -- /bin/bash "$v/script.sh"
	)
}

# One field out of bundle-intervals.py's report, by name.
ui_intervals() {
	local cap="$1" glyphs="$2" field="$3"
	python3 "$(ui_src)/tests/support/bundle-intervals.py" "$cap" "$glyphs" |
		tr ' ' '\n' | sed -n "s/^$field=//p"
}

# A `brew` stub that holds each bundle interval open and brackets it on
# /dev/tty.
#
# The dwell is load-bearing and was measured as the only variable that decided
# the answer. Against a violating script the same check reported ok with an
# instant stub and `301 tty bytes inside bundle 1` with the same stub holding
# 0.6s. A stub that returns immediately leaves no window for a frame to land
# in, so the check cannot fail and certifies whatever it is given.
#
# Regime `retry` produces the one state that reaches the second bundle: a fetch
# phase failure with no `<Verb> <entry> has failed!` line, one `Failed to fetch`
# line, and `brew info` resolving a strict subset of the batched names.
ui_write_brew_bundle_stub() {
	local v="$1" regime="$2" drop="$3" keep="$4"
	cat >"$v/stubs/brew" <<STUB
#!/bin/bash
BUNDLE_LOG="$v/bundle-calls.log"
case "\$1" in
info)
	if [ "\$2" = "$drop" ]; then exit 1; fi
	exit 0
	;;
bundle)
	n=\$((\$(wc -l <"\$BUNDLE_LOG" 2>/dev/null || echo 0) + 1))
	echo "bundle \$n" >>"\$BUNDLE_LOG"
	printf 'BUNDLE-ENTER-%s' "\$n" >/dev/tty 2>/dev/null || true
	cat >/dev/null
	sleep 0.6
	printf 'BUNDLE-EXIT-%s' "\$n" >/dev/tty 2>/dev/null || true
	if [ "$regime" = "retry" ] && [ "\$n" -eq 1 ]; then
		echo "Fetching $keep, $drop"
		echo '\`brew bundle\` failed! Failed to fetch $keep, $drop' >&2
		echo 'Error: No available formula with the name "$drop".' >&2
		exit 1
	fi
	echo "Homebrew Bundle complete! 0 Brewfile dependencies now installed."
	exit 0
	;;
esac
exit 0
STUB
	chmod +x "$v/stubs/brew"
	: >"$v/bundle-calls.log"
}

# Two real Brewfile entry names. A name the render never contained would make
# the drop-and-retry gate vacuous, the same reason install-failures.bats reads
# its fixtures out of the render.
ui_brewfile_names() {
	local cfg
	cfg="$(ui_fixture_config)"
	env -u XDG_CONFIG_HOME -u XDG_CACHE_HOME chezmoi execute-template \
		--source "$(ui_src)" --config "$cfg" <<<'{{ template "Brewfile" . }}' |
		grep '^brew "' | head -2 | sed -E 's/^brew "([^"]+)"$/\1/'
}

# The clause's own failing example: the installer with a frame loop running
# across its `brew bundle`. C-4 still passes against this, because the settled
# line still reaches stdout on every path, which is exactly why the guarantee
# needs a venue that watches /dev/tty instead.
ui_animate_over_bundle() {
	local script="$1"
	python3 - "$script" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'brew bundle --file=/dev/stdin <<<"$brewfile" 2>&1 | tee "$bundle_log"'
assert old in s, "bundle invocation not found in rendered script"
s = s.replace(old,
  '( while :; do step_tick 1 1 "installing"; sleep 0.1; done ) &\n'
  'ui_spin=$!\n' + old, 1)
old2 = 'bundle_status=${PIPESTATUS[0]}'
assert old2 in s
s = s.replace(old2, old2 + '\nkill "$ui_spin" 2>/dev/null || true', 1)
open(p, 'w').write(s)
EOF
	grep -q 'ui_spin=' "$script"
}

# The widest live line in a capture, in display columns.
ui_widest_line() {
	python3 "$(ui_src)/tests/support/line-width.py" "$1"
}

# A probe whose live line is as long as the real ones get. The licensed-fonts
# loop ticks with entries like "Font: Operator Mono Lig Nerd Font", which blows
# past 40 columns on its own, so a narrow-terminal check driven by a short
# label proves nothing.
ui_probe_body_wide() {
	cat <<'BODY'
step_begin 'licensed fonts'
i=0
while [ "$i" -lt 15 ]; do
	step_tick "$i" 15 'Font: Operator Mono Lig Nerd Font'
	sleep 0.1
	i=$((i + 1))
done
step_ok 'licensed fonts' 'done'
BODY
}
