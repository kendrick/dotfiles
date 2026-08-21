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

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/dot_local/bin/executable_dotfiles-doctor"

# Resolved before setup() puts the stub dir on PATH, so the last test can reach the real
# binary to render the repo's own templates.
REAL_CHEZMOI="$(command -v chezmoi)"

# Same capture-before-stub idiom, for the one case that has to narrow PATH far enough to
# hide a tool that is genuinely installed. Guarded the way helpers.bash guards its own
# captures: `load` runs under errexit, so an unguarded miss here would abort every case in
# the file before one of them ran.
REAL_JQ="$(command -v jq || true)"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export FIXTURE="$BATS_TEST_TMPDIR/src"
	mkdir -p "$HOME" "$STUBS" "$FIXTURE/dot_config/font"
	# Otherwise chezmoi resolves its config out of the real ~/.config no matter where
	# $HOME points, the same reason font.bats and packages.bats unset these.
	unset XDG_CONFIG_HOME XDG_CACHE_HOME

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

app_store_section() {
	bash "$SCRIPT" 2>&1 | sed -n '/== App Store ==/,/^$/p'
}

# `mas list` prints "<id>  <Name>  (<version>)". Only the id column is read, but the stub
# emits the whole shape so a change to which column gets parsed fails here rather than
# passing against a stub that was already reduced to the convenient answer.
#
# Called with no arguments this is a machine with nothing from the App Store on it, which
# is still a mas that runs — distinct from the no-mas-at-all case below.
stub_mas() {
	{
		printf '#!/usr/bin/env bash\n'
		printf 'case "$1" in\nlist)\n'
		local entry
		for entry in "$@"; do
			printf '  echo "%s"\n' "$entry"
		done
		printf '  ;;\nesac\n'
	} >"$STUBS/mas"
	chmod +x "$STUBS/mas"
}

write_mas_packages() {
	cat >"$FIXTURE/packages.json"
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
	assert_contains "in a bundle you've enabled but not installed"
	assert_contains "fixture-missing-formula"
}

# ---- App Store (mas) ----
#
# The registry's third package type, which the doctor read neither half of until #24. A
# missing menu-bar utility is the self-concealing kind of gap: an uninstalled formula
# announces itself the next time you reach for it, while "I thought I had that on this
# machine" is not a thought that reliably arrives.

@test "doctor: a tracked mas app that isn't installed is reported" {
	write_bundles core
	write_mas_packages <<'JSON'
[{"name": "Hidden Bar", "type": "mas", "id": 1452453066, "bundles": ["core"]}]
JSON
	stub_mas

	run app_store_section

	[ "$status" -eq 0 ]
	assert_contains "Hidden Bar"
	assert_contains "1452453066"
}

@test "doctor: a tracked mas app that is installed is not reported" {
	write_bundles core
	write_mas_packages <<'JSON'
[{"name": "Hidden Bar", "type": "mas", "id": 1452453066, "bundles": ["core"]}]
JSON
	stub_mas "1452453066  Hidden Bar  (1.9)"

	run app_store_section

	[ "$status" -eq 0 ]
	assert_not_contains "Hidden Bar"
}

# The decision on #24: this machine tracks 2 App Store apps and has 12, and the other 10
# are GarageBand, Keynote and friends that shipped with macOS. Reporting them would push
# every machine toward carrying the same App Store set, which is the opposite of what
# bundles are for. The Homebrew section reports both directions; this one deliberately
# does not, and this case is what says so.
@test "doctor: an installed mas app nobody tracks is not reported" {
	write_bundles core
	write_mas_packages <<'JSON'
[]
JSON
	stub_mas "408981434  iMovie  (10.4)" "682658836  GarageBand  (10.4)"

	run app_store_section

	[ "$status" -eq 0 ]
	assert_not_contains "iMovie"
	assert_not_contains "GarageBand"
}

@test "doctor: a mas app in a bundle this machine hasn't enabled is not reported" {
	write_bundles core
	write_mas_packages <<'JSON'
[{"name": "Presentify", "type": "mas", "id": 1507246666, "bundles": ["media"]}]
JSON
	stub_mas

	run app_store_section

	[ "$status" -eq 0 ]
	assert_not_contains "Presentify"
}

# App Store display names change under you, and "Hidden Bar" carries a space, so the id is
# the half worth matching on. Same id, renamed app: installed, and must stay quiet.
@test "doctor: a mas app is matched on id, not on display name" {
	write_bundles core
	write_mas_packages <<'JSON'
[{"name": "Hidden Bar", "type": "mas", "id": 1452453066, "bundles": ["core"]}]
JSON
	stub_mas "1452453066  Hidden Bar 2  (2.0)"

	run app_store_section

	[ "$status" -eq 0 ]
	# The heading prints either way, the way the Homebrew section's does, so the id is what
	# says whether this entry was reported: it appears only on a line naming a missing app.
	assert_not_contains "1452453066"
}

