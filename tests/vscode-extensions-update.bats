#!/usr/bin/env bats
#
# VS Code's extensions.autoUpdate is off (#45), so vscode-extensions-update is the
# only thing keeping extensions current. Two callers share it, and the interesting
# behavior is all in the seam between them: the stamp decides who actually does the
# work, and it must not advance on a run that failed. A week silently skipped is the
# failure this file exists to catch, because nothing else would report it.
#
# Every case runs the real scripts as subprocesses with `code` stubbed on PATH, under
# a synthetic $HOME, so nothing here touches the machine's own extensions or state.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
HELPER="$SRC/dot_local/bin/executable_vscode-extensions-update"
RUN_AFTER="$SRC/run_after_update-vscode-extensions.sh"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export CALL_LOG="$BATS_TEST_TMPDIR/code-calls.log"
	mkdir -p "$HOME" "$STUBS"
	: >"$CALL_LOG"
	STAMP="$HOME/.local/state/dotfiles/last-extension-update"
}

# Records every invocation so a case can prove the update did not run, which is the
# whole point of the stamp and is invisible from exit status alone.
stub_code() {
	local rc="${1:-0}"
	cat >"$STUBS/code" <<STUB
#!/usr/bin/env bash
echo "\$*" >>"$CALL_LOG"
exit $rc
STUB
	chmod +x "$STUBS/code"
}

# Backdates the stamp far enough past the seven-day interval that find -mtime sees it.
age_stamp() {
	mkdir -p "$(dirname "$STAMP")"
	touch "$STAMP"
	touch -t "$(date -v-30d '+%Y%m%d%H%M')" "$STAMP"
}

# ---- the helper ----

@test "vscode-extensions-update: absent code CLI skips clean" {
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER"
	[ "$status" -eq 0 ]
	assert_contains "code CLI not found"
}

@test "vscode-extensions-update: no stamp at all runs the update" {
	stub_code 0
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER"
	[ "$status" -eq 0 ]
	assert_contains "extensions updated"
	assert_contains "--update-extensions" "$(cat "$CALL_LOG")"
	[ -f "$STAMP" ]
}

@test "vscode-extensions-update: a fresh stamp skips without calling code" {
	stub_code 0
	mkdir -p "$(dirname "$STAMP")"
	touch "$STAMP"
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER"
	[ "$status" -eq 0 ]
	assert_contains "next run due after 7 days"
	[ ! -s "$CALL_LOG" ]
}

@test "vscode-extensions-update: a stamp past the interval runs the update" {
	stub_code 0
	age_stamp
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER"
	[ "$status" -eq 0 ]
	assert_contains "extensions updated"
	assert_contains "--update-extensions" "$(cat "$CALL_LOG")"
}

@test "vscode-extensions-update: --force runs despite a fresh stamp" {
	stub_code 0
	mkdir -p "$(dirname "$STAMP")"
	touch "$STAMP"
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER" --force
	[ "$status" -eq 0 ]
	assert_contains "--update-extensions" "$(cat "$CALL_LOG")"
}

# The one that matters. Stamping a failed run costs a week of updates and reports
# nothing, so the next caller has to find the stamp exactly as stale as it was.
@test "vscode-extensions-update: a failed update leaves the stamp untouched" {
	stub_code 1
	age_stamp
	local before
	before="$(stat -f %m "$STAMP")"
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER"
	[ "$status" -ne 0 ]
	[ "$(stat -f %m "$STAMP")" = "$before" ]
}

@test "vscode-extensions-update: a failed update with no stamp writes none" {
	stub_code 1
	PATH="$STUBS:/usr/bin:/bin" run bash "$HELPER"
	[ "$status" -ne 0 ]
	[ ! -f "$STAMP" ]
}

# ---- the run_after caller ----

@test "run_after_update-vscode-extensions: absent helper exits clean" {
	PATH="$STUBS:/usr/bin:/bin" run bash "$RUN_AFTER"
	[ "$status" -eq 0 ]
}

@test "run_after_update-vscode-extensions: delegates to the helper" {
	cp "$HELPER" "$STUBS/vscode-extensions-update"
	chmod +x "$STUBS/vscode-extensions-update"
	stub_code 0
	PATH="$STUBS:/usr/bin:/bin" run bash "$RUN_AFTER"
	[ "$status" -eq 0 ]
	assert_contains "extensions updated"
	assert_contains "--update-extensions" "$(cat "$CALL_LOG")"
}

# An apply that dies because the marketplace was unreachable is a worse outcome than
# extensions that are a week stale, so the caller swallows the helper's exit code.
@test "run_after_update-vscode-extensions: a failing helper does not fail the apply" {
	cp "$HELPER" "$STUBS/vscode-extensions-update"
	chmod +x "$STUBS/vscode-extensions-update"
	stub_code 1
	PATH="$STUBS:/usr/bin:/bin" run bash "$RUN_AFTER"
	[ "$status" -eq 0 ]
	assert_contains "update failed"
}
