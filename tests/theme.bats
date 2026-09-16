#!/usr/bin/env bats
#
# Drives the real `theme` script as a subprocess against a fake $HOME with
# every external tool stubbed on PATH, the way font.bats does. Cases assert on
# exit status and on what the run left on disk, never on log wording. The one
# exception is Herdr's diagnostics, which the script exists to surface.

load 'helpers'

SCRIPT="${BATS_TEST_DIRNAME}/../dot_local/bin/executable_theme"
SRC="${BATS_TEST_DIRNAME}/.."

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	# Set on this machine, and they would send the script straight back to the
	# real ~/.config no matter what HOME says.
	unset XDG_CONFIG_HOME
	unset XDG_CACHE_HOME
	VSCODE="$HOME/Library/Application Support/Code/User/settings.json"
	GHOSTTY="$HOME/.config/ghostty/config"
	HERDR="$HOME/.config/herdr/config.toml"
	REGISTRY="$HOME/.config/theme/registry.json"

	mkdir -p "$HOME/.config/theme" "$HOME/.config/font" "$HOME/.config/ghostty" \
		"$HOME/.config/herdr" "$(dirname "$VSCODE")" "$STUBS"
	cp "$SRC/dot_config/theme/registry.json" "$REGISTRY"
	cp "$SRC/dot_config/font/jsonc.jq" "$HOME/.config/font/jsonc.jq"
	cp "$SRC/dot_config/ghostty/config" "$GHOSTTY"
	cp "$SRC/dot_config/herdr/config.toml" "$HERDR"
	cp "$SRC/private_Library/private_Application Support/Code/User/settings.json" "$VSCODE"

	# Records its arguments instead of touching the real source tree.
	cat >"$STUBS/chezmoi" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/chezmoi-calls"
	STUB

	# Answers +list-themes from a file the test controls, in the real output's
	# shape: one name per line, tagged with where it came from.
	cat >"$STUBS/ghostty" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/ghostty-calls"
		[ "$1" = "+list-themes" ] || exit 1
		sed 's/$/ (resources)/' "$HOME/ghostty-themes"
	STUB

	cat >"$STUBS/code" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/code-calls"
		[ "$1" = "--list-extensions" ] || exit 1
		cat "$HOME/installed-extensions"
	STUB

	# A running server unless the test says otherwise, answering the way the
	# real one does: JSON with a diagnostics array that is usually empty.
	cat >"$STUBS/herdr" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/herdr-calls"
		if [ -e "$HOME/herdr-down" ]; then
			echo '{"error":{"code":"server_unavailable"}}' >&2
			exit 1
		fi
		diagnostics='[]'
		[ -f "$HOME/herdr-diagnostics" ] && diagnostics=$(cat "$HOME/herdr-diagnostics")
		printf '{"id":"cli:server:reload-config","result":{"diagnostics":%s,"status":"applied","type":"config_reload"}}\n' "$diagnostics"
	STUB

	# Light unless the test says dark, failing the way `defaults` does when the
	# key is absent, since that failure is what the script reads as light.
	cat >"$STUBS/defaults" <<-'STUB'
		#!/usr/bin/env bash
		if [ ! -e "$HOME/dark-mode" ]; then
			echo "The domain/default pair of (kCFPreferencesAnyApplication, AppleInterfaceStyle) does not exist" >&2
			exit 1
		fi
		echo Dark
	STUB

	chmod +x "$STUBS/chezmoi" "$STUBS/ghostty" "$STUBS/code" "$STUBS/herdr" "$STUBS/defaults"
	export PATH="$STUBS:$PATH"

	# Derived from the registry rather than hardcoded, so a new family doesn't
	# leave the stubs reporting last month's roster.
	jq -r '.[] | .ghostty.dark, .ghostty.light' "$REGISTRY" | sort -u >"$HOME/ghostty-themes"
	jq -r '.[].vscode.extension' "$REGISTRY" | sort -u >"$HOME/installed-extensions"
}

theme() {
	bash "$SCRIPT" "$@"
}

keys_in_order() {
	jq -r 'to_entries | sort_by(.value.order) | .[].key' "$REGISTRY"
}

first_key() {
	keys_in_order | head -1
}

second_key() {
	keys_in_order | sed -n '2p'
}

# field <key> <path>, e.g. `field catppuccin ghostty.dark`.
field() {
	jq -r --arg k "$1" ".[\$k].$2" "$REGISTRY"
}

