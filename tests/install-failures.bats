#!/usr/bin/env bats
#
# Before this conversion, "the tool isn't here" and "the tool ran and a specific
# item didn't install" printed the same nothing-in-particular and both exited 0.
# That made a failed `chezmoi apply` indistinguishable from a clean one short of
# reading brew/code/claude's own scrollback, which is what #17 is about.
#
# Every case here drives one of the four converted scripts as a real subprocess,
# with its CLI stubbed on PATH rather than actually installing anything. The
# constant across all fifteen is `[ "$status" -eq 0 ]`: a script that names its
# failures and then aborts the apply is not fixed, it's relocated.
#
# Two environments are deliberately kept apart. Templates are rendered under the
# real $HOME, because install-claude-plugins gates on ~/.config/chezmoi/key.txt
# and renders no install calls at all without it. The rendered script is then run
# under a synthetic $HOME with stubs on PATH, so nothing here touches real
# machine state.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
REAL_HOME="$HOME"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	mkdir -p "$HOME" "$STUBS"
}

# A case that chmods a dir to 555 and fails before restoring it would leave
# bats unable to delete its tmpdir.
teardown() {
	chmod -R u+w "$BATS_TEST_TMPDIR" 2>/dev/null || :
}

# Rendered with the real $HOME regardless of what setup() just pointed $HOME at,
# so the claude-plugins template's decrypt gate sees the key that's actually
# there. That gate is why this file needs the real $HOME rather than just the
# real source dir.
#
# --source is separate and equally required. Without it the script body comes
# from the tree under test while `{{ template "sh-ui.sh" . }}` resolves against
# whatever source dir the config names, so a run from a copied tree renders a
# script that calls step_begin and defines it nowhere. That produced twelve
# failures at exit 127, none of them on a string assertion, which is a
# confusing way to learn the render was wrong.
render_script() {
	local tmpl="$1" out="$BATS_TEST_TMPDIR/${1%.tmpl}"
	HOME="$REAL_HOME" chezmoi execute-template --source "$SRC" <"$SRC/$tmpl" >"$out"
	echo "$out"
}

first_extension() {
	grep -vE '^\s*#|^\s*$' "$SRC/dot_config/vscode-extensions.txt" | head -1
}

first_raycast_extension() {
	grep -vE '^\s*#|^\s*$' "$SRC/dot_config/raycast-extensions.txt" | head -1
}

# Rendered the same way render_script renders a full script — real $HOME, since the
# Brewfile partial pulls from .chezmoidata.toml rather than anything install-packages
# itself gates on. Used to read real entry names for the drop-and-retry cases below: a
# fixture name the render never contained would make "not the dropped name" vacuously
# true, per the constitution's C-1.
render_brewfile() {
	HOME="$REAL_HOME" chezmoi execute-template --source "$SRC" <<<'{{ template "Brewfile" . }}'
}

# Raycast's hotkey write ignores $HOME and lands in the real
# ~/Library/Preferences, so every case that reaches it needs this on PATH first
# — recording, not just swallowing, since the proof D-4 wants is that the real
# `defaults` was never reached, not that the stored value happens to match.
stub_defaults() {
	export DEFAULTS_LOG="$BATS_TEST_TMPDIR/defaults-calls.log"
	: >"$DEFAULTS_LOG"
	cat >"$STUBS/defaults" <<'STUB'
#!/usr/bin/env bash
echo "$@" >>"$DEFAULTS_LOG"
exit 0
STUB
	chmod +x "$STUBS/defaults"
}

# Raycast's loop sleeps a real second per URL; nothing under test depends on the
# wait, so a no-op stub keeps ~30-item cases from costing real wall-clock time.
stub_sleep() {
	printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/sleep"
	chmod +x "$STUBS/sleep"
}

# ---- install-packages ----
# `brew bundle` already continues past a failing entry internally, so this
# suite has no keeps-going case of its own — B-3 exempts it. #22 adds one
# exception below: a fetch-phase failure where some but not all of the
# batched names are unresolvable gets exactly one retry with the dead lines
# dropped.

@test "install-packages: absent tool skips clean" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "Homebrew not found"
}

@test "install-packages: present tool failing names the item" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	cat >"$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
trust) exit 0 ;;
bundle)
  echo "Installing fixture-widget has failed!"
  exit 1
  ;;
esac
STUB
	chmod +x "$STUBS/brew"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "fixture-widget"
	assert_contains "could not install these Brewfile entries"
}

# brew fails in two phases and the case above only covers one. An entry that doesn't
# exist dies in the batched pre-fetch at Homebrew's installer.rb:84-87, which returns
# before the install phase runs, so no "Installing X has failed!" line is ever written
# and the install-phase parser has nothing to match. The one line that phase does emit
# names every entry that needed fetching, guilty or not — which is why the two innocent
# fixtures below have to stay out of the summary. Found by the live apply for #17, not
# by this suite, because every stub here spoke only the install-phase dialect.
@test "install-packages: a fetch-phase failure names only the entry that doesn't exist" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	cat >"$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
trust) exit 0 ;;
info)
	case "$2" in
	fixture-nonexistent-xyz) exit 1 ;;
	*) exit 0 ;;
	esac
	;;
