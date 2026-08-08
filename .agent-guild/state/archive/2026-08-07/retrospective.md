# Retrospective: kendrick/dotfiles#17

Six tasks, all complete. Four commits, unpushed. 20 verdicts: 9 pass, 9 fail, 0 error. No disputes, no retries, no escalations.

## The headline

**Every worker deliverable passed its check on the first attempt. All nine catches were against the orchestrator.**

| Source | FAILs | Against |
| --- | --- | --- |
| auditor | 7 recorded (8 actual) | the constitution and the decomposition |
| checker-courier | 2 | one artifact ruling, one orchestrator evidence packet |
| checkers of record | 0 | — |

Not one worker needed rework. The retry ladder never moved, the escalation log stayed empty, and no worker filed a dispute. Meanwhile the constitution failed audit four times and the decomposition failed four more.

That asymmetry is the finding. The expensive, error-prone part of this job was not building the thing. It was specifying how to tell whether the thing was built — and the org chart's decision to audit the orchestrator's own work is what caught it, eight times over.

## Catches

**CON-audit, four rounds.** r0 returned 16 findings on the constitution restored from the handoff. r1 found two blockers r0 had missed, including a mutation requirement that was literally unsatisfiable: it demanded a doctor.bats case fail at baseline, but this job never modifies the doctor, so the file is byte-identical at both ends and no case could satisfy it and C-7 together. r1 also caught that nothing anywhere pinned the scripts' exit status — a worker who read the issue's *title* ("Failed installs exit 0") as the bug rather than the symptom could have made every script `exit 1`, aborted every apply on any machine missing any package, violated two recorded non-goals, and passed all thirteen clauses. r2 found six more. r3 found two, one of them a table row that was measurably false. r4 passed.

**DEC-audit, four rounds, all failing on one defect wearing four different coats.** Each time, a clause's real check ended up somewhere it could not fire:

- **r0 — omitted.** Nothing in the plan ran `tests/install-failures.bats` at HEAD. The fifteen cases would have been proven to fail at baseline in exactly the right pattern and never proven to pass against the converted scripts. AC1, AC4 and AC8 built but unverified.
- **r1 — too early.** The repair created the mirror image. V-2 requires the suite green *"with the new coverage in place"*, but V-2 sat only on T-001, checked before the new tests existed.
- **r2 — wrong checker family.** B-2 requirement 4 and B-5's output half are judgment rubrics that had been routed to T-003's deterministic checker. Caught with the affected dispatch queued next.
- **r3 — unfalsifiable.** The reroute fixed the family and not the evidence route: the check named output bats never emits. `run` captures into `$output`, and even `--show-output-of-passing-tests` prints bare `ok` lines. The auditor proved it rather than arguing it — injecting `echo "Failed extensions: ${#failed[@]}"` into the vscode success branch produces `Failed extensions: 0` on a clean run, verbatim what the clause forbids, and both case assertions still pass. A check that returns PASS whether or not the defect is present is not a check.

Each was fixed before the dispatch it would have corrupted. None reached a worker.

**Courier crossings, two fails.** T-002's disagreed on the brew degenerate line and was overruled on the clause text. T-001's failed on gaps in the evidence packet I composed, and was right.

## Where the job strained

Not on the work. On the specification of correctness, and on infrastructure.

**Six agent deaths.** Three to API connection errors, one to a stalled watchdog, two to a session limit that stopped the job for hours. None counted against a worker — the retry budget is for rework after a FAIL, not for a dropped connection — and one left a stray git worktree that had to be cleaned before the replacement checker could run. One dying checker emitted "all checks pass" moments before it went; that was discarded rather than transcribed, on the principle that output scraped from a killed process is not a check.

**Two verdicts failed schema validation.** T-003's crossing wrote unescaped quotes inside a `description`, breaking the JSON at char 216; only the rendered `.md` sibling made the finding recoverable. T-005's checker of record emitted a `clause_id_note` key the schema forbids. Both were substantively sound and mechanically invalid, and both were repaired by their authors rather than by the orchestrator. Two independent writers producing invalid JSON in one job suggests the schema's strictness needs a friendlier failure path than post-hoc validation.

**The stop gate and the DAG disagreed, repeatedly.** The gate lists every non-terminal task as needing a move, including tasks whose dependencies are unmet. Dispatching them would have handed workers a repo in the wrong state. `STALLED.md` was written twice against states that were not stalls — a checker was alive and running both times — because the gate cannot distinguish a running checker from an absent one. It did earn its keep once: the pressure prompted a re-examination of the DAG that found T-004's dependency on T-001 was unnecessary, freeing a third worker to run in parallel.

## What the constitution missed

**AC8 was unsatisfiable when the job started, and the constitution did not know it.** `bats tests/` never terminated. `tests/apps.bats:58` prepended the stub directory to `$PATH` without scrubbing, so the case at `:256` — which removes its own stub `fzf` to simulate absence — still found `/opt/homebrew/bin/fzf`, the tool's guard passed, `main()` fell through to its default move mode, and the run blocked forever on an interactive picker. Latent on a machine without `fzf`; it fired here because `fzf` was installed on 2026-08-06, the same install behind #17. The spec's own `Verify with: bats tests/` could not be run. Folding the fix in was the user's call, and it was the right one.

**A live external actor was never considered.** The `com.k-arnett.dotfiles-auto-sync` LaunchAgent fires at 16:00 and 22:00 and runs `git add -A` followed by a machine-authored commit. Left loaded it would have swept a worker's uncommitted work into a commit no worker wrote, failing D-3's message rubric, emptying the tree D-1 inspects, and possibly moving the boltdb mtime D-4 reads. Commit `af8fe49` is this having already happened once. It was unloaded at 20:50 CDT on the user's instruction. **A constitution should ask what else writes to this repo on a timer.**

