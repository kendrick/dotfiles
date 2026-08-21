#!/usr/bin/env bats
#
# The package registry replaced a hand-maintained Brewfile with data plus a render, which
# trades one failure mode for another. The old file was checked by reading it. This one can
# be wrong in ways that look fine: a bundle name typo'd into a bundle nobody enables, a
# tapped formula whose tap sits in a bundle that's off, a render that indents a `tap` line
# far enough to slip past the installer's trust step. None of those raise an error. They
# just quietly install less than you asked for.
#
# So this file asserts the two halves separately: the data says what it has to say, and the
# render turns it into a Brewfile that `brew bundle` and the installer can both act on.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."

setup() {
	# Both can redirect chezmoi at another config or cache mid-run, which would make these
	# assertions describe a tree nobody asked about.
	unset XDG_CONFIG_HOME
	unset XDG_CACHE_HOME
}

pkg_json() {
	chezmoi execute-template --source "$SRC" '{{ .pkg | toJson }}'
}

# Renders the Brewfile as a machine with exactly these bundles would see it. Passing a
# config rather than relying on the machine's own is what lets one test cover three roles.
render_with() {
	local cfg="$BATS_TEST_TMPDIR/chezmoi.toml"
	{
		echo '[data]'
		echo "  machine_role = \"$1\""
		shift
		if [ "$#" -gt 0 ]; then
			printf '  bundles = ['
			printf '"%s",' "$@"
			printf ']\n'
		fi
	} >"$cfg"
	chezmoi execute-template --source "$SRC" --config "$cfg" '{{ template "Brewfile" . }}'
}

# ---- the data ----

