# Retrospective: `kendrick/dotfiles#19`

Job: add a guard to `dotfiles-sync` that refuses to commit from a source dir nothing could push from. Shipped as `d2a02f6` (the guard) and `faba26f` (five bats cases), suite green at 125.

## The headline: every catch landed on my work, none on the workers'

The summarizer reports 6 FAILs and attributes all of them to the auditor. That is correct and it is the whole story:

| verification surface | PASS | FAIL |
| --- | --- | --- |
| auditor, on my constitution | 2 | 5 |
| auditor, on my decomposition | 1 | 1 |
| checkers of record, on worker artifacts | 4 | 0 |

Zero reworks. Zero escalations. Zero disputes. Four workers across three model tiers built four artifacts and every one passed its check on the first dispatch.

Read one way that says the workers were good. Read more carefully it says something less comfortable: **the constitution needed five revisions to become checkable, and until it was, the checks it specified would have passed defective work and failed correct work.** The auditor measured both, repeatedly. The workers never got the chance to fail because the bar was rewritten five times before they saw it.

That is the org chart working exactly as designed — verification reaches the orchestrator's work first — but the ratio is worth carrying forward. Six of seven audits found something. If the next job budgets one audit round, it will ship a constitution in roughly the state this one was in at revision 2.

## What the audits caught, and why each was hard to see

Five CON-audit rounds, each finding something the previous four missed. Two of them found that the *fix* for a previous finding was itself wrong.

1. **A rebase in progress is also a detached HEAD.** Revision 1 demanded "three mutually exclusive state messages," which no correct guard can produce, and its case matrix let a guard checking only `symbolic-ref` pass every case *and* the deletion mutation, because every state it named detaches HEAD in practice. Fixed by building the rebase and merge cases on an **attached** HEAD and mutating per detector.
2. **A commit's id depends on its parent.** Revision 2 pinned `GIT_*_DATE` around the run under test, but the scratch repo's base commit is made during setup, so two repos built a second apart diverged and V-4 was a coin flip. Measured: 5 of 8 trials differed unpinned, 30 of 30 identical pinned through setup.
3. **`doctor.bats:62` prepends `PATH`.** I cited it as the harness precedent. The auditor ran an unguarded script under it and got all three of V-1's assertions passing with no guard present. `apps.bats:73` is the authoritative form, and it is authoritative because #17 fixed exactly this after a removed `fzf` stub kept resolving.
4. **A leaky harness makes the clean cases fake.** A guard placed after the clean-tree exit — the placement Phase 0 forbade — cleared all nine cases and all three mutations whenever the harness left the scratch repo dirty. I then claimed three mechanisms each closed it; the next audit showed only one did, because the negative control runs the *baseline*, which commits the dirt away, while the artifact under test refuses and leaves it behind.
5. **`git clean -xdff` touches nothing under `.git/`.** Offering it as an alternative to a fresh repo per case meant rebase markers survived into the merge cases, so a *correct* guard reported the rebase state there and failed V-2.
6. **Path-level scope checks cannot see inside an allowlisted file.** The DEC-audit found B-1 and D-4 reading `298c8a6..HEAD` while T-001's work is uncommitted, so both passed vacuously against any guard. A later audit committed the two edits the document explicitly forbids and watched every path-level check clear them, which is why D-1 gained a removed-line count and D-4 exists at all.

The through-line: **five of the six are a check that reads as precise while leaving unstated the one detail that decides its outcome.** That is the failure mode this repo's constitutions keep producing, and it is now three jobs running.

## What the constitution missed anyway

**B-5 did not exist until Phase 2.** All four cases T-002 shipped write a file before invoking the script, so every one exercised the dirty path. Refusing on a *clean* tree — Phase 0 override 1, the user's own decision, and the half of the fix aimed at `chezmoi update` rather than `git push` — had no permanent coverage. An edit moving the guard below `:130-133` would have regressed it with the whole suite green.

B-3 permitted this because it enumerates committed cases by repo state (attached, detached, rebase, merge) and says nothing about the tree. Six revisions went into making V-1's *probe* prove the clean path and none into requiring the shipped suite to keep proving it. T-002 satisfied its clause and its checker passed it correctly; the clause was the defect.

**It was found by the courier lane, not by the in-family check.** That is the single most useful thing this job produced for `kendrick/agent-guild#34`.

## The courier lane

Four crossings, all attack-framed on judgment rubrics, framing held constant so outcome differences attribute to the lane rather than the ask.

