---
name: hydrate-reconcile
description: >
  Compare drafts against existing working memory and against the codebase.
  Annotates each draft as net-new, would-overwrite, or conflicts-with-code.
  Greenfield projects skip the existing-working-memory comparison.
---

# hydrate-reconcile

Input: drafts from `hydrate-draft`.

When this skill is activated:

1. For each draft, check against existing working memory if present:
   - **Net new:** no matching content; safe to add.
   - **Would overwrite:** existing content covers the same territory; surface the diff.
2. For each draft, sanity-check against the codebase. The draft asserts something; does the code agree?
   - If yes: leave the annotation as-is.
   - If no: flag as **conflicts with code**. Either the draft is wrong (extracted from stale source) or the code is wrong (drift from stated intent). Investigation needed.
3. Output the drafts plus annotations.

## Output

The original drafts plus a reconciliation block per draft.

## Common gotchas

- Trusting a stale README over current code. The README is a source, but it can lie. When in conflict, the code is more often right.
- Flagging convention drafts as "conflicts" when the code has multiple patterns. The convention is the dominant pattern; minority patterns are noise unless they're the new direction.
- Treating an existing working memory entry as authoritative when it predates a major refactor. `git log _working-memory/<file>.md` tells you when the entry was last touched. If the codebase moved on, the entry needs updating.