@test "every package declares a name, a known type, and at least one bundle" {
	run bash -c "$(declare -f pkg_json); SRC='$SRC' pkg_json | jq -e '
		.packages | all(
			(.name | type == \"string\" and length > 0)
			and (.type | IN(\"brew\", \"cask\", \"mas\"))
			and (.bundles | type == \"array\" and length > 0))'"
	[ "$status" -eq 0 ]
}

# `mas` entries install by numeric id, not by name, so a missing or stringified id renders a
# line brew bundle can't act on. Nothing else takes an id, and one arriving on a brew entry
# means a line got edited into the wrong group.
@test "mas entries carry an integer id and no other type does" {
	run bash -c "$(declare -f pkg_json); SRC='$SRC' pkg_json | jq -e '
		.packages | all(
			if .type == \"mas\" then (.id | type == \"number\")
			else (has(\"id\") | not) end)'"
	[ "$status" -eq 0 ]
}

# A bundle name that isn't in the catalog is the silent failure this whole file exists for:
# no role enables it, so the package renders nowhere and nothing says why.
@test "every bundle a package or tap names is in the catalog" {
	run bash -c "$(declare -f pkg_json); SRC='$SRC' pkg_json | jq -e '
		. as \$p | [\$p.packages[], \$p.taps[]] | all(.bundles | all(IN(\$p.catalog[])))'"
	[ "$status" -eq 0 ]
}

@test "no package is declared twice" {
	run bash -c "$(declare -f pkg_json); SRC='$SRC' pkg_json | jq -e '
		.packages | map(\"\(.type)/\(.name)\") | (length == (unique | length))'"
	[ "$status" -eq 0 ]
}

# min_macos (#23) is optional — most entries have no OS floor at all — but an entry that
# does name one has to be a bare version string, or .chezmoitemplates/os-held hands it
# straight to semverCompare and takes every `chezmoi apply` on the machine down with it.
@test "min_macos, when present, is a non-empty version string" {
	run bash -c "$(declare -f pkg_json); SRC='$SRC' pkg_json | jq -r '
		.packages[] | select(has(\"min_macos\")) | .min_macos'"
	[ "$status" -eq 0 ]
	local v
	while IFS= read -r v; do
		[ -n "$v" ] || continue
		printf '%s' "$v" | grep -qE '^[0-9]+(\.[0-9]+)*$' || {
			echo "min_macos '$v' is not a bare version string" >&2
			return 1
		}
	done <<<"$output"
}

# Homebrew 6 won't load a formula from an untrusted tap, and the installer trusts exactly the
# taps the render emits. If a tapped formula's bundle is on while its tap's bundle is off, the
# formula renders with nothing to install it from and `brew bundle` gives up at that line.
@test "every tapped formula's tap is enabled wherever the formula is" {
	run bash -c "$(declare -f pkg_json); SRC='$SRC' pkg_json | jq -e '
		. as \$p | \$p.packages | map(select(.name | contains(\"/\"))) | all(
			(.name | split(\"/\")[0:2] | join(\"/\")) as \$tap
			| .bundles as \$need
			| \$p.taps | any(.name == \$tap and (.bundles as \$have | \$need | all(IN(\$have[]))))
		)'"
	[ "$status" -eq 0 ]
}

# ---- the render ----

# run_onchange_install-packages.sh.tmpl finds taps with `awk '/^tap /'` to run `brew trust`
# before bundling. An indented tap line matches nothing, the tap goes untrusted, and bundle
# silently drops every formula that needed it.
@test "taps render first, contiguously, at column zero" {
	run render_with work
	[ "$status" -eq 0 ]
	local taps
	taps="$(grep -c '^tap "' <<<"$output")"
	[ "$taps" -gt 0 ]
	# The tap block is the head of the file: the first non-tap line ends it for good.
	[ "$(head -n "$taps" <<<"$output" | grep -c '^tap "')" -eq "$taps" ]
	[ "$(grep -c '^[[:space:]]' <<<"$output")" -eq 0 ]
}

@test "the trust step still finds every tap the render emits" {
	run render_with work
	[ "$(awk '/^tap /{gsub(/"/,"",$2); print $2}' <<<"$output" | wc -l | tr -d ' ')" \
		-eq "$(grep -c '^tap "' <<<"$output")" ]
}

@test "a package in a bundle you haven't enabled renders nowhere" {
	run render_with work core
	[ "$status" -eq 0 ]
	assert_contains 'brew "age"'
	# Both halves matter: cloud off means no databricks, and no databricks tap either.
	assert_not_contains "databricks"
	assert_not_contains "font-lilex"
}

# The guard on resolving bundles with `hasKey` rather than `default`. An empty list is falsy
# in Go templates, so the obvious spelling would hand this machine the whole role default
# back and install nine bundles' worth of apps it explicitly asked for none of.
@test "an empty bundle list renders an empty Brewfile" {
	local cfg="$BATS_TEST_TMPDIR/empty.toml"
	printf '[data]\n  machine_role = "work"\n  bundles = []\n' >"$cfg"
	run chezmoi execute-template --source "$SRC" --config "$cfg" '{{ template "Brewfile" . }}'
	[ "$status" -eq 0 ]
	[ "$(grep -cE '^(tap|brew|cask|mas) ' <<<"$output")" -eq 0 ]
}

# The role-level form of the Config dependencies check in dotfiles-doctor, which can only
# ever speak for the machine it runs on. Fonts are ungated because a client machine wants
# readable code too, and this is what holds that true: move the fonts bundle out of any
# role's defaults and every role fails here at once.
@test "every role installs every font the roster names" {
	local casks
	casks="$(jq -r '.[] | (.terminal.casks // [])[], (.editor.casks // [])[]' \
		"$SRC/dot_config/font/registry.json" | sort -u)"
	for role in work client personal; do
		local rendered
		rendered="$(render_with "$role")"
		while IFS= read -r cask; do
			[ -n "$cask" ] || continue
			if ! grep -qxF "cask \"$cask\"" <<<"$rendered"; then
				echo "role $role does not install $cask" >&2
				return 1
			fi
		done <<<"$casks"
	done
}

# The role-to-bundles map exists twice: .chezmoi.toml.tmpl needs it at prompt time and
# .chezmoitemplates/bundles needs it at render time, and prompt functions don't exist outside
# config rendering, so there's no way to share one copy. Drift between them is invisible —
# init would seed a machine with one list while every apply before its next init used another.
@test "the seeded bundle list matches what the render falls back to" {
	local blank="$BATS_TEST_TMPDIR/blank.toml"
	printf '[data]\n' >"$blank"
	for role in work client personal; do
		local seeded fallback rolecfg="$BATS_TEST_TMPDIR/$role.toml"
		seeded="$(chezmoi execute-template --init --stdinisatty=false --config "$blank" \
			--promptString "Machine role (work/client/personal)=$role" \
			--promptString "Work email address=a@b.c" \
			--promptString "Client email address=a@b.c" \
			--promptString "Personal email address=a@b.c" \
			<"$SRC/.chezmoi.toml.tmpl" | grep '^  bundles = ' | cut -d= -f2- | tr -d ' ')"
		printf '[data]\n  machine_role = "%s"\n' "$role" >"$rolecfg"
		fallback="$(chezmoi execute-template --source "$SRC" --config "$rolecfg" \
			'{{ template "bundles" . }}' | tr -d ' ')"
		[ "$seeded" = "$fallback" ] || {
			echo "role $role: init seeds $seeded but the render falls back to $fallback" >&2
			return 1
		}
	done
}

# Bundles are a refinement of the machine_role conditionals they replaced, and the property
# that makes the roles mean anything is that they nest: everything a client machine installs,
# a personal machine also installs, and everything a personal machine installs, a work machine
# also installs. A bundle that straddled a gate class would break the nesting, which is the
# same failure the migration was checked against by rendering all three roles before and after
# (91 / 77 / 84 entries, byte-identical). Asserting the shape rather than those counts, so
# adding a package doesn't mean editing three magic numbers nobody will re-derive.
@test "each role's packages are a superset of the narrower role's" {
	local client personal work
	client="$(render_with client | grep -E '^(tap|brew|cask|mas) ' | sort)"
	personal="$(render_with personal | grep -E '^(tap|brew|cask|mas) ' | sort)"
	work="$(render_with work | grep -E '^(tap|brew|cask|mas) ' | sort)"

	# comm -23 prints lines only in the first set. Empty means fully contained.
	[ -z "$(comm -23 <(echo "$client") <(echo "$personal"))" ]
	[ -z "$(comm -23 <(echo "$personal") <(echo "$work"))" ]

	# And each step actually adds something, or the roles have collapsed into one.
	[ -n "$(comm -13 <(echo "$client") <(echo "$personal"))" ]
	[ -n "$(comm -13 <(echo "$personal") <(echo "$work"))" ]
}

# A bundle no role's defaults name is a hole with no bottom: packages filed into it render
# on no machine, `dotfiles-apps` offers it as a target anyway because it's in the catalog,
# and nothing anywhere reports that the thing you just filed will never install.
@test "every bundle in the catalog is reachable from some role's defaults" {
	local reachable="" role
	for role in work client personal; do
		local cfg="$BATS_TEST_TMPDIR/$role.toml"
		printf '[data]\n  machine_role = "%s"\n' "$role" >"$cfg"
		reachable="$reachable
$(chezmoi execute-template --source "$SRC" --config "$cfg" '{{ template "bundles" . }}' | jq -r '.[]')"
	done
	local b
	while IFS= read -r b; do
		[ -n "$b" ] || continue
		grep -qxF "$b" <<<"$reachable" || {
			echo "bundle '$b' is in the catalog but no role installs it" >&2
			return 1
		}
	done < <(chezmoi execute-template --source "$SRC" '{{ .pkg.catalog | toJson }}' | jq -r '.[]')
}

# ---- os-held (#23) ----
#
# zappy needs macOS 15+ and one machine here runs Sonoma, so its install fails on every
# apply, forever — training the user to ignore the failure list (#17 exists because that
# training already happened once). .chezmoitemplates/os-held reads the running macOS at
# RENDER time and the Brewfile drops whatever it names, so the entry comes back on its own
# the moment the machine upgrades rather than needing a manual unblock. These cases stub
# `sw_vers` rather than trusting whatever OS this suite happens to run on, since #23's own
# fixture — zappy at floor 15 — passes on this machine's real macOS (26.6.1) either way.

# Stubs `sw_vers -productVersion` to print $1 and renders the Brewfile through the existing
# render_with, so every case here reads the OS version through the same PATH lookup a real
# `chezmoi apply` uses rather than templating a fake answer straight in. One stub dir per
# test file run is enough — bats runs cases one at a time, and each call overwrites the
# stub before the render that reads it.
render_with_os() {
	local ver="$1" role="$2"
	shift 2
	local stubdir="$BATS_TEST_TMPDIR/os-stub"
	mkdir -p "$stubdir"
	printf '#!/usr/bin/env bash\necho "%s"\n' "$ver" >"$stubdir/sw_vers"
	chmod +x "$stubdir/sw_vers"
	PATH="$stubdir:$PATH" render_with "$role" "$@"
}

@test "os-held: below zappy's floor, zappy is absent" {
	run render_with_os "14.4.1" work
	[ "$status" -eq 0 ]
	assert_not_contains 'cask "zappy"'
}

# The boundary is inclusive: semverCompare ">=15" against exactly "15.0" is true, so a
# machine sitting right on the floor still gets it.
@test "os-held: exactly at zappy's floor, zappy is present" {
	run render_with_os "15.0" work
	[ "$status" -eq 0 ]
	assert_contains 'cask "zappy"'
}

@test "os-held: above zappy's floor, zappy is present" {
	run render_with_os "16.1" work
	[ "$status" -eq 0 ]
	assert_contains 'cask "zappy"'
}

# A single held fixture (zappy) would pass almost any implementation, including one that
# just special-cased its name. Asserting an entry with no min_macos at all rides through
# every stubbed OS version is what forces the filter to actually key off the field rather
# than off zappy.
@test "os-held: an entry with no min_macos renders at every stubbed OS version" {
	local ver
	for ver in 14.4.1 15.0 16.1; do
		run render_with_os "$ver" work
		[ "$status" -eq 0 ]
		assert_contains 'brew "age"'
	done
}

# The other half of the same guard against a one-element cheat: the low and high renders
# should differ, and every line that differs should be about the one entry with a floor.
@test "os-held: renders below and above the floor differ only by held lines" {
	local low high changed
	low="$(render_with_os "14.4.1" work)"
	high="$(render_with_os "16.1" work)"
	changed="$(diff <(printf '%s\n' "$low") <(printf '%s\n' "$high") | grep -E '^[<>]')"
	[ -n "$changed" ]
	local line
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		assert_contains "zappy" "$line"
	done <<<"$changed"
}

# Acceptance criterion 3: run_onchange_install-packages.sh.tmpl hashes the rendered
# Brewfile in its own header comment, and that hash is what makes the script re-run on the
# next apply. Reading the OS at render time is the whole point — if the hash didn't move
# here, an OS upgrade would never re-trigger the install and zappy would stay stuck exactly
# the way #23 describes. Rendered via stdin, matching render_with's own --source/--config
# handling, since this is a different template than render_with itself renders.
render_install_script_with_os() {
	local ver="$1" role="$2"
	local stubdir="$BATS_TEST_TMPDIR/os-stub-hash" cfg="$BATS_TEST_TMPDIR/hash.toml"
	mkdir -p "$stubdir"
	printf '#!/usr/bin/env bash\necho "%s"\n' "$ver" >"$stubdir/sw_vers"
	chmod +x "$stubdir/sw_vers"
	printf '[data]\n  machine_role = "%s"\n' "$role" >"$cfg"
	PATH="$stubdir:$PATH" chezmoi execute-template --source "$SRC" --config "$cfg" \
		<"$SRC/run_onchange_install-packages.sh.tmpl"
}

@test "os-held: the install script's Brewfile hash line moves across the floor" {
	run render_install_script_with_os "14.4.1" work
	[ "$status" -eq 0 ]
	local low_hash
	low_hash="$(grep '^# Brewfile hash:' <<<"$output")"

	run render_install_script_with_os "15.0" work
	[ "$status" -eq 0 ]
	local high_hash
	high_hash="$(grep '^# Brewfile hash:' <<<"$output")"

	[ -n "$low_hash" ]
	[ -n "$high_hash" ]
	[ "$low_hash" != "$high_hash" ]
}

# semverCompare hard-errors on garbage input, and a template error here would take down
# every `chezmoi apply` on the machine — not just the packages this filter gates. Garbage
# has to fail open to exactly the all-qualifying render, the same as a machine with no
# os-held guard at all would produce.
@test "os-held: garbage sw_vers output fails open to the all-qualifying render" {
	local baseline
	baseline="$(render_with_os "16.1" work)"
	run render_with_os "not-a-version" work
	[ "$status" -eq 0 ]
	[ "$output" = "$baseline" ]
}
