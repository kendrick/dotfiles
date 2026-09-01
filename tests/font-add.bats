#!/usr/bin/env bats
#
# `font --add`/`--remove` (issue #15) trade a seven-step manual gauntlet for a
# script that refuses on its own. Every trap the issue names — cask names that
# don't track family names, a family diff that has to run before/after rather
# than being guessed, a ligature verdict that is wrong in both directions
# taken alone — gets its own case here, driven against synthetic fixtures
# rather than real fonts so a refusal is provable without betting on what
# happens to be installed on whatever machine runs the suite.
#
# `font-inspect` is never stubbed: the real inspector runs against
# `build-font-fixture.py` output, because the whole point of the fixture
# builder is giving that inspector real sfnt bytes to read ligature evidence
# out of. `brew`, `system_profiler`, and `chezmoi` are stubbed, because those
# are the three things this suite must never touch for real.

load 'helpers'

SCRIPT="${BATS_TEST_DIRNAME}/../dot_local/bin/executable_font"
SRC="${BATS_TEST_DIRNAME}/.."

# Captured before setup() puts $STUBS ahead of it on PATH, same reasoning as
# tests/settings-normalize.bats:25-27: the fixture builder needs a real
# interpreter, and this is the last point PATH is guaranteed to resolve one.
REAL_PYTHON3="$(command -v python3 || true)"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	# Set on this machine, and they would send the script straight back to the
	# real ~/.config and ~/.cache no matter what HOME says.
	unset XDG_CONFIG_HOME
	unset XDG_CACHE_HOME
	VSCODE="$HOME/Library/Application Support/Code/User/settings.json"
	GHOSTTY="$HOME/.config/ghostty/config"
	# --add/--remove write into the chezmoi *source* tree, a separate copy from
	# the live registry above — the switcher's own comment calls this out as
	# the opposite direction from write_ghostty/write_vscode_key. Every
	# "written" assertion below reads these two, never the live registry.
	SOURCE_TREE="$HOME/src"
	REGISTRY_SRC="$SOURCE_TREE/dot_config/font/registry.json"
	TOML_SRC="$SOURCE_TREE/.chezmoidata.toml"

	mkdir -p "$HOME/.config/font" "$HOME/.config/ghostty" "$(dirname "$VSCODE")" "$STUBS"
	cp "$SRC/dot_config/font/registry.json" "$HOME/.config/font/registry.json"
	cp "$SRC/dot_config/font/jsonc.jq" "$HOME/.config/font/jsonc.jq"
	cp "$SRC/dot_config/ghostty/config" "$GHOSTTY"
	cp "$SRC/private_Library/private_Application Support/Code/User/settings.json" "$VSCODE"

	# The real inspector, not a stub. Every fixture built below exists so this
	# binary has real ligature evidence to read, positive or absent.
	cp "$SRC/dot_local/bin/executable_font-inspect" "$STUBS/font-inspect"
	chmod +x "$STUBS/font-inspect"

	# A real git repo, seeded with the same two files `chezmoi source-path`
	# would hand back on a real machine, so `show_diff`'s `git diff` has real
	# history to compare against rather than a directory that was never a repo.
	mkdir -p "$(dirname "$REGISTRY_SRC")"
	cp "$SRC/dot_config/font/registry.json" "$REGISTRY_SRC"
	cp "$SRC/.chezmoidata.toml" "$TOML_SRC"
	git -C "$SOURCE_TREE" init --quiet
	git -C "$SOURCE_TREE" -c user.email=test@test.example -c user.name=test add -A
	git -C "$SOURCE_TREE" -c user.email=test@test.example -c user.name=test commit --quiet -m seed

	# source-path answers into the repo above; apply/re-add are logged no-ops,
	# because a real apply would need a real destination this suite has no
	# business writing to.
	cat >"$STUBS/chezmoi" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/chezmoi-calls"
		case "$1" in
		source-path) echo "$HOME/src" ;;
		esac
		exit 0
	STUB
	chmod +x "$STUBS/chezmoi"

	# Serves both forms `font` and `font-inspect` make of it. The text form
	# (snapshot_families, the before/after diff) synthesizes Family: lines from
	# $HOME/installed-families, which `brew install`/`uninstall` below mutate.
	# The -json form (font-inspect's resolve_family) maps a family to fixture
	# files from $HOME/family-paths, a table that stays fixed all test long —
	# it answers "where would this family's files live", not "is it installed".
	cat >"$STUBS/system_profiler" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/system_profiler-calls"
		case "$*" in
		*-json*)
			python3 -c '