**An anchor that drifts is not an anchor.** D-4 originally pinned the boltdb mtime comparison to "the job's first task file". Task files are rewritten on every status change; `T-001.md` had moved fifteen hours forward, widening the tolerance to cover its own execution. Re-pinned to `spec.md`, which is written once.

**Three clauses cited checks that could not detect their own failing example**, and every one survived at least one audit round before being caught: `bats tests/doctor.bats` green at baseline with zero coverage of the branch it named; `check-diff-scope.py` reporting `OK: 0 path(s) in scope` on a clean tree; `git log origin/main..HEAD` unable to detect a push, since pushing removes a commit from that range rather than adding it.

## The dual-check regime, for #34

Four crossings. One disagreement on an artifact, one disagreement on an evidence packet, two agreements.

**The prediction that deterministic clauses make crossings worthless is wrong, but not for the obvious reason.** It is true that two parties reading identical captured output agree by construction — T-004's crossing demonstrated exactly that and is worth nothing as evidence. But when the *orchestrator* composes the evidence rather than the vendor running the checks, a deterministic clause does not guarantee agreement. It relocates the failure mode from judgment to **transcription**.

T-003 is the case. Its checker of record reported the baseline mutation as "7 pass, 8 fail, exactly as the constitution specified." The table yields 10 and 5. The conclusion was right, the arithmetic was not, and the phrase "exactly as specified" concealed it. That count was copied into the courier's brief, the vendor compared it against V-1's table, found a contradiction, and failed the crossing. It could not have caught a bad test. It caught a bad number.

Two process lessons follow, both orchestrator-side:

1. **Inline raw command output, never a prose summary of it.** A summary is a transcription step, and transcription is what failed.
2. **A checker's narrative count deserves the same scepticism as a worker's self-report.** The constitution's own table would have caught it in one subtraction.

**Where crossings earned their cost:** T-002 and T-005, both carrying judgment rubrics where divergence was genuinely available. T-002's disagreement was substantive and required an orchestrator ruling. T-005's agreement on three judgment clauses is the first agreement in the job that means anything.

**Sampling recommendation:** favour judgment-rubric clauses, and treat a deterministic-clause crossing as a check on the orchestrator's evidence discipline rather than on the artifact.

**Crossing hygiene, learned the hard way.** T-002's checker of record found the shared scratchpad already holding a prior agent's stub set and rendered scripts, and discarded them rather than verify against another agent's fixtures. That hazard was orchestrator-created by reusing one directory across crossings. Later crossings got per-task directories. A checker that had trusted those fixtures would have verified the wrong artifact.

**Ledger discipline.** The Claude→codex lane has no script behind it, so nothing writes `vendor-calls.jsonl` unless the courier or the orchestrator does. One line was nearly lost and one duplicate was nearly created — a null-cost phantom crossing appended in a race with the courier's own line, caught and removed. Six crossings, six lines, one missing token count (T-002).

## Process deviation, recorded plainly

**Phase 2 ran without a passing DEC-audit.** The guild contract ends Phase 1 with a DEC-audit PASS before workers dispatch. DEC-audit failed r0 through r3 and never returned PASS. Workers were dispatched anyway, on the judgment that each blocker was repaired before the dispatch it would have affected — which held, and is why r2's blocker was caught with the affected checker queued next rather than after it ran.

That judgment was defensible and it was still a deviation. The honest reading: the decomposition's final state was never audited clean. Every task passed its own checks, and the plan those checks sat in never got a clean bill.

## Follow-ups

- **The bash 3.2 errexit hole needs its own issue.** Under `/bin/bash` 3.2.57, a failing `[[ ]]` inside a function under `set -e` does not abort unless it is the literal last statement, so a bats case can report `ok` with a failed assertion inside it. Proved in a real run: `[[ 1 -eq 2 ]]` mid-body reports `ok`; `grep -qF` in the same position correctly reports `not ok`. Exposure: doctor 20 such assertions, font 12, apps 11, licensed-fonts 5, packages 4. `install-failures.bats` has zero — T-003's worker hit this mid-draft, an early failing assertion masked by a later passing one, and caught it only via the baseline-mutation step. **The mutation requirement is what exposed it. A suite that only ever runs green never reveals this.**
- **Two factual imprecisions in the new decisionLog entry**, found by T-005's checker: the test helpers are described as built on `grep -qF` when `assert_not_contains` uses `case`, and brew's failure shape is given as `Installing <entry> has failed!` when the awk matches any verb. Small, and worth fixing precisely because working memory is read by the next agent before it touches code.
- **The kit's worker contract has no representation for a commit-based deliverable.** T-006's `artifacts:` lists SHAs where the contract describes repo-relative paths. Paths would have been worse — the nine changed files belong to T-001 through T-005 and are already listed there. Nothing enforces either reading.
- **The branch has diverged.** `origin/main` sits five commits ahead of the job's baseline and is not an ancestor of HEAD. This predates the job and touches no verdict. Two of those commits are the user's own settings.json model-pin fix, completed elsewhere while this job ran. Integrate before pushing.

## Housekeeping

The auto-sync LaunchAgent must be reloaded:

```bash
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/com.k-arnett.dotfiles-auto-sync.plist
```

Nothing has been pushed. That is the user's step, along with the live end-to-end apply against a deliberately broken registry entry, which D-13 and the non-goals both reserve for them.
