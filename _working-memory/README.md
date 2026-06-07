# `_working-memory/`

A two-tier working memory for this project. AI coding agents read these files for project context, and so should you — `decisionLog.md`, `conventions.md`, and `antipatterns.md` in particular are first-class onboarding material for human contributors.

## What's here

| File                       | What it holds                                                                                                          |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `activeContext.md`         | Current focus, last decision, known risks. ≤20 lines. **Local-only — gitignored.** Each developer maintains their own. |
| `activeContext.example.md` | Starter content for new contributors to copy into `activeContext.md`.                                                  |
| `projectOverview.md`       | What this project is, its stack, repo layout, and constraints. Stable over weeks.                                      |
| `decisionLog.md`           | Append-only log of architectural and scoping decisions. Most recent first.                                             |
| `dataContracts.md`         | Canonical shapes for data flowing through the application — either pointer-to-types, schema sketch, or prose.          |
| `conventions.md`           | "How we do things here" — naming, file layout, error handling, anything pattern-shaped.                                |
| `openQuestions.md`         | Unresolved ambiguity. Check here before guessing; answers move into `decisionLog.md` when resolved.                    |
| `antipatterns.md`          | Things the team tried that didn't work. Append-only. Agents must check before proposing refactors or library swaps.    |

## When to update each file

- After completing a feature or making a meaningful decision, update `activeContext.md` and the relevant on-demand file.
- `activeContext.md` is a queue, not an archive. Evict completed items to `decisionLog.md` so the file stays under twenty lines.
- `decisionLog.md` and `antipatterns.md` are append-only. Never edit past entries — add a new entry that supersedes the old one.
- `projectOverview.md`, `dataContracts.md`, and `conventions.md` update when the project's _shape_ changes (new layer, new type, new pattern), not on every feature.

Agents follow the same rules. The full on-demand table lives in [`../AGENTS.md`](../AGENTS.md).

## For new contributors

After cloning this repo, copy the example file into your local one:

```bash
cp _working-memory/activeContext.example.md _working-memory/activeContext.md
```

`activeContext.md` is gitignored because two developers on the same team rarely have the same active context, and committing it makes the file a permanent merge-conflict factory.

## Editing by hand vs. invoking an agent

Both work. Edit directly when you know exactly what to add. Run `/update-working-memory` (or invoke the `working-memory-synchronizer` agent) when you want help proposing diffs based on recent git changes.

For a one-time deeper hydration of an existing codebase — scanning code, git history, README, and ADRs to populate the files end-to-end — invoke the `hydrator` agent. That's the recommended starting move on brownfield installs.
