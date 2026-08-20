#!/usr/bin/env bats
#
# The source-ahead-of-machine guard (design doc:
# docs/superpowers/specs/2026-08-07-dotfiles-sync-preflight-guard-design.md).
# The guard slots between the plugin-manifest phase and `chezmoi re-add`, so
# every case here pays the same six-phase cost tests/sync.bats documents
# before the guard's own two lines even have a chance to print. See that
# file's header for why PATH is replaced rather than extended and why each
# case rebuilds its repo from scratch.
#
# The central risk in this suite is proving a negative: that re-add was
# never reached. Exit status alone can't carry that, because the commit
# phase downstream fails for reasons of its own in several of these cases
# (the not-a-git-repo one in particular). $READD_LOG is what actually proves
# it—the chezmoi stub's `re-add` arm appends to it, so an empty log after a
# run is the only real evidence capture never happened.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/dot_local/bin/executable_dotfiles-sync"

# Three fixed points on the timeline, chosen far apart and far from
# wall-clock "now" so every comparison in this file is unambiguous without
# ever touching a real clock. NEW > OLD > OLDER.
OLD_EPOCH=1000000000
NEW_EPOCH=2000000000
OLDER_EPOCH=500000000

# The last commit before the preflight guard existed, used by the byte-identity
# case as its "before" baseline. Only ever repoint this at another pre-guard
# commit; moving it forward past the guard makes that case compare the script
# against itself and quietly stop proving anything.
PREGUARD_REV=e77da9a

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	mkdir -p "$HOME" "$STUBS"
	unset DOTFILES_AUTO_PUSH SRC_PATH_OVERRIDE

	# $HOME has no .gitconfig once redirected above, so without these `git
	# commit` fails with "Please tell me who you are" before the guard's
	# own git calls ever run.
	export GIT_AUTHOR_NAME="dotfiles-sync tests"
	export GIT_AUTHOR_EMAIL="dotfiles-sync-tests@example.invalid"
	export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
	export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

	export OSA_LOG="$BATS_TEST_TMPDIR/osascript.log"
	: >"$OSA_LOG"

	# The chezmoi `status` stub cats this rather than deriving rows from
	# real repo state, so every test controls the exact column bytes it's
	# proving against instead of hoping a real `chezmoi status` invocation
	# happens to line up.
	export STATUS_FIXTURE="$BATS_TEST_TMPDIR/status.fixture"
	: >"$STATUS_FIXTURE"

	# The chezmoi `re-add` stub appends here. This is the suite's real
	# oracle for "capture never ran"—see file header.
	export READD_LOG="$BATS_TEST_TMPDIR/readd.log"
	: >"$READD_LOG"

	# Tab-separated target -> absolute source path, appended to by
	# sg_prepare_target (helpers.bash) for every fixture the decision-table
	# machinery builds. The source-path stub arm below consults it before
	# falling back to the original dot_-prefix convention, which is what
	# lets nested and encrypted fixtures skip faking that convention
	# themselves. Empty and unused by the ten pre-existing cases.
	export SRC_MAP="$BATS_TEST_TMPDIR/src-map"
	: >"$SRC_MAP"

	write_stubs
	export PATH="$STUBS:/usr/bin:/bin"
}

# chezmoi, date and osascript are the only tools the guarded path needs
# present. code, brew, jq, claude-plugins-capture and claude-settings-normalize
# are deliberately never written here, so each of their phases takes its
# documented "not found, skipping" branch—see tests/sync.bats for the same
# contract.
write_stubs() {
	cat >"$STUBS/chezmoi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
source-path)
	if [ -n "${2:-}" ]; then
		# A single override escape hatch for the one case (git log erroring
		# on a path outside the repo) that the naming convention below
		# can't produce on its own, since that convention always builds a
		# path rooted under $REPO.
		if [ -n "${SRC_PATH_OVERRIDE:-}" ]; then
			printf '%s\n' "$SRC_PATH_OVERRIDE"
			exit 0
		fi
		tgt="${2#"$HOME"/}"
		# Decision-table fixtures (tests/helpers.bash, sg_prepare_target)
		# register an exact mapping here instead of faking chezmoi's
		# dot_/private_/encrypted_ naming convention, which the fallback
		# below still handles unchanged for every case that predates this
		# file. Last match wins, which only matters when a name is
		# reused -- the builder guarantees none is.
		if [ -s "$SRC_MAP" ]; then
			mapped="$(awk -F'\t' -v t="$tgt" '$1 == t { v = $2 } END { if (v != "") print v }' "$SRC_MAP")"
			if [ -n "$mapped" ]; then
				printf '%s\n' "$mapped"
				exit 0
			fi
		fi
		case "$tgt" in
		.*)
			base="dot_${tgt#.}"
			;;
		*)
			exit 1
			;;
		esac
		if [ -f "$REPO/$base.tmpl" ]; then
			printf '%s\n' "$REPO/$base.tmpl"
			exit 0
		fi
		if [ -f "$REPO/$base" ]; then
			printf '%s\n' "$REPO/$base"
			exit 0
		fi
		exit 1
	fi
	printf '%s\n' "$REPO"
	;;