snapshot() {
	cp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	cp "$HERDR" "$BATS_TEST_TMPDIR/herdr.before"
}

assert_unchanged() {
	cmp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cmp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	cmp "$HERDR" "$BATS_TEST_TMPDIR/herdr.before"
}

@test "lists the roster in order and marks the active family" {
	theme "$(first_key)"
	run theme
	[ "$status" -eq 0 ]
	expected=$(keys_in_order)
	listed=$(echo "$output" | grep '^[* ] ' | cut -c3- | awk '{print $1}')
	[ "$listed" = "$expected" ]
	echo "$output" | grep -q "^\* $(first_key)"
	assert_contains "active: $(first_key)"
}

# Listing reports where switching refuses, so a machine that hasn't installed
# a family yet still sees it in the roster with the gap named.
@test "listing names the pieces this machine is missing without refusing" {
	key=$(second_key)
	ext=$(field "$key" vscode.extension)
	grep -vxF "$ext" "$HOME/installed-extensions" >"$HOME/installed-extensions.tmp"
	mv "$HOME/installed-extensions.tmp" "$HOME/installed-extensions"
	run theme
	[ "$status" -eq 0 ]
	echo "$output" | grep -q "^  $key  .*(missing: vscode $ext)"
}

@test "switching writes the same family into all three configs" {
	key=$(second_key)
	run theme "$key"
	[ "$status" -eq 0 ]
	grep -qxF "theme = dark:$(field "$key" ghostty.dark),light:$(field "$key" ghostty.light)" "$GHOSTTY"
	grep -qxF "dark_name = \"$(field "$key" herdr.dark)\"" "$HERDR"
	grep -qxF "light_name = \"$(field "$key" herdr.light)\"" "$HERDR"
	grep -qxF "name = \"$(field "$key" herdr.dark)\"" "$HERDR"
	grep -qxF 'auto_switch = true' "$HERDR"
	grep -qF "\"workbench.preferredDarkColorTheme\": \"$(field "$key" vscode.dark)\"" "$VSCODE"
	grep -qF "\"workbench.preferredLightColorTheme\": \"$(field "$key" vscode.light)\"" "$VSCODE"
	grep -qF '"window.autoDetectColorScheme": true' "$VSCODE"
}

# The marker block is the only part of Herdr's file this script owns; the UI
# settings around it have to come through untouched.
@test "the Herdr rewrite leaves everything outside the markers alone" {
	run theme "$(second_key)"
	[ "$status" -eq 0 ]
	sed '/BEGIN theme/,/END theme/d' "$HERDR" >"$BATS_TEST_TMPDIR/herdr.outside"
	sed '/BEGIN theme/,/END theme/d' "$SRC/dot_config/herdr/config.toml" >"$BATS_TEST_TMPDIR/herdr.outside.expected"
	cmp "$BATS_TEST_TMPDIR/herdr.outside" "$BATS_TEST_TMPDIR/herdr.outside.expected"
	[ "$(grep -c '^\[theme\]' "$HERDR")" -eq 1 ]
}

@test "the active VS Code theme follows the current appearance" {
	key=$(second_key)
	run theme "$key"
	[ "$status" -eq 0 ]
	grep -qF "\"workbench.colorTheme\": \"$(field "$key" vscode.light)\"" "$VSCODE"

	touch "$HOME/dark-mode"
	run theme "$key"
	[ "$status" -eq 0 ]
	grep -qF "\"workbench.colorTheme\": \"$(field "$key" vscode.dark)\"" "$VSCODE"
}

@test "hands all three files back to chezmoi" {
	run theme "$(first_key)"
	[ "$status" -eq 0 ]
	grep -q 're-add' "$HOME/chezmoi-calls"
	grep -q 'ghostty/config' "$HOME/chezmoi-calls"
	grep -q 'settings.json' "$HOME/chezmoi-calls"
	grep -q 'herdr/config.toml' "$HOME/chezmoi-calls"
}

@test "asks a running Herdr to reload" {
	run theme "$(first_key)"
	[ "$status" -eq 0 ]
	grep -q 'server reload-config' "$HOME/herdr-calls"
}

