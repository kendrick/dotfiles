# AGENTS.md

## Stack

<!-- One line per layer. Detected from project. -->

## Build / Test / Lint

```bash
bats tests/              # the whole suite; green as of 2026-08-20 (164 passing, 0 failures, 0 skips)
bats tests/doctor.bats   # one file
tests/mutation-check.sh  # inverts each assertion and requires its case to report `not ok`
```

`bats tests/` is the only entry point anyone has to remember, and it exits 0. Treat any failure as a regression you caused—there are no grandfathered failures left to skip past. Run `mutation-check.sh` after changing an assertion, and read its per-file counts rather than its total.

There is no build step, and no lint or format gate on the dotfiles themselves. `tests/lint.bats` is a suite-internal guard against bare `[[`/`((` in test code, not a repo linter.

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
