#!/usr/bin/env bats
#
# dotfiles-apps writes two files that look alike and mean different things, and it edits
# them by anchored line replacement rather than by reserializing TOML. Both of those are
# choices that fail quietly when they fail: a replacement anchored one character too loosely
# rewrites the neighbouring package, and a reserializer drops the cask-naming comments
# without erroring. So the assertions here are on resulting file bytes, not on what the
# script said it did.
#
# fzf is stubbed by a queue: one line of FZF_QUEUE per call, `|` separating the rows a
# multi-select returns. That's the only way to drive a picker from a test.

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/dot_local/bin/executable_dotfiles-apps"

setup() {
	unset XDG_CACHE_HOME
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export FIXTURE="$BATS_TEST_TMPDIR/src"
	export XDG_CONFIG_HOME="$HOME/.config"
	export FZF_QUEUE="$BATS_TEST_TMPDIR/fzf-queue"
	export FZF_CALL="$BATS_TEST_TMPDIR/fzf-call"
	mkdir -p "$HOME" "$STUBS" "$FIXTURE" "$XDG_CONFIG_HOME/chezmoi"
	: >"$FZF_QUEUE"

	cat >"$STUBS/fzf" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
n=$(cat "$FZF_CALL" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$FZF_CALL"
sed -n "${n}p" "$FZF_QUEUE" | tr '|' '\n'
STUB

	cat >"$STUBS/chezmoi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
source-path) echo "$FIXTURE" ;;
execute-template)
  case "$2" in
  *catalog*) echo '["core","fonts","media","cloud"]' ;;
  *bundles*) echo '["core","fonts"]' ;;
  *packages*)
    # Derived from the fixture registry rather than hardcoded, so a test that edits the
    # file sees its own edit on a second read.
    grep -oE '\{ name = "[^"]+", *type = "[^"]+", *bundles = \[[^]]*\] \}' "$FIXTURE/.chezmoidata.toml" \
      | sed -E 's/\{ name = "([^"]+)", *type = "([^"]+)", *bundles = \[([^]]*)\] \}/{"name":"\1","type":"\2","bundles":[\3]}/' \
      | paste -sd, - | sed 's/^/[/; s/$/]/'
    ;;
  esac
  ;;
esac
STUB

	printf '#!/usr/bin/env bash\n:\n' >"$STUBS/brew"
	chmod +x "$STUBS/fzf" "$STUBS/chezmoi" "$STUBS/brew"
	export PATH="$STUBS:$PATH"

	write_registry
	write_config
}

# Alignment padding and a trailing comment on one entry, because preserving both is the
# reason this edits lines instead of reserializing.
write_registry() {
	cat >"$FIXTURE/.chezmoidata.toml" <<'TOML'
[pkg]
catalog = ["core", "fonts", "media", "cloud"]

taps = [
  { name = "owner/repo", bundles = ["core"] },
]

packages = [
  # ---- core ----
  { name = "1password",     type = "cask", bundles = ["core"] },
  { name = "1password-cli", type = "cask", bundles = ["core"] },
  { name = "spotify",       type = "cask", bundles = ["media"] }, # keep this comment
  { name = "owner/repo/x",  type = "brew", bundles = ["core"] },
]
TOML
}

write_config() {
	cat >"$XDG_CONFIG_HOME/chezmoi/chezmoi.toml" <<'TOML'
[data]
  machine_role = "work"
  bundles = ["core","fonts"]
  [data.sync_times]
    workday_start = "10:00"
TOML
}

queue() { printf '%s\n' "$@" >"$FZF_QUEUE"; }

registry_line() { grep "name = \"$1\"," "$FIXTURE/.chezmoidata.toml"; }

# ---- moving a package between bundles ----

@test "moves the selected package and leaves its alignment and comment alone" {
	queue 'cask  spotify                            media' 'core'
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(registry_line spotify)" = '  { name = "spotify",       type = "cask", bundles = ["core"] }, # keep this comment' ]
}

# The anchor carries the closing quote and comma for exactly this case. A prefix match
# would rewrite 1password-cli while claiming to have moved 1password.
@test "a package whose name prefixes another's is not confused for it" {
	queue 'cask  1password                          core' 'media'
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(registry_line 1password)" = '  { name = "1password",     type = "cask", bundles = ["media"] },' ]
	[ "$(registry_line 1password-cli)" = '  { name = "1password-cli", type = "cask", bundles = ["core"] },' ]
}

@test "a tapped name with slashes in it is matched literally" {
	queue 'brew  owner/repo/x                       core' 'media'
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[[ "$(registry_line 'owner/repo/x')" == *'bundles = ["media"]'* ]]
}

@test "several packages selected at once all move" {
	queue 'cask  spotify   media|cask  1password   core' 'cloud'
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[[ "$(registry_line spotify)" == *'["cloud"]'* ]]
	[[ "$(registry_line 1password)" == *'["cloud"]'* ]]
}

@test "multiple target bundles are written as a list" {
	queue 'cask  spotify   media' 'core|media'
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[[ "$(registry_line spotify)" == *'bundles = ["core", "media"]'* ]]
}

