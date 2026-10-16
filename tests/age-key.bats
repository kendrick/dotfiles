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
	export OP_LOG OP_ACCOUNTS

	HOME="$HOME_FX" env -u XDG_CONFIG_HOME -u XDG_CACHE_HOME \
		chezmoi execute-template \
		--source "$(ui_src)" \
		--config "$(ui_fixture_config)" \
		--destination "$D/dest" \
		<"$(ui_src)/run_before_provision-age-key.sh.tmpl" >"$D/age-key.sh"
	adapt_script "$D/age-key.sh"
}

# Rewrites the two fixed values in the rendered copy instead of adding env overrides to
# production code. Fails setup unless the key path lands under the temp dir and exactly the
# wait and the brew probe changed, or the cases would wait ten minutes or reach the real op.
adapt_script() {
	grep -q "^KEY_PATH=\"$HOME_FX/.config/chezmoi/key.txt\"\$" "$1"
	sed -e 's|^WAIT_TIMEOUT=600$|WAIT_TIMEOUT=2|' \
		-e 's|/opt/homebrew/bin/brew|/nonexistent/brew|g' "$1" >"$1.adapted"
	[ "$(diff "$1" "$1.adapted" | grep -c '^>')" -eq 2 ]
	mv "$1.adapted" "$1"
	[ "$(grep -c '^WAIT_TIMEOUT=2$' "$1")" -eq 1 ]
	[ "$(grep -c '/opt/homebrew' "$1")" -eq 0 ]
}

run_attended() {
	local st=0
	PATH="$STUBS:/usr/bin:/bin" ui_pty --stdin-from-tty --timeout 20 \
		--stdout "$D/out" --stderr "$D/err" -- /bin/bash "$D/age-key.sh" || st=$?
	ATT_STATUS="$st"
	ATT_OUT="$(cat "$D/out" "$D/err")"
}

@test "attended, not ready after the wait: settles instead of hanging on op's prompt" {
	printf '[]' >"$OP_ACCOUNTS"
	run_attended
	# 199 is pty-run's own bound, the signature of the hang.
	[ "$ATT_STATUS" -ne 199 ]
	# The settled line trims its detail to 24 columns, so the issue's full phrase never prints whole.
	assert_contains "age key          1Password would not ans" "$ATT_OUT"
	if [ -f "$OP_LOG" ]; then
		assert_not_contains "read tty=yes" "$(cat "$OP_LOG")"
	fi
	[ ! -e "$KEY" ]
}

@test "attended, ready: still fetches the key" {
	printf '[{"url":"my.1password.com"}]' >"$OP_ACCOUNTS"
	run_attended
	[ "$ATT_STATUS" -eq 0 ]
	assert_contains "fetched from 1Password" "$ATT_OUT"
	assert_contains "AGE-SECRET-KEY-1FIXTURE" "$(cat "$KEY")"
}

@test "non-interactive, not ready: settles failed without a tty read" {
	printf '[]' >"$OP_ACCOUNTS"
	run env PATH="$STUBS:/usr/bin:/bin" /bin/bash "$D/age-key.sh" </dev/null
	[ "$status" -eq 0 ]
	assert_contains "age key          1Password would not ans"
	if [ -f "$OP_LOG" ]; then
		assert_not_contains "read tty=yes" "$(cat "$OP_LOG")"
	fi
}

@test "already provisioned: no op call at all" {
	mkdir -p "$(dirname "$KEY")"
	printf 'AGE-SECRET-KEY-1ALREADYHERE\n' >"$KEY"
	run env PATH="$STUBS:/usr/bin:/bin" /bin/bash "$D/age-key.sh" </dev/null
	[ "$status" -eq 0 ]
	assert_contains "already provisioned"
	[ ! -e "$OP_LOG" ]
}
