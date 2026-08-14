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
dep_rationale: []
# One entry per dep in `deps`, naming what THIS task actually needs from
# that one task—not a summary of what the other task does. Example:
#   dep_rationale:
#     - T-001: provides the schema the tests import
# Every dep edge is a serialization point, so an edge nobody can justify is
# wall clock nobody agreed to pay. check-job-spec.py's R14 checks only that
# the two lists correspond one to one, and only on a task that also
# declares `owns`; whether a given rationale is actually true is the
# auditor's call, not R14's.
owns: []
# Each entry is an exact file path, or a directory prefix ending in `/`
# (covers everything under it). Repo-relative, forward slashes, no `./` or
# `..`—R15 refuses anything else, because a directory written without its
# trailing slash reads as a file claim and then collides with nothing.
# Tasks whose `owns` entries overlap must be connected by a dep path—one
# transitively depending on the other—because overlapping owners must never
# run concurrently. Leaving this empty is not a claim that the task writes
# nothing; it's the absence of a claim, and the wave reads it that way, so
# an owns-less task always dispatches alone.
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

<!-- Delete this whole section on a task nobody dispatched a courier for, which
since #167 is most of them. The second opinion is opt-in now; this block is
what a crossing you did ask for leaves behind, and it's where the retrospective
reads that crossing from.

ORCHESTRATOR writes it once the second opinion lands, or once it is settled
that none is coming. Read both verdicts directly and record three counts:
findings only the courier raised, findings only the checker of record raised,
and the overlap. Name the clause behind each unique finding — a count with no
clause attached can't be audited later.

Say which cited clauses were deterministic. Those never crossed at all:
compose-brief.py drops them before the brief is written, so the second opinion
covered the judgment clauses only and the counts above are read against that
shorter list.

A crossing you dispatched that never landed goes here too, with the reason.
An absence recorded is data; an absence unrecorded reads later as agreement.

This section never reaches the vendor: compose-brief.py extracts only the spec
excerpt and rework diagnosis.

Lead with the YAML below, then the prose. docs/courier-comparison.md is the
schema of record and explains every field; the two worth knowing before you
start are brief_framing, which has to be recorded from the dispatch you are
about to send because nothing persists it afterward, and verdict_pair, whose
filenames come from the ledger's artifacts field. -->

```yaml
repo:
job:
task:
verdict_pair: [{of_record: , lane: }]
clause_types_sampled:   # judgment | deterministic | mixed
brief_framing:          # confirm | attack | open | unknown | null
courier_outcome:        # pass | fail | blocked | denied
agreement_on_outcome:   # agree | disagree | null
disagreement_kind:      # substantive | evidence_packet | null
unique_courier: {defect: 0, inference: 0, evidence_quality: 0, coverage: 0}
unique_checker: 0
unique_checker_access_derived: 0
overlap: 0
changed_verdict: no
cost: {wall_s: , tokens_in: , tokens_cached: , tokens_out: , brief_tokens: , vendor_calls: }
```