# Escaping the picker has to leave the file alone. A tool that writes on an empty selection
# is one stray keystroke from a reassignment nobody asked for.
@test "selecting no package writes nothing" {
	queue ''
	local before
	before="$(cat "$FIXTURE/.chezmoidata.toml")"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$before" = "$(cat "$FIXTURE/.chezmoidata.toml")" ]
}

@test "selecting a package but no bundle writes nothing" {
	queue 'cask  spotify   media' ''
	local before
	before="$(cat "$FIXTURE/.chezmoidata.toml")"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$before" = "$(cat "$FIXTURE/.chezmoidata.toml")" ]
}

# The registry is the thing being edited, so a name that isn't in it means the anchor is
# wrong. Refusing beats writing a line nobody can find later.
@test "refuses when the anchor matches no entry" {
	queue 'cask  nonesuch   media' 'core'
	run bash "$SCRIPT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"found 0"* ]]
}

# ---- adopting untracked packages ----

@test "adopts an installed package the registry never named" {
	printf '#!/usr/bin/env bash\ncase "$*" in\n*leaves*) echo yq ;;\n*cask*) : ;;\nesac\n' >"$STUBS/brew"
	chmod +x "$STUBS/brew"
	queue 'brew  yq' 'core'
	run bash "$SCRIPT" --adopt
	[ "$status" -eq 0 ]
	[[ "$(registry_line yq)" == *'{ name = "yq", type = "brew", bundles = ["core"] },'* ]]
	# Appended inside the packages array, not after it.
	[ "$(tail -1 "$FIXTURE/.chezmoidata.toml")" = "]" ]
}

@test "says so and writes nothing when everything installed is already tracked" {
	printf '#!/usr/bin/env bash\ncase "$*" in\n*leaves*) echo owner/repo/x ;;\n*cask*) echo spotify ;;\nesac\n' >"$STUBS/brew"
	chmod +x "$STUBS/brew"
	local before
	before="$(cat "$FIXTURE/.chezmoidata.toml")"
	run bash "$SCRIPT" --adopt
	[ "$status" -eq 0 ]
	[[ "$output" == *"nothing untracked"* ]]
	[ "$before" = "$(cat "$FIXTURE/.chezmoidata.toml")" ]
}

# ---- this machine's enabled bundles ----

@test "rewrites the bundles line in the local config" {
	queue 'core|media'
	run bash "$SCRIPT" --machine
	[ "$status" -eq 0 ]
	[ "$(grep '^  bundles' "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml")" = '  bundles = ["core","media"]' ]
	# The table that follows must survive: a careless sub would swallow it.
	grep -q 'workday_start' "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"
}

# A machine that predates the key runs on the role fallback and has no line to rewrite.
# Appending blindly would land the key inside [data.sync_times] and change the wrong table.
@test "inserts the key under [data] when the machine never re-inited" {
	cat >"$XDG_CONFIG_HOME/chezmoi/chezmoi.toml" <<'TOML'
[data]
  machine_role = "work"
  [data.sync_times]
    workday_start = "10:00"
TOML
	queue 'core'
	run bash "$SCRIPT" --machine
	[ "$status" -eq 0 ]
	[ "$(sed -n '2p' "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml")" = '  bundles = ["core"]' ]
	grep -q 'workday_start' "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml"
}

# Marking nothing means the picker was escaped. Reading it as "install no bundles at all"
# would turn one stray keystroke into a machine that installs nothing.
@test "marking no bundles leaves the local config alone" {
	queue ''
	local before
	before="$(cat "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml")"
	run bash "$SCRIPT" --machine
	[ "$status" -eq 0 ]
	[ "$before" = "$(cat "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml")" ]
}

# ---- the two files stay separate ----

# The whole point of the mode split. A repo edit must never reach the local config and a
# local edit must never reach the repo, or the blast radius the modes exist to keep
# distinct stops being distinct.
@test "moving a package leaves the local config untouched" {
	queue 'cask  spotify   media' 'core'
	local before
	before="$(cat "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml")"
	run bash "$SCRIPT"
	[ "$status" -eq 0 ]
	[ "$before" = "$(cat "$XDG_CONFIG_HOME/chezmoi/chezmoi.toml")" ]
}

@test "choosing this machine's bundles leaves the registry untouched" {
	queue 'core'
	local before
	before="$(cat "$FIXTURE/.chezmoidata.toml")"
	run bash "$SCRIPT" --machine
	[ "$status" -eq 0 ]
	[ "$before" = "$(cat "$FIXTURE/.chezmoidata.toml")" ]
}

# ---- plumbing ----

@test "names the missing tool rather than failing somewhere inside a pipeline" {
	printf '#!/usr/bin/env bash\nexit 127\n' >"$STUBS/fzf"
	rm "$STUBS/fzf"
	run bash "$SCRIPT"
	[ "$status" -ne 0 ]
	[[ "$output" == *"fzf"* ]]
}

@test "rejects an unknown flag instead of guessing" {
	run bash "$SCRIPT" --oops
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option"* ]]
}

@test "--help lists all three modes and exits clean" {
	run bash "$SCRIPT" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"--adopt"* ]]
	[[ "$output" == *"--machine"* ]]
}