status)
	cat "$STATUS_FIXTURE"
	;;
re-add)
	echo "re-add" >>"$READD_LOG"
	exit 0
	;;
execute-template)
	exit 0
	;;
*)
	exit 1
	;;
esac
STUB

	# Records the full argument list, not just that osascript ran: the
	# title in "$1" is the only thing that tells notify_fail's calls apart
	# from the bare notify() ones, and a stub that only touched a marker
	# file would throw that distinction away.
	cat >"$STUBS/osascript" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OSA_LOG"
STUB

	# The commit phase folds this into the commit message, which would
	# otherwise give two identical runs different shas depending on the
	# second they ran in. The real `date` is shadowed for the script under
	# test only—touch_at() below reaches for /bin/date directly for exactly
	# that reason, to compute timestamps in the test body.
	cat >"$STUBS/date" <<'STUB'
#!/usr/bin/env bash
echo "2026-01-01"
STUB

	chmod +x "$STUBS/chezmoi" "$STUBS/osascript" "$STUBS/date"
}

# One throwaway repo per case, with a bare origin so the push path's opt-in
# branch has a remote to reason about even though DOTFILES_AUTO_PUSH stays
# unset here. $REPO is exported for the chezmoi stub to read at run time.
fresh_repo() {
	local origin="$BATS_TEST_TMPDIR/origin.git"
	export REPO="$BATS_TEST_TMPDIR/repo"
	git init -q --bare "$origin"
	git init -q "$REPO"
	printf 'seed\n' >"$REPO/seed.txt"
	git -C "$REPO" add seed.txt
	git -C "$REPO" commit -q -m 'seed'
	git -C "$REPO" branch -M main
	git -C "$REPO" remote add origin "$origin"
	git -C "$REPO" push -q origin main
}

# Writes each argument as its own row in the status fixture. Every row is
# hand-built to the XY-PATH contract (column 0 at index 0, column 1 at
# index 1, a literal space at index 2, path from index 3) since that's the
# exact byte layout the guard reads, and the point of a fixture is that the
# columns are test-controlled rather than derived from a real invocation.
write_status() {
	printf '%s\n' "$@" >"$STATUS_FIXTURE"
}

# Commits $2 (a path relative to $REPO) with both git clocks pinned to
# epoch $1. The guard's whole comparison rests on git commit time vs. live
# mtime, never on wall-clock "now"—a real clock here would make the case
# nondeterministic depending on the second it happened to run in.
commit_at() {
	local epoch="$1" rel="$2"
	git -C "$REPO" add "$rel"
	GIT_AUTHOR_DATE="@$epoch" GIT_COMMITTER_DATE="@$epoch" \
		git -C "$REPO" commit -q -m "seed $rel"
}

# Sets $2's mtime to epoch $1 via the real date binary at its absolute
# path—PATH's `date` is the stub above, which always prints a fixed string
# and can't do this conversion. touch -t creates the file if it doesn't
# already exist, same as plain touch.
touch_at() {
	local epoch="$1" path="$2"
	touch -t "$(/bin/date -r "$epoch" +%Y%m%d%H%M.%S)" "$path"
}

