#!/usr/bin/env bats
#
# Drives the real `font` script as a subprocess against a fake $HOME with
# `chezmoi` stubbed on PATH. Nothing reaches inside for a helper function and
# nothing asserts on log wording: what matters is what the run left on disk and
# whether it said no when it should have, both observable from outside.
#
# Prior art is the age-key work, which was verified this way by hand. This is
# the same technique with the hand work taken out.

SCRIPT="${BATS_TEST_DIRNAME}/../dot_local/bin/executable_font"
SRC="${BATS_TEST_DIRNAME}/.."

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	# Set on this machine, and they would send the script straight back to the
	# real ~/.config and ~/.cache no matter what HOME says.
	unset XDG_CONFIG_HOME
	unset XDG_CACHE_HOME
	VSCODE="$HOME/Library/Application Support/Code/User/settings.json"
	GHOSTTY="$HOME/.config/ghostty/config"

	mkdir -p "$HOME/.config/font" "$HOME/.config/ghostty" "$(dirname "$VSCODE")" "$STUBS"
	cp "$SRC/dot_config/font/registry.json" "$HOME/.config/font/registry.json"
	cp "$SRC/dot_config/font/jsonc.jq" "$HOME/.config/font/jsonc.jq"
	cp "$SRC/dot_config/ghostty/config" "$GHOSTTY"
	cp "$SRC/private_Library/private_Application Support/Code/User/settings.json" "$VSCODE"

	# Records its arguments instead of touching the real source tree.
	cat >"$STUBS/chezmoi" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/chezmoi-calls"
	STUB
	chmod +x "$STUBS/chezmoi"

	# The real thing takes ten seconds and answers a question about whichever
	# machine is running the suite, which would make these tests both slow and
	# dependent on the fonts that machine happens to have. The stub answers from
	# what the test declared. It also logs every call, which is the only way to
	# prove a warm-cache switch never reached for it.
	cat >"$STUBS/system_profiler" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/system_profiler-calls"
		echo "Fonts:"
		while IFS= read -r family; do
			printf '    Stub.ttf:\n      Typefaces:\n        Stub:\n          Family: %s\n' "$family"
		done <"$HOME/installed-families"
	STUB
	chmod +x "$STUBS/system_profiler"
	export PATH="$STUBS:$PATH"

	# Derived from the registry rather than hardcoded, so widening the roster
	# doesn't leave the stub reporting last month's fonts.
	jq -r '.[].terminal.family' "$HOME/.config/font/registry.json" >"$HOME/installed-families"

	# Most tests exercise the warm-cache path; the ones that don't clear this or
	# backdate it themselves.
	mkdir -p "$HOME/.cache/font"
	sort -u "$HOME/installed-families" >"$HOME/.cache/font/families"
}

font() {
	bash "$SCRIPT" "$@"
}

# A registry entry pointing at a family no machine can have. The refusal path has
# to be provable without betting on which fonts the machine running the suite
# happens to be missing today.
add_absent_entry() {
	jq --arg tier "$1" \
		--arg family 'NoSuchFamily XX' \
		--arg editor_family "'NoSuchFamily XX'" \
		--arg ligatures "'calt'" '
		.absent = {
			order: 999,
			tier: $tier,
			label: "Nonexistent Test Face",
			size: 14,
			terminal: { family: $family, features: "calt" },
			editor: {
				family: $editor_family,
				variations: "",
				ligatures: $ligatures,
				terminalFamily: $family
			}
		}
	' "$HOME/.config/font/registry.json" >"$HOME/registry.tmp"
	mv "$HOME/registry.tmp" "$HOME/.config/font/registry.json"
}

@test "lists the roster in order and marks the active font" {
	run font
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | grep -c '^[* ] ')" -eq 3 ]
	# Drop the two-column active marker before reading the key, so the active row
	# and the inactive ones parse the same way.
	[ "$(echo "$output" | sed -n '1p' | cut -c3- | awk '{print $1}')" = "fantasque" ]
	[ "$(echo "$output" | sed -n '2p' | cut -c3- | awk '{print $1}')" = "maple" ]
	[ "$(echo "$output" | sed -n '3p' | cut -c3- | awk '{print $1}')" = "victor" ]
	[[ "$output" == *"active terminal family: FantasqueSansM Nerd Font"* ]]
	echo "$output" | grep -q '^\* fantasque'
}

