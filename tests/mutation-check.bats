#!/usr/bin/env bats
#
# An abandoned mutation-check run must leave the test files exactly as it
# found them and must actually stop (#48).
#
# Runs against a scratch copy of the WORKING TREE, never the tests/ this
# suite is executing from: the script rewrites the files it scans, and it is
# the uncommitted script that must be exercised (a git worktree would check
# out HEAD). The signal is anchored on an event, never a clock
# (tests/progress.bats:325-330): it fires the moment the target on disk
# differs from its pristine copy, which is exactly the state under test.
#
# The job is started under `set -m` so it gets its own process group — the
# signal goes to the group, as a terminal's Ctrl-C does, and reaches the
# bats child too — and because bash starts `&` jobs with SIGINT ignored when
# job control is off, which would make the script unable to trap it.

load 'helpers'

TARGET="tests/jsonc.bats"

setup() {
	SCRATCH="$BATS_TEST_TMPDIR/scratch"
	PRISTINE="$BATS_TEST_TMPDIR/pristine"
	LOG="$BATS_TEST_TMPDIR/log"
	local src="$BATS_TEST_DIRNAME/.."
	local vscode="private_Library/private_Application Support/Code/User"
	mkdir -p "$SCRATCH/dot_config" "$SCRATCH/$vscode"
	cp -R "$BATS_TEST_DIRNAME" "$SCRATCH/tests"
	# The pristine side is copied from the scratch, not read a second time
	# out of the live tests/: another worker saving a file in there between
	# the two reads would leave the two copies differing for a reason that
	# has nothing to do with the script under test, and the `diff -r` below
	# would flake red. Copying from the scratch makes them identical by
	# construction, which is the only property this comparison needs.
	cp -R "$SCRATCH/tests" "$PRISTINE"
	cp -R "$src/dot_config/font" "$SCRATCH/dot_config/font"
	cp "$src/$vscode/settings.json" "$SCRATCH/$vscode/settings.json"
	# The script cd's to `git rev-parse --show-toplevel` from its caller's
	# cwd. A repo of its own pins that to the scratch.
	git init -q "$SCRATCH"
}

# fd 3 is closed so the job cannot hold bats' own output pipe open.
mc_start() {
	set -m
	( cd "$SCRATCH" && exec bash tests/mutation-check.sh "$TARGET" ) \
		>"$LOG" 2>&1 3>&- </dev/null &
	MC_PID=$!
	set +m
}

# Returns once the scratch copy of TARGET differs from the pristine one.
# The cap only turns a script that never mutates into a loud failure.
mc_wait_mutated() {
	local i=0
	while cmp -s "$PRISTINE/${TARGET#tests/}" "$SCRATCH/$TARGET"; do
		i=$((i + 1))
		if [ "$i" -ge 600 ]; then
			echo "no mutation of $TARGET observed after 30s:"
			cat "$LOG"
			kill -TERM -- "-$MC_PID" 2>/dev/null
			return 1
		fi
		sleep 0.05
	done
}

mc_interrupted_by() {
	local sig="$1" expected="$2" st=0
	mc_start
	mc_wait_mutated
	kill "-$sig" -- "-$MC_PID"
	# Unbounded on purpose: the script has no path that waits forever (bats
	# bounds itself), and the pre-fix script completes rather than hangs.
	wait "$MC_PID" || st=$?

	assert_contains "mutation-check: scanning $TARGET" "$(cat "$LOG")"
	[ "$st" -eq "$expected" ]
	# "no second site" rather than "no site at all": the ~1ms race where
	# site 1 restores between the cmp and the kill has to land as a pass,
	# not a flake. What #48 is about is the run marching on to site 2.
	assert_not_contains "site [2/" "$(cat "$LOG")"
	diff -r "$PRISTINE" "$SCRATCH/tests"
}

@test "Ctrl-C mid-mutation restores the file and stops the run" {
	mc_interrupted_by INT 130
}

@test "SIGTERM mid-mutation restores the file and stops the run" {
	mc_interrupted_by TERM 143
}

@test "SIGHUP mid-mutation restores the file and stops the run" {
	mc_interrupted_by HUP 129
}