bundle)
	echo "Fetching fixture-nonexistent-xyz, fixture-real-one, fixture-real-two"
	echo '`brew bundle` failed! Failed to fetch fixture-nonexistent-xyz, fixture-real-one, fixture-real-two' >&2
	echo 'Error: No available formula with the name "fixture-nonexistent-xyz".' >&2
	exit 1
	;;
esac
STUB
	chmod +x "$STUBS/brew"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	# Two-space prefix matches the summary's `sed 's/^/  /'` indent, so these assertions
	# read the script's own report rather than brew's echoed batch line.
	assert_contains "  fixture-nonexistent-xyz"
	assert_not_contains "  fixture-real-one"
	assert_not_contains "  fixture-real-two"
	assert_not_contains "without naming a failed entry"
}

# The other fetch-phase outcome. Every entry resolves, so the registry is right and the
# download is what broke — a locked network, a mirror hiccup. Nothing in the batch has
# earned the blame, so the report names all of it rather than picking the first line.
@test "install-packages: a fetch failure where every entry exists names the whole batch" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	cat >"$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
trust) exit 0 ;;
info) exit 0 ;;
bundle)
	echo '`brew bundle` failed! Failed to fetch fixture-real-one, fixture-real-two' >&2
	echo 'Error: Failed to download resource "fixture-real-one"' >&2
	exit 1
	;;
esac
STUB
	chmod +x "$STUBS/brew"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "though all of them exist"
	assert_contains "  fixture-real-one"
	assert_contains "  fixture-real-two"
	assert_not_contains "entries don't exist"
}

@test "install-packages: all items succeed prints no failure summary" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	cat >"$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
trust) exit 0 ;;
bundle)
  echo "Homebrew Bundle complete! 0 Brewfile dependencies now installed."
  exit 0
  ;;
esac
STUB
	chmod +x "$STUBS/brew"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_not_contains "could not install"
	assert_not_contains "without naming a failed entry"
}

# The stub logs one line per `brew bundle` call to $BUNDLE_LOG (a real recorded log of
# every invocation, not the summary text alone — C-1 rules out proving the retry from
# text `run_onchange_install-packages.sh.tmpl:94-95` already printed before any retry
# branch existed) and saves each call's received Brewfile under $BUNDLE_DIR/<n>, since
# the mixed-batch case has to show the second call's Brewfile, not just that a second
# call happened.
@test "install-packages: drop-and-retry, mixed batch installs the survivors" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	brewfile="$(render_brewfile)"
	local -a names
	names=($(printf '%s\n' "$brewfile" | grep '^brew "' | head -3 | sed -E 's/^brew "([^"]+)"$/\1/'))
	export SURVIVOR1="${names[0]}" DROP_NAME="${names[1]}" SURVIVOR2="${names[2]}"
	export BUNDLE_LOG="$BATS_TEST_TMPDIR/bundle-calls.log"
	export BUNDLE_DIR="$BATS_TEST_TMPDIR/bundle-brewfiles"
	: >"$BUNDLE_LOG"
	mkdir -p "$BUNDLE_DIR"

	cat >"$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
trust) exit 0 ;;
info)
	case "$2" in
	"$DROP_NAME") exit 1 ;;
	*) exit 0 ;;
	esac
	;;
bundle)
	n=$(( $(wc -l <"$BUNDLE_LOG") + 1 ))
	echo "bundle $n" >>"$BUNDLE_LOG"
	cat >"$BUNDLE_DIR/$n"
	if [ "$n" -eq 1 ]; then
		echo "Fetching $SURVIVOR1, $DROP_NAME, $SURVIVOR2"
		echo "\`brew bundle\` failed! Failed to fetch $SURVIVOR1, $DROP_NAME, $SURVIVOR2" >&2
		echo "Error: No available formula with the name \"$DROP_NAME\"." >&2
		exit 1
	fi
	exit 0
	;;
esac
STUB
	chmod +x "$STUBS/brew"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$BUNDLE_LOG")" -eq 2 ]
	second="$(cat "$BUNDLE_DIR/2")"
	assert_contains "\"$SURVIVOR1\"" "$second"
	assert_contains "\"$SURVIVOR2\"" "$second"
	assert_not_contains "\"$DROP_NAME\"" "$second"
}

# The all-dead counterpart to the mixed-batch case above. Gating the retry on "the
# trimmed Brewfile is non-empty" would still fire here — the fetch batch is two names out
# of dozens elsewhere in the real Brewfile — so this asserts the log holds exactly one
# `bundle` call, the way C-1's rubric requires it be gated instead: every batched name
# unresolvable, not merely some Brewfile lines surviving.
@test "install-packages: drop-and-retry, all unresolvable reports without retrying" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	brewfile="$(render_brewfile)"
	local -a names
	names=($(printf '%s\n' "$brewfile" | grep '^brew "' | head -2 | sed -E 's/^brew "([^"]+)"$/\1/'))
	export NAME1="${names[0]}" NAME2="${names[1]}"
	export BUNDLE_LOG="$BATS_TEST_TMPDIR/bundle-calls.log"
	: >"$BUNDLE_LOG"

	cat >"$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