import json, os, sys
entries = []
path = os.path.join(os.environ["HOME"], "family-paths")
if os.path.exists(path):
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            family, filepath = line.split("\t", 1)
            entries.append({"path": filepath, "typefaces": [{"family": family}]})
json.dump({"SPFontsDataType": entries}, sys.stdout)
'
			;;
		*)
			echo "Fonts:"
			while IFS= read -r family; do
				printf '    Stub.ttf:\n      Typefaces:\n        Stub:\n          Family: %s\n' "$family"
			done <"$HOME/installed-families"
			;;
		esac
	STUB
	chmod +x "$STUBS/system_profiler"

	# info/list answer from two flat name lists; install/uninstall move a
	# cask's declared families (from $HOME/cask-families/<cask>) into or out of
	# $HOME/installed-families, which is the file the family diff actually
	# reads. Every call is logged, which is how the "nothing installed"/
	# "uninstalled again" cases prove themselves from outside.
	cat >"$STUBS/brew" <<-'STUB'
		#!/usr/bin/env bash
		printf '%s\n' "$*" >>"$HOME/brew-calls"
		case "$1" in
		info)
			grep -qxF "$3" "$HOME/known-casks" 2>/dev/null
			exit $?
			;;
		list)
			grep -qxF "$3" "$HOME/installed-casks" 2>/dev/null
			exit $?
			;;
		install)
			famfile="$HOME/cask-families/$3"
			if [ -f "$famfile" ]; then
				cat "$famfile" >>"$HOME/installed-families"
				sort -u -o "$HOME/installed-families" "$HOME/installed-families"
			fi
			printf '%s\n' "$3" >>"$HOME/installed-casks"
			exit 0
			;;
		uninstall)
			famfile="$HOME/cask-families/$3"
			if [ -f "$famfile" ]; then
				grep -vxFf "$famfile" "$HOME/installed-families" >"$HOME/installed-families.tmp" 2>/dev/null
				mv "$HOME/installed-families.tmp" "$HOME/installed-families"
			fi
			grep -vxF "$3" "$HOME/installed-casks" >"$HOME/installed-casks.tmp" 2>/dev/null
			mv "$HOME/installed-casks.tmp" "$HOME/installed-casks"
			exit 0
			;;
		esac
		exit 1
	STUB
	chmod +x "$STUBS/brew"

	export PATH="$STUBS:$PATH"

	# Derived from the registry rather than hardcoded, same reasoning as
	# font.bats: widening the roster shouldn't leave this stub answering for a
	# roster that no longer exists.
	jq -r '.[].terminal.family' "$HOME/.config/font/registry.json" >"$HOME/installed-families"
	mkdir -p "$HOME/.cache/font"
	sort -u "$HOME/installed-families" >"$HOME/.cache/font/families"

	: >"$HOME/known-casks"
	: >"$HOME/installed-casks"
	: >"$HOME/family-paths"
	mkdir -p "$HOME/cask-families" "$BATS_TEST_TMPDIR/fonts"

	build_all_fixtures
}

font() {
	bash "$SCRIPT" "$@"
}

fx() {
	printf '%s' "$BATS_TEST_TMPDIR/fonts/$1.ttf"
}

build_fixture() {
	local out="$1"
	shift
	"$REAL_PYTHON3" "$SRC/tests/support/build-font-fixture.py" "$out" "$@"
}

register_family() {
	printf '%s\t%s\n' "$1" "$2" >>"$HOME/family-paths"
}

mark_known_cask() {
	printf '%s\n' "$1" >>"$HOME/known-casks"
}

mark_installed_cask() {
	printf '%s\n' "$1" >>"$HOME/installed-casks"
}

# One cask's worth of families, ready for `brew install` to register: marks
# the cask known and writes its family list, one per line, for the stub's
# install branch to fold into $HOME/installed-families.
declare_cask() {
	local cask="$1"
	shift
	mark_known_cask "$cask"
	printf '%s\n' "$@" >"$HOME/cask-families/$cask"
}

snapshot_source() {
	cp "$REGISTRY_SRC" "$BATS_TEST_TMPDIR/registry.before"
	cp "$TOML_SRC" "$BATS_TEST_TMPDIR/toml.before"
}

assert_source_unchanged() {
	cmp "$REGISTRY_SRC" "$BATS_TEST_TMPDIR/registry.before"
	cmp "$TOML_SRC" "$BATS_TEST_TMPDIR/toml.before"
}

