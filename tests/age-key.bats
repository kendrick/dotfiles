#!/usr/bin/env bats
#
# The op read call in run_before_provision-age-key (#74). With no 1Password account set up
# and stdin on a tty, `op` asks on /dev/tty whether to add one, and its follow-up prompt goes
# to the stderr the script discards, so the apply waited on a question nobody could see.
#
# Expected outcomes come from the issue (settles "1Password would not answer" in bounded
# time, never reads with a tty on stdin when not ready, still fetches when ready), never from
# reading what the script does.

load 'helpers'

setup() {
	unset XDG_CONFIG_HOME XDG_CACHE_HOME
	D="$BATS_TEST_TMPDIR/ak"
	STUBS="$D/stubs"
	HOME_FX="$D/home"
	KEY="$HOME_FX/.config/chezmoi/key.txt"
	OP_LOG="$D/op.log"
	OP_ACCOUNTS="$D/accounts.json"
	OP_DETACHED_OK="$D/detached-ok"
	mkdir -p "$STUBS" "$HOME_FX"
	printf '[]' >"$OP_ACCOUNTS"

	# Mirrors what `op` 2.40.0 was measured to do: `account list` never prompts, and `read`
	# with no account on a tty asks on /dev/tty, then blocks on stdin.
	cat >"$STUBS/op" <<'OP'
#!/bin/sh
case "$1" in
account) cat "$OP_ACCOUNTS" ;;
read)
	if [ -t 0 ]; then echo "read tty=yes" >>"$OP_LOG"; else echo "read tty=no" >>"$OP_LOG"; fi
	if grep -q '"url"' "$OP_ACCOUNTS"; then
		echo "AGE-SECRET-KEY-1FIXTURE"
		exit 0
	fi
	# A read that works without the desktop integration, but only when it can't prompt.
	if [ ! -t 0 ] && [ -e "$OP_DETACHED_OK" ]; then
		echo "AGE-SECRET-KEY-1FIXTURE"
		exit 0
	fi
	if [ -t 0 ]; then
		printf 'Do you want to add an account manually now? [Y/n] ' >/dev/tty
		read -r _
	fi
	exit 1
	;;
