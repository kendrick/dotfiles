# Constitution: <job name>

<!--
Phase 0 produces this ONCE. It is the single standard "done right" is measured
against—every task, every verdict, and every dispute ruling references it by
clause id. The /constitution skill writes it; the auditor agent must PASS it
(CON-audit) before any worker is dispatched (dispatch-guard enforces this).

THE FALSIFIABILITY RULE: every clause must name a concrete check method AND be
something you can state a failing example for. If you cannot describe an
artifact that violates the clause, the clause is unfalsifiable—rewrite it or
drop it. "The site should feel welcoming" is not a clause. "Every page's
<h1> matches the nav label that links to it" is.

CHECK METHOD is one of:
  - a script: .agent-guild/scripts/check-foo.sh <args>  (exit 0 = pass; deterministic)
  - a judgment call: "checker-judgment: <one-line rubric the checker applies>"
Deterministic checks route to checker-deterministic (haiku); judgment checks
route to checker-judgment (opus). A scoped-diff clause ("touch only these
paths") has a standard script—don't hand-roll it as judgment prose:
.agent-guild/scripts/check-diff-scope.py <allowed>... [--ignore <path>].
-->

## Clauses

### C-1: <short name>
- **text**: <the standard, stated so a violation is recognizable>
- **check**: .agent-guild/scripts/check-foo.sh <args>   <!-- or: checker-judgment: <rubric> -->
- **severity**: blocker   <!-- blocker | major | minor -->
- **failing example**: <one concrete artifact that would violate this>

### C-2: <short name>
- **text**:
- **check**:
- **severity**:
- **failing example**:

## Protected content

<!-- If any author words must ship verbatim, list the manifest and point every
relevant clause's check at .agent-guild/scripts/check-protected.py. -->
- manifest: .agent-guild/templates/protected-passages.md   <!-- or a job-local copy -->

## Non-goals

<!-- What this job explicitly does NOT cover, so workers don't gold-plate and
the auditor doesn't flag missing coverage that was never in scope. -->
-