trust) exit 0 ;;
info) exit 1 ;;
bundle)
	echo "bundle" >>"$BUNDLE_LOG"
	cat >/dev/null
	echo "Fetching $NAME1, $NAME2"
	echo "\`brew bundle\` failed! Failed to fetch $NAME1, $NAME2" >&2
	echo "Error: No available formula with the name \"$NAME1\"." >&2
	exit 1
	;;
esac
STUB
	chmod +x "$STUBS/brew"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$BUNDLE_LOG")" -eq 1 ]
	assert_contains "  $NAME1"
	assert_contains "  $NAME2"
}

@test "install-packages: no extra brew calls on a clean run" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	export BUNDLE_LOG="$BATS_TEST_TMPDIR/bundle-calls.log"
	export INFO_LOG="$BATS_TEST_TMPDIR/info-calls.log"
	: >"$BUNDLE_LOG"
	: >"$INFO_LOG"

	cat >"$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
trust) exit 0 ;;
info) echo "info $2" >>"$INFO_LOG"; exit 0 ;;
bundle)
	echo "bundle" >>"$BUNDLE_LOG"
	cat >/dev/null
	echo "Homebrew Bundle complete! 0 Brewfile dependencies now installed."
	exit 0
	;;
esac
STUB
	chmod +x "$STUBS/brew"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$INFO_LOG")" -eq 0 ]
	[ "$(wc -l <"$BUNDLE_LOG")" -eq 1 ]
}

# A second failure after the retry, in the other phase this time — install rather than
# fetch. Drops one of two names, so the retry fires; the survivor then fails to install
# for an unrelated reason. Only the count matters here: two `bundle` calls and no third,
# regardless of which phase the second failure lands in.
@test "install-packages: reports and stops after a second failure" {
	script="$(render_script run_onchange_install-packages.sh.tmpl)"
	brewfile="$(render_brewfile)"
	local -a names
	names=($(printf '%s\n' "$brewfile" | grep '^brew "' | head -2 | sed -E 's/^brew "([^"]+)"$/\1/'))
	export DROP_NAME="${names[0]}" SURVIVOR_NAME="${names[1]}"
	export BUNDLE_LOG="$BATS_TEST_TMPDIR/bundle-calls.log"
	: >"$BUNDLE_LOG"

	cat >"$STUBS/brew" <<'STUB'
#!/usr/bin/env bash
case "$1" in
trust) exit 0 ;;
info)
	case "$2" in
	"$DROP_NAME") exit 1 ;;
	*) exit 0 ;;
	esac
	;;
bundle)
	n=$(( $(wc -l <"$BUNDLE_LOG") + 1 ))
	echo "bundle $n" >>"$BUNDLE_LOG"
	cat >/dev/null
	if [ "$n" -eq 1 ]; then
		echo "Fetching $SURVIVOR_NAME, $DROP_NAME"
		echo "\`brew bundle\` failed! Failed to fetch $SURVIVOR_NAME, $DROP_NAME" >&2
		echo "Error: No available formula with the name \"$DROP_NAME\"." >&2
		exit 1
	fi
	echo "Installing $SURVIVOR_NAME has failed!"
	exit 1
	;;
esac
STUB
	chmod +x "$STUBS/brew"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$BUNDLE_LOG")" -eq 2 ]
	assert_contains "  $SURVIVOR_NAME"
}

# ---- install-vscode-extensions ----
# Every count here is read from the list files, so a list edit can't leave a
# case asserting a stale number. A profile is the default list plus its own.

vscode_ids() {
	grep -vE '^\s*#|^\s*$' "$1"
}

# Space-joined, the form the pending marker and the "Couldn't register" line use.
vscode_profiles_joined() {
	vscode_profiles | tr '\n' ' ' | sed 's/ $//'
}

vscode_profiles() {
	local f b
	for f in "$SRC"/dot_config/vscode-profiles/*.txt; do
		b="${f##*/}"
		case "$b" in *-removed.txt) continue ;; esac
		echo "${b%.txt}"
	done
}

vscode_storage() {
	echo "$HOME/Library/Application Support/Code/User/globalStorage/storage.json"
}

vscode_write_storage() {
	mkdir -p "$(dirname "$(vscode_storage)")"
	printf '%s\n' "$1" >"$(vscode_storage)"
}

vscode_marker() {
	echo "$HOME/.local/state/dotfiles/vscode-profiles-pending"
}

# The installer asks pgrep whether VS Code is open, and on the machine running
# this suite it may well be. Every case stubs it, closed unless PGREP_RC=0.
stub_pgrep() {
	cat >"$STUBS/pgrep" <<'STUB'
#!/usr/bin/env bash
exit "${PGREP_RC:-1}"
STUB
	chmod +x "$STUBS/pgrep"
}

# Logs every call whole, so a case can tell a default install from a profile
# one. FAIL_ID refuses one id, and only inside FAIL_PROFILE when that's set.
stub_code_logging() {
	export CALL_LOG="$BATS_TEST_TMPDIR/vscode-calls.log"
	: >"$CALL_LOG"
	cat >"$STUBS/code" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$CALL_LOG"
if [ -n "${FAIL_ID:-}" ] && [ "$2" = "$FAIL_ID" ] && [ "${5:-}" = "${FAIL_PROFILE:-}" ]; then
  exit 1
fi
exit 0
STUB
	chmod +x "$STUBS/code"
	stub_pgrep
}

