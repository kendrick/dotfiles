---
name: hydrate-draft
description: >
  Map findings into the six working memory files: projectOverview, decisionLog,
  dataContracts, conventions, openQuestions. Drafts include source provenance
  inline. activeContext.md is excluded; the developer drives that file directly.
---

# hydrate-draft

Input: findings from `hydrate-extract`.

When this skill is activated:

1. For each finding, route to the right working memory file:

   | Finding type                                                  | Lands in                                                     |
   | ------------------------------------------------------------- | ------------------------------------------------------------ |
   | Stack, framework, language, deployment                        | `projectOverview.md` (Stack section)                         |
   | Repository structure, monorepo rules, off-limits areas        | `projectOverview.md` (Repository Structure, Key Constraints) |
   | Decisions made (with context)                                 | `decisionLog.md`                                             |
   | Recurring patterns: naming, file organization, error handling | `conventions.md`                                             |
   | Type definitions, API shapes, schemas                         | `dataContracts.md`                                           |
   | Unresolved questions about the project's intent               | `openQuestions.md`                                           |

2. Compose draft content for each target section. Keep entries terse; working memory rewards brevity.
3. Include source as inline reference. For `decisionLog.md`, cite the commit hash or ADR file. For `conventions.md`, cite an example file path. For `dataContracts.md`, point at the source type definition.
4. Do not write to the working memory files directly; output drafts as proposed changes for `hydrate-reconcile`.

## Output

One drafted change per target file, grouped by file.

## Common gotchas

- Bloating `projectOverview.md`. The file is for orientation, not exhaustive cataloging. Keep it under a screen of content.
- Putting recent decisions in `conventions.md`. Decisions go in `decisionLog.md`; conventions are stable patterns.
- Generating `openQuestions.md` entries for things the AI just doesn't know. Open questions should be things the project's authors haven't resolved, not things the AI can't determine. Phrase them in the project's voice, not the agent's.
