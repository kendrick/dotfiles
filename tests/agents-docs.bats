#!/usr/bin/env bats
#
# #105: the rules in ~/.agents are read by Claude Code, OpenCode and Codex, so they mustn't assume any one harness. Harness tool names live only in harness-notes.md, which AGENTS.md points readers to.
#
# Reads the plaintext sources directly; no chezmoi, HOME or network needed.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."

@test "AGENTS.md and DELEGATION.md name no ~/.claude path" {
	assert_not_contains '~/.claude' "$(cat "$SRC/dot_agents/AGENTS.md" "$SRC/dot_agents/private_DELEGATION.md")"
}

@test "only harness-notes.md names harness tools" {
	run bash -c "cd '$SRC' && grep -l 'Skill tool\|AskUserQuestion\|Task tool' dot_agents/*.md"
	# Brackets make this an exact match: any second file adds a line inside them.
	assert_contains "[dot_agents/harness-notes.md]" "[$output]"
}

@test "AGENTS.md cites harness-notes.md" {
	assert_contains '~/.agents/harness-notes.md' "$(cat "$SRC/dot_agents/AGENTS.md")"
}