# The switch writes the files either way. A server that isn't up reads them on
# launch, and that is not a reason to report the switch as failed.
@test "a Herdr that is not running does not fail the switch" {
	key=$(first_key)
	touch "$HOME/herdr-down"
	run theme "$key"
	[ "$status" -eq 0 ]
	grep -qxF "theme = dark:$(field "$key" ghostty.dark),light:$(field "$key" ghostty.light)" "$GHOSTTY"
	assert_contains "next launch"
}

# A reload with a theme name Herdr doesn't know still exits 0 and says
# "applied"; the complaint is in the diagnostics array, which is why the
# script prints it rather than trusting the exit status.
@test "surfaces Herdr's reload diagnostics" {
	echo '["theme.dark_name: unknown theme"]' >"$HOME/herdr-diagnostics"
	run theme "$(first_key)"
	[ "$status" -eq 0 ]
	assert_contains "unknown theme"
}

@test "rejects an unknown key without touching anything" {
	snapshot
	run theme no-such-family
	[ "$status" -ne 0 ]
	assert_unchanged
}

@test "refuses when Ghostty does not know one of the family's themes" {
	key=$(second_key)
	grep -vxF "$(field "$key" ghostty.light)" "$HOME/ghostty-themes" >"$HOME/ghostty-themes.tmp"
	mv "$HOME/ghostty-themes.tmp" "$HOME/ghostty-themes"
	snapshot
	run theme "$key"
	[ "$status" -ne 0 ]
	assert_contains "$(field "$key" ghostty.light)"
	assert_unchanged
}

@test "refuses when the VS Code extension is not installed" {
	key=$(second_key)
	: >"$HOME/installed-extensions"
	snapshot
	run theme "$key"
	[ "$status" -ne 0 ]
	assert_contains "$(field "$key" vscode.extension)"
	assert_unchanged
}

@test "--force writes without the availability checks" {
	key=$(second_key)
	: >"$HOME/ghostty-themes"
	: >"$HOME/installed-extensions"
	run theme "$key" --force
	[ "$status" -eq 0 ]
	grep -qxF "theme = dark:$(field "$key" ghostty.dark),light:$(field "$key" ghostty.light)" "$GHOSTTY"
}

@test "--force on its own is refused" {
	run theme --force
	[ "$status" -ne 0 ]
}

# The script checks every anchor before the first write, so a Herdr file with
# no markers refuses while Ghostty and VS Code are still untouched, instead of
# leaving two of three configs switched.
@test "refuses a Herdr config without markers and leaves the other two alone" {
	grep -v 'theme (managed by' "$HERDR" | grep -v '^# END theme$' >"$HERDR.tmp"
	mv "$HERDR.tmp" "$HERDR"
	snapshot
	run theme "$(second_key)"
	[ "$status" -ne 0 ]
	assert_unchanged
}

@test "refuses a Ghostty config with two theme lines" {
	echo 'theme = Something Else' >>"$GHOSTTY"
	snapshot
	run theme "$(second_key)"
	[ "$status" -ne 0 ]
	assert_unchanged
}

# The criterion that catches the most: if any write is lossy, cycling the whole
# roster and coming home won't reproduce the starting bytes.
@test "round-tripping the whole roster restores all three files byte for byte" {
	theme "$(first_key)"
	snapshot
	for key in $(keys_in_order); do
		run theme "$key"
		[ "$status" -eq 0 ]
	done
	theme "$(first_key)"
	assert_unchanged
}

@test "every entry carries the fields the switcher reads" {
	run jq -e '
		to_entries | all(
			(.value.order | type == "number")
			and (.value.label | length > 0)
			and (.value.herdr.dark | length > 0)
			and (.value.herdr.light | length > 0)
			and (.value.ghostty.dark | length > 0)
			and (.value.ghostty.light | length > 0)
			and (.value.vscode.dark | length > 0)
			and (.value.vscode.light | length > 0)
			and (.value.vscode.extension | test("^[a-z0-9-]+\\.[a-z0-9-]+$"))
		)
	' "$REGISTRY"
	[ "$status" -eq 0 ]
}

# A family whose extension isn't in the tracked list installs on this machine
# and on no other, which is the gap dotfiles-doctor reports. This case pins it
# at the source so it never reaches the doctor.
@test "every extension the registry names is in the tracked list" {
	for ext in $(jq -r '.[].vscode.extension' "$REGISTRY"); do
		grep -qixF "$ext" "$SRC/dot_config/vscode-extensions.txt"
	done
}
