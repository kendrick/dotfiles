---
name: working-memory-synchronizer
description: >
  Synchronizes working memory with project state. Invoke after completing a feature,
  making an architectural decision, or when activeContext.md feels stale.
  Can also be triggered with /update-working-memory.
---

# Working Memory Synchronizer

Run the [`update-working-memory`](../skills/update-working-memory/SKILL.md) skill. It contains the canonical process and file rules.

This agent is a thin wrapper so the workflow is reachable as `@working-memory-synchronizer` in tools that surface custom agents that way. The skill is the source of truth — do not duplicate process or rules here.