@test "sync-guard: source commit newer than live mtime trips the guard" {
	fresh_repo
	mkdir -p "$REPO/dot_claude" "$HOME/.claude"
	printf 'source version\n' >"$REPO/dot_claude/CLAUDE.md"
	commit_at "$NEW_EPOCH" dot_claude/CLAUDE.md
	touch_at "$OLD_EPOCH" "$HOME/.claude/CLAUDE.md"

	mkdir -p "$REPO/dot_local/bin" "$HOME/.local/bin"
	printf 'source version\n' >"$REPO/dot_local/bin/dotfiles-sync"
	commit_at "$OLD_EPOCH" dot_local/bin/dotfiles-sync
	touch_at "$OLDER_EPOCH" "$HOME/.local/bin/dotfiles-sync"

	write_status " M .claude/CLAUDE.md" " M .local/bin/dotfiles-sync"

	run bash "$SCRIPT"

	[ "$status" -ne 0 ]
	assert_contains "==> Checking whether source moved ahead of this machine"
	assert_contains "    ! these files have source commits this machine never applied:"
	assert_contains "        .claude/CLAUDE.md"
	assert_contains "        .local/bin/dotfiles-sync"
	assert_contains "    Capturing now would revert them. Nothing was captured."
	assert_contains "    See what would change:       chezmoi diff ~/.claude/CLAUDE.md"
	assert_contains "    Take source's version:       chezmoi apply ~/.claude/CLAUDE.md"
	assert_contains "    Keep this machine's version: chezmoi re-add ~/.claude/CLAUDE.md"
	assert_contains "    Then re-run:                 dotfiles-sync"
	assert_contains "Dotfiles sync failed" "$(cat "$OSA_LOG")"
	[ ! -s "$READD_LOG" ]
}

@test "sync-guard: live mtime newer than source commit proceeds" {
	fresh_repo
	printf 'source version\n' >"$REPO/dot_vimrc"
	commit_at "$OLD_EPOCH" dot_vimrc
	touch_at "$NEW_EPOCH" "$HOME/.vimrc"

	write_status " M .vimrc"

	run bash "$SCRIPT"

	[ "$status" -eq 0 ]
	assert_not_contains "these files have source commits this machine never applied"
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ]
}

@test "sync-guard: one file behind and one drifted forward reports only the behind file" {
	fresh_repo
	printf 'source\n' >"$REPO/dot_behindfile"
	commit_at "$NEW_EPOCH" dot_behindfile
	touch_at "$OLD_EPOCH" "$HOME/.behindfile"

	printf 'source\n' >"$REPO/dot_forwardfile"
	commit_at "$OLD_EPOCH" dot_forwardfile
	touch_at "$NEW_EPOCH" "$HOME/.forwardfile"

	write_status " M .behindfile" " M .forwardfile"

	run bash "$SCRIPT"

	[ "$status" -ne 0 ]
	assert_contains "        .behindfile"
	assert_not_contains ".forwardfile"
	assert_contains "Dotfiles sync failed" "$(cat "$OSA_LOG")"
	[ ! -s "$READD_LOG" ]
}

@test "sync-guard: A, D, and R status rows are ignored" {
	fresh_repo
	# The D row gets a real, resolvable, committed source file on purpose. Left
	# unresolvable it would pass for the wrong reason: D also satisfies the
	# template-drift loop's column-0 condition downstream, so a `source-path`
	# that simply fails hides the guard's own column-1 skip behind that loop's
	# `|| continue`. With the file present, both phases genuinely evaluate the
	# row and both have to stay quiet on their own merits.
	printf 'source\n' >"$REPO/dot_removed"
	commit_at "$NEW_EPOCH" dot_removed
	touch_at "$OLDER_EPOCH" "$HOME/.removed"
	write_status "A  .added" "D  .removed" "R  .local/bin/run_onchange_thing.sh"

	run bash "$SCRIPT"

	[ "$status" -eq 0 ]
	assert_not_contains "these files have source commits this machine never applied"
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ]
}

@test "sync-guard: template sources stay silent on both a genuine drift and an unapplied source edit" {
	fresh_repo
	printf 'template source\n' >"$REPO/dot_tmplfileA.tmpl"
	commit_at "$NEW_EPOCH" dot_tmplfileA.tmpl
	touch_at "$OLD_EPOCH" "$HOME/.tmplfileA"

	printf 'template source\n' >"$REPO/dot_tmplfileB.tmpl"
	commit_at "$NEW_EPOCH" dot_tmplfileB.tmpl
	touch_at "$OLD_EPOCH" "$HOME/.tmplfileB"

	# Column 0 M: genuine live drift the existing template-drift phase (now
	# reading column 0—the fix this row exists to prove) must still report.
	# Column 0 blank, column 1 M: an unapplied source edit, the exact shape
	# the pre-fix column-1 read would have wrongly reported as drift. Both
	# rows also carry a column-1 M with a live mtime older than the commit,
	# so if the guard's own .tmpl skip were ever dropped, either row would
	# trip it. That's a canary against a regression, not just a check that
	# it currently behaves.
	write_status "MM .tmplfileA" " M .tmplfileB"

	run bash "$SCRIPT"

	[ "$status" -eq 0 ]
	assert_not_contains "these files have source commits this machine never applied"
	assert_contains "    ! .tmplfileA drifted but is a template — not captured; reconcile by hand"
	assert_not_contains ".tmplfileB drifted"
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ]
}

