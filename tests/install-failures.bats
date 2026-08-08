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
# there. tests/licensed-fonts.bats:22 is the same move for the same reason.
render_script() {
	local tmpl="$1" out="$BATS_TEST_TMPDIR/${1%.tmpl}"
	HOME="$REAL_HOME" chezmoi execute-template <"$SRC/$tmpl" >"$out"
	echo "$out"
}

first_extension() {
	grep -vE '^\s*#|^\s*$' "$SRC/dot_config/vscode-extensions.txt" | head -1
}

first_raycast_extension() {
	grep -vE '^\s*#|^\s*$' "$SRC/dot_config/raycast-extensions.txt" | head -1
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
# One `brew bundle` call over the whole rendered Brewfile, so it has no
# keeps-going case of its own — B-3 exempts it, since `brew bundle` already
# continues past a failing entry internally.

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
	assert_contains "VS Code extensions installed."
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
	assert_contains "Claude Code plugins ready."
	assert_not_contains "did not install"
}
