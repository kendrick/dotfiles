---
name: update-working-memory
description: >
  Reads the current working memory state, diffs it against recent git changes,
  and proposes updates. Use when finishing a feature, resolving a decision,
  or when active context feels stale.
---

# Update Working Memory

When this skill is activated, perform the following:

1. Read `_working-memory/activeContext.md` (local, may not exist yet — if missing, create from `activeContext.example.md`).
2. Read all other files in `_working-memory/`.
3. Run `git diff --stat HEAD~5` to identify recent changes.
4. For each working memory file, determine if anything is stale or missing.
5. Enforce the 20-line hard limit on `activeContext.md` — evict completed items to `decisionLog.md`.
6. Propose all changes as a batch, grouped by file, and wait for confirmation before writing.

## File rules

| File | Update policy |
|---|---|
| `activeContext.md` | Queue, not archive. Evict completed items. ≤20 lines. |
| `decisionLog.md` | Append only. Never edit past entries. Most recent at top. |
| `projectOverview.md` | Update only when project shape changes (stack, structure). |
| `dataContracts.md` | Update when interfaces, schemas, or API shapes change. |
| `conventions.md` | Update when a new pattern emerges or an old one is deprecated. |
| `openQuestions.md` | Remove answered questions (move answers to decision log). |
| `antipatterns.md` | Append only. Add an entry when an approach was tried and abandoned — include a specific "Don't suggest" line so future agents avoid re-proposing it. |
