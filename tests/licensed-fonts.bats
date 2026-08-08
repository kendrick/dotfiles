#!/usr/bin/env bats
#
# The licensed-font fetch is the one script in this feature allowed to fail
# quietly. Everything else exits non-zero and names the file; this one must never
# take `chezmoi apply` down, because a machine with no licensed fonts is a normal
# machine rather than a broken one.
#
# That makes its soft-fail paths the whole test surface: each one has to exit 0,
# and each has to say something true about why. An honest message matters more
# here than anywhere else in the feature, since nothing else will ever complain.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/run_onchange_after_fetch-licensed-fonts.sh.tmpl"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	mkdir -p "$HOME/Library/Fonts" "$STUBS"

	# Rendered rather than read raw: the manifest reaches the script through a Go
	# template include, so the raw .tmpl has no font names in it to act on.
	chezmoi execute-template <"$SCRIPT" >"$BATS_TEST_TMPDIR/fetch.sh"
	export PATH="$STUBS:$PATH"
}

fetch() {
	bash "$BATS_TEST_TMPDIR/fetch.sh"
}

stub_op() {
	cat >"$STUBS/op" <<STUB
#!/usr/bin/env bash
case "\$1" in
account) exit ${1:-0} ;;
document) $2 ;;
esac
STUB
	chmod +x "$STUBS/op"
}

@test "exits 0 when op is absent" {
	# A PATH with no op on it at all, standing in for a machine that never
	# installed the 1Password CLI.
	PATH="$STUBS:/usr/bin:/bin" run fetch
	[ "$status" -eq 0 ]
	assert_contains "not installed"
}

@test "exits 0 when op is present but signed out" {
	stub_op 1 'exit 1'
	run fetch
	[ "$status" -eq 0 ]
	assert_contains "not signed in"
}

@test "exits 0 and says so when the vault will not authorize" {
	stub_op 0 'echo "[ERROR] authorization timeout" >&2; exit 1'
	run fetch
	[ "$status" -eq 0 ]
	# The distinction that matters: an unlock problem must not be reported as a
	# missing item, or you go looking in the vault for something that's there.
	assert_contains "would not authorize"
	assert_not_contains "not in vault"
}

@test "skips an item missing from the vault and keeps going" {
	stub_op 0 'echo "not found" >&2; exit 1'
	run fetch
	[ "$status" -eq 0 ]
	assert_contains "not in vault"
	# Every manifest entry is attempted; one absent font doesn't end the run.
	[ "$(echo "$output" | grep -c 'not in vault')" -eq 3 ]
}

@test "leaves no temp directory behind when a run fails partway" {
	before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'tmp.*' 2>/dev/null | wc -l)
	stub_op 0 'echo "not found" >&2; exit 1'
	run fetch
	[ "$status" -eq 0 ]
	after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'tmp.*' 2>/dev/null | wc -l)
	[ "$after" -le "$before" ]
}

@test "installs into a subdirectory so teardown has one path to remove" {
	# macOS scans subdirectories of ~/Library/Fonts, verified on this machine, so
	# the fonts still register while staying separable from the brew-managed
	# roster beside them. Licensed fonts belong to the person, not the machine.
	grep -qF 'FONT_DIR="$HOME/Library/Fonts/Licensed"' "$BATS_TEST_TMPDIR/fetch.sh"
}

@test "pins the account on every op call" {
	# Two accounts are signed in here. An unpinned call can resolve against the
	# work account, where none of these documents exist.
	calls=$(grep -cE '^\s*(op|.*\bop) (account|document)' "$BATS_TEST_TMPDIR/fetch.sh")
	pinned=$(grep -c 'OP_ACCOUNT' "$BATS_TEST_TMPDIR/fetch.sh")
	[ "$calls" -ge 2 ]
	[ "$pinned" -ge "$calls" ]
}
