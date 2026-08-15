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
