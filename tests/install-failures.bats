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

@test "install-vscode-extensions: absent tool skips clean" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "VS Code CLI not found"
}

@test "install-vscode-extensions: present tool failing names the item" {
	script="$(render_script run_onchange_install-vscode-extensions.sh.tmpl)"
	ext="$(first_extension)"
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
	expected="$(grep -vcE '^\s*#|^\s*$' "$SRC/dot_config/vscode-extensions.txt")"
	export CALL_LOG="$BATS_TEST_TMPDIR/vscode-calls.log"
	: >"$CALL_LOG"
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
	printf '#!/usr/bin/env bash\nexit 0\n' >"$STUBS/code"
	chmod +x "$STUBS/code"
	PATH="$STUBS:/usr/bin:/bin" run bash "$script"
	[ "$status" -eq 0 ]
	assert_contains "  ✓  vscode ext"
	assert_not_contains "could not install"
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