@test "sync-guard: source file with no commits falls back to today's behavior" {
	fresh_repo
	printf 'untracked\n' >"$REPO/dot_nocommits"
	# Deliberately not committed—git log on this path returns empty, not an
	# error, which is the fallback this case exists to prove.
	touch_at "$OLD_EPOCH" "$HOME/.nocommits"
	write_status " M .nocommits"

	run bash "$SCRIPT"

	[ "$status" -eq 0 ]
	assert_not_contains "these files have source commits this machine never applied"
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ]
}

@test "sync-guard: live file missing falls back to today's behavior" {
	fresh_repo
	printf 'source\n' >"$REPO/dot_missinglive"
	commit_at "$NEW_EPOCH" dot_missinglive
	# $HOME/.missinglive deliberately never created—stat fails.
	write_status " M .missinglive"

	run bash "$SCRIPT"

	[ "$status" -eq 0 ]
	assert_not_contains "these files have source commits this machine never applied"
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ]
}

@test "sync-guard: git log erroring on a path outside the repo falls back to today's behavior" {
	fresh_repo
	mkdir -p "$BATS_TEST_TMPDIR/outside"
	printf 'source\n' >"$BATS_TEST_TMPDIR/outside/dot_outsiderepo"
	export SRC_PATH_OVERRIDE="$BATS_TEST_TMPDIR/outside/dot_outsiderepo"
	touch_at "$OLD_EPOCH" "$HOME/.outsiderepo"
	write_status " M .outsiderepo"

	run bash "$SCRIPT"

	[ "$status" -eq 0 ]
	assert_not_contains "these files have source commits this machine never applied"
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ]
}

@test "sync-guard: source directory not a git repo at all falls back to today's behavior" {
	export REPO="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$REPO"
	printf 'source\n' >"$REPO/dot_norepo"
	touch_at "$OLD_EPOCH" "$HOME/.norepo"
	write_status " M .norepo"

	run bash "$SCRIPT"

	# The commit phase downstream fails for its own reason here: $SRC isn't
	# a git repo at all, so `git symbolic-ref` and friends blow up after the
	# guard has already run. That failure is real and expected, and it isn't
	# what this case is testing, so the exit code is deliberately not
	# asserted. What's asserted instead is that the guard itself stayed
	# quiet and that re-add was reached before the later, unrelated failure.
	assert_not_contains "these files have source commits this machine never applied"
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ]
}

@test "sync-guard: clean status proceeds and is byte-identical to today's output modulo the guard's own lines" {
	fresh_repo
	# STATUS_FIXTURE is already empty from setup—a genuinely clean `chezmoi
	# status` prints nothing, so there's nothing to write here.

	run bash "$SCRIPT"
	out_new="$output"
	status_new="$status"

	[ "$status_new" -eq 0 ]
	assert_contains "==> Checking whether source moved ahead of this machine" "$out_new"
	assert_contains "    none" "$out_new"
	[ "$(wc -l <"$READD_LOG" | tr -d ' ')" -eq 1 ]

	# Pinned to the last commit before the guard landed, never to HEAD. HEAD
	# is the guard's own commit the moment this ships, which would compare the
	# script against itself, strip two lines from one side only, and fail on
	# the landing commit. A sha is the only baseline that stays "today's
	# output" after today.
	local head_script="$BATS_TEST_TMPDIR/preguard-dotfiles-sync"
	git -C "$SRC" show "$PREGUARD_REV:dot_local/bin/executable_dotfiles-sync" >"$head_script"
	chmod +x "$head_script"

	run bash "$head_script"
	out_head="$output"
	status_head="$status"

	[ "$status_new" -eq "$status_head" ]

	# The spec mandates the guard's own heading and "none" line on every
	# clean run, so "byte-identical to today's output" is read as
	# byte-identical modulo exactly those two lines. They're matched as a
	# contiguous pair rather than filtered independently: the template-drift
	# phase reports its own clean case with the very same "    none" line, so
	# dropping every match of it strips a line HEAD also prints and turns a
	# passing comparison into a failing one. Anchoring on the heading and
	# taking only the "none" directly beneath it is what keeps this a test of
	# the guard's footprint instead of the word's.
	local filtered_new
	filtered_new="$(printf '%s\n' "$out_new" | awk '
		$0 == "==> Checking whether source moved ahead of this machine" { pending = 1; next }
		pending == 1 && $0 == "    none" { pending = 0; next }
		{ pending = 0; print }
	')"

	[ "$filtered_new" = "$out_head" ]
}