@test "install-vscode-extensions: absent tool skips clean" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "VS Code CLI not found"
}

@test "install-vscode-extensions: present tool failing names the item" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	ext="$(first_extension)"
	stub_pgrep
	cat >"$STUBS/code" <<STUB
#!/usr/bin/env bash
if [ "\$2" = "$ext" ]; then
  exit 1
fi
exit 0
STUB
	chmod +x "$STUBS/code"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "$ext"
	assert_contains "could not install these extensions"
}

@test "install-vscode-extensions: one failure does not stop the rest" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	default="$(grep -vcE '^\s*#|^\s*$' "$SRC/dot_config/vscode-extensions.txt")"
	expected="$default"
	for p in $(vscode_profiles); do
		own="$(grep -vcE '^\s*#|^\s*$' "$SRC/dot_config/vscode-profiles/$p.txt")"
		expected=$((expected + default + own))
	done
	export CALL_LOG="$BATS_TEST_TMPDIR/vscode-calls.log"
	: >"$CALL_LOG"
	stub_pgrep
	cat >"$STUBS/code" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "--install-extension" ]; then
  echo "$2" >>"$CALL_LOG"
fi
exit 1
STUB
	chmod +x "$STUBS/code"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ "$(grep -c '' "$CALL_LOG")" -eq "$expected" ]
}

@test "install-vscode-extensions: all items succeed prints no failure summary" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	stub_pgrep
	printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/code"
	chmod +x "$STUBS/code"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "  ✓  vscode ext"
	assert_not_contains "could not install"
}

@test "install-vscode-extensions: a registered profile gets the default list and its own, each with --profile" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	p="$(vscode_profiles | head -1)"
	vscode_write_storage "{\"userDataProfiles\":[{\"location\":\"x1\",\"name\":\"$p\"}]}"
	stub_code_logging
	# Running, so every other profile is pending and only $p installs.
	PGREP_RC=0 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	for id in $(vscode_ids "$SRC/dot_config/vscode-extensions.txt") $(vscode_ids "$SRC/dot_config/vscode-profiles/$p.txt"); do
		grep -qxF -- "--install-extension $id --force --profile $p" "$CALL_LOG"
	done
	n_default="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | grep -c '')"
	n_own="$(vscode_ids "$SRC/dot_config/vscode-profiles/$p.txt" | grep -c '')"
	[ "$(grep -c -- "--profile $p\$" "$CALL_LOG")" -eq $((n_default + n_own)) ]
	[ "$(grep -vc -- '--profile' "$CALL_LOG")" -eq "$n_default" ]
}

@test "install-vscode-extensions: with VS Code closed, an unregistered profile is registered and installed" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	vscode_write_storage '{"userDataProfiles":[]}'
	stub_code_logging
	PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	n_default="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | grep -c '')"
	for p in $(vscode_profiles); do
		[ "$(jq -r --arg n "$p" '.userDataProfiles[] | select(.name == $n) | .location' "$(vscode_storage)")" = "chezmoi-$p" ]
		[ "$(jq -r --arg n "$p" '.userDataProfiles[] | select(.name == $n) | .useDefaultFlags.settings' "$(vscode_storage)")" = "true" ]
		[ -d "$HOME/Library/Application Support/Code/User/profiles/chezmoi-$p" ]
		n_own="$(vscode_ids "$SRC/dot_config/vscode-profiles/$p.txt" | grep -c '')"
		[ "$(grep -c -- "--profile $p\$" "$CALL_LOG")" -eq $((n_default + n_own)) ]
	done
	# The atomic write goes through a temp file beside storage.json.
	[ "$(ls -A "$(dirname "$(vscode_storage)")")" = "storage.json" ]
}

@test "install-vscode-extensions: registration keeps every other entry and key in storage.json" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	p="$(vscode_profiles | head -1)"
	vscode_write_storage "{\"theme\":\"vs-dark\",\"windowsState\":{\"lastActiveWindow\":{\"folder\":\"file:///x\"}},\"userDataProfiles\":[{\"location\":\"1a2b3c\",\"name\":\"hand-made\"},{\"location\":\"elsewhere\",\"name\":\"$p\"}]}"
	chmod 644 "$(vscode_storage)"
	before="$BATS_TEST_TMPDIR/storage-before.json"
	cp "$(vscode_storage)" "$before"
	stub_code_logging
	PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	# mktemp's 0600 must not replace the file's own mode.
	[ "$(stat -f %Lp "$(vscode_storage)")" = "644" ]
	[ "$(jq -S 'del(.userDataProfiles)' "$before")" = "$(jq -S 'del(.userDataProfiles)' "$(vscode_storage)")" ]
	[ "$(jq -S '.userDataProfiles[0:2]' "$before")" = "$(jq -S '.userDataProfiles[0:2]' "$(vscode_storage)")" ]
	# Already registered under its name, so it isn't added a second time.
	[ "$(jq --arg n "$p" '[.userDataProfiles[] | select(.name == $n)] | length' "$(vscode_storage)")" -eq 1 ]
	total="$(vscode_profiles | grep -c '')"
	[ "$(jq '.userDataProfiles | length' "$(vscode_storage)")" -eq $((total + 1)) ]
}