esac
exit 1
OP
	printf '#!/bin/sh\nexit 0\n' >"$STUBS/open"
	printf '#!/bin/sh\nexit 0\n' >"$STUBS/brew"
	chmod +x "$STUBS"/*

	# The Homebrew sh-ui.sh loads at include time. Its shellenv names the fake prefix too, so
	# nothing that defaults to ${HOMEBREW_PREFIX:-/opt/homebrew} falls through to the real one.
	FAKE_PREFIX="$D/prefix"
	BREW_LOG="$D/brew.log"
	mkdir -p "$FAKE_PREFIX/bin"
	cat >"$FAKE_PREFIX/bin/brew" <<'BREW'
#!/bin/sh
echo "$*" >>"$BREW_LOG"
[ "$1" = shellenv ] && echo "export HOMEBREW_PREFIX=\"$FAKE_PREFIX\""
exit 0
BREW
	chmod +x "$FAKE_PREFIX/bin/brew"
	DOTFILES_BREW_BIN="$FAKE_PREFIX/bin/brew"
	export OP_LOG OP_ACCOUNTS OP_DETACHED_OK FAKE_PREFIX BREW_LOG DOTFILES_BREW_BIN

	HOME="$HOME_FX" env -u XDG_CONFIG_HOME -u XDG_CACHE_HOME \
		chezmoi execute-template \
		--source "$(ui_src)" \
		--config "$(ui_fixture_config)" \
		--destination "$D/dest" \
		<"$(ui_src)/run_before_provision-age-key.sh.tmpl" >"$D/age-key.sh"
	retarget_wait "$D/age-key.sh"
}

# Every case ran the script, and the script loaded the fake Homebrew rather than the real
# one. A case that reached /opt/homebrew would never call this stub.
teardown() {
	grep -qx shellenv "$BREW_LOG"
}

# Rewrites the fixed wait in the rendered copy instead of adding an env override to
# production code. Fail here unless the key path lands under the temp dir and exactly that
# line changed, or the cases would wait ten minutes or reach the real op.
retarget_wait() {
	grep -q "^KEY_PATH=\"$HOME_FX/.config/chezmoi/key.txt\"\$" "$1"
	sed -e 's|^WAIT_TIMEOUT=600$|WAIT_TIMEOUT=2|' "$1" >"$1.adapted"
	[ "$(diff "$1" "$1.adapted" | grep -c '^>')" -eq 1 ]
	mv "$1.adapted" "$1"
	[ "$(grep -c '^WAIT_TIMEOUT=2$' "$1")" -eq 1 ]
}

run_attended() {
	ATT_STATUS="$(PATH="$STUBS:/usr/bin:/bin" ui_pty_status --stdin-from-tty --timeout 20 \
		--stdout "$D/out" --stderr "$D/err" -- /bin/bash "$D/age-key.sh")"
	ATT_OUT="$(cat "$D/out" "$D/err")"
}

@test "attended, not ready after the wait: settles instead of hanging on op's prompt" {
	printf '[]' >"$OP_ACCOUNTS"
	run_attended
	# 199 is pty-run's own bound, the signature of the hang.
	[ "$ATT_STATUS" -ne 199 ]
	# The settled line trims its detail to 24 columns, so the issue's full phrase never prints whole.
	assert_contains "age key          1Password would not ans" "$ATT_OUT"
	assert_contains "Unlock 1Password and turn on its CLI integration" "$ATT_OUT"
	assert_contains "op read \"op://Personal/chezmoi age key/key.txt\" > \"$KEY\"" "$ATT_OUT"
	[ -f "$OP_LOG" ]
	assert_contains "read tty=no" "$(cat "$OP_LOG")"
	assert_not_contains "read tty=yes" "$(cat "$OP_LOG")"
	[ ! -e "$KEY" ]
}

@test "attended, not ready: a read that works without a prompt still fetches" {
	printf '[]' >"$OP_ACCOUNTS"
	: >"$OP_DETACHED_OK"
	run_attended
	[ "$ATT_STATUS" -eq 0 ]
	assert_contains "fetched from 1Password" "$ATT_OUT"
	[ -f "$OP_LOG" ]
	assert_contains "read tty=no" "$(cat "$OP_LOG")"
	assert_not_contains "read tty=yes" "$(cat "$OP_LOG")"
	assert_contains "AGE-SECRET-KEY-1FIXTURE" "$(cat "$KEY")"
}

@test "attended, ready: still fetches the key, with the tty kept for Touch ID" {
	printf '[{"url":"my.1password.com"}]' >"$OP_ACCOUNTS"
	run_attended
	[ "$ATT_STATUS" -eq 0 ]
	assert_contains "fetched from 1Password" "$ATT_OUT"
	assert_contains "AGE-SECRET-KEY-1FIXTURE" "$(cat "$KEY")"
	assert_contains "read tty=yes" "$(cat "$OP_LOG")"
}

@test "non-interactive, not ready: settles failed without a tty read" {
	printf '[]' >"$OP_ACCOUNTS"
	run env PATH="$STUBS:/usr/bin:/bin" /bin/bash "$D/age-key.sh" </dev/null
	[ "$status" -eq 0 ]
	assert_contains "age key          1Password would not ans" "$output"
	assert_contains "Unlock 1Password and turn on its CLI integration" "$output"
	assert_contains "op read \"op://Personal/chezmoi age key/key.txt\" > \"$KEY\"" "$output"
	[ -f "$OP_LOG" ]
	assert_contains "read tty=no" "$(cat "$OP_LOG")"
	assert_not_contains "read tty=yes" "$(cat "$OP_LOG")"
	[ ! -e "$KEY" ]
}

@test "already provisioned: no op call at all" {
	mkdir -p "$(dirname "$KEY")"
	printf 'AGE-SECRET-KEY-1ALREADYHERE\n' >"$KEY"
	run env PATH="$STUBS:/usr/bin:/bin" /bin/bash "$D/age-key.sh" </dev/null
	[ "$status" -eq 0 ]
	assert_contains "already provisioned"
	[ ! -e "$OP_LOG" ]
}

# The guarantee the cases above lean on, checked on what the script executes rather than on
# its text: the shared kit still names /opt/homebrew as its default, so a grep can't tell.
@test "the cases load only the fake Homebrew and execute nothing under /opt/homebrew" {
	printf '[]' >"$OP_ACCOUNTS"
	env PATH="$STUBS:/usr/bin:/bin" /bin/bash -x "$D/age-key.sh" </dev/null >"$D/out" 2>"$D/trace" || true
	assert_contains "brew_bin=$FAKE_PREFIX/bin/brew" "$(cat "$D/trace")"
	assert_contains "$FAKE_PREFIX/bin/brew shellenv" "$(cat "$D/trace")"
	assert_not_contains "/opt/homebrew" "$(cat "$D/trace")"
}