# ---------------------------------------------------------------------------
# Constitution C-1/C-8/C-9: the decision table's anchor cases.
#
# These small cases run against both the working tree and, via C-8/C-9's
# check scripts, a worktree checked out at the pre-fix commit — the check
# scripts copy this whole tests/ directory over that checkout, so the same
# case body runs against old and new guard code without any change here.
# Every fixture below is built through sg_build_row_and_check
# (tests/helpers.bash), the same machinery the table case below uses, so a
# row is built identically wherever it appears in this file.
# ---------------------------------------------------------------------------

@test "sync-guard: decision table row 1 fails today" {
	# ("_", edited, head, behind) — the uncommitted source edit issue #29's
	# row 1 describes. Today's guard only compares commit time to live
	# mtime, so an edit that was never committed never advances anything it
	# reads and this row proceeds when it must block.
	fresh_repo
	sg_reset_state
	sg_build_row_and_check "row1" 1 0 " " edited head behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 6 24 "$(sg_next_nonce)" BLOCK
}

@test "sync-guard: decision table row 4 fails today" {
	# ("_", clean, near, behind) — issue #29 row 2 in its commonest form:
	# source committed one commit ahead, then something rewrote the live
	# file back onto an older value afterward. Today's guard has no arm 3
	# at all, so a live file matching an old commit reads the same as one
	# that never drifted.
	fresh_repo
	sg_reset_state
	local dist
	dist="$(sg_next_near_dist)"
	sg_build_row_and_check "row4" 2 0 " " clean near behind "$dist" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 5 20 "$(sg_next_nonce)" BLOCK
}

@test "sync-guard: decision table row 6 fails today" {
	# ("_", clean, far, behind) — row 4's deep form: the live file sits on
	# a commit many revisions back instead of the one right before HEAD.
	fresh_repo
	sg_reset_state
	local dist
	dist="$(sg_next_far_dist)"
	sg_build_row_and_check "row6" 3 0 " " clean far behind "$dist" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 7 40 "$(sg_next_nonce)" BLOCK
}

@test "sync-guard: decision table row 12 fails today" {
	# ("M", edited, none, behind) — ordinary live drift (column 1 M) sitting
	# on top of an uncommitted source edit. Today's guard reads no status
	# column at all and has no arm 1, so the edit is invisible either way.
	fresh_repo
	sg_reset_state
	sg_build_row_and_check "row12" 0 0 "M" edited none behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 4 15 "$(sg_next_nonce)" BLOCK
}

@test "sync-guard: decision table row 13 fails today" {
	# ("_", edited, near, behind) — issue #29's two rows stacked on one
	# file: an uncommitted edit *and* the source committed ahead of what
	# this machine applied.
	fresh_repo
	sg_reset_state
	local dist
	dist="$(sg_next_near_dist)"
	sg_build_row_and_check "row13" 4 0 " " edited near behind "$dist" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 9 33 "$(sg_next_nonce)" BLOCK
}

@test "sync-guard: the decision table PROCEED rows hold today" {
	# Rows 7, 8, 9 and 10 — what the guard already does correctly. This
	# case has to pass at both the working tree and the pre-fix anchor
	# (C-8), so it carries no BLOCK build at all: changing any of these four
	# outcomes would be a regression, not a fix.
	fresh_repo
	sg_reset_state

	# Row 7: (" ", clean, none, behind) — ordinary drift on a machine with
	# no chezmoi persistent state, where every row's column 1 reads blank.
	sg_build_row_and_check "proceed7" 0 0 " " clean none behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 3 10 "$(sg_next_nonce)" PROCEED || return 1

	# Row 8: ("M", clean, none, behind) — ordinary live drift, the thing
	# re-add exists for.
	sg_build_row_and_check "proceed8" 1 0 "M" clean none behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 4 12 "$(sg_next_nonce)" PROCEED || return 1

	# Row 9: ("M", clean, near, behind) — the live file drifted back onto a
	# value this repo once committed.
	local dist9
	dist9="$(sg_next_near_dist)"
	sg_build_row_and_check "proceed9" 2 0 "M" clean near behind "$dist9" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 5 18 "$(sg_next_nonce)" PROCEED || return 1

	# Row 10: ("M", clean, far, behind) — the same, onto a much older value.
	local dist10
	dist10="$(sg_next_far_dist)"
	sg_build_row_and_check "proceed10" 3 0 "M" clean far behind "$dist10" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 6 22 "$(sg_next_nonce)" PROCEED || return 1
}