@test "switching rewrites the Ghostty block and the VS Code keys together" {
	run font victor
	[ "$status" -eq 0 ]
	grep -qxF 'font-family = "VictorMono Nerd Font"' "$GHOSTTY"
	grep -q "'VictorMono Nerd Font'" "$VSCODE"
	# The marker block stays intact and everything outside it is untouched.
	grep -qxF '# BEGIN font (managed by `font`)' "$GHOSTTY"
	grep -qxF '# END font' "$GHOSTTY"
	grep -qxF 'theme = dark:Synthwave Everything,light:Light Owl' "$GHOSTTY"
	grep -qxF 'cursor-style = block' "$GHOSTTY"
}

@test "hands both files back to chezmoi" {
	run font maple
	[ "$status" -eq 0 ]
	grep -q 're-add' "$HOME/chezmoi-calls"
	grep -q 'ghostty/config' "$HOME/chezmoi-calls"
	grep -q 'settings.json' "$HOME/chezmoi-calls"
}

@test "a second argument overrides the registry size" {
	run font maple 18
	[ "$status" -eq 0 ]
	grep -qxF 'font-size = 18' "$GHOSTTY"
	grep -q '"terminal.integrated.fontSize": 18' "$VSCODE"
}

@test "rejects a size that is not a positive integer" {
	cp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	run font maple 14pt
	[ "$status" -ne 0 ]
	cmp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
}

# The criterion that catches the most: if any write is lossy, cycling the whole
# roster and coming home won't reproduce the starting bytes.
@test "round-tripping all three keys restores both files byte for byte" {
	font fantasque
	cp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.start"
	cp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.start"

	font maple
	font victor
	font fantasque

	cmp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.start"
	cmp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.start"
}

@test "preserves the trailing commas the formatter keeps re-adding" {
	before=$(grep -c ',$' "$VSCODE")
	run font victor
	[ "$status" -eq 0 ]
	[ "$(grep -c ',$' "$VSCODE")" -eq "$before" ]
}

# mktemp creates 0600, so replacing a file by moving a temp over it silently
# tightens its mode. chezmoi then re-adds it as a `private_` source file, which
# renames the source entry and shows up as a delete plus an add. Caught only by
# running against a real chezmoi; the stub can't see it.
@test "preserves file modes so chezmoi does not re-add them as private" {
	chmod 644 "$GHOSTTY" "$VSCODE"
	run font victor
	[ "$status" -eq 0 ]
	[ "$(stat -f '%Lp' "$GHOSTTY")" = "644" ]
	[ "$(stat -f '%Lp' "$VSCODE")" = "644" ]
}

@test "an unknown key exits non-zero with neither file modified" {
	cp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	run font bogus
	[ "$status" -ne 0 ]
	cmp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cmp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	[ ! -f "$HOME/chezmoi-calls" ]
}

@test "a Ghostty config missing its end marker exits non-zero and changes nothing" {
	grep -vxF '# END font' "$GHOSTTY" >"$GHOSTTY.tmp" && mv "$GHOSTTY.tmp" "$GHOSTTY"
	cp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	run font victor
	[ "$status" -ne 0 ]
	cmp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cmp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
}

@test "a missing registry exits non-zero naming the file" {
	rm "$HOME/.config/font/registry.json"
	run font victor
	[ "$status" -ne 0 ]
	[[ "$output" == *"registry.json"* ]]
}

@test "an absent jq exits non-zero" {
	# /bin carries bash for the runner but not jq, which lives in /usr/bin here.
	# The dependency check fires before the script needs anything else on PATH.
	PATH="$STUBS:/bin" run font victor
	[ "$status" -ne 0 ]
	[[ "$output" == *"jq"* ]]
}

@test "settings carrying comments are reported, not stripped, and nothing is written" {
	printf '{\n\t// mine\n\t"editor.fontFamily": "x",\n}\n' >"$VSCODE"
	cp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	run font victor
	[ "$status" -ne 0 ]
	cmp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	cmp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	grep -q '// mine' "$VSCODE"
}

@test "an anchor matching zero times exits non-zero" {
	grep -v '"editor.fontLigatures"' "$VSCODE" >"$VSCODE.tmp" && mv "$VSCODE.tmp" "$VSCODE"
	run font victor
	[ "$status" -ne 0 ]
	[[ "$output" == *"editor.fontLigatures"* ]]
}

