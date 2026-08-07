#!/usr/bin/env bats
#
# dotfiles-doctor reports; it never fixes. So the thing worth testing is whether it
# reports the gaps it exists to catch, and stays quiet when there aren't any — a doctor
# that cries wolf gets ignored, and one that misses the case it was written for is worse
# than not having it.
#
# The Config dependencies section is the one under test here. It's the answer to Fantasque
# going years undetected: the configs named a family, no font was tracked anywhere, and
# nothing in the older sections could see the gap because a hand-dropped font satisfies
# neither side of an installed-versus-tracked comparison.

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/dot_local/bin/executable_dotfiles-doctor"

# Resolved before setup() puts the stub dir on PATH, so the last test can reach the real
# binary to render the repo's own templates.
REAL_CHEZMOI="$(command -v chezmoi)"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export FIXTURE="$BATS_TEST_TMPDIR/src"
	mkdir -p "$HOME" "$STUBS" "$FIXTURE/dot_config/font"

	# The doctor asks chezmoi four things: where the source tree is, what's drifted, and since
	# packages became data, what the registry holds and which bundles this machine has on.
	# Answering all four from fixture files is the whole seam: every section then reads what
	# this test wrote rather than the repo it's running inside.
	cat >"$STUBS/chezmoi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
source-path) echo "$FIXTURE" ;;
status) : ;;
execute-template)
  case "$2" in
  *bundles*) cat "$FIXTURE/bundles.json" ;;
  *packages*) cat "$FIXTURE/packages.json" ;;
  esac
  ;;
esac
STUB

	# Reporting one extension that's also in the fixture list, rather than reporting none.
	# An empty list would make the section's `grep -v` exit 1 on a file with nothing to
	# match, and under `set -e` the script dies before it reaches the section under test.
	echo "fixture.extension" >"$FIXTURE/dot_config/vscode-extensions.txt"
	printf '#!/usr/bin/env bash\necho fixture.extension\n' >"$STUBS/code"

	# Nothing installed. The Homebrew section reads this through a while loop, which is
	# happy with no input at all.
	printf '#!/usr/bin/env bash\n:\n' >"$STUBS/brew"

	# Defaults the cases below override. Both files have to be valid JSON even for tests
	# that don't care, because the Homebrew section runs first and pipes them through jq.
	write_bundles fonts
	echo '[]' >"$FIXTURE/packages.json"

	chmod +x "$STUBS/chezmoi" "$STUBS/code" "$STUBS/brew"
	export PATH="$STUBS:$PATH"
}

# Only the section under test. The others have their own failure modes and would drown
# the assertion in noise.
deps_section() {
	bash "$SCRIPT" 2>&1 | sed -n '/== Config dependencies ==/,/^$/p'
}

# Same idea, for the Homebrew section instead of Config dependencies.
homebrew_section() {
	bash "$SCRIPT" 2>&1 | sed -n '/== Homebrew ==/,/^$/p'
}

# Casks in the fonts bundle, which is the shape every roster font has.
write_packages() {
	printf '%s\n' "$@" | jq -Rs 'split("\n") | map(select(length > 0))
		| map({name: ., type: "cask", bundles: ["fonts"]})' >"$FIXTURE/packages.json"
}

write_bundles() {
	printf '%s\n' "$@" | jq -Rs 'split("\n") | map(select(length > 0))' >"$FIXTURE/bundles.json"
}

write_registry() {
	cat >"$FIXTURE/dot_config/font/registry.json"
}

# The Homebrew section, not Config dependencies: a formula tracked in an enabled bundle
# that `brew list` doesn't return. The stubbed `brew` in setup() is `:`, so nothing ever
# reads as installed — the fixture only has to name a formula in the default "fonts"
# bundle to land in the missing branch.
@test "doctor: a tracked but uninstalled formula is reported" {
	jq -n '[{name: "fixture-missing-formula", type: "brew", bundles: ["fonts"]}]' \
		>"$FIXTURE/packages.json"
	run homebrew_section
	[ "$status" -eq 0 ]
	[[ "$output" == *"in a bundle you've enabled but not installed"* ]]
	[[ "$output" == *"fixture-missing-formula"* ]]
}

# A roster entry that declares one cask per half, used as the shape the failure cases
# deviate from one field at a time.
@test "says nothing when every declared cask is tracked" {
	write_packages "font-victor-mono-nerd-font"
	write_registry <<'JSON'
{
  "victor": {
    "tier": "a",
    "terminal": { "casks": ["font-victor-mono-nerd-font"] },
    "editor": { "casks": ["font-victor-mono-nerd-font"] }
  }
}
JSON
	run deps_section
	[ "$status" -eq 0 ]
	[[ "$output" == *"none"* ]]
}