@test "install-vscode-extensions: with VS Code running, an unregistered profile waits and the apply still succeeds" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	vscode_write_storage '{"theme":"vs-dark"}'
	before="$BATS_TEST_TMPDIR/storage-before.json"
	cp "$(vscode_storage)" "$before"
	stub_code_logging
	PGREP_RC=0 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	! grep -q -- '--profile' "$CALL_LOG" || false
	cmp -s "$before" "$(vscode_storage)"
	[ "$(cat "$(vscode_marker)")" = "$(vscode_profiles_joined)" ]
	assert_contains "Quit VS Code, then run 'chezmoi apply' again to create:"
}

@test "install-vscode-extensions: an absent storage.json is created holding every profile" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	stub_code_logging
	[ ! -e "$(vscode_storage)" ]
	PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ "$(jq -r '[.userDataProfiles[].name] | sort | join(" ")' "$(vscode_storage)")" = "$(vscode_profiles | sort | tr '\n' ' ' | sed 's/ $//')" ]
}

# The issue's acceptance case: a marketplace refusal inside one profile.
@test "install-vscode-extensions: a refusal inside a profile is named with the profile and the rest still install" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	p="$(vscode_profiles | head -1)"
	bad="$(vscode_ids "$SRC/dot_config/vscode-profiles/$p.txt" | head -1)"
	vscode_write_storage "{\"userDataProfiles\":[{\"location\":\"x1\",\"name\":\"$p\"}]}"
	stub_code_logging
	FAIL_ID="$bad" FAIL_PROFILE="$p" PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "  $bad ($p)"
	assert_contains "1 of "
	for id in $(vscode_ids "$SRC/dot_config/vscode-profiles/$p.txt"); do
		grep -qxF -- "--install-extension $id --force --profile $p" "$CALL_LOG"
	done
}

# /usr/bin carries jq, so absence needs a PATH built from only what the
# script calls besides jq.
@test "install-vscode-extensions: without jq, profiles are skipped and the default still installs" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	stub_code_logging
	tools="$BATS_TEST_TMPDIR/nojq"
	mkdir -p "$tools"
	for t in bash cat grep mkdir dirname mktemp mv rm chmod stat; do
		ln -s "$(PATH=/usr/bin:/bin command -v "$t")" "$tools/$t"
	done
	PGREP_RC=1 PATH="$STUBS:$tools" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "!  vscode ext       no jq, profiles skipped"
	assert_contains "  ✓  vscode ext"
	n_default="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | grep -c '')"
	[ "$(grep -c '' "$CALL_LOG")" -eq "$n_default" ]
	! grep -q -- '--profile' "$CALL_LOG" || false
	[ ! -e "$(vscode_storage)" ]
	# The skip settles as its own line ahead of the step's summary.
	[ "$(grep -n 'no jq, profiles skipped' <<<"$output" | cut -d: -f1)" -lt "$(grep -n '✓  vscode ext' <<<"$output" | cut -d: -f1)" ]
}

@test "install-vscode-extensions: no pending profiles deletes the marker" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	mkdir -p "$(dirname "$(vscode_marker)")"
	vscode_profiles | tr '\n' ' ' >"$(vscode_marker)"
	stub_code_logging
	PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ ! -e "$(vscode_marker)" ]
}

# Rendered under a scratch $HOME, since the pending line reads the marker
# under .chezmoi.homeDir. The stubbed pgrep has to be first on the PATH
# chezmoi itself runs, because the template calls it at render time.
vscode_render_home() {
	local out="$1"
	HOME="$BATS_TEST_TMPDIR/rhome" PATH="$STUBS:$PATH" \
		chezmoi execute-template --source "$SRC" \
		<"$SRC/run_onchange_install-vscode-extensions.sh.tmpl" >"$out"
}

@test "install-vscode-extensions: the render hashes every profile list and adds the pending line only with a marker" {
	stub_pgrep
	mkdir -p "$BATS_TEST_TMPDIR/rhome"
	plain="$BATS_TEST_TMPDIR/plain.sh"
	vscode_render_home "$plain"
	for p in $(vscode_profiles); do
		sum="$(shasum -a 256 "$SRC/dot_config/vscode-profiles/$p.txt" | cut -d' ' -f1)"
		grep -qxF "# VS Code profile $p.txt hash: $sum" "$plain"
	done
	! grep -q '^# pending profiles' "$plain" || false

	marker="$BATS_TEST_TMPDIR/rhome/.local/state/dotfiles/vscode-profiles-pending"
	mkdir -p "$(dirname "$marker")"
	echo "web" >"$marker"
	open="$BATS_TEST_TMPDIR/open.sh"
	closed="$BATS_TEST_TMPDIR/closed.sh"
	PGREP_RC=0 vscode_render_home "$open"
	PGREP_RC=1 vscode_render_home "$closed"
	grep -qxF '# pending profiles: web (VS Code running at render: yes)' "$open"
	grep -qxF '# pending profiles: web (VS Code running at render: no)' "$closed"
	# In chezmoi's units: run_onchange_ reruns only when these bytes differ.
	! cmp -s "$open" "$closed" || false
}