# Every fixture this file's cases need, built fresh per test rather than
# shared, so one test's cask-family bookkeeping can never leak into another's.
# Each one dials in exactly the evidence its case needs and nothing else —
# see build-font-fixture.py's own docstring for why that CLI exists at all.
build_all_fixtures() {
	# All three signals absent: the general "nothing here at all" refusal.
	build_fixture "$(fx refuse)" --family 'Refuse Test Face'
	register_family 'Refuse Test Face' "$(fx refuse)"
	declare_cask font-refuse-test 'Refuse Test Face'

	# BlexMono Nerd Font's own shape: real LigatureSubst rules (they hang off
	# frac/ccmp in the real font) with no ligature feature tag at all. Counting
	# rules alone would admit this; decide() must not.
	build_fixture "$(fx blexmono-trap)" --family 'BlexTrap Test Face' --liga-rules 5
	register_family 'BlexTrap Test Face' "$(fx blexmono-trap)"
	declare_cask font-blexmono-trap-test 'BlexTrap Test Face'

	# One cask, two families — Monaspace's own shape (issue #15's Ar/Kr/Ne/Rn/Xe
	# example, shrunk to two). Both pass on their own so picking either is a
	# clean success, which is what isolates the family-choice behavior from the
	# ligature-verdict behavior.
	build_fixture "$(fx multi-alpha)" --family 'MultiFace Alpha' --gsub-tags calt --liga-rules 2
	register_family 'MultiFace Alpha' "$(fx multi-alpha)"
	build_fixture "$(fx multi-beta)" --family 'MultiFace Beta' --gsub-tags calt --liga-rules 2
	register_family 'MultiFace Beta' "$(fx multi-beta)"
	declare_cask font-multi-test 'MultiFace Alpha' 'MultiFace Beta'

	# Passes, no Nerd Font codepoints planted: needs the Symbols fallback.
	build_fixture "$(fx partial)" --family 'PartialCoverage Test Face' --gsub-tags calt --liga-rules 2
	register_family 'PartialCoverage Test Face' "$(fx partial)"
	declare_cask font-partial-test 'PartialCoverage Test Face'

	# Same evidence, full icon coverage: no fallback needed.
	build_fixture "$(fx full)" --family 'FullCoverage Test Face' --gsub-tags calt --liga-rules 2 --nerd full
	register_family 'FullCoverage Test Face' "$(fx full)"
	declare_cask font-full-test 'FullCoverage Test Face'

	# Two stylistic sets, one of them nameless — Cascadia's own shape, and the
	# case that would crash a renderer that assumes every set has a UI name.
	build_fixture "$(fx stylistic)" --family 'Stylistic Test Face' --gsub-tags calt --liga-rules 2 \
		--ss 'ss01:Cool Ligatures' --ss 'ss02:'
	register_family 'Stylistic Test Face' "$(fx stylistic)"
	declare_cask font-stylistic-test 'Stylistic Test Face'

	# --inspect's two entry points: a path needs no cask or registration at
	# all, a family name needs only the -json resolution table.
	build_fixture "$(fx inspect-path)" --family 'InspectPath Test Face' --gsub-tags calt --liga-rules 1
	build_fixture "$(fx inspect-family)" --family 'InspectFamily Test Face' --gsub-tags calt --liga-rules 1
	register_family 'InspectFamily Test Face' "$(fx inspect-family)"

	# Already on the machine, for the "already installed" refusal — never
	# inspected, so it needs no fixture of its own.
	mark_known_cask font-preinstalled-test
	mark_installed_cask font-preinstalled-test
}

@test "an unknown cask exits non-zero, installs nothing, and leaves both files untouched" {
	snapshot_source
	run font --add font-does-not-exist-test
	[ "$status" -ne 0 ]
	assert_contains "not a known cask"
	assert_not_contains "install --cask" "$(cat "$HOME/brew-calls")"
	assert_source_unchanged
}

@test "a cask already installed is refused before anything is touched" {
	run font --add font-preinstalled-test
	[ "$status" -ne 0 ]
	assert_contains "already installed"
}

@test "a cask already declared in the registry is refused" {
	# font-maple-mono-nf is the maple entry's own terminal cask, already in the
	# seeded registry — no fixture needed, this refusal fires before any file
	# is ever inspected.
	mark_known_cask font-maple-mono-nf
	run font --add font-maple-mono-nf
	[ "$status" -ne 0 ]
	assert_contains "already declared in the registry"
}