@test "names the key, the half and the cask when the registry is missing one" {
	# The editor half's cask is absent while the terminal half's is present, which is the
	# realistic shape: Tier B needs a second cask for the variable build, and dropping it
	# breaks the editor while the terminal keeps working.
	write_packages "font-maple-mono-nf"
	write_registry <<'JSON'
{
  "maple": {
    "tier": "b",
    "terminal": { "casks": ["font-maple-mono-nf"] },
    "editor": { "casks": ["font-maple-mono", "font-symbols-only-nerd-font"] }
  }
}
JSON
	run deps_section
	[[ "$output" == *"maple"* ]]
	[[ "$output" == *"editor"* ]]
	[[ "$output" == *"font-maple-mono"* ]]
	[[ "$output" == *"font-symbols-only-nerd-font"* ]]
	# The half that's satisfied must not be reported, or the section stops distinguishing
	# a real gap from a fully-declared entry.
	[[ "$output" != *"terminal"* ]]
}

@test "a formula does not satisfy a cask dependency" {
	jq -n '[{name: "font-victor-mono-nerd-font", type: "brew", bundles: ["fonts"]}]' \
		>"$FIXTURE/packages.json"
	write_registry <<'JSON'
{
  "victor": {
    "tier": "a",
    "terminal": { "casks": ["font-victor-mono-nerd-font"] },
    "editor": { "casks": [] }
  }
}
JSON
	run deps_section
	[[ "$output" == *"font-victor-mono-nerd-font"* ]]
}

# The near misses in this roster are plausible enough to install without noticing, so a
# prefix match would report success on the wrong cask. font-lilex and font-lilex-nerd-font
# are different fonts serving different halves.
@test "matches the whole cask name, not a prefix of a longer one" {
	write_packages "font-lilex-nerd-font"
	write_registry <<'JSON'
{
  "lilex": {
    "tier": "b",
    "terminal": { "casks": ["font-lilex-nerd-font"] },
    "editor": { "casks": ["font-lilex"] }
  }
}
JSON
	run deps_section
	[[ "$output" == *"font-lilex"* ]]
	[[ "$output" != *"none"* ]]
}

# Bundles are what makes a tracked cask still not arrive. Filing a font into a bundle this
# machine hasn't enabled leaves the configs naming a family nothing will install, which is
# the same failure as never declaring it, so it has to read the same way.
@test "a cask in a bundle this machine hasn't enabled is a gap" {
	write_bundles "core"
	write_packages "font-victor-mono-nerd-font"
	write_registry <<'JSON'
{
  "victor": {
    "tier": "a",
    "terminal": { "casks": ["font-victor-mono-nerd-font"] },
    "editor": { "casks": ["font-victor-mono-nerd-font"] }
  }
}
JSON
	run deps_section
	[[ "$output" == *"victor"* ]]
	[[ "$output" != *"none"* ]]
}

@test "an empty list is fine on Tier C, which is fetched from 1Password" {
	write_packages "font-victor-mono-nerd-font"
	write_registry <<'JSON'
{
  "operator": {
    "tier": "c",
    "terminal": { "casks": [] },
    "editor": { "casks": [] }
  }
}
JSON
	run deps_section
	[[ "$output" == *"none"* ]]
}

# The distinction the empty list has to carry: on Tier C it's an answer, anywhere else
# it's a roster entry nobody said where to get.
@test "an empty list is a gap on a tier that installs from Homebrew" {
	write_packages "font-victor-mono-nerd-font"
	write_registry <<'JSON'
{
  "cascadia": {
    "tier": "b",
    "terminal": { "casks": [] },
    "editor": { "casks": ["font-cascadia-code"] }
  }
}
JSON
	run deps_section
	[[ "$output" == *"cascadia"* ]]
	[[ "$output" != *"none"* ]]
}

@test "a half with no casks key at all is reported as undeclared" {
	write_packages "font-victor-mono-nerd-font"
	write_registry <<'JSON'
{
  "victor": {
    "tier": "a",
    "terminal": { "family": "VictorMono Nerd Font" },
    "editor": { "casks": ["font-victor-mono-nerd-font"] }
  }
}
JSON
	run deps_section
	[[ "$output" == *"victor"* ]]
	[[ "$output" == *"undeclared"* || "$output" == *"casks"* ]]
}

@test "skips rather than dies when there is no registry to read" {
	write_packages "font-victor-mono-nerd-font"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[[ "$output" == *"skipping"* ]]
}

# The regression guard, and the reason the fixtures above aren't the whole file: it runs
# against the real registry and the real package data, so a roster entry added later without
# a cask declaration, or filed into a bundle no role enables, fails here rather than on
# someone's fresh machine.
@test "the repo's own font registry and package registry agree" {
	unset FIXTURE
	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path) echo "$SRC" ;;
status) : ;;
execute-template) exec "$REAL_CHEZMOI" execute-template --source "$SRC" "\$2" ;;
esac
STUB
	chmod +x "$STUBS/chezmoi"
	run deps_section
	[ "$status" -eq 0 ]
	[[ "$output" == *"none"* ]]
}
