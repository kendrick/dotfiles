# Copilot Project Instructions

## Working Memory

This project maintains a two-tier working memory at `_working-memory/` for cross-session context.

**AGENT INSTRUCTION:** before deciding what to read, scan the on-demand table under `## Working Memory` in [`AGENTS.md`](../AGENTS.md). If your task matches a row, that file is required reading before you proceed.

- **Always read on session start:** `_working-memory/activeContext.md` (≤20 lines, local only).
- **Canonical surface:** [`AGENTS.md`](../AGENTS.md)'s `## Working Memory` section holds the on-demand table and update rules.
- **To sync working memory:** run `/update-working-memory` in Copilot Chat, or invoke the `working-memory-synchronizer` custom agent.
