#!/usr/bin/env bats
#
# dotfiles-sync runs six phases before it ever reaches the guard this suite exists to
# check (headings at :39, :57, :65, :75, :85, :103), and `chezmoi re-add` at :66 has no
# `command -v` guard in front of it — an unstubbed run aborts right there and the guard
# is never exercised at all. Stubbing chezmoi, the four optional-tool phases, osascript
# and date is what actually reaches :128; everything below exists to get there honestly
# rather than to make the assertions pass.
#
# PATH is replaced, not extended (`export PATH="$STUBS:/usr/bin:/bin"`, the form
# tests/apps.bats:73 uses). Appending the inherited PATH instead — tests/doctor.bats:62's
# form — lets code/brew/jq resolve to whatever this machine happens to have installed,
# which silences the skip branches the stub contract depends on and, if any of them
# writes into $SRC, turns a case meant to be clean into one that's dirty for reasons that
# have nothing to do with the guard.
#
# Every case builds its own scratch repo from scratch. `git reset --hard` plus
# `git clean -xdff` touch nothing under .git/, so a rebase marker or a refused case's
# dirty tree from one case would otherwise survive into the next and make states
# indistinguishable from each other.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/dot_local/bin/executable_dotfiles-sync"

DETACHED_MSG="Refusing to commit: HEAD is detached"
REBASE_MSG="Refusing to commit: rebase in progress"
MERGE_MSG="Refusing to commit: merge in progress"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	mkdir -p "$HOME" "$STUBS"
	unset DOTFILES_AUTO_PUSH

	# $HOME has no .gitconfig once redirected above, so without these `git commit`
	# fails with "Please tell me who you are" instead of exercising the guard.
	export GIT_AUTHOR_NAME="dotfiles-sync tests"
	export GIT_AUTHOR_EMAIL="dotfiles-sync-tests@example.invalid"
	export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
	export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

	export OSA_LOG="$BATS_TEST_TMPDIR/osascript.log"
	: >"$OSA_LOG"

	write_stubs
	export PATH="$STUBS:/usr/bin:/bin"
}

# chezmoi, date and osascript are the only tools the guarded path needs present. code,
# brew, jq, claude-plugins-capture and claude-settings-normalize are deliberately never
# written here, and the authoritative PATH above has nowhere else to find them, so each
# of their phases takes its documented "not found, skipping" branch.
write_stubs() {
	cat >"$STUBS/chezmoi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
source-path)
	# With an argument this is the template-drift loop (:87-95) probing a path; its
	# `|| continue` at :90 expects that to fail, not to resolve one of $REPO's own
	# files. It never actually fires here, since the status stub below feeds that
	# loop nothing to iterate over, but the contract names it so it's handled anyway.
	if [ -n "${2:-}" ]; then
		exit 1
	fi
	printf '%s\n' "$REPO"
	;;
re-add)
	# :66 has no `command -v` guard in front of it, so failing here takes the whole
	# run down before it ever reaches the code this suite exists to check.
	exit 0
	;;
status)
	exit 0
	;;
*)
	exit 1
	;;
esac
STUB

	# Records the full argument list, not just that osascript ran: the title in "$1" is
	# the only thing that tells notify_fail's calls (:33-36) apart from the bare
	# notify() ones (:28-31), and a stub that only touched a marker file would throw
	# that distinction away.
	cat >"$STUBS/osascript" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OSA_LOG"
STUB

	# :142 folds this into the commit message, which makes it part of the commit's
	# content — a real clock would give two otherwise-identical runs different shas
	# depending on the second they happened to run in.
	cat >"$STUBS/date" <<'STUB'
#!/usr/bin/env bash
echo "2026-01-01"
STUB

	chmod +x "$STUBS/chezmoi" "$STUBS/osascript" "$STUBS/date"
}

# One throwaway repo per case, with a bare origin so the push path's opt-in branch has a
# remote to reason about even though DOTFILES_AUTO_PUSH stays unset here. $REPO is
# exported for the chezmoi stub above to read from its own environment at run time,
# rather than baking a path into the stub when it's written.
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

@test "sync: attached branch with no operation in progress commits normally" {
	fresh_repo
	printf 'change\n' >"$REPO/change.txt"

	run bash "$SCRIPT"

	[ "$status" -eq 0 ]
	assert_not_contains "Refusing to commit"
	assert_contains "Committed locally"
	[ "$(git -C "$REPO" rev-list --count HEAD)" -eq 2 ]
}

@test "sync: detached HEAD refuses, names itself, and leaves the repo untouched" {
	fresh_repo
	git -C "$REPO" checkout -q --detach HEAD
	printf 'change\n' >"$REPO/change.txt"
	local before_count
	before_count="$(git -C "$REPO" rev-list --count HEAD)"

	run bash "$SCRIPT"

	[ "$status" -ne 0 ]
	assert_contains "$DETACHED_MSG"
	assert_not_contains "$REBASE_MSG"
	assert_not_contains "$MERGE_MSG"
	[ "$(git -C "$REPO" rev-list --count HEAD)" -eq "$before_count" ]
}

@test "sync: rebase in progress refuses, names itself, and leaves the repo untouched" {
	fresh_repo
	mkdir -p "$REPO/.git/rebase-merge"
	printf 'change\n' >"$REPO/change.txt"
	local before_count
	before_count="$(git -C "$REPO" rev-list --count HEAD)"

	run bash "$SCRIPT"

	[ "$status" -ne 0 ]
	assert_contains "$REBASE_MSG"
	assert_not_contains "$DETACHED_MSG"
	assert_not_contains "$MERGE_MSG"
	[ "$(git -C "$REPO" rev-list --count HEAD)" -eq "$before_count" ]
}

@test "sync: merge in progress refuses, names itself, and leaves the repo untouched" {
	fresh_repo
	# An empty MERGE_HEAD would pass `test -f` while `git rev-parse --verify -q
	# MERGE_HEAD` fails on it, so writing a real commit id is what makes this case
	# test the guard's own logic rather than however it happens to check existence.
	git -C "$REPO" rev-parse HEAD >"$REPO/.git/MERGE_HEAD"
	printf 'change\n' >"$REPO/change.txt"
	local before_count
	before_count="$(git -C "$REPO" rev-list --count HEAD)"

	run bash "$SCRIPT"

	[ "$status" -ne 0 ]
	assert_contains "$MERGE_MSG"
	assert_not_contains "$DETACHED_MSG"
	assert_not_contains "$REBASE_MSG"
	[ "$(git -C "$REPO" rev-list --count HEAD)" -eq "$before_count" ]
}

@test "sync: detached HEAD refuses on a clean tree, before the clean-tree exit ever runs" {
	fresh_repo
	git -C "$REPO" checkout -q --detach HEAD
	local porcelain
	porcelain="$(git -C "$REPO" status --porcelain)"
	[ -z "$porcelain" ]
	local before_count
	before_count="$(git -C "$REPO" rev-list --count HEAD)"

	run bash "$SCRIPT"

	[ "$status" -ne 0 ]
	assert_contains "$DETACHED_MSG"
	assert_not_contains "$REBASE_MSG"
	assert_not_contains "$MERGE_MSG"
	assert_not_contains "Nothing to commit. Already in sync."
	[ "$(git -C "$REPO" rev-list --count HEAD)" -eq "$before_count" ]
}
