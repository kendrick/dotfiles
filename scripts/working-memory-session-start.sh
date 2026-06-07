#!/bin/bash
# Ensures activeContext.md exists at session start.
# If missing, copies from the example template.

set -eu

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WM_DIR="$REPO_ROOT/_working-memory"

# Hooks fire on every session in every project, not just working-memory
# consumers. Bail quietly so unrelated repos don't see noise.
if [ ! -d "$WM_DIR" ]; then
  exit 0
fi

# Reads a key from .working-memoryrc with a default. Parses key=value instead
# of sourcing the file, so a malicious rc can't execute arbitrary shell.
read_cfg() {
  local key="$1" default="$2" file="$REPO_ROOT/.working-memoryrc"
  local val=""
  [ -f "$file" ] && val=$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "'\''')
  echo "${val:-$default}"
}

MAX_LINES="${WORKING_MEMORY_MAX_LINES:-$(read_cfg MAX_ACTIVE_CONTEXT_LINES 20)}"

# The directive lands every session, regardless of file state. The kit can't
# enforce that the host tool auto-loaded AGENTS.md / CLAUDE.md at session
# start, so the hook plants the working-memory directive directly. Hosts
# that DID auto-load those files get a harmless duplicate — small cost
# next to the value of not silently failing on cold-start.
DIRECTIVE="Working memory at _working-memory/ is active. AGENT INSTRUCTION: before deciding what to read, scan the on-demand table in AGENTS.md's '## Working Memory' section. If your task matches a row, that file is required reading before you proceed."

# Compose any condition message on top of the directive.
CONDITION=""
if [ ! -f "$WM_DIR/activeContext.md" ]; then
  if [ -f "$WM_DIR/activeContext.example.md" ]; then
    cp "$WM_DIR/activeContext.example.md" "$WM_DIR/activeContext.md"
    CONDITION=" Created activeContext.md from template — update it with your current focus."
  else
    CONDITION=" Warning: no activeContext.example.md found; working memory may not be initialized."
  fi
else
  # The default limit (20) comes from activeContext.example.md. Past that,
  # the file has stopped being a queue and started being an archive.
  LINE_COUNT=$(grep -c '[^[:space:]]' "$WM_DIR/activeContext.md" || true)
  if [ "${LINE_COUNT:-0}" -gt "$MAX_LINES" ]; then
    CONDITION=" Warning: activeContext.md has $LINE_COUNT non-empty lines (limit is $MAX_LINES). Run /update-working-memory to prune it."
  fi
fi

# {"systemMessage":"..."} on stdout is the hook protocol — the host surfaces
# it to the user. Plain echoes get ignored.
echo "{\"systemMessage\":\"${DIRECTIVE}${CONDITION}\"}"