@test "sync-guard: an encrypted source with no key falls back to today's behavior" {
	# Row 3's encrypted build (ct=ahead) with the age identity removed
	# afterward, rather than merely pointed away from. Arm 2 (commit time
	# vs. live mtime) needs no decryption at all, so this must still block
	# through it even with the key gone — a PROCEED row can't prove this,
	# since it would go green whether the fallback worked or the path was
	# skipped outright.
	fresh_repo
	sg_reset_state
	sg_age_setup
	local dist
	dist="$(sg_next_near_dist)"
	sg_prepare_target "nokeytarget" 1 1 " " clean near ahead "$dist" \
		"$NEW_EPOCH" "$OLD_EPOCH" "$OLDER_EPOCH" 6 20 "$(sg_next_nonce)"
	write_status "$SG_STATUS_LINE"
	rm -f "$SG_AGE_KEYFILE"

	sg_run_guard

	[ "$status" -ne 0 ]
	assert_contains "        $SG_HOME_REL"
	[ ! -s "$READD_LOG" ]
}

@test "sync-guard: the decision table holds when many targets share one run" {
	# Two runs at deliberately different scales — round 19's defeat was a
	# single ax_live=none initialised above the per-target loop, which every
	# single-target case in this file is structurally blind to: it only
	# shows up once a BLOCK target resolving near or far follows one
	# resolving head in the same run, carrying the stale value forward. Both
	# runs place that ordering; the second also puts real-repo scale (six
	# BLOCK targets among twenty-five-plus rows) behind both counts, since
	# two fixed counts alone would only exclude the thresholds between them.
	fresh_repo
	sg_reset_state
	sg_age_setup

	# --- run 1: small — five rows, two BLOCK targets --------------------
	STATUS_LINES=()
	BLOCK_TARGETS=()
	PROCEED_TARGETS=()

	# live=none, encrypted: covers the "at least one encrypted target" and
	# "none" requirements.
	sg_add_target "m1-none" 1 1 " " clean none behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 4 12 "$(sg_next_nonce)" PROCEED

	# live=head, BLOCK, space-bearing name — the "resolving head" anchor a
	# later near/far BLOCK target in this run must follow.
	sg_add_target "m1 head block" 0 0 " " edited head behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 5 14 "$(sg_next_nonce)" BLOCK

	# live=near, PROCEED (drifted back onto an old committed value).
	local m1n3
	m1n3="$(sg_next_near_dist)"
	sg_add_target "m1-near-proceed" 2 0 "M" clean near behind "$m1n3" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 6 16 "$(sg_next_nonce)" PROCEED

	# live=near, BLOCK — placed after the head BLOCK target above.
	local m1n4
	m1n4="$(sg_next_near_dist)"
	sg_add_target "m1-near-block" 1 0 " " clean near behind "$m1n4" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 7 18 "$(sg_next_nonce)" BLOCK

	# live=far, PROCEED — the fourth live value, completing the mix.
	local m1f5
	m1f5="$(sg_next_far_dist)"
	sg_add_target "m1-far-proceed" 3 0 "M" clean far behind "$m1f5" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 8 20 "$(sg_next_nonce)" PROCEED

	[ "${#STATUS_LINES[@]}" -eq 5 ]
	[ "${#BLOCK_TARGETS[@]}" -eq 2 ]

	write_status "${STATUS_LINES[@]}"
	sg_run_guard

	[ "$status" -ne 0 ]
	[ ! -s "$READD_LOG" ]
	sg_assert_multi_block_set

	# --- run 2: large — at least 25 rows, six BLOCK targets --------------
	STATUS_LINES=()
	BLOCK_TARGETS=()
	PROCEED_TARGETS=()

	# The head anchor this run's near/far BLOCK targets must all follow.
	sg_add_target "m2-head-anchor" 0 0 " " clean head behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 3 10 "$(sg_next_nonce)" PROCEED
	sg_add_target "m2-head-block" 1 0 " " edited head behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 4 11 "$(sg_next_nonce)" BLOCK

	local m2n1
	m2n1="$(sg_next_near_dist)"
	sg_add_target "m2-near-block-1" 2 0 " " clean near behind "$m2n1" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 5 13 "$(sg_next_nonce)" BLOCK

	sg_add_target "m2-none-proceed" 0 0 " " clean none behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 6 15 "$(sg_next_nonce)" PROCEED

	local m2n2
	m2n2="$(sg_next_near_dist)"
	sg_add_target "m2-near-proceed" 3 0 "M" clean near behind "$m2n2" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 7 17 "$(sg_next_nonce)" PROCEED

	local m2f1
	m2f1="$(sg_next_far_dist)"
	sg_add_target "m2-far-block-1" 1 0 " " clean far behind "$m2f1" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 8 19 "$(sg_next_nonce)" BLOCK

	local m2f2
	m2f2="$(sg_next_far_dist)"
	sg_add_target "m2-far-proceed" 2 0 "M" clean far behind "$m2f2" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 9 21 "$(sg_next_nonce)" PROCEED

	sg_add_target "m2-none-block" 0 0 "M" edited none behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 10 23 "$(sg_next_nonce)" BLOCK

	sg_add_target "m2-none-proceed-enc" 1 1 " " clean none behind 0 \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 11 25 "$(sg_next_nonce)" PROCEED

	local m2n3
	m2n3="$(sg_next_near_dist)"
	sg_add_target "m2 near block space" 2 0 " " edited near behind "$m2n3" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 12 27 "$(sg_next_nonce)" BLOCK

	local m2f3
	m2f3="$(sg_next_far_dist)"
	sg_add_target "m2-far-block-2" 3 0 "M" edited far behind "$m2f3" \
		"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" 13 29 "$(sg_next_nonce)" BLOCK

	# Sixteen more PROCEED fillers, cycling the four PROCEED row-shapes
	# (rows 7-10), to put the run's total past twenty-five while holding
	# the BLOCK count fixed at the six built above.
	local i shape dist filler_nonce filler_leaf
	i=0
	while [ "$i" -lt 16 ]; do
		filler_nonce="$(sg_next_nonce)"
		filler_leaf="m2-filler-${filler_nonce}"
		shape=$((i % 4))
		case "$shape" in
		0)
			sg_add_target "$filler_leaf" $((i % 5)) 0 " " clean none behind 0 \
				"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" $((3 + i)) $((10 + i * 3)) "$filler_nonce" PROCEED
			;;
		1)
			sg_add_target "$filler_leaf" $((i % 5)) 0 "M" clean none behind 0 \
				"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" $((3 + i)) $((10 + i * 3)) "$filler_nonce" PROCEED
			;;
		2)
			dist="$(sg_next_near_dist)"
			sg_add_target "$filler_leaf" $((i % 5)) 0 "M" clean near behind "$dist" \
				"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" $((3 + i)) $((10 + i * 3)) "$filler_nonce" PROCEED
			;;
		3)
			dist="$(sg_next_far_dist)"
			sg_add_target "$filler_leaf" $((i % 5)) 0 "M" clean far behind "$dist" \
				"$OLD_EPOCH" "$NEW_EPOCH" "$OLDER_EPOCH" $((3 + i)) $((10 + i * 3)) "$filler_nonce" PROCEED
			;;
		esac
		i=$((i + 1))
	done

	[ "${#STATUS_LINES[@]}" -ge 25 ]
	[ "${#BLOCK_TARGETS[@]}" -eq 6 ]

	write_status "${STATUS_LINES[@]}"
	sg_run_guard

	[ "$status" -ne 0 ]
	[ ! -s "$READD_LOG" ]
	sg_assert_multi_block_set
}

