#!/usr/bin/env bats
#
# #105: ~/.agents is the canonical home for the user-level rules; Claude Code, Codex and OpenCode read them through chezmoi-managed symlinks.
#
# Expected values come from the issue, not the source layout. HOME is a temp dir and chezmoi runs with --exclude scripts, so nothing touches the real home or the network.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."

# Resolved before HOME/PATH change.
REAL_CHEZMOI="$(command -v chezmoi || true)"

setup() {
	[ -n "$REAL_CHEZMOI" ] || skip "chezmoi not installed"
	unset XDG_CONFIG_HOME XDG_CACHE_HOME
	HOME="$BATS_TEST_TMPDIR/home"
	export HOME
	mkdir -p "$HOME/.config/chezmoi"
	cfg="$BATS_TEST_TMPDIR/chezmoi.toml"
	# encryption must be configured or chezmoi lists the encrypted sources as PROSE.md.age; the key file is never read here.
	printf 'encryption = "age"\n[data]\nmachine_role = "work"\n[age]\nidentity = "%s/.config/chezmoi/key.txt"\nrecipient = "age1xy04pcarcglpwfafwenw8z7aygv2sknl54jvfrd0c0zlww328fnsrakm7x"\n' "$HOME" >"$cfg"
}

cz() { "$REAL_CHEZMOI" --source "$SRC" --destination "$HOME" --config "$cfg" "$@"; }

count() { printf '%s\n' "$managed" | grep -cxF -- "$1" || true; }

@test "with a key, chezmoi managed lists the canonical docs and every adapter" {
	printf 'AGE-SECRET-KEY-fixture\n' >"$HOME/.config/chezmoi/key.txt"
	managed="$(cz managed)"
	for p in .agents/AGENTS.md .agents/DELEGATION.md .agents/PROSE.md .agents/VOICE.md \
		.agents/voice-samples-work.md .agents/voice-samples-personal.md \
		.claude/CLAUDE.md .claude/PROSE.md .claude/VOICE.md \
		.claude/voice-samples-work.md .claude/voice-samples-personal.md \
		.codex/AGENTS.md .config/opencode/AGENTS.md; do
		assert_contains "$p=1" "$p=$(count "$p")"
	done
	assert_contains "count=0" "count=$(count AGENTS.md)"
}

@test "without a key, PROSE, VOICE, the voice samples and their adapters are not managed" {
	managed="$(cz managed)"
	assert_contains "AGENTS=1" "AGENTS=$(count .agents/AGENTS.md)"
	assert_contains "DELEGATION=1" "DELEGATION=$(count .agents/DELEGATION.md)"
	for p in .agents/PROSE.md .agents/VOICE.md .claude/PROSE.md .claude/VOICE.md \
		.agents/voice-samples-work.md .agents/voice-samples-personal.md \
		.claude/voice-samples-work.md .claude/voice-samples-personal.md; do
		assert_contains "$p=0" "$p=$(count "$p")"
	done
}

@test "apply on a non-kendrick home links every adapter to ~/.agents/AGENTS.md, and a second apply is clean" {
	mkdir -p "$HOME/.claude"
	printf 'old\n' >"$HOME/.claude/CLAUDE.md"
	printf 'stale\n' >"$HOME/.claude/DELEGATION.md"
	targets=("$HOME/.agents" "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode")
	cz apply --force --exclude scripts "${targets[@]}"
	cz apply --force --exclude scripts "${targets[@]}"
	for a in .claude/CLAUDE.md .codex/AGENTS.md .config/opencode/AGENTS.md; do
		assert_contains "$HOME/.agents/AGENTS.md" "$(readlink -f "$HOME/$a")"
		assert_contains "same" "$(cmp -s "$HOME/$a" "$SRC/dot_agents/AGENTS.md" && echo same || echo differ)"
	done
	# No key here, so any adapter whose target the keyless block skips would dangle.
	dangling=""
	while IFS= read -r f; do
		[ -e "$f" ] || dangling="$dangling ${f#"$HOME"/}"
	done < <(find "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode" -type l)
	assert_contains "dangling=[]" "dangling=[$dangling]"
	assert_contains "absent" "$([ -e "$HOME/.claude/DELEGATION.md" ] && echo present || echo absent)"
	assert_contains "absent" "$([ -e "$HOME/AGENTS.md" ] && echo present || echo absent)"
	assert_contains "clean" "$(out="$(cz status --exclude scripts "${targets[@]}")"; [ -z "$out" ] && echo clean || echo "dirty: $out")"
}