@test "a multi-family cask with no --family and no tty lists every new family, undoes the install, and writes nothing" {
	snapshot_source
	run font --add font-multi-test
	[ "$status" -ne 0 ]
	assert_contains "MultiFace Alpha"
	assert_contains "MultiFace Beta"
	assert_contains "no terminal to prompt"
	assert_contains "uninstall --cask font-multi-test" "$(cat "$HOME/brew-calls")"
	assert_source_unchanged
}

@test "the same multi-family cask with --family records exactly the named family" {
	run font --add font-multi-test --family "MultiFace Beta"
	[ "$status" -eq 0 ]
	[ "$(jq -r '.["multi-test"].terminal.family' "$REGISTRY_SRC")" = "MultiFace Beta" ]
}

@test "a font with no ligature evidence at all is refused, names every signal, and is uninstalled" {
	snapshot_source
	run font --add font-refuse-test
	[ "$status" -ne 0 ]
	assert_contains "tags: (none)"
	assert_contains "ligature_subst_rules: 0"
	assert_contains "glyph_names:"
	assert_contains "no ligature evidence across tags, substitution rules, or glyph names"
	assert_contains "uninstall --cask font-refuse-test" "$(cat "$HOME/brew-calls")"
	assert_source_unchanged
}

# BlexMono Nerd Font reached the roster on reputation and turned out to carry
# 47 real LigatureSubst rules with no ligature feature at all — they hang off
# frac and ccmp, compositions every text font has. Counting rules alone would
# have admitted it; a tag is necessary and never sufficient, so --liga-rules
# with no --gsub-tags has to refuse just as hard as zero evidence does.
@test "ligature rules with no feature tag still refuse, the BlexMono trap" {
	run font --add font-blexmono-trap-test
	[ "$status" -ne 0 ]
	assert_contains "tags: (none)"
	assert_contains "ligature_subst_rules: 5"
}

@test "partial icon coverage adds a Symbols Nerd Font Mono fallback to the terminal entry and both editor chains" {
	run font --add font-partial-test
	[ "$status" -eq 0 ]
	[ "$(jq -r '.["partial-test"].terminal.fallback' "$REGISTRY_SRC")" = "Symbols Nerd Font Mono" ]
	assert_contains "Symbols Nerd Font Mono" "$(jq -r '.["partial-test"].editor.family' "$REGISTRY_SRC")"
	[ "$(jq -r '.["partial-test"].editor.terminalFamily' "$REGISTRY_SRC")" = "'PartialCoverage Test Face', 'Symbols Nerd Font Mono'" ]
}

@test "full icon coverage writes no fallback key at all" {
	run font --add font-full-test
	[ "$status" -eq 0 ]
	run jq -e '.["full-test"].terminal | has("fallback") | not' "$REGISTRY_SRC"
	[ "$status" -eq 0 ]
}

@test "stylistic set names print, including one with no name, and neither reaches the feature strings without --set" {
	run font --add font-stylistic-test
	[ "$status" -eq 0 ]
	assert_contains "ss01: Cool Ligatures"
	assert_contains "ss02: (no name)"
	assert_not_contains "ss01" "$(jq -r '.["stylistic-test"].terminal.features' "$REGISTRY_SRC")"
	assert_not_contains "ss01" "$(jq -r '.["stylistic-test"].editor.ligatures' "$REGISTRY_SRC")"
}

@test "--set enables exactly the named stylistic set in both feature strings" {
	run font --add font-stylistic-test --set ss01
	[ "$status" -eq 0 ]
	assert_contains "ss01" "$(jq -r '.["stylistic-test"].terminal.features' "$REGISTRY_SRC")"
	assert_contains "'ss01'" "$(jq -r '.["stylistic-test"].editor.ligatures' "$REGISTRY_SRC")"
	assert_not_contains "ss02" "$(jq -r '.["stylistic-test"].terminal.features' "$REGISTRY_SRC")"
}

@test "the written registry still parses and the new entry carries every field the switcher reads" {
	run font --add font-partial-test
	[ "$status" -eq 0 ]
	run jq -e '
		.["partial-test"] |
		(.order | type == "number")
		and (.tier | test("^[abc]$"))
		and (.label | length > 0)
		and (.size | type == "number")
		and (.terminal.family | length > 0)
		and (.terminal.features | length > 0)
		and (.terminal.casks | type == "array")
		and (.editor.family | length > 0)
		and (.editor.casks | type == "array")
	' "$REGISTRY_SRC"
	[ "$status" -eq 0 ]
}

