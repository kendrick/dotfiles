#!/usr/bin/env bats
#
# Every run_ script finds Homebrew whatever PATH chezmoi started it with (#92). On a factory
# Mac that PATH is /usr/bin:/bin, so a script that trusts it can't see the brew prerequisites
# just installed, settles as skipped, exits 0, and never reruns.
#
# Expected outcomes come from the issue (the stub is called, the not-found guard still fires
# with no Homebrew, a tool only in Homebrew's bin is found), never from reading the scripts.

load 'helpers'

setup() {
	D="$BATS_TEST_TMPDIR/bp"
	FAKE_PREFIX="$D/prefix"
	BREW_LOG="$D/brew.log"
	CODE_LOG="$D/code.log"
	mkdir -p "$D/home" "$D/dest" "$FAKE_PREFIX/bin"
}

render() {
	HOME="$D/home" env -u XDG_CONFIG_HOME -u XDG_CACHE_HOME \
		chezmoi execute-template \
		--source "$(ui_src)" \
		--config "$(ui_fixture_config)" \
		--destination "$D/dest" \
		<"$(ui_src)/$1" >"$D/script.sh"
}

# A brew whose shellenv puts the fake prefix on PATH, the way the real one does.
stub_brew() {
	cat >"$FAKE_PREFIX/bin/brew" <<BREW
#!/bin/sh
echo "\$*" >>"$BREW_LOG"
if [ "\$1" = shellenv ]; then
	echo 'export HOMEBREW_PREFIX="$FAKE_PREFIX"'
	echo 'export PATH="$FAKE_PREFIX/bin:\$PATH"'
fi
exit 0
BREW
	chmod +x "$FAKE_PREFIX/bin/brew"
}

# The PATH a factory Mac's shell hands chezmoi, and nothing else from this one.
run_factory() {
	run env -i HOME="$D/home" TERM=dumb PATH=/usr/bin:/bin DOTFILES_NO_PROGRESS=1 \
		DOTFILES_BREW_BIN="$FAKE_PREFIX/bin/brew" /bin/bash "$D/script.sh" </dev/null
}

@test "brew path: install-packages calls the prefix's brew from a factory PATH" {
	stub_brew
	render run_onchange_install-packages.sh.tmpl
	run_factory
	[ "$status" -eq 0 ]
	assert_not_contains "Homebrew not found"
	assert_contains "bundle" "$(cat "$BREW_LOG")"
}

@test "brew path: with no Homebrew at the prefix, install-packages still says so and exits 0" {
	render run_onchange_install-packages.sh.tmpl
	run_factory
	[ "$status" -eq 0 ]
	assert_contains "Homebrew not found"
	[ ! -e "$BREW_LOG" ]
}

@test "brew path: a code that lives only in Homebrew's bin is found by the VS Code installer" {
	stub_brew
	cat >"$FAKE_PREFIX/bin/code" <<CODE
#!/bin/sh
echo "\$*" >>"$CODE_LOG"
exit 0
CODE
	chmod +x "$FAKE_PREFIX/bin/code"
	render run_onchange_install-vscode-extensions.sh.tmpl
	run_factory
	[ "$status" -eq 0 ]
	assert_not_contains "VS Code CLI not found"
	assert_contains "--install-extension" "$(cat "$CODE_LOG")"
}