# A minimal source tree real `chezmoi apply` can run: the installer, the UI
# partial it includes, and every list it reads. Copied, so a case can change
# the template or the lists without touching the tree under test.
vscode_venue() {
	local v="$1"
	mkdir -p "$v/src/.chezmoitemplates" "$v/src/dot_config" "$v/dest" "$v/home"
	cp "$SRC/.chezmoitemplates/sh-ui.sh" "$v/src/.chezmoitemplates/"
	cp "$SRC/run_onchange_install-vscode-extensions.sh.tmpl" "$v/src/"
	cp "$SRC"/dot_config/vscode-extensions*.txt "$v/src/dot_config/"
	cp -R "$SRC/dot_config/vscode-profiles" "$v/src/dot_config/"
	: >"$v/chezmoi.toml"
}

@test "install-vscode-extensions: a profile list name outside [a-z0-9-] fails the render" {
	v="$BATS_TEST_TMPDIR/venue"
	vscode_venue "$v"
	printf '# x\n# y\nsome.ext\n' >"$v/src/dot_config/vscode-profiles/Bad_Name.txt"
	HOME="$v/home" run chezmoi execute-template --source "$v/src" \
		<"$v/src/run_onchange_install-vscode-extensions.sh.tmpl"
	[ "$status" -ne 0 ]
	assert_contains "Bad_Name.txt"
}

# The stubs come first on the PATH chezmoi runs under, which is the PATH the
# template's render-time pgrep and the script's own calls both see. chezmoi is
# called by its absolute path because that PATH no longer finds it.
vscode_apply() {
	local v="$1"
	(
		unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME NVM_DIR HOMEBREW_PREFIX
		export HOME="$v/home" PATH="$STUBS:/usr/bin:/bin"
		"$CHEZMOI" apply --source "$v/src" --destination "$v/dest" \
			--config "$v/chezmoi.toml" --persistent-state "$v/state.boltdb"
	) >>"$v/apply.out" 2>&1
}

vscode_calls() {
	grep -c '' "$CALL_LOG"
}

# Measured on chezmoi 2.73: run_onchange_ compares against the last run's
# bytes, so the first apply that renders the pending line reruns once even
# with VS Code still open, because the run before it had no marker to render
# from. Every later apply with VS Code open renders the same line and doesn't.
@test "install-vscode-extensions: real chezmoi apply reruns a pending profile only once VS Code quits" {
	CHEZMOI="$(command -v chezmoi)"
	v="$BATS_TEST_TMPDIR/venue"
	vscode_venue "$v"
	stub_code_logging
	export HOME="$v/home"
	n_default="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | grep -c '')"

	PGREP_RC=0 vscode_apply "$v"
	[ "$(vscode_calls)" -eq "$n_default" ]
	! grep -q -- '--profile' "$CALL_LOG" || false
	[ -e "$(vscode_marker)" ]
	[ ! -e "$(vscode_storage)" ]

	PGREP_RC=0 vscode_apply "$v"
	after_first_pending_render="$(vscode_calls)"
	[ "$after_first_pending_render" -eq $((2 * n_default)) ]
	! grep -q -- '--profile' "$CALL_LOG" || false

	PGREP_RC=0 vscode_apply "$v"
	[ "$(vscode_calls)" -eq "$after_first_pending_render" ]

	PGREP_RC=1 vscode_apply "$v"
	[ "$(vscode_calls)" -gt "$after_first_pending_render" ]
	for p in $(vscode_profiles); do
		[ "$(jq -r --arg n "$p" '.userDataProfiles[] | select(.name == $n) | .location' "$(vscode_storage)")" = "chezmoi-$p" ]
		n_own="$(vscode_ids "$SRC/dot_config/vscode-profiles/$p.txt" | grep -c '')"
		[ "$(grep -c -- "--profile $p\$" "$CALL_LOG")" -eq $((n_default + n_own)) ]
	done
	[ ! -e "$(vscode_marker)" ]
}

# Falsifier for the case above: with the pending block gone, nothing in the
# script changes when VS Code quits, so the profiles are never created.
@test "install-vscode-extensions: without the pending block, quitting VS Code never reruns the installer" {
	CHEZMOI="$(command -v chezmoi)"
	v="$BATS_TEST_TMPDIR/venue"
	vscode_venue "$v"
	tmpl="$v/src/run_onchange_install-vscode-extensions.sh.tmpl"
	grep -q 'vscode-profiles-pending' "$tmpl"
	awk 'index($0, "$pending := ") { skip = 1 } skip && $0 == "{{- end }}" { skip = 0; next } !skip' "$tmpl" >"$tmpl.new"
	mv "$tmpl.new" "$tmpl"
	! grep -q 'pending profiles:' "$tmpl" || false
	stub_code_logging
	export HOME="$v/home"

	PGREP_RC=0 vscode_apply "$v"
	first="$(vscode_calls)"
	[ -e "$(vscode_marker)" ]

	PGREP_RC=0 vscode_apply "$v"
	PGREP_RC=1 vscode_apply "$v"
	[ "$(vscode_calls)" -eq "$first" ]
	[ ! -e "$(vscode_storage)" ]
}