@test "sync-guard: the decision table holds in every cell" {
	# Constitution C-1: thirteen rows, each built twice — plaintext and
	# encrypted — for fifty-two builds total. Every non-axis detail is
	# stratified by a fixed, deterministic scheme (never $RANDOM, never the
	# wall clock) so no threshold anywhere in the guard's diff can sit
	# outside every build's spread. The scheme, spelled out because C-1
	# requires it written down rather than merely implemented:
	#
	#   - epochs: eight decade anchors (1980 through 2030), cycled by build
	#     index. ct's ordering (ahead/behind) is layered on top of whichever
	#     anchor a build lands on rather than replacing it, so the anchor
	#     still varies while the ordering stays exactly what the row names.
	#     Anchors stay >= 315532800: git's "@<epoch>" date parsing silently
	#     rejects anything under nine digits (confirmed by hand — @99999999
	#     fails, @100000000 doesn't), and a far build's filler commits walk
	#     up to 30 days *below* a row's anchor, so the floor needs headroom
	#     past nine digits, not merely nine digits itself.
	#   - source-working-file mtime (a decoy the guard must not read):
	#     offset from the live mtime by one of six magnitudes spanning a
	#     minute to a year, with the sign flipping between a row's two
	#     builds (arm 0 older, arm 1 newer) so every row takes both
	#     orderings.
	#   - content: 1-400 lines and roughly 20 bytes to 40KB of padding, both
	#     functions of the build index, so sizes span the stratum's full
	#     width and no two builds match.
	#   - depth: build index mod 5 (0-4 all appear); a row's two adjacent
	#     builds always land on different depths since consecutive indices
	#     can never share a mod-5 remainder.
	#   - near distance: alternates 1 and 2 (sg_next_near_dist).
	#   - far distance: cycles 3-30 without repeating in this case
	#     (sg_next_far_dist, 28 possible values against at most 12 far
	#     builds here).
	#   - filename: "f<nonce><padding>", padding length (build index * 3)
	#     mod 40, so names run from a couple of characters to several
	#     dozen. The very first build (row 1, plaintext, arm 0) — a BLOCK
	#     row — embeds a literal space in its name.
	fresh_repo
	sg_reset_state
	sg_age_setup

	local -a ROWS=(
		"1| |edited|head|behind|BLOCK|none"
		"2| |edited|head|ahead|BLOCK|none"
		"3| |clean|near|ahead|BLOCK|near"
		"4| |clean|near|behind|BLOCK|near"
		"5| |clean|far|ahead|BLOCK|far"
		"6| |clean|far|behind|BLOCK|far"
		"7| |clean|none|behind|PROCEED|none"
		"8|M|clean|none|behind|PROCEED|none"
		"9|M|clean|near|behind|PROCEED|near"
		"10|M|clean|far|behind|PROCEED|far"
		"11|M|clean|none|ahead|BLOCK|none"
		"12|M|edited|none|behind|BLOCK|none"
		"13| |edited|near|behind|BLOCK|near"
	)
	local -a DECADE_EPOCHS=(315532800 473385600 631152000 789033600 946684800 1262304000 1577836800 1893456000)
	local -a MTIME_OFFSETS=(60 3600 86400 604800 2592000 31536000)

	local k=0 row_entry row_num col1 src live ct required dist_kind
	local enc arm anchor commit_epoch live_mtime_epoch offset src_mtime_epoch
	local content_lines content_bytes depth nonce leaf pad_len pad j dist

	for row_entry in "${ROWS[@]}"; do
		IFS='|' read -r row_num col1 src live ct required dist_kind <<<"$row_entry"
		for enc in 0 1; do
			for arm in 0 1; do
				nonce="$(sg_next_nonce)"

				anchor="${DECADE_EPOCHS[$((k % 8))]}"
				if [ "$ct" = "ahead" ]; then
					commit_epoch=$((anchor + 500000))
					live_mtime_epoch="$anchor"
				else
					commit_epoch="$anchor"
					live_mtime_epoch=$((anchor + 500000))
				fi

				offset="${MTIME_OFFSETS[$((k % 6))]}"
				if [ "$arm" -eq 0 ]; then
					src_mtime_epoch=$((live_mtime_epoch - offset))
				else
					src_mtime_epoch=$((live_mtime_epoch + offset))
				fi

				content_lines=$((1 + (k * 7) % 400))
				content_bytes=$((20 + (k * 733) % 40000))
				depth=$((k % 5))

				pad_len=$(((k * 3) % 40))
				pad=""
				j=0
				while [ "$j" -lt "$pad_len" ]; do
					pad="${pad}x"
					j=$((j + 1))
				done
				leaf="f${nonce}${pad}"
				if [ "$k" -eq 0 ]; then
					leaf="f${nonce} sp${pad}"
				fi

				case "$dist_kind" in
				near) dist="$(sg_next_near_dist)" ;;
				far) dist="$(sg_next_far_dist)" ;;
				*) dist=0 ;;
				esac

				sg_build_row_and_check "$leaf" "$depth" "$enc" "$col1" "$src" "$live" "$ct" \
					"$dist" "$commit_epoch" "$live_mtime_epoch" "$src_mtime_epoch" \
					"$content_lines" "$content_bytes" "$nonce" "$required" || {
					echo "# FAILED: row $row_num, encrypted=$enc, arm=$arm, build index $k" >&2
					return 1
				}

				k=$((k + 1))
			done
		done
	done
}