# The mirror of the case above: a different app whose display name happens to match is not
# the tracked one, so the tracked one is still missing.
@test "doctor: a matching name under a different id does not satisfy the entry" {
	write_bundles core
	write_mas_packages <<'JSON'
[{"name": "Hidden Bar", "type": "mas", "id": 1452453066, "bundles": ["core"]}]
JSON
	stub_mas "9999999999  Hidden Bar  (1.0)"

	run app_store_section

	[ "$status" -eq 0 ]
	assert_contains "1452453066"
}

# Read-only tool: a machine without mas gets a skip line naming it, not a failure. mas
# rides in the core bundle so it is normally present, which is exactly why the absent
# case needs a test rather than an assumption.
@test "doctor: skips rather than dies when mas is not installed" {
	write_bundles core
	write_mas_packages <<'JSON'
[{"name": "Hidden Bar", "type": "mas", "id": 1452453066, "bundles": ["core"]}]
JSON
	# Removing the stub is not enough. setup() appends the inherited PATH rather than
	# replacing it, and mas really is installed on a machine that tracks App Store apps, so
	# the real binary would answer and this case would quietly assert the opposite of what
	# it says. Narrow PATH to the stubs plus a directory holding only jq, which this section
	# needs and nothing here stubs.
	local only_jq="$BATS_TEST_TMPDIR/only-jq"
	mkdir -p "$only_jq"
	ln -sf "$REAL_JQ" "$only_jq/jq"
	rm -f "$STUBS/mas"
	PATH="$STUBS:$only_jq:/usr/bin:/bin"

	run app_store_section

	[ "$status" -eq 0 ]
	assert_contains "mas"
	assert_not_contains "1452453066"
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
	assert_contains "none"
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
	assert_contains "maple"
	assert_contains "editor"
	assert_contains "font-maple-mono"
	assert_contains "font-symbols-only-nerd-font"
	# The half that's satisfied must not be reported, or the section stops distinguishing
	# a real gap from a fully-declared entry.
	assert_not_contains "terminal"
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
	assert_contains "font-victor-mono-nerd-font"
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
	assert_contains "font-lilex"
	assert_not_contains "none"
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
	assert_contains "victor"
	assert_not_contains "none"
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
	assert_contains "none"
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
	assert_contains "cascadia"
	assert_not_contains "none"
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
	assert_contains "victor"
	# The suite's only disjunction, and so the one assertion the helpers can't
	# express — they take a single needle. `case` is the hand-written stand-in
	# because its failure propagates from any position, which a bare `[[ ]]` here
	# would not (tests/helpers.bash). Keep both arms: whichever one the doctor's
	# wording happens to match today isn't the contract, and dropping the other
	# narrows the assertion without turning anything red. tests/mutation-check.sh
	# finds this block by these two needles rather than by line number, so
	# renaming one means editing the harness in the same breath.
	case "$output" in
	*undeclared* | *casks*) ;;
	*) return 1 ;;
	esac
}

@test "skips rather than dies when there is no registry to read" {
	write_packages "font-victor-mono-nerd-font"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	assert_contains "skipping"
}

# The regression guard, and the reason the fixtures above aren't the whole file: it runs
# against the real registry and the real package data, so a roster entry added later without
# a cask declaration, or filed into a bundle no role enables, fails here rather than on
# someone's fresh machine.
@test "the repo's own font registry and package registry agree" {
	unset FIXTURE
	# --source alone isn't enough here, unlike everywhere else that reaches the real
	# binary. The section under test narrows tracked casks to the bundles this machine
	# has enabled, and `bundles` derives those from config data, not from the source
	# tree: under the synthetic $HOME there's no config, machine_role is absent, and
	# the template's documented fallback to core alone excludes the fonts bundle every
	# roster cask is filed in — so all of them read as gaps and the "none" below never
	# prints. Pinning the role supplies that data without coupling the case to whatever
	# this machine's real chezmoi.toml happens to say. work is deliberately the widest
	# role, so a cask filed into a bundle no role enables still fails here, which is
	# the regression this case exists to catch.
	local cfg="$BATS_TEST_TMPDIR/role.toml"
	printf '[data]\n  machine_role = "work"\n' >"$cfg"
	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path) echo "$SRC" ;;
status) : ;;
execute-template) exec "$REAL_CHEZMOI" execute-template --source "$SRC" --config "$cfg" "\$2" ;;
esac
STUB
	chmod +x "$STUBS/chezmoi"
	run deps_section
	[ "$status" -eq 0 ]
	assert_contains "none"
}