@test "install-vscode-extensions: a profile that fails to register is named and left pending" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	vscode_write_storage '{bad'
	stub_code_logging
	PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "run 'chezmoi apply' again to create: $(vscode_profiles_joined)"
	assert_not_contains "  profile "
	assert_contains "Couldn't register these with VS Code"
	assert_not_contains "Quit VS Code"
	[ "$(cat "$(vscode_marker)")" = "$(vscode_profiles_joined)" ]
	! grep -q -- '--profile' "$CALL_LOG" || false
}

@test "install-vscode-extensions: when only registrations fail, the summary counts no refused extensions" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	total="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | wc -l | tr -d ' ')"
	vscode_write_storage '{bad'
	stub_code_logging
	PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_not_contains "refused"
	assert_not_contains "could not install these extensions"
	assert_contains "$total installed"
	assert_contains "Couldn't register these with VS Code"
}

# Falsifier for the fix: a real refusal beside failed registrations still
# counts, and only that id is listed. Hiding the refused line whenever a
# registration fails, or still counting the profiles, both fail here.
@test "install-vscode-extensions: a refused id beside failed registrations counts alone" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	total="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | wc -l | tr -d ' ')"
	id="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | head -1)"
	vscode_write_storage '{bad'
	stub_code_logging
	FAIL_ID="$id" PGREP_RC=1 PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "1 of $total refused"
	assert_contains "  $id"
	assert_not_contains "  profile "
}

# Repairing storage.json changes nothing VS Code's open-or-closed state can
# see, so this pins the second render line. Without it, apply 3 below renders
# the same bytes as apply 2 and the fix never reruns.
@test "install-vscode-extensions: real chezmoi apply registers a failed profile once storage.json is fixed" {
	CHEZMOI="$(command -v chezmoi)"
	v="$BATS_TEST_TMPDIR/venue"
	vscode_venue "$v"
	stub_code_logging
	export HOME="$v/home"
	vscode_write_storage '{bad'
	n_default="$(vscode_ids "$SRC/dot_config/vscode-extensions.txt" | grep -c '')"

	PGREP_RC=1 vscode_apply "$v"
	[ -e "$(vscode_marker)" ]
	! grep -q -- '--profile' "$CALL_LOG" || false

	# First render with the pending lines, so it reruns and fails the same way.
	PGREP_RC=1 vscode_apply "$v"
	[ -e "$(vscode_marker)" ]
	after_broken="$(vscode_calls)"

	vscode_write_storage '{}'
	PGREP_RC=1 vscode_apply "$v"
	[ "$(vscode_calls)" -gt "$after_broken" ]
	for p in $(vscode_profiles); do
		[ "$(jq -r --arg n "$p" '.userDataProfiles[] | select(.name == $n) | .location' "$(vscode_storage)")" = "chezmoi-$p" ]
		n_own="$(vscode_ids "$SRC/dot_config/vscode-profiles/$p.txt" | grep -c '')"
		[ "$(grep -c -- "--profile $p\$" "$CALL_LOG")" -eq $((n_default + n_own)) ]
	done
	[ ! -e "$(vscode_marker)" ]
}

@test "install-vscode-extensions: real chezmoi apply registers once the globalStorage dir is writable again" {
	CHEZMOI="$(command -v chezmoi)"
	v="$BATS_TEST_TMPDIR/venue"
	vscode_venue "$v"
	stub_code_logging
	export HOME="$v/home"
	vscode_write_storage '{}'
	gsdir="$(dirname "$(vscode_storage)")"
	chmod 555 "$gsdir"

	PGREP_RC=1 vscode_apply "$v"
	[ -e "$(vscode_marker)" ]
	! grep -q -- '--profile' "$CALL_LOG" || false

	# First render with the pending lines, so it reruns and fails the same way.
	PGREP_RC=1 vscode_apply "$v"
	[ -e "$(vscode_marker)" ]
	after_broken="$(vscode_calls)"

	chmod 755 "$gsdir"
	PGREP_RC=1 vscode_apply "$v"
	[ "$(vscode_calls)" -gt "$after_broken" ]
	for p in $(vscode_profiles); do
		[ "$(jq -r --arg n "$p" '.userDataProfiles[] | select(.name == $n) | .location' "$(vscode_storage)")" = "chezmoi-$p" ]
	done
	[ ! -e "$(vscode_marker)" ]
}

# ---- configure-raycast ----
# `open` is a macOS built-in at /usr/bin/open, so PATH here is trimmed to /bin —
# wide enough for the `cat`/`sleep` the script itself needs, narrow enough that
# an unstubbed `open` genuinely reads as absent.

@test "configure-raycast: absent tool skips clean" {
	script="$(render_script run_onchange_configure-raycast.sh.tmpl)"
	stub_defaults
	PATH="$STUBS:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "skipping Raycast configuration"
}

@test "configure-raycast: present tool failing names the item" {
	script="$(render_script run_onchange_configure-raycast.sh.tmpl)"
	stub_defaults
	stub_sleep
	ext="$(first_raycast_extension)"
	cat >"$STUBS/open" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "raycast://extensions/install/$ext" ]; then
  exit 1