@test "the new package entry lands in the fonts group with its type column aligned to its neighbours" {
	run font --add font-partial-test
	[ "$status" -eq 0 ]
	inserted=$(grep -n 'font-partial-test' "$TOML_SRC" | cut -d: -f1)
	[ -n "$inserted" ]
	anchor=$(grep -n 'font-symbols-only-nerd-font' "$TOML_SRC" | cut -d: -f1)
	[ -n "$anchor" ]
	# Inserted right after the fonts group's last existing line, per the
	# script's own anchor comment — never at the whole array's tail.
	[ "$inserted" -eq "$((anchor + 1))" ]
	inserted_line=$(sed -n "${inserted}p" "$TOML_SRC")
	anchor_line=$(sed -n "${anchor}p" "$TOML_SRC")
	assert_contains 'bundles = ["fonts"] },' "$inserted_line"
	inserted_col=$(awk -v s="$inserted_line" 'BEGIN { print index(s, "type =") }')
	anchor_col=$(awk -v s="$anchor_line" 'BEGIN { print index(s, "type =") }')
	[ "$inserted_col" -eq "$anchor_col" ]
}

@test "--add shows a diff of both written files before it exits" {
	run font --add font-partial-test
	[ "$status" -eq 0 ]
	assert_contains "font: wrote registry entry 'partial-test':"
	assert_contains "font: wrote package entry for 'font-partial-test':"
	[ "$(printf '%s\n' "$output" | grep -c '^  +')" -gt 0 ]
}

@test "--remove of the active font exits non-zero and changes nothing" {
	# The committed Ghostty config's active family is DankMono Nerd Font,
	# exactly the dank entry's terminal.family — read out of the fixture
	# rather than hardcoded, so a future re-add doesn't silently break this.
	snapshot_source
	run font --remove dank
	[ "$status" -ne 0 ]
	assert_contains "active terminal font"
	assert_source_unchanged
	[ ! -f "$HOME/brew-calls" ]
}

@test "--remove of a non-active font drops its own casks but leaves one another entry still declares" {
	run font --remove maple
	[ "$status" -eq 0 ]
	run jq -e 'has("maple") | not' "$REGISTRY_SRC"
	[ "$status" -eq 0 ]
	assert_not_contains "font-maple-mono-nf" "$(cat "$TOML_SRC")"
	assert_not_contains "font-maple-mono\"" "$(cat "$TOML_SRC")"
	# font-symbols-only-nerd-font is also maple's, but half a dozen other
	# entries declare it too — it has to survive maple's removal intact.
	assert_contains "font-symbols-only-nerd-font" "$(cat "$TOML_SRC")"
	assert_contains "uninstall --cask font-maple-mono-nf" "$(cat "$HOME/brew-calls")"
	assert_contains "uninstall --cask font-maple-mono" "$(cat "$HOME/brew-calls")"
	assert_not_contains "uninstall --cask font-symbols-only-nerd-font" "$(cat "$HOME/brew-calls")"
}

@test "removing the last registry entry repairs the trailing comma and stays valid JSON" {
	# operator is the registry's last key. A trailing comma left behind on the
	# entry before it (monolisa) would make this fail on the parse alone, so
	# jq -e succeeding is itself the proof, not just the has() check it runs.
	run font --remove operator
	[ "$status" -eq 0 ]
	run jq -e 'has("operator") | not' "$REGISTRY_SRC"
	[ "$status" -eq 0 ]
}

@test "--rm behaves exactly like --remove" {
	run font --rm maple
	[ "$status" -eq 0 ]
	run jq -e 'has("maple") | not' "$REGISTRY_SRC"
	[ "$status" -eq 0 ]
	assert_contains "uninstall --cask font-maple-mono-nf" "$(cat "$HOME/brew-calls")"
}

@test "--inspect runs directly against a fixture path" {
	run font --inspect "$(fx inspect-path)"
	[ "$status" -eq 0 ]
	assert_contains "InspectPath Test Face"
	assert_contains "Verdict: PASS"
}

@test "--inspect resolves a stubbed family name to its files" {
	run font --inspect "InspectFamily Test Face"
	[ "$status" -eq 0 ]
	assert_contains "InspectFamily Test Face"
	assert_contains "Verdict: PASS"
}

@test "--add with no value dies" {
	run font --add
	[ "$status" -ne 0 ]
	assert_contains "--add needs a cask name"
}

@test "--add and --remove together are mutually exclusive" {
	run font --add font-partial-test --remove maple
	[ "$status" -ne 0 ]
	assert_contains "mutually exclusive"
}

@test "--family without --add dies" {
	run font --family "Some Family" victor
	[ "$status" -ne 0 ]
	assert_contains "only legal with --add"
}
