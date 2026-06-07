# AGENTS.md

## Stack

<!-- One line per layer. Detected from project. -->

## Build / Test / Lint

<!-- Copy exact commands so agents don't guess. -->

## Working Memory

This project uses a two-tier working memory at `_working-memory/`.

**AGENT INSTRUCTION:** scan this section BEFORE deciding what to read. If your task matches a row in the on-demand table, that file is required reading before you proceed.

### Always read on session start:

- `_working-memory/activeContext.md` — Current focus, last decision, known risks (≤20 lines, local only / gitignored)

### Read on demand:

| File                 | Read when...                                                                                                      |
| -------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `projectOverview.md` | Starting a new feature or onboarding                                                                              |
| `decisionLog.md`     | Making an architectural or scoping decision                                                                       |
| `dataContracts.md`   | Creating or modifying data-consuming components                                                                   |
| `conventions.md`     | Writing new code or reviewing patterns                                                                            |
| `openQuestions.md`   | Encountering ambiguity — check here before guessing                                                               |
| `antipatterns.md`    | BEFORE suggesting a refactor, library swap, or architectural change — check whether the team has already tried it |

### Updating working memory:

- After completing a feature or making a significant decision, update `activeContext.md` and the relevant on-demand file.
- `activeContext.md` is a queue: evict completed items to `decisionLog.md`.
- `decisionLog.md` and `antipatterns.md` are both append-only. Never edit past entries.
- Never let `activeContext.md` exceed 20 lines.

## Conventions

<!-- Populated from detection or manually. Keep to ≤10 rules. -->
