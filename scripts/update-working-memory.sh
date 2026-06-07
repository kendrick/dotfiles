#!/bin/bash
# Manual working memory sync trigger.
# Works from any terminal — not tied to a specific AI tool.
# Prints a summary of working memory staleness for the developer to act on.

set -eu

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WM_DIR="$REPO_ROOT/_working-memory"

echo "=== Working Memory Status ==="
echo ""

if [ ! -d "$WM_DIR" ]; then
  echo "No _working-memory/ directory found at $REPO_ROOT."
  echo "Run the working-memory-kit installer to scaffold one."
  exit 1
fi

# Same key=value parser the hooks use (kept inline to avoid making this
# script depend on a shared lib).
read_cfg() {
  local key="$1" default="$2" file="$REPO_ROOT/.working-memoryrc"
  local val=""
  [ -f "$file" ] && val=$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "'\''')
  echo "${val:-$default}"
}

# Env var > .working-memoryrc > built-in default. Same precedence as the hooks,
# so what this script reports matches what SessionStart and Stop will use.
MAX_LINES="${WORKING_MEMORY_MAX_LINES:-$(read_cfg MAX_ACTIVE_CONTEXT_LINES 20)}"
FILE_THRESHOLD="${WORKING_MEMORY_FILE_THRESHOLD:-$(read_cfg NUDGE_FILE_THRESHOLD 5)}"
LINE_THRESHOLD="${WORKING_MEMORY_LINE_THRESHOLD:-$(read_cfg NUDGE_LINE_THRESHOLD 200)}"

echo "Active config:"
echo "  activeContext.md max lines: $MAX_LINES"
echo "  Nudge: > $FILE_THRESHOLD files OR > $LINE_THRESHOLD lines changed"
[ -f "$REPO_ROOT/.working-memoryrc" ] && echo "  (source: .working-memoryrc; env vars override per developer)"
echo ""

# activeContext.md status
if [ -f "$WM_DIR/activeContext.md" ]; then
  LINES=$(grep -c '[^[:space:]]' "$WM_DIR/activeContext.md" || echo 0)
  echo "activeContext.md: $LINES non-empty lines (limit: $MAX_LINES)"
else
  echo "activeContext.md: MISSING — run: cp _working-memory/activeContext.example.md _working-memory/activeContext.md"
fi

# Last modified times
echo ""
echo "Last modified:"
for f in "$WM_DIR"/*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  # BSD stat (macOS) and GNU stat (Linux) take incompatible flags for
  # formatted output, so the format string itself has to switch.
  if [[ "$OSTYPE" == "darwin"* ]]; then
    MOD=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$f")
  else
    MOD=$(stat -c '%y' "$f" | cut -d. -f1)
  fi
  echo "  $BASENAME: $MOD"
done

# Recent change context
echo ""
echo "Recent changes (last 5 commits):"
git -C "$REPO_ROOT" diff --stat HEAD~5 2>/dev/null || echo "  (not enough git history)"
