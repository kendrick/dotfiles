---
id: T-000
title: One-line task title
spec: .agent-guild/state/spec.md#section-anchor
clauses: [C-1]
executor: worker-standard
executor_model: sonnet
checker: checker-deterministic
check_method: >-
  How this task is verified. Name each clause's check: a script invocation
  (.agent-guild/scripts/check-foo.sh <args>) or "checker-judgment: <one-line rubric>".
  Every clause in `clauses` must appear here.
status: pending
retries: 0
max_retries: 2
deps: []
escalations: []
artifacts: []
---

## Spec excerpt

<!-- ORCHESTRATOR writes this: the self-contained slice of the spec this task
covers. A worker sees only this section and the constitution, not the whole
spec. Include everything needed to do the work without guessing. -->

## Rework diagnosis

<!-- ORCHESTRATOR appends here on each FAIL, copied verbatim from the checker's
verdict Diagnosis. Newest at the bottom, headed with the attempt it addresses
(e.g. "### sonnet r1"). Empty until the first failure. -->

## Courier comparison

<!-- ORCHESTRATOR writes this once the second opinion lands, while #34 is still
open. Read both verdicts directly and record three counts: findings only the
courier raised, findings only the checker of record raised, and the overlap.
Name the clause behind each unique finding — #34 rules on the unique-finding
rate, and a count with no clause attached can't be audited later.

Say which cited clauses were deterministic. Those cross as pre-run output for
the far side to judge, so they agree by construction and are worth nothing as
evidence either way.

A denied or blocked second opinion goes here too, with the reason. An absence
recorded is data; an absence unrecorded reads later as agreement.

This section never reaches the vendor: compose-brief.py extracts only the spec
excerpt and rework diagnosis. -->
