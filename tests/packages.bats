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
	[[ "$output" == *'brew "age"'* ]]
	# Both halves matter: cloud off means no databricks, and no databricks tap either.
	[[ "$output" != *"databricks"* ]]
	[[ "$output" != *"font-lilex"* ]]
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
			[[ -n "$cask" ]] || continue
			if ! grep -qxF "cask \"$cask\"" <<<"$rendered"; then
				echo "role $role does not install $cask" >&2
				return 1
			fi
		done <<<"$casks"
	done
}

# Bundles are a refinement of the machine_role conditionals they replaced, so each role's
# defaults have to land on the same package count the old template produced. These numbers
# are the pre-migration render, captured before the conditionals came out.
@test "each role's defaults render the package count its conditionals used to" {
	[ "$(render_with work | grep -cE '^(tap|brew|cask|mas) ')" -eq 91 ]
	[ "$(render_with client | grep -cE '^(tap|brew|cask|mas) ')" -eq 77 ]
	[ "$(render_with personal | grep -cE '^(tap|brew|cask|mas) ')" -eq 84 ]
}
