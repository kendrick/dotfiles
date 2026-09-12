#!/usr/bin/env bats

# Tests for _gh_account_for_cwd in dot_config/zsh/functions.zsh.
#
# The hook rewrites GH_TOKEN in a live shell's environment, so the thing under
# test is a transition between directories, not a single call. Every case here
# starts a real zsh, sources the functions file the way .zshrc does, walks a
# path, and prints what GH_TOKEN ended up as. That start-then-walk shape is
# load-bearing: the first hook run happens at source time against whatever
# directory the shell opened in, and a shell opened straight into a personal
# checkout is its own case.
#
# gh is stubbed on $PATH, both to keep a real keyring out of the suite and to
# count calls, since skipping the subshell on repeat visits is a property worth
# holding onto.
#
# GH_TOKEN can be unset, set-and-empty, or set to someone else's token, and the
# hook has to tell all three apart when it puts things back. The helper prints
# the literal <unset> for the first so a test can see the difference that
# ${GH_TOKEN:-} would flatten.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
FUNCS="$SRC/dot_config/zsh/functions.zsh"

# Resolve zsh before setup() narrows PATH to the stub dir. || true because
# helpers load under errexit.
REAL_ZSH="$(command -v zsh || true)"

PERSONAL="gho_stub_personal_account"
FOREIGN="gho_stub_someone_elses_token"

setup() {
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	mkdir -p "$STUBS"

	export FAKE_HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$FAKE_HOME/repos/personal/proj" \
		"$FAKE_HOME/code/personal/proj" \
		"$FAKE_HOME/repos/work"

	export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
	: >"$GH_LOG"

	cat >"$STUBS/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$*" in
	"auth token --user kendrick")
		printf '%s\n' "$STUB_GH_TOKEN"
		;;
	*)
		echo "gh stub: unrecognised: $*" >&2
		exit 64
		;;
esac
STUB
	chmod +x "$STUBS/gh"

	export PATH="$STUBS:/usr/bin:/bin"
}

# Start a zsh in $1, source the functions file the way .zshrc would, run the
# zsh snippet in $2, then print the resulting GH_TOKEN. Any leading NAME=value
# arguments after that are placed in the shell's starting environment, which is
# how a test hands the shell a token to inherit.
run_hook() {
	local startdir="$1" script="$2"
	shift 2
	env -i HOME="$FAKE_HOME" PATH="$PATH" GH_LOG="$GH_LOG" \
		STUB_GH_TOKEN="$PERSONAL" "$@" \
		"$REAL_ZSH" -c "cd '$startdir'; source '$FUNCS'; $script
printf '%s' \"\${GH_TOKEN-<unset>}\""
}

gh_calls() {
	/usr/bin/grep -c . "$GH_LOG" || true
}

@test "gh-account: a shell that opens outside the roots has no token" {
	run run_hook "$FAKE_HOME/repos/work" ":"

	[ "$status" -eq 0 ]
	[ "$output" = "<unset>" ]
}

@test "gh-account: cd into a personal root installs the personal token" {
	run run_hook "$FAKE_HOME/repos/work" "cd '$FAKE_HOME/repos/personal/proj'"

	[ "$status" -eq 0 ]
	[ "$output" = "$PERSONAL" ]
}

@test "gh-account: the second personal root behaves like the first" {
	run run_hook "$FAKE_HOME/repos/work" "cd '$FAKE_HOME/code/personal/proj'"

	[ "$status" -eq 0 ]
	[ "$output" = "$PERSONAL" ]
}

@test "gh-account: leaving a personal root drops the token it installed" {
	run run_hook "$FAKE_HOME/repos/work" \
		"cd '$FAKE_HOME/repos/personal/proj'; cd '$FAKE_HOME/repos/work'"

	[ "$status" -eq 0 ]
	[ "$output" = "<unset>" ]
}

@test "gh-account: a shell opened inside a personal root overrides an inherited token" {
	run run_hook "$FAKE_HOME/repos/personal/proj" ":" "GH_TOKEN=$FOREIGN"

	[ "$status" -eq 0 ]
	[ "$output" = "$PERSONAL" ]
}

@test "gh-account: an inherited token survives outside the roots" {
	run run_hook "$FAKE_HOME/repos/work" ":" "GH_TOKEN=$FOREIGN"

	[ "$status" -eq 0 ]
	[ "$output" = "$FOREIGN" ]
}

@test "gh-account: an inherited token comes back after a round trip through a root" {
	run run_hook "$FAKE_HOME/repos/work" \
		"cd '$FAKE_HOME/repos/personal/proj'; cd '$FAKE_HOME/repos/work'" \
		"GH_TOKEN=$FOREIGN"

	[ "$status" -eq 0 ]
	[ "$output" = "$FOREIGN" ]
}

@test "gh-account: an inherited empty token is restored as empty, not as unset" {
	run run_hook "$FAKE_HOME/repos/personal/proj" "cd '$FAKE_HOME/repos/work'" \
		"GH_TOKEN="

	[ "$status" -eq 0 ]
	[ "$output" = "" ]
}

@test "gh-account: moving around inside a root asks gh for the token once" {
	run run_hook "$FAKE_HOME/repos/work" \
		"cd '$FAKE_HOME/repos/personal'; cd proj; cd '$FAKE_HOME/code/personal/proj'"

	[ "$status" -eq 0 ]
	[ "$output" = "$PERSONAL" ]
	[ "$(gh_calls)" -eq 1 ]
}

@test "gh-account: a root's sibling by prefix is not treated as a personal root" {
	mkdir -p "$FAKE_HOME/repos/personal-archive"

	run run_hook "$FAKE_HOME/repos/personal-archive" ":"

	[ "$status" -eq 0 ]
	[ "$output" = "<unset>" ]
	[ "$(gh_calls)" -eq 0 ]
}
