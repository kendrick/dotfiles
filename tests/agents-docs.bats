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

# Rungs carry capability names so the routing reads the same in every harness. Model names belong only under "## Rungs by Harness", the one place a harness's lineup is pinned.
MODEL_RE='haiku|sonnet|opus|fable|claude-[a-z0-9.-]+|gpt-[0-9][a-z0-9.-]*'

section() {
	awk -v h="## $2" '/^## /{m=($0==h)} m' "$1"
}

models_outside_mapping() {
	awk '/^## /{m=($0=="## Rungs by Harness")} !m' "$1" | grep -iwE "$MODEL_RE"
}

@test "model names appear only in the per-harness mapping table" {
	local f="$SRC/dot_agents/private_DELEGATION.md"
	assert_contains '[]' "[$(models_outside_mapping "$f")]"
	# Guards against passing vacuously with the section missing or emptied.
	assert_contains 'haiku' "$(section "$f" 'Rungs by Harness')"
}

@test "the rung table names no models" {
	local rows
	rows=$(section "$SRC/dot_agents/private_DELEGATION.md" 'The Rungs' | grep '^| ' | sed 1,2d)
	assert_contains '[0]' "[$(grep -ciwE "$MODEL_RE" <<<"$rows")]"
	assert_contains '[stays in session,quick,standard,deep,frontier]' "[$(awk -F'|' '{gsub(/[` ]+$|^[` ]+/, "", $2); print $2}' <<<"$rows" | paste -sd, -)]"
}

@test "a planted model name outside the mapping table fails the check" {
	local copy="$BATS_TEST_TMPDIR/DELEGATION.md"
	awk 'NR==4{print "Route this to sonnet."; print ""} 1' "$SRC/dot_agents/private_DELEGATION.md" >"$copy"
	assert_contains 'Route this to sonnet.' "$(models_outside_mapping "$copy")"
}
