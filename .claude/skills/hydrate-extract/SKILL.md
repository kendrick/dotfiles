---
name: hydrate-extract
description: >
  Pull findings from a single source location. Each finding is one sentence
  about a fact, decision, convention, or contract, plus a pointer back to
  source. Deterministic for structured sources, AI semantic for prose.
---

# hydrate-extract

Input: one source location from `hydrate-discover` output.

When this skill is activated:

1. Determine extraction mode:
   - **Deterministic:** manifests (parse JSON/TOML), file structure (walk dirs), config files, conventional-commit prefixes
   - **AI semantic:** README prose, ADR bodies, PR descriptions
2. For each detected fact:
   - Identify the target file in working memory (see `hydrate-draft` mapping table)
   - Pull a one-sentence statement
   - Note source provenance: file path, commit hash, line range
3. Output one finding per fact as a small structured record.

## Output shape

```yaml
findings:
  - source: package.json
    target: projectOverview.md (Stack section)
    statement: 'Stack is React 18, TypeScript 5, Tailwind 3, vitest.'
    confidence: high
  - source: src/api/types.ts
    target: dataContracts.md
    statement: 'User and Account interfaces define the canonical API response shapes.'
    confidence: high
  - source: git log
    target: decisionLog.md
    statement: 'Migrated from Redux to Zustand on 2026-03-12 (commit a4f8e21).'
    confidence: medium
```

## Common gotchas

- Inferring conventions from a single example. A pattern is a convention only when it shows up in multiple places.
- Treating outdated comments as current truth. Cross-check what comments claim against what the code actually does.
- Pulling debugging breadcrumbs into findings. "We had a flaky test on Tuesday" is session noise, not working memory.