@test "an anchor matching more than once exits non-zero" {
	awk '/"editor\.fontLigatures"/ { print; print } !/"editor\.fontLigatures"/ { print }' \
		"$VSCODE" >"$VSCODE.tmp" && mv "$VSCODE.tmp" "$VSCODE"
	run font victor
	[ "$status" -ne 0 ]
	[[ "$output" == *"editor.fontLigatures"* ]]
}

@test "builds the family cache when it is missing" {
	rm -rf "$HOME/.cache/font"
	run font
	[ "$status" -eq 0 ]
	[ -s "$HOME/.cache/font/families" ]
	grep -q 'SPFontsDataType' "$HOME/system_profiler-calls"
}

@test "rebuilds the family cache once it is older than seven days" {
	touch -t "$(date -v-8d '+%Y%m%d%H%M')" "$HOME/.cache/font/families"
	run font victor
	[ "$status" -eq 0 ]
	grep -q 'SPFontsDataType' "$HOME/system_profiler-calls"
}

@test "leaves a family cache younger than seven days alone" {
	touch -t "$(date -v-6d '+%Y%m%d%H%M')" "$HOME/.cache/font/families"
	run font victor
	[ "$status" -eq 0 ]
	[ ! -f "$HOME/system_profiler-calls" ]
}

@test "--refresh rebuilds the cache on demand" {
	echo 'Stale Family' >"$HOME/.cache/font/families"
	run font --refresh
	[ "$status" -eq 0 ]
	grep -q 'SPFontsDataType' "$HOME/system_profiler-calls"
	! grep -qxF 'Stale Family' "$HOME/.cache/font/families"
}

# system_profiler is the reason the cache exists. If an ordinary switch still
# pays for it, the cache is decoration.
@test "does not invoke system_profiler on an ordinary switch with a warm cache" {
	run font victor
	[ "$status" -eq 0 ]
	[ ! -f "$HOME/system_profiler-calls" ]
}

# Asserting on the label and the tier rather than on phrasing. A refusal that
# doesn't say which font or which tier leaves you no better off than the tofu
# did, so those two are the behavior; the sentence around them isn't.
@test "refuses a font whose family is absent, naming it and its tier, touching nothing" {
	add_absent_entry a
	cp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	run font absent
	[ "$status" -ne 0 ]
	[[ "$output" == *"Nonexistent Test Face"* ]]
	[[ "$output" == *"tier a"* ]]
	cmp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.before"
	cmp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.before"
	[ ! -f "$HOME/chezmoi-calls" ]
}

@test "a Tier C refusal points at 1Password and the fetch that may not have run" {
	add_absent_entry c
	run font absent
	[ "$status" -ne 0 ]
	[[ "$output" == *"tier c"* ]]
	[[ "$output" == *"1Password"* ]]
	[[ "$output" == *"fetch"* ]]
}

@test "--force writes a font the cache says is absent" {
	add_absent_entry a
	run font absent --force
	[ "$status" -eq 0 ]
	grep -qxF 'font-family = "NoSuchFamily XX"' "$GHOSTTY"
	grep -q "'NoSuchFamily XX'" "$VSCODE"
}

# A client machine with no licensed fonts should look like a machine missing
# fonts, not like a registry that's broken.
@test "lists an absent entry marked rather than hiding it, and exits 0" {
	add_absent_entry c
	run font
	[ "$status" -eq 0 ]
	echo "$output" | grep -q '^  absent .*(not installed)'
	[ "$(echo "$output" | grep -c '(not installed)')" -eq 1 ]
}

@test "an unknown option exits non-zero rather than being read as a key" {
	run font --nope
	[ "$status" -ne 0 ]
}

# The registry is meant to be the only place a family name appears. This is the
# test that keeps it that way as the script grows.
@test "no family name appears outside the registry" {
	! grep -qE 'FantasqueSansM|VictorMono|Maple Mono|Nerd Font' "$SCRIPT"
}

# `chezmoi re-add` skips templates, so turning either config into a .tmpl would
# quietly drop it from dotfiles-sync capture. That failure is invisible until
# you notice a machine has stopped tracking its own edits.
@test "neither config is a chezmoi template" {
	[ ! -e "$SRC/dot_config/ghostty/config.tmpl" ]
	[ ! -e "$SRC/private_Library/private_Application Support/Code/User/settings.json.tmpl" ]
	[ -f "$SRC/dot_config/ghostty/config" ]
	[ -f "$SRC/private_Library/private_Application Support/Code/User/settings.json" ]
}
