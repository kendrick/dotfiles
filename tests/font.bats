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

keys_in_order() {
	jq -r 'to_entries | sort_by(.value.order) | .[].key' "$HOME/.config/font/registry.json"
}

@test "lists the roster in order and marks the active font" {
	run font
	[ "$status" -eq 0 ]
	# Compared against the registry rather than a hardcoded list, so adding a font
	# extends this test instead of breaking it.
	expected=$(keys_in_order)
	# Drop the two-column active marker before reading the key, so the active row
	# and the inactive ones parse the same way.
	listed=$(echo "$output" | grep '^[* ] ' | cut -c3- | awk '{print $1}')
	[ "$listed" = "$expected" ]
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
@test "round-tripping the whole roster restores both files byte for byte" {
	font fantasque
	cp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.start"
	cp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.start"

	for key in $(keys_in_order); do
		run font "$key"
		[ "$status" -eq 0 ]
	done
	font fantasque

	cmp "$GHOSTTY" "$BATS_TEST_TMPDIR/ghostty.start"
	cmp "$VSCODE" "$BATS_TEST_TMPDIR/vscode.start"
}

# Ghostty takes one font-feature per line, so a multi-tag family is where a
# comma would leak through as a literal and the whole string go inert.
@test "writes one Ghostty font-feature line per tag" {
	run font monaspace
	[ "$status" -eq 0 ]
	expected=$(jq -r '.monaspace.terminal.features | split(",") | length' "$HOME/.config/font/registry.json")
	[ "$(grep -c '^font-feature = ' "$GHOSTTY")" -eq "$expected" ]
	! grep -q '^font-feature = .*,' "$GHOSTTY"
}

@test "switching writes the editor axes and the terminal family too" {
	run font recursive
	[ "$status" -eq 0 ]
	grep -q "\"editor.fontVariations\": \"$(jq -r '.recursive.editor.variations' "$HOME/.config/font/registry.json")\"" "$VSCODE"
	grep -q "\"terminal.integrated.fontFamily\": \"$(jq -r '.recursive.editor.terminalFamily' "$HOME/.config/font/registry.json")\"" "$VSCODE"
}

# The asymmetry reads as a bug to anyone seeing it cold, so it gets asserted
# rather than left to chance. The patcher can't round-trip fvar/gvar, which makes
# the editor's variable build and the terminal's patched static genuinely
# different fonts.
@test "a Tier B key leaves the editor and the terminal on different families" {
	run font maple
	[ "$status" -eq 0 ]
	editor=$(jq -r '.maple.editor.family' "$HOME/.config/font/registry.json")
	terminal=$(jq -r '.maple.editor.terminalFamily' "$HOME/.config/font/registry.json")
	[ "$editor" != "$terminal" ]
	grep -qF "\"editor.fontFamily\": \"$editor\"" "$VSCODE"
	grep -qF "\"terminal.integrated.fontFamily\": \"$terminal\"" "$VSCODE"
}

# Losing the variable axes costs glyph coverage, since the patch is where the
# icons came from. Every Tier B editor entry has to name the symbols family to
# get them back.
@test "every Tier B editor entry falls back to the symbols family" {
	# An entry whose editor chain leads with its own terminal family is Tier A,
	# one font serving both halves, and needs no fallback.
	run jq -e '
		to_entries
		| map(select(.value.editor as $e | ($e.family | contains($e.terminalFamily)) | not))
		| all(.value.editor.family | test("Symbols Nerd Font Mono"))
	' "$HOME/.config/font/registry.json"
	[ "$status" -eq 0 ]
}

@test "every entry carries the fields the switcher reads" {
	run jq -e '
		to_entries | all(
			(.value.order | type == "number")
			and (.value.tier | test("^[abc]$"))
			and (.value.label | length > 0)
			and (.value.size | type == "number")
			and (.value.terminal.family | length > 0)
			and (.value.terminal.features | length > 0)
			and (.value.editor.family | length > 0)
			and (.value.editor.ligatures | length > 0)
			and (.value.editor | has("variations"))
			and (.value.editor.terminalFamily | length > 0)
		)
	' "$HOME/.config/font/registry.json"
	[ "$status" -eq 0 ]
}

# order drives the list, so a collision makes the roster reshuffle depending on
# whatever order jq happened to hand back.
@test "no two entries share an order" {
	run jq -e '[.[].order] | (length == (unique | length))' "$HOME/.config/font/registry.json"
	[ "$status" -eq 0 ]
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

<<<<<<< HEAD
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

# The registry is meant to be the only place a family name appears. Reading the
# names out of the registry rather than listing them here means adding a font
# can't quietly shrink what this test covers.
@test "no family name appears outside the registry" {
	# The editor value is a whole fallback chain, so it gets split into the
	# individual families before matching. Without the split, only an exact copy
	# of the entire chain would ever trip this.
	# Spelled as an if/return rather than `! grep`, because bash exempts a
	# negated command from errexit and the loop would run to completion
	# reporting success no matter what it found.
	while IFS= read -r family; do
		if grep -qF "$family" "$SCRIPT"; then
			echo "family name '$family' appears in $SCRIPT" >&2
			return 1
		fi
	done < <(jq -r '.[] | .terminal.family, .editor.terminalFamily, (.editor.family | split(", ")[])' \
		"$HOME/.config/font/registry.json" | tr -d "\047" | sort -u)
}

# The switcher writes by anchor, and an anchor matching zero times is a hard
# error, so a registry field naming a key the settings file doesn't have breaks
# every invocation rather than degrading. Deleting any of these from the settings
# file takes the whole switcher down with it.
@test "the settings file carries every key the switcher writes" {
	settings="$SRC/private_Library/private_Application Support/Code/User/settings.json"
	for key in editor.fontFamily editor.fontLigatures editor.fontVariations \
		terminal.integrated.fontFamily terminal.integrated.fontSize; do
		[ "$(grep -cE "^[[:space:]]*\"${key//./\\.}\"[[:space:]]*:" "$settings")" -eq 1 ]
	done
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
