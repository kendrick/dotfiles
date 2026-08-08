# Retrospective: kendrick/dotfiles#21

A false assertion must fail its test. Baseline `61213fe`, landed at `814d917` across five commits, unpushed.

9 tasks, 23 verdicts, 0 disputes, 0 escalations, 1 retry. `bats tests/` green at 120 cases, every one of the 54 converted sites proven to still fail when inverted.

## The headline, and it is not in the summary numbers

`summarize.py` reports **5 catches: 4 by the auditor, 1 by the courier**. Both halves of that are wrong in ways worth understanding, because the same distortion will appear in every job run under this regime.

**The courier's one counted FAIL was a false positive.** T-001's crossing failed the task for evidence that covered only `tests/helpers.bash` rather than B-1's full guarded surface. That was correct about the clause and wrong about the task — T-001's `check_method` scoped B-1 deliberately, since at that point the six conversion files still held all 54 bare `[[` by design. The finding was real but it was not a defect in the work.

**The courier's one genuine catch is invisible.** On T-006's r1 crossing the far side found that the reintroduction guard matched only at line start, so `true; [[ 1 -eq 2 ]]` — a bare statement bash 3.2 swallows identically to a line-initial one — evaded it entirely. That crossing then hit the codex lane's quota and died before persisting its verdict. It appears in the run state as `quota_event: true` and nothing else. The defect it found appears as `T-006 retries=1`.

So the single most valuable thing verification produced in this job is recorded, in the machine-readable state, as a quota error.

## Catches

**Four audit FAILs on the constitution and decomposition**, all before a worker ran. Every one was the same defect in a different clause: **a requirement stated in a clause's text that its check did not test.**

- CON-audit r0 — V-1's mutation planted its canary only in a `.bats` file, while its stated failing example was a guard that skips `helpers.bash`. It passed against its own failing example.
- CON-audit r1 — V-2 compared the mutation script's HEAD line numbers against baseline line numbers, but B-3 mandates adding a `load` line to every test file, so every line shifts. The check could never have passed against a correct implementation.
- CON-audit r2 — V-2's TAP requirement went into the clause text and never into the check. A script with a correct parser that still judged by file exit status passed all three parts.
- DEC-audit r0 — T-007 had no enumeration boundary. `install-failures.bats` carries 30 pre-existing helper calls that became indistinguishable from this job's conversions the moment T-001 moved the definitions into `helpers.bash`. A naive glob finds 82-plus and fails its own count check on the first run.

**One rework, T-006**, from the courier finding above.

**Three defects workers caught in their own work** and disclosed rather than hid. These never became FAILs and so appear nowhere in the counts, but each would have shipped silently:

- The mutation harness reported **0 sites for `font.bats` instead of 12**, without erroring, because `<<-'STUB'` heredocs with tab-indented terminators broke its heredoc tracking. Only the per-file count caught it — and that per-file count exists only because CON-audit r1 forced V-2 to stop cross-checking against baseline line numbers.
- The guard's first draft was killed by this bug's own cousin: `hits="$(grep ...)"` followed by `local status=$?` propagates the substitution's exit code under `set -e`, so grep's clean pass aborted the case and the guard reported `not ok` unconditionally.
- The harness's `case`-block needle search matched the enclosing `@test` header, because that test's *name* contains the words "undeclared" and "casks" in prose.

## Strain

**One retry across nine tasks, no escalations.** Routing held: four conversion tasks at sonnet with opus judgment checkers, the two script deliverables at sonnet, the two prose tasks at opus.

The strain was not in the tasks. **It was in Phase 0.** Four constitution revisions and three audit FAILs before a single worker was dispatched, against a job whose entire deliverable is a mechanical conversion of 54 lines. The measured facts — 54 sites, 53 assertions, 119 cases, the `[[`-versus-`[ ]` split — were correct after the first measurement pass and never moved. What took four rounds was making the *checks* honest.

That ratio is the finding. Establishing ground truth was cheap; writing verification that could actually fail was not.

## Disputes

None filed. Two orchestrator rulings were made directly instead, both recorded in the task files:

- **T-006's residual gaps.** After the semicolon hole was closed, three further evasions remain: the zero-space `true;[[ x ]]`, a compound after a background `&`, and one inside a `case` arm. All three verified present. Ruled acceptable, with the boundary stated once rather than per construct: *this guard catches every form present in the corpus and every form idiomatic test code would use; complete coverage of statement position requires parsing shell, not matching it.* Trying to close the zero-space gap made the pattern match `helpers.bash`'s own comment, which is the collision that proves the ceiling is real.
- **T-002's `case` where B-2 names an `if`.** My divergence, not the worker's: the DEC-audit forced the `case` form and I never updated B-2's text. B-2's operative properties all hold.

## Check-infra debt

**No ERROR verdicts, and that undercounts too.** Three infrastructure failures occurred that the schema has no way to record:

1. **T-006's r0 verdict was written as invalid JSON** and had to be re-emitted. The checker embedded the grep pattern it ran — containing `\[\[` — directly into a JSON string, where `\[` is not a valid escape. This is agent-guild#112's failure mode, and the trigger is systematic rather than incidental: a deterministic checker's evidence field naturally quotes the regex it executed, and this constitution's clauses are mostly regexes. It will recur.
2. **Two agents died mid-flight on an API session limit.** No partial state was left behind and `retries` correctly stayed at 0, but nothing in the run state distinguishes an infrastructure death from a worker failure.
3. **`STALLED.md` was written twice, both times falsely** — once with four opus checkers legitimately mid-derivation, once with T-009's checker running. Reported to agent-guild#111 with the specific finding that the gate's suggested next move ("assign it and dispatch its executor") would, for three of the four named tasks, have violated the dependency order the DEC-audit added to stop a guard from passing vacuously.

