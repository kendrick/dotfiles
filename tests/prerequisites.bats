#!/usr/bin/env bats
#
# The Homebrew step of run_once_before_install-prerequisites (#59). Its contract is the
# opposite of install-failures.bats, which pins "exit 0 whatever happens": a bootstrap that
# can't get Homebrew must fail loudly and exit non-zero, because chezmoi records a
# run_once_ script only after it succeeds, so a false success is never retried.
#
# Expected outcomes come from the issue (non-zero exit, a failed settled line, no eval of an
# empty shellenv), never from reading what the script does.

load 'helpers'

setup() {
	unset XDG_CONFIG_HOME XDG_CACHE_HOME
	D="$BATS_TEST_TMPDIR/pre"
	STUBS="$D/stubs"
	CHEZMOI="$(command -v chezmoi)"
	CURL_LOG="$D/curl.log"
	BREW_LOG="$D/brew.log"
	FAKE_PREFIX="$D/prefix"
	mkdir -p "$STUBS" "$D/clt/usr/bin"

	# have_clt passes on these, so no case depends on the developer's real CLT.
	printf '#!/bin/sh\nexit 0\n' >"$D/clt/usr/bin/clang"
	cp "$D/clt/usr/bin/clang" "$D/clt/usr/bin/git"
	chmod +x "$D/clt/usr/bin/clang" "$D/clt/usr/bin/git"
	printf '#!/bin/sh\necho "%s"\n' "$D/clt" >"$STUBS/xcode-select"

	# curl reads its behavior from files so a case can flip it between runs, including
	# between two chezmoi applies where the environment is fixed.
	cat >"$STUBS/curl" <<'CURL'
#!/bin/sh
echo "$*" >>"$CURL_LOG"
if [ "$(cat "$CURL_MODE")" = fail ]; then
	echo "curl: (6) Could not resolve host" >&2
	exit 6
fi
cat "$CURL_BODY"
CURL
	chmod +x "$STUBS"/*
	printf 'fail' >"$D/curl.mode"
	CURL_MODE="$D/curl.mode"
	CURL_BODY="$D/installer.sh"
	# Where install.sh "lands" brew in these cases, so none of them probes the real Homebrew.
	DOTFILES_BREW_BIN="$FAKE_PREFIX/bin/brew"
	export CURL_LOG CURL_MODE CURL_BODY BREW_LOG FAKE_PREFIX DOTFILES_BREW_BIN

	env -u XDG_CONFIG_HOME -u XDG_CACHE_HOME \
		chezmoi execute-template \
		--source "$(ui_src)" \
		--config "$(ui_fixture_config)" \
		--destination "$D/dest" \
		<"$(ui_src)/run_once_before_install-prerequisites.sh.tmpl" >"$D/prereqs.sh"
}

# What the fake Homebrew installer does: nothing but exit, or land a brew stub that logs argv
# and answers shellenv.
installer_exits() {
	printf 'exit %s\n' "$1" >"$CURL_BODY"
	printf 'serve' >"$CURL_MODE"
}

installer_lands_brew() {
	cat >"$CURL_BODY" <<'INSTALLER'
mkdir -p "$FAKE_PREFIX/bin"
cat >"$FAKE_PREFIX/bin/brew" <<'BREW'
#!/bin/sh
echo "$*" >>"$BREW_LOG"
[ "$1" = shellenv ] && echo 'export FIXTURE_SHELLENV=1'
exit 0
BREW
chmod +x "$FAKE_PREFIX/bin/brew"
INSTALLER
	printf 'serve' >"$CURL_MODE"
}

curl_calls() {
	wc -l <"$CURL_LOG" | tr -d ' '
}

run_prereqs() {
	run env DOTFILES_NO_PROGRESS=1 "$@" PATH="$STUBS:/usr/bin:/bin" \
		/bin/bash "$D/prereqs.sh" </dev/null
}

@test "prerequisites: a failed download exits non-zero and never evals shellenv" {
	run_prereqs
	[ "$status" -ne 0 ]
	assert_contains "did not install"
	assert_contains "re-run 'chezmoi apply'"
	assert_not_contains "Prerequisites ready"
	assert_not_contains "✓  homebrew"
	[ ! -e "$BREW_LOG" ]
}

@test "prerequisites: an installer that fails exits non-zero" {
	installer_exits 1
	run_prereqs
	[ "$status" -ne 0 ]
	assert_contains "did not install"
	assert_contains "re-run 'chezmoi apply'"
	assert_not_contains "Prerequisites ready"
	assert_not_contains "✓  homebrew"
	[ ! -e "$BREW_LOG" ]
}

@test "prerequisites: an installer that exits 0 without installing is still a failure" {
	installer_exits 0
	run_prereqs
	[ "$status" -ne 0 ]
	assert_contains "did not install"
	assert_contains "re-run 'chezmoi apply'"
	assert_not_contains "Prerequisites ready"
	assert_not_contains "✓  homebrew"
	[ ! -e "$BREW_LOG" ]
}

@test "prerequisites: a successful install still reports success" {
	installer_lands_brew
	run_prereqs
	[ "$status" -eq 0 ]
	assert_contains "✓  homebrew"
	# The CLT line also says "already installed", so isolate the Homebrew line first.
	local settled
	settled="$(grep -F '✓  homebrew' <<<"$output")"
	assert_contains "installed" "$settled"
	assert_not_contains "already" "$settled"
	assert_not_contains "did not install"
	assert_contains "Prerequisites ready"
	assert_contains "shellenv" "$(cat "$BREW_LOG")"
}

@test "prerequisites: an inherited HOMEBREW_PREFIX doesn't change where the install is probed" {
	installer_lands_brew
	run_prereqs HOMEBREW_PREFIX="$D/bogus"
	[ "$status" -eq 0 ]
	assert_contains "✓  homebrew"
	assert_not_contains "did not install"
	assert_contains "Prerequisites ready"
	assert_contains "shellenv" "$(cat "$BREW_LOG")"
}

@test "prerequisites: chezmoi retries the script after a failure and stops once it succeeds" {
	local v="$D/venue" state="$D/state.boltdb"
	mkdir -p "$v/src/.chezmoitemplates" "$v/dest" "$v/home"
	cp "$(ui_src)/.chezmoitemplates/sh-ui.sh" "$v/src/.chezmoitemplates/sh-ui.sh"
	cp "$(ui_src)/run_once_before_install-prerequisites.sh.tmpl" "$v/src/"
	cp "$(ui_fixture_config)" "$v/chezmoi.toml"

	chezmoi_apply() {
		(
			unset NVM_DIR XDG_CONFIG_HOME XDG_CACHE_HOME NO_COLOR
			export HOME="$v/home" DOTFILES_NO_PROGRESS=1 PATH="$STUBS:/usr/bin:/bin"
			"$CHEZMOI" apply --source "$v/src" --destination "$v/dest" \
				--config "$v/chezmoi.toml" --persistent-state "$state" </dev/null
		)
	}

	printf 'fail' >"$CURL_MODE"
	run chezmoi_apply
	[ "$status" -ne 0 ]
	run chezmoi_apply
	[ "$status" -ne 0 ]
	[ "$(curl_calls)" -eq 2 ]

	installer_lands_brew
	run chezmoi_apply
	[ "$status" -eq 0 ]
	[ "$(curl_calls)" -eq 3 ]

	# Recorded now: a fourth apply must not run it again.
	run chezmoi_apply
	[ "$status" -eq 0 ]
	[ "$(curl_calls)" -eq 3 ]
}