| task | clause | outcome | wall | brief | what it produced |
| --- | --- | --- | --- | --- | --- |
| T-001 | V-3, D-4 | fail (salvaged) | 120s | 5,525 | one interpretive disagreement, two evidence_quality findings about my brief |
| T-002 | B-2 | fail | 15s | — | **the coverage gap that added B-5 and T-004** |
| T-004 | B-2 | blocked | 180s | 1,519 | nothing |
| T-003 | D-3, D-4 | blocked | 120s | 1,892 | nothing |

**Zero unique defects in any artifact across all four.** One genuine gap in a *clause*. The pattern from the 2026-08-08 job holds and sharpens: the lane earns its cost reasoning about what it can read, and returns nothing when the question needs execution.

Three things worth carrying to #34:

- **Half the crossings produced no data.** Two timeouts out of four is the most important cost figure here, and it is not a payload problem: the 1,519-token brief timed out at 180s while the second-largest returned in 15s. Whatever drives it is not brief size, which cuts against the hypothesis the previous job's T-007 crossing raised.
- **Standing instruction 4 changed behavior mid-run.** T-001's crossing salvaged past its timeout and returned a verdict anyway. After that was recorded against it, T-004 and T-003 both returned conforming `blocked` verdicts instead. The instruction works; it needs enforcement in the lane rather than in the prompt.
- **Both of T-001's unique findings measured my brief, not the artifact.** It said the checker showed no evidence commits survive `git switch -c`, and no baseline for the `head_sha` shadowing check. The checker ran both; I did not carry either into the brief. Same failure the 2026-08-07 job's T-003 recorded. Composing a summary instead of transcribing evidence is apparently a lesson that does not stay learned.

## Two incidents, neither caused by a worker

**An auditor committed to `main`.** During the sixth CON-audit it meant to work in a throwaway clone, hit a `cd` to an empty variable, and committed 22 lines of probe code plus a stub test file as `f46ee11` — author `a <a@a>`, date faked to the epoch. Its own cleanup was denied by the permission system while its commit was not. Every diff-scoped clause in the job anchors at `298c8a6`, so leaving it would have meant D-1, D-2 and B-1 verifying the auditor's probe code as the worker's deliverable. Reset, and filed as `kendrick/agent-guild#118`: verifiers hold `Bash` with no path constraint while the orchestrator has `orchestrator-write-guard`.

**The machine's real `dotfiles-auto-sync` LaunchAgent fired mid-job** and committed the uncommitted guard as drift (`75a2325`). The worker recovered and the digest verified, but this is a standing hazard for any guild job in this repo that leaves work uncommitted across tasks — which is most of them. The previous job unloaded the agent for its duration; this one did not, and paid for it. **Unload it in Phase 0, not after the first collision.**

One silver lining worth recording: T-004's checker used that accidental commit as a forensic baseline to prove T-002's four cases were byte-identical, which `git diff` could not do because `tests/sync.bats` was untracked.

## Check-infra debt

Zero ERROR verdicts; every check ran. Three things still owe work:

- **The summarizer's catch count needs a source dimension.** "6 catches, all by auditor" reads as verification finding six defects. It found six defects *in the orchestrator's own specification*, and zero in the workers' artifacts. Those are different facts and the report should not flatten them.
- **The courier's ledger line records one call per crossing regardless of retries**, still, per `agent-guild#116`. T-001's crossing is recorded as one call at 120s; whether it retried internally is unrecoverable.
- **`tests/lint.bats` and `tests/mutation-check.sh` cover only the test suite.** Neither reaches `dot_local/bin/`, so B-1 had to hand-roll its scan over added lines. Any future job touching a script under `dot_local/bin/` will hand-roll it again.

## Input for the next Phase 0

1. **Budget five audit rounds, not one.** Six of seven found something, and two found that a previous fix was wrong. A constitution that passes its first audit in this repo has probably not been attacked hard enough.
2. **Unload the auto-sync LaunchAgent before Phase 1.** Add it to the job checklist.
3. **Ask of every clause: what detail decides this check's outcome that I have not stated?** Marker file contents, repo isolation between cases, which diff range, whether the instrument can go silently dead. Five of six blockers this job were exactly that question going unasked.
4. **For every clause that proves a behavior in a checker's probe, ask whether the shipped suite keeps proving it.** B-5 exists because that question was never asked, and a courier asked it instead.
5. **Absence-only checks need a positive control.** B-1's verdict rode entirely on `grep` exiting 1, and a two-space indent would have made it pass against anything.