Two issues filed from this run: **#115** (severity used for confidence rather than defect impact — every in-family checker did it on every task, five for five, while the courier got it right three times in five) and **#116** (a crossing that retries records one ledger line, so wasted vendor calls are uncounted).

## What the constitution missed

**V-1's check encoded a narrower rule than V-1's text.** The clause says the guard fails the suite "if a bare `[[` or `((` statement is reintroduced anywhere on the guarded surface." I wrote its check with a `^` anchor and never asked whether "bare statement" and "line-initial statement" were the same thing. They are not.

Four constitution audits did not catch it, and the reason is instructive: **they audited whether each check matched its clause, not whether my regex matched my own prose.** The auditor read "first non-whitespace token" in the check and "bare statement" in the text and treated them as the same claim, because I had written them as though they were.

That is the gap to carry into the next Phase 0. Falsifiability asks "can you state a failing example this check would catch." It does not ask "does the check's language mean the same thing as the clause's language." Those are different questions and this job only failed the second one.

**Everything else the constitution demanded, it got.** The per-file mutation counts caught a silent 12-site coverage hole. The TAP-not-exit-status requirement caught nothing in the end, but only because the worker implemented it correctly after being told four times in the task file why it mattered. The `cp`-not-`git checkout` restore rule mattered concretely: the work was uncommitted for the entire job, and a `git checkout` restore in either the guard's mutation block or the harness's own restore path would have silently reverted all 54 conversions to baseline.

## The #34 dual-check evaluation

Nine crossings attempted, eight ledgered: **819,798 input tokens, 19,088 output**, one timeout, one quota exhaustion, one denied.

| task | clauses | brief framing | outcome | unique courier findings |
| --- | --- | --- | --- | --- |
| T-001 | deterministic | confirm | fail | 1 evidence-quality (false positive on the task, right about the clause) |
| T-005 | judgment | confirm | pass | none |
| T-004 | judgment | confirm | pass | none |
| T-002 | judgment | attack | pass | 1 inference — closed a real gap in the checker's mutation reasoning |
| T-003 | judgment | attack | pass | 2 evidence-quality, 1 coverage |
| T-007 | deterministic | attack | blocked | timed out at 120s on the largest brief of the run |
| T-006 r1 | deterministic | attack | quota | **1 real defect** — plus 2 further gaps, and 2 misreads I had to correct |
| T-008 | judgment | attack | pass | 1 coverage — durability of the prose read cold |
| T-009 | mixed | — | denied | lane exhausted; a judgment clause went unsampled |

**Zero defects found by the courier in any worker's deliverable.** The one real defect it found was in *my* clause, not in anyone's code.

**The read-versus-execute asymmetry held across every crossing.** In-family checkers raised 16 unique findings to the courier's 6, and every single divergence went the same way: the checker was ahead because it could run things. It probed `assert_contains 'needle' 'SOMETHING ELSE'` to prove an argument was really a haystack. It matched a needle with and without a trailing comma to prove the comma was load-bearing. It injected a failing registry key and ran the conversion *and* a `[[ ]]` control to prove the fix was real. The courier reasoned about the same lines from their text.

Where the courier added value, it was doing what a cold reader is structurally good at and an executing checker skips past:

- **T-002** — the checker proved polarity empirically by flipping four assertions and watching four cases go red. The courier supplied the missing logical step: each flipped assertion is *terminal in its `@test` body*, so nothing later could have caused the red. Without that, the mutation is suggestive rather than conclusive.
- **T-008** — asked whether an agent reading only the working-memory files six months from now could come away with the narrow rule, it quoted the specific sentences that carry the general one rather than asserting a conclusion.
- **T-006** — asked the one question I had flagged as an unknown, it named a construct I had not tested.

**The brief-framing correlation, with its confounds stated.** Confirm-framed briefs produced 1 unique finding across 3 crossings; attack-framed produced 5 across 4, including the only real defect. But: attack framing also produced the only timeout, on the largest brief of the run, and the confound cannot be separated here. T-002 and T-003 were the two tasks whose checkers produced the most intricate evidence, so the far side may simply have had more to bite on. n=9 is not a result.

**Two courier claims were wrong and had to be corrected by hand.** It reported `true | [[ ... ]]` as a swallowed gap — the pipe propagates correctly. It reported `: [[ ... ]]` likewise — `[[` after a command name is an ordinary word, the test never executes, and the line asserts nothing whether flagged or not. Both were plausible and both were false. **A courier's claim is not evidence until it is re-derived**, which is the same standard this constitution applies to workers and should apply here too.

**The methodological recommendation for #34.** A single unique-finding rate destroys the actual result. This run produced 0 defects, 1 analytical contribution, 3 evidence-quality critiques, 2 coverage observations, and 2 false claims. Rendering that as "6/9 crossings produced a unique finding" or "0/9 found a defect" are both less true than the breakdown. Stratify by clause type and by brief framing, or the number means nothing — and record `vendor_calls`, which #116 shows is currently unrecoverable and is the one dimension that cannot be reconstructed retroactively.

## For the next Phase 0

1. **Audit clause language against check language, not just check against clause.** This job's only shipped defect lived in the gap between "bare statement" and `^[[:space:]]*`.
2. **A guard built on pattern matching has a stateable ceiling.** Say where it is in the clause, rather than discovering it one construct at a time under rework.
3. **Deterministic checkers should emit JSON through a serializer, never by hand.** Their evidence fields quote the regexes they ran.
4. **Green is not evidence, and the constitution should keep saying so.** This suite ran green for months with an unknown number of assertions checking nothing. `tests/mutation-check.sh` is what changed that; `tests/lint.bats` is a tripwire. Be clear which is load-bearing.