fi
exit 0
STUB
	chmod +x "$STUBS/open"
	PATH="$STUBS:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "raycastGlobalHotkey" "$(cat "$DEFAULTS_LOG")"
	# The bare id also shows up in the per-item progress line the baseline script
	# already prints, so the proof has to be the failure line's own format — the
	# full raycast:// URL, which only the summary this job adds ever prints.
	assert_contains "raycast://extensions/install/$ext"
	assert_contains "would not hand these install URLs to Raycast"
}

@test "configure-raycast: one failure does not stop the rest" {
	script="$(render_script run_onchange_configure-raycast.sh.tmpl)"
	stub_defaults
	stub_sleep
	expected="$(grep -vcE '^\s*#|^\s*$' "$SRC/dot_config/raycast-extensions.txt")"
	export CALL_LOG="$BATS_TEST_TMPDIR/raycast-calls.log"
	: >"$CALL_LOG"
	cat >"$STUBS/open" <<'STUB'
#!/usr/bin/env bash
case "$1" in
raycast://*) echo "$1" >>"$CALL_LOG" ;;
esac
exit 1
STUB
	chmod +x "$STUBS/open"
	PATH="$STUBS:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ "$(grep -c '' "$CALL_LOG")" -eq "$expected" ]
	assert_contains "raycastGlobalHotkey" "$(cat "$DEFAULTS_LOG")"
}

@test "configure-raycast: all items succeed prints no failure summary" {
	script="$(render_script run_onchange_configure-raycast.sh.tmpl)"
	stub_defaults
	stub_sleep
	printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/open"
	chmod +x "$STUBS/open"
	PATH="$STUBS:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	# Not asserting on the success wording here: it's reworded by this job as
	# part of B-2's "the two read differently" requirement, so it isn't a string
	# the baseline script ever printed, and this case is a regression guard that
	# has to pass at baseline per V-1's table.
	assert_not_contains "would not hand these install URLs"
	assert_contains "raycastGlobalHotkey" "$(cat "$DEFAULTS_LOG")"
}

# ---- install-claude-plugins ----
# The manifest is age-encrypted, so identifiers are read back out of the render
# itself rather than hardcoded — the same 7 calls the constitution measured
# under the real $HOME, as `add_marketplace`/`install_plugin` lines the render
# leaves in plain text.

@test "install-claude-plugins: absent tool skips clean" {
	script="$(render_script run_onchange_after_install-claude-plugins.sh.tmpl)"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "claude CLI not found"
}

@test "install-claude-plugins: present tool failing names the item" {
	script="$(render_script run_onchange_after_install-claude-plugins.sh.tmpl)"
	spec="$(grep -m1 '^install_plugin ' "$script" | awk '{print $2}')"
	cat >"$STUBS/claude" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "plugin" ] && [ "\$2" = "marketplace" ] && [ "\$3" = "list" ]; then
  exit 1
fi
if [ "\$1" = "plugin" ] && [ "\$2" = "list" ]; then
  exit 1
fi
if [ "\$1" = "plugin" ] && [ "\$2" = "marketplace" ] && [ "\$3" = "add" ]; then
  exit 0
fi
if [ "\$1" = "plugin" ] && [ "\$2" = "install" ] && [ "\$3" = "$spec" ]; then
  exit 1
fi
exit 0
STUB
	chmod +x "$STUBS/claude"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	# Both versions print "Installing $spec..." on the way in; the summary line
	# this job adds reads "plugin $spec", which is the substring that actually
	# distinguishes a named failure from ordinary progress output.
	assert_contains "plugin $spec"
	assert_contains "did not install"
}

@test "install-claude-plugins: one failure does not stop the rest" {
	script="$(render_script run_onchange_after_install-claude-plugins.sh.tmpl)"
	expected="$(grep -cE '^(add_marketplace|install_plugin) ' "$script")"
	export CALL_LOG="$BATS_TEST_TMPDIR/claude-calls.log"
	: >"$CALL_LOG"
	cat >"$STUBS/claude" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "plugin" ] && [ "$2" = "marketplace" ] && [ "$3" = "list" ]; then
  exit 1
fi
if [ "$1" = "plugin" ] && [ "$2" = "list" ]; then
  exit 1
fi
if [ "$1" = "plugin" ] && [ "$2" = "marketplace" ] && [ "$3" = "add" ]; then
  echo "add $4" >>"$CALL_LOG"
  exit 1
fi
if [ "$1" = "plugin" ] && [ "$2" = "install" ]; then
  echo "install $3" >>"$CALL_LOG"
  exit 1
fi
exit 0
STUB
	chmod +x "$STUBS/claude"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	[ "$(grep -c '' "$CALL_LOG")" -eq "$expected" ]
}

@test "install-claude-plugins: all items succeed prints no failure summary" {
	script="$(render_script run_onchange_after_install-claude-plugins.sh.tmpl)"
	cat >"$STUBS/claude" <<'STUB'
#!/usr/bin/env bash
if [ "$1" = "plugin" ] && [ "$2" = "marketplace" ] && [ "$3" = "list" ]; then
  exit 1
fi
if [ "$1" = "plugin" ] && [ "$2" = "list" ]; then
  exit 1
fi
exit 0
STUB
	chmod +x "$STUBS/claude"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "  ✓  claude plugins"
	assert_not_contains "did not install"
}
