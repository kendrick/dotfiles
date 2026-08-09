# Constitution: dotfiles-sync refuses to commit from an unpushable source dir

Job source: `kendrick/dotfiles#19` via `.agent-guild/state/spec.md`. Baseline commit for every diff-scoped check in this document: **`298c8a6`**.

The defect this job closes ran undetected for six weeks: `dotfiles-sync` committed 26 times onto a detached HEAD, reported success every time, and left the machine unable to push and unable to pull. Every clause below exists to make a repeat of that silence impossible, and each is falsifiable against a scratch repo.

Three decisions settled with the user at Phase 0, which override the spec where the spec is silent:

1. **The guard runs before the clean-tree early exit.** A blocked state is refused whether or not there is anything to commit. The spec's AC 1 only covers the dirty case; a detached HEAD with a clean tree also blocks `chezmoi update`, which was half the incident's cost.
2. **Three blocked states, not five.** Detached HEAD, rebase in progress, merge in progress. Cherry-pick and revert are the same hazard class but have no incident behind them here, and bisect needs no entry because it detaches HEAD.
3. **`dotfiles-sync` only.** `dotfiles-doctor` gains nothing in this job.

## Revision 2

Revision 1 failed CON-audit with six blockers. Three would have failed a correct implementation; three would have passed a defective one. Recorded here rather than quietly applied, because two of them are mistakes this repo has now made in three consecutive jobs.

- **A rebase in progress is also a detached HEAD.** Verified: `.git/rebase-merge` present and `git symbolic-ref -q HEAD` exiting 1 at the same instant. Revision 1's V-2 demanded "three mutually exclusive matches," which no correct guard can satisfy, and its V-1 case matrix let a guard that never looks at `rebase-merge` pass every case *and* the deletion mutation, because the rebase cases were detached anyway. Detection precedence is now stated in V-2, and V-1's matrix builds the rebase and merge states on an **attached** HEAD so each detector is independently load-bearing, with a per-detector mutation to prove it.
- **`git diff --cached` is not empty in the merge and rebase cases** regardless of what the guard does. An add/add conflict stages a path before `dotfiles-sync` is ever invoked. The assertion is now "unchanged from before the run," matching the shape the commit-count assertion already had.
- **`git commit` prints an abbreviated SHA that varies with the commit timestamp**, so revision 1's V-4 was a coin flip that also forbade normalizing the one thing that varies. Both runs now pin `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE`, which makes the SHA a function of content. V-4 also asked for stdout and stderr separately; `:26` merges them, so the comparison is over the single merged stream.
- **`check-diff-scope.py` reads working-tree views only.** D-3 requires committed work, so on a clean tree D-1 returned `OK: 0 path(s) in scope` and passed its own failing example. D-1 and D-2 now diff `298c8a6..HEAD`.
- **B-1's checks never reached the artifact.** `tests/lint.bats` scans `tests/*.bats`, `tests/helpers.bash`, and `tests/mutation-check.sh`; `mutation-check.sh` iterates a hardcoded six-file list. Neither covers `dot_local/bin/executable_dotfiles-sync`, and revision 1's own grep returned pre-existing hits on the unmodified script with no polarity stated. B-1 now applies `lint.bats`'s pattern verbatim to the added lines only.
- **The probe seam was undefined.** Five phases run before `cd "$SRC"`, and `chezmoi re-add` is unguarded. B-4 now names the whole stub contract.

Line citations throughout are re-derived against `298c8a6`; revision 1's were stale by roughly twenty lines.

## Revision 3

The r1 audit closed five of revision 2's six blockers and found two more, plus four majors. Both new blockers are the same species: a clause that reads as precise while leaving the one detail that decides the outcome unstated.

- **V-4's date pinning was scoped to the wrong thing.** A commit's id depends on its parent, and the parent is the scratch repo's base commit made during *setup*, which env vars wrapped around the run never reach. Pinning now covers the whole harness, setup included, and the clause says why rather than asserting that pinning "makes the sha a function of content."
- **`.git/MERGE_HEAD`'s content decides D1 and D2.** Empty file: `git rev-parse --verify -q MERGE_HEAD` exits 1 while `test -f` exits 0. So the idiomatic guard passes or fails those cases according to how the checker built them, and the merge-detector mutation then reports a working detector as dead. The construction is now specified.
- **V-3 checked half its own text.** It required `notify_fail` and then asked only about the recovery command. Spec AC 3's second half was covered by nothing.
- **Spec AC 7 was half-mapped.** Nothing required a *committed* case for the attached path; V-4 and V-5 exercise it only through the checker's transient probes. A worker could have shipped blocked-state cases alone and passed everything.
- **B-4 cited `tests/doctor.bats` as its precedent while requiring tools to be absent, and `doctor.bats:62` prepends the inherited `PATH`.** Under that harness the auditor ran case A1 against an unguarded script and got exit 1 with commits and staged paths unchanged: all three of V-1's assertions satisfied with no guard present. That is B-4's own failing example reached by following B-4's own citation. The authoritative form at `tests/apps.bats:73` replaces it, and a positive control now runs first so a broken harness announces itself instead of manufacturing nine passes.
- **B-4's stated reason for excluding `code` was wrong.** The failed redirect does not abort under `set -e`. The real hazard is a clean case being turned dirty.

One minor from r1 also folded in: V-1's probe is now explicitly the checker's own and may not be delegated to the worker's bats file.

## Revision 4

The r2 audit confirmed both r3 blockers and all four majors closed, and found one blocker plus two majors of its own. The blocker is the sharpest finding of the four audits, because it defeats a Phase 0 override through a route no clause was watching.

- **The harness control was one-sided, and the missing side is the one that matters.** A guard placed *after* the clean-tree exit — the placement override 1 forbids, and which the constitution itself calls half the incident's cost — passes all nine V-1 cases, all three per-detector mutations, and V-5, provided the harness leaves the scratch repo dirty in the cases labelled clean. The auditor built that guard and that harness and measured it. Putting `$STUBS` inside the scratch repo is enough to cause it, and nothing forbade that. Closed three ways: the control is now two-sided, V-1 asserts pre-run porcelain per case rather than merely recording it, and B-4 requires the stub and `$HOME` paths to sit outside the repo. Any one would close it; all three are cheap and the failure is silent.
- **B-3 was the mirror image of the r1 major it was written to close.** It named a committed *attached* case and no committed *blocked-state* case, and "the cases covering that detector's state must go red" says nothing when that set is empty. All four are now named.
- **V-3's notification half could not be followed as written.** It told the checker to read osascript invocations out of V-1's runs, and V-1's record carries exit code, commit count, staged paths and porcelain, not that. V-3 now runs its own probe and checks the `Dotfiles sync failed` title, which is the only thing separating `notify_fail` at `:33-36` from the bare `notify` at `:28-31`.
- Four minors folded in: V-4 now normalizes the unpinned UTC date token the commit subject builds at `:142`; V-1 asserts its own after-`:128` placement claim instead of leaving it as prose; V-3 checks the notification title rather than the bare fact of a call; and the mutation restores in V-1 and B-3 now name the backup step they restore from, which was circular.

## Revision 5

The r3 audit confirmed r2's blocker closed, then showed my account of *how* it was closed was wrong, and found a second class of escape that four audits had walked past.

- **Only one of the three mechanisms actually closes the r2 blocker, and revision 4 claimed all three did.** The auditor built a harness fully compliant with B-4 — stubs and `$HOME` outside the repo, authoritative PATH — that reused one scratch repo across all nine cases, which is what V-1's singular wording described. The defective guard cleared everything. B-4's outside-the-repo rule closes exactly one way of causing the leak; B-4's negative control is structurally incapable of catching any of it, because the control runs the *baseline*, which commits the dirty marker away, while the artifact under test refuses and leaves it behind. V-1 now requires a fresh repo per case, and says so with the reason.
- **The porcelain assertion was pointed at the wrong target.** Under a leaky harness a correct guard violates it in the same four cases a defective one does, so as an assertion about the artifact it fails good work and hides bad. It is now a precondition on the harness that voids the run, which is the language B-4's control already used and V-1 lacked.
- **D-1 could not see an out-of-scope edit inside an allowlisted file**, which is where every remaining non-goal lives. Both halves were path-level. The auditor committed the two edits this document explicitly forbids — the `:137` bare-compound "fix" and flipping `${DOTFILES_AUTO_PUSH:-0}` to `:-1` — and D-1 passed its own failing example, with B-1 and V-4 passing too. D-1 gains a third part: the script's diff must contain no removed lines. A guard is an insertion, so correct work satisfies it for free.
- **V-4's date fix did not fix anything.** The `:142` token goes into the commit message and therefore into the commit id, and V-4 forbids normalizing the sha, so normalizing the visible date left the shas divergent. `date` is now stubbed in the harness instead.
- **V-3's title assertion was uncheckable against B-4's stub contract**, which asked the `osascript` stub only to record that it ran. It now records the full argument list.
- The placement assertion's claim is corrected rather than dropped: it catches a guard hoisted above the six pre-commit phases and does not catch one sitting immediately before `:128` using `git -C "$SRC"`, which is functionally equivalent anyway. What enforces override 1 is the clean cases. Phase-heading line numbers are also corrected, to the `echo` lines at `:39`, `:57`, `:65`, `:75`, `:85`, `:103`, rather than the phase comments a line or two above each.

## Revision 6

The r4 audit found one blocker and would otherwise have passed the document.

- **V-1's reset alternative was not equivalent to a fresh repo.** Revision 5 offered "build a fresh one per case, or hard-reset and `git clean -xdff` between cases" as interchangeable. Neither command touches anything under `.git/`, so the `rebase-merge` and `rebase-apply` directories the B and C cases create survive into D1 and D2. Measured against a *correct* guard: the merge cases report the rebase state and fail V-2, the merge-detector mutation fails to flip them and fails V-1, and a guard with no merge detector becomes indistinguishable from one that has it. The porcelain precondition does not warn, because `git clean -xdff` does remove the working-tree dirt its stated reason names. The alternative is deleted.
- Three minors folded in: the porcelain precondition now voids in both directions, since a dirty case that starts clean exercises the wrong branch just as silently; B-4's control gets its own repo; and `DOTFILES_AUTO_PUSH` is named in the stub contract, because pinning it to `0` would make an additive change to the push default invisible to V-4.
- **D-4 is new.** D-1's three parts are all mechanical and none can see a *purely additive* out-of-scope change inside the allowlisted script. The auditor measured two that clear every other clause: an added arm in the push-failure classifier at `:169-177`, which no check ever executes, and a new phase gated behind a tool B-4 makes absent. D-4 is the judgment read that covers them.

## Revision 7

The r5 audit returned **PASS**, with one major and three minors. All four are folded in here rather than deferred, because each fix is a sentence and three of them are the same species of gap this document spent five revisions learning to spot. Revision 7 changes no clause's intent.

- **B-1 was the document's only absence-only check with no positive control.** Its verdict rides entirely on `grep -E` exiting 1, so any way the pipeline goes inert reads as a pass, and there is a one-character route in: the pattern sits indented inside a bullet in this file, and pasted with those two leading spaces it matches nothing, including B-1's own failing example. B-1 now requires confirming the pattern matches that example before a zero-match result is trusted. What escaped was narrow — a behaviorally broken guard still fails V-1 through V-4 — but it was a latent violation of a blocker clause that nothing else in the repo covers, since neither `lint.bats` nor `mutation-check.sh` reaches the sync script.
- **B-4's control halves may share a repo, and sharing kills the negative half.** After the positive half the repo is detached and clean, which is A2's construction, so the economy is the natural thing to do. Each half now gets its own.
- **B-3 imported V-1's `MERGE_HEAD` rule but not its repo-isolation rule.** A shared fixture leaves the merge case red under the merge mutation. It fails safe, costing a retry rather than admitting a defect, but for nothing.
- **D-2 had D-4's blind spot one directory over.** An assertion deleted from inside an existing case is invisible: floors count `@test` blocks, the skip check reads added lines only, and a case with one fewer assert still reports `ok`. D-2 gains the removed-line count.
- D-4's severity is raised to blocker, matching D-1, whose enforcement it completes.

The clause ordering in the D block reads 1, 4, 2, 3 and is left alone; clause ids are the reference mechanism and renumbering after six audits would invalidate every citation in five verdicts.

## Revision 8

Added **B-5** during Phase 2, after T-002's courier crossing surfaced a gap no clause covered.

All four of T-002's committed cases write a file before invoking the script, so every one exercises the dirty path. The clean-tree refusal — Phase 0 override 1, the user's own decision, and the half of the fix aimed at `chezmoi update` rather than `git push` — is covered only by V-1's A2/B2/C2/D2, which are the checker's transient probes and never run again. An edit that moved the guard below `:130-133` would regress exactly that behavior with the whole suite staying green.

T-002 satisfied B-3 as written and its checker passed it correctly. B-3 enumerates committed cases by repo state (attached, detached, rebase, merge) and says nothing about the tree, which is the omission. Six revisions went into making V-1's *probe* prove the clean path and none into requiring the shipped suite to keep proving it.

B-5 is a new clause rather than an amendment to B-3, so T-001 and T-002 are not retroactively re-scoped against a bar that did not exist when they were checked. T-004 carries it.

## Notes for the worker

Three things the audits surfaced that no clause covers, recorded so they are not rediscovered the hard way.

- `tests/lint.bats` scans `$BATS_TEST_DIRNAME/*.bats`, so any new test file is lint-covered through D-2 even though B-1 is scoped to the sync script.
- **A refusal leaves the source dir dirtier than it found it.** `chezmoi re-add` at `:66` runs six phases before the guard, so by the time the refusal fires, live `$HOME` changes have already been captured into the working tree. This is correct and deliberate — the capture is the point, and only the *commit* is unsafe — but it is the opposite of what "refuses before staging" sounds like. Do not "fix" it by hoisting the guard above the capture phases; V-1's placement check exists partly to catch that.
- **D-3's green-at-checkout rule constrains commit order.** Tests committed before the guard they cover are red at their own checkout. The guard and its tests go in together, or the guard goes first.

## Clauses

### V-1: The guard refuses in all three blocked states, before staging

- **text**: With the source dir in any of the three blocked states (`HEAD` detached; `.git/rebase-merge` or `.git/rebase-apply` present; `.git/MERGE_HEAD` present), `dotfiles-sync` exits non-zero, creates no commit, and never reaches `git add -A`. This holds with the tree dirty **and** with the tree clean, which places the guard after `cd "$SRC"` at `:128` and before the clean-tree early exit at `:130-133`. All three detectors are independently load-bearing: none may rely on another catching its state.
- **check**: build a scratch repo with a bare origin per B-4's harness, and run these nine cases:

  | case | `HEAD` | markers present | tree |
  | --- | --- | --- | --- |
  | A1 | detached | none | dirty |
  | A2 | detached | none | clean |
  | B1 | **attached** | `.git/rebase-merge/` | dirty |
  | B2 | **attached** | `.git/rebase-merge/` | clean |
  | C1 | **attached** | `.git/rebase-apply/` | dirty |
  | C2 | **attached** | `.git/rebase-apply/` | clean |
  | D1 | **attached** | `.git/MERGE_HEAD` | dirty |
  | D2 | **attached** | `.git/MERGE_HEAD` | clean |
  | E1 | detached | `.git/rebase-merge/` (real stopped `git rebase`) | dirty |

  B through D are constructed by creating the marker directly on an attached branch, because a real `git rebase` or conflicted `git merge` detaches or leaves `HEAD` attached only incidentally, and spec AC 4 asks for exactly the attached case. **The marker's content is part of the case, not an implementation detail.** D1 and D2 must be built with `git rev-parse HEAD > .git/MERGE_HEAD`, so the file holds a real commit id: against an empty `MERGE_HEAD`, `git rev-parse --verify -q MERGE_HEAD` exits 1 while `test -f` exits 0, which means an idiomatic rev-parse guard passes or fails these cases depending on how the checker built them, and the merge-detector mutation then reports a working detector as dead. B and C are directories, detected by existence, and `mkdir` is sufficient.

  For each case: record `git rev-list --count HEAD`, `git diff --cached --name-only`, **and `git status --porcelain`** before the run, then assert `exit != 0`, commit count unchanged, and the staged-path list unchanged. Not "empty": an add/add conflict stages a path before the script is ever invoked.

  **Each case gets its own scratch repo, built from scratch. There is no reset alternative.** B-4's two-sided control gets its own repos too, one per half.

  A reused repo fails this clause for two independent reasons, and cleaning does not fix either. A refusing case leaves its dirty marker behind by design, because the guard refuses instead of committing, so case *n*'s leftovers become case *n+1*'s starting state and every clean case after the first is clean in name only. And `git reset --hard` plus `git clean -xdff` touches nothing under `.git/`, so the `.git/rebase-merge` and `.git/rebase-apply` directories B and C install by `mkdir` survive into D1 and D2. A correct guard then reports the rebase state on the merge cases, failing V-2; the merge-detector mutation fails to flip them, failing V-1; and a guard with no merge detector at all becomes indistinguishable from one that has it, which is precisely the independence this table exists to establish.

  **The pre-run porcelain is a precondition on the harness, not an assertion about the artifact.** The four clean cases (A2, B2, C2, D2) must show it empty and the five dirty cases must show it non-empty. If a clean case shows anything, **or a dirty case shows nothing, the run is void and the harness is broken; do not record a verdict against the artifact from it.** Both directions void: a dirty case that starts clean exercises the wrong branch just as silently as the reverse. A correct guard and a defective one both leave those four cases non-empty under a leaky harness, so reading it as an artifact failure fails correct work and reading it as a pass hides the defect. Fix the harness and re-run.

  This matters because it is the only mechanism that catches the whole class. A guard placed *after* the clean-tree exit at `:130-133` — the placement Phase 0 override 1 exists to forbid, and which the constitution itself calls half the incident's cost — clears all nine cases and all three mutations whenever the clean cases are not genuinely clean. B-4's outside-the-repo rule closes one way of causing that and no others, and B-4's negative control cannot catch it at all, because the control runs the baseline, which commits the marker away and leaves the repo clean, while the artifact under test refuses and leaves it behind.

  **Placement gets a weaker check, stated as what it is.** For at least one refusing case, the captured log must contain the headings of the six phases that precede `cd "$SRC"` at `:128`, printed at `:39`, `:57`, `:65`, `:75`, `:85` and `:103`. This catches a guard hoisted above those phases; it does not catch one placed immediately before `:128` operating through `git -C "$SRC"`, which emits all six headings and is functionally equivalent anyway. The placement that actually matters for override 1 is "before the clean-tree exit," and the clean cases are what enforce it.

  This probe is the checker's own. It may not be delegated to the worker's bats file — running the worker's cases and reading their asserts would make the worker's instrument the measurement, which is the arrangement B-2 exists to prevent.

  Then run three **per-detector** mutations. Before the first, copy the unmodified script to a path outside the repo, and restore from that copy between mutations; never `git checkout`, which would restore `298c8a6` and revert the entire guard rather than the one detector under test, since the job's work is uncommitted while this runs. Delete only the detached-HEAD check and require A1 and A2 to flip to exit 0 or a created commit; delete only the rebase check and require B1, B2, C1, C2 to flip; delete only the merge check and require D1 and D2 to flip. A single whole-guard deletion is not sufficient and does not satisfy this clause.
- **severity**: blocker
- **failing example**: A guard whose only test is `git symbolic-ref -q HEAD`, per the spec's own hint that this "is the whole test." It passes A, B, C, D and E under a whole-guard mutation, because every state the spec names except the attached ones detaches `HEAD` in practice. The per-detector mutation is what catches it: deleting the rebase check changes nothing, because there is no rebase check.

### V-2: The refusal names the state it found, under a stated precedence

- **text**: The refusal names which blocked state was detected, and a reader of `~/.local/state/dotfiles/last-sync.log` can tell a detached HEAD from a suspended rebase from a suspended merge without running a further command. Because a rebase in progress is *also* a detached HEAD, the guard checks operation-in-progress markers **before** it checks `HEAD`, and reports the most specific state that applies.
- **check**: from V-1's nine runs, capture output per case and assert: A1 and A2 match a detached-specific string; B1, B2, C1, C2 match a rebase-specific string; D1 and D2 match a merge-specific string; and each of the three strings fails to match the other two families' cases. Then assert **E1 matches the rebase string and not the detached string** — that case is both, and it is the one that proves precedence rather than luck.
- **severity**: blocker
- **failing example**: A guard that tests `symbolic-ref` first and returns early. E1 reports a detached HEAD, which is true and useless: the user runs `git checkout main`, git refuses because a rebase is in progress, and the message that was supposed to name the next step named the wrong one.

### V-3: The refusal is actionable

- **text**: The refusal names a command that actually gets the user out of the state it found, and fires a notification through the existing `notify_fail` helper at `:33-36` so it reaches the desktop the way every other failure in this script does. The command has to fit the state: what gets you off a detached HEAD is not what finishes a suspended rebase.
- **check**: checker-judgment, in two halves, both required. **The command:** for each of the three states, does the named command, run as printed, move the repo out of that state or begin the recovery a human must finish? Reject a command that is merely diagnostic (`git status`), one that discards work without saying so, and one that is right for a different state than the one being reported. **The notification:** does the refusal path actually call `notify_fail`, on every blocked state rather than some of them? Read the call site, then run V-1's nine cases again under B-4's harness as this clause's own probe — V-1's record is fixed at exit code, commit count, staged paths and porcelain, and does not carry this — and assert the recording `osascript` stub was invoked in all nine, with the title `Dotfiles sync failed`. The title is what distinguishes `notify_fail` at `:33-36` from the bare `notify` at `:28-31`; asserting only that osascript ran would accept a guard that fired the drift notification instead. A guard that prints a perfect message to a log nobody opens satisfies half of spec AC 3 and none of its intent.
- **severity**: blocker
- **failing example**: The detached-HEAD refusal suggests `git checkout main`. On the incident's actual repo that silently strands 26 commits, because it moves `HEAD` without carrying them anywhere, and the message says nothing about the commits it just orphaned.

### V-4: The attached-branch path is byte-identical

- **text**: On an attached branch with no operation in progress, the script's output and exit code are byte-identical to the baseline script at `298c8a6`, for both the dirty and clean cases. The guard is invisible when it does not fire.
- **check**: check out `dot_local/bin/executable_dotfiles-sync` at `298c8a6` to a temp path, and run baseline and working-tree versions against two identically-constructed scratch repos, dirty and clean, under B-4's harness. Compare the **single merged stream** — `:26` is `exec > >(tee -a "$LOG") 2>&1`, so stdout and stderr are one stream by the time anything observes them — plus the exit code. Normalize the scratch path and nothing else. In particular the abbreviated sha may not be normalized: a changed sha is how a real tree difference would show up. The `:142` date token is handled at the source by B-4's stubbed `date` rather than by normalization here, because that token goes into the commit *message* and therefore into the commit id, so normalizing the visible date would leave the sha divergent anyway.

  **`GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` must be exported to the same fixed value for the whole harness, scratch-repo setup included, not merely around the run under test.** A commit's id is a function of its tree, message, author and committer identity and dates, **and its parent**. The parent here is the scratch repo's base commit, made during setup, which env vars scoped to the run never reach: two repos built a second apart get different base ids, so `git commit`'s abbreviated sha differs downstream and this clause fails a correct implementation at random. Measured against a byte-identical copy of the unmodified script, that difference appeared on every trial at a 1.2s setup gap and on 1 of 5 back-to-back; pinning the dates through setup made the streams identical, measured 30 times across gaps from back-to-back to 2.5 seconds.
- **severity**: blocker
- **failing example**: The guard prints `==> Source dir is pushable` before proceeding. Harmless-looking, and it changes every successful run's log forever, which is what this clause exists to prevent.

### V-5: The refusal is distinguishable from the "nothing to commit" exit

- **text**: In `~/.local/state/dotfiles/last-sync.log`, a refusal is distinguishable from the existing `==> Nothing to commit. Already in sync.` early exit at `:130-133`. Both end the run early; only one is a problem, and a reader scanning the log must not have to infer which happened.
- **check**: from V-1's clean-tree cases (A2, B2, C2, D2), assert the log contains no line matching `Nothing to commit` and does contain the refusal's marker. From a clean attached run, assert the reverse. Both directions, so a refusal that merely prints a warning and then falls through to the old message fails.
- **severity**: major
- **failing example**: The refusal path warns and then falls through to the clean-tree branch, so the log reads `==> Nothing to commit. Already in sync.` underneath the warning and the last line a skimmer sees says everything is fine.

### B-1: bash 3.2 rules hold on every line this job adds

- **text**: Every line this job adds to `dot_local/bin/executable_dotfiles-sync` obeys the repo's bash 3.2 rules: no bare `[[` or `((` as a statement in command position, every array expansion guarded with `[ "${#arr[@]}" -gt 0 ]`, nothing assuming bash 4. The script runs `set -euo pipefail` at `:16`, so a bare command substitution whose command fails aborts the run.
- **check**: extract the added lines with `git diff 298c8a6..HEAD -- dot_local/bin/executable_dotfiles-sync | grep '^+' | grep -v '^+++'`, strip the leading `+`, drop whole-line comments, and match against `tests/lint.bats`'s own pattern verbatim:

  ```text
  (^[[:space:]]*|;[[:space:]]+|&&[[:space:]]+|\|\|[[:space:]]+|\{[[:space:]]+|\bthen\b[[:space:]]+|\bdo\b[[:space:]]+|\belse\b[[:space:]]+)(\[\[|\(\()
  ```

  **Polarity: zero matches required**, i.e. `grep -E` exits 1 over the added lines.

  **Confirm the instrument before trusting the result.** This is the only absence-only check in the document: its verdict rides entirely on `grep` exiting 1, so every way the pipeline can go inert reads as a pass. Before accepting zero matches, run the pattern against this clause's own failing example and require it to match. If it does not, the run is void and the pattern was transcribed wrong — most likely with the two leading spaces it carries in this file, where it sits indented inside a bullet. Dedented it is byte-identical to `tests/lint.bats:50`; indented it matches nothing at all, including the failing example below. Scoping to added lines is deliberate: the unmodified script already contains bare compounds at `:88`, `:122` and `:137`, which are out of this job's scope and must not be "fixed" (D-1 forbids it). Note also that neither `tests/lint.bats` nor `tests/mutation-check.sh` covers this file — lint scans `tests/*.bats`, `tests/helpers.bash` and `tests/mutation-check.sh`, and the harness iterates a hardcoded six-file list — so running them proves nothing about this artifact and neither is accepted as evidence for this clause.
- **severity**: blocker
- **failing example**: The guard reads `[[ -z "$(git symbolic-ref -q HEAD)" ]]` as a statement inside a helper, followed by anything else. Under bash 3.2 its failure is discarded, the helper returns the status of whatever ran last, and the guard reports pushable on a detached HEAD. The bug this repo just spent a job eliminating, reintroduced by the fix for a different one.

### B-2: The tests drive the real script, never a copy of its logic

- **text**: The new cases exercise `dot_local/bin/executable_dotfiles-sync` itself against a throwaway repo, never a reimplementation of the guard inside the test file, and never the real `~/.local/share/chezmoi`.
- **check**: checker-judgment: read the new test file and answer two questions. Does each case invoke the actual script, or does it reimplement the guard's logic and assert against the copy? And is there any path on which a case could reach the real source dir if a stub failed to take effect — in particular, does anything derive a path from an unstubbed `chezmoi source-path`?
- **severity**: blocker
- **failing example**: The test file defines its own `is_pushable()` mirroring the script's and asserts on that. Every case passes, V-1's mutations leave them green because they never called the script, and the guard could be deleted entirely without a single test noticing.

### B-3: The new cases fail when the guard is removed

- **text**: The committed cases cover both the blocked states **and** the attached path, per spec AC 7, and each blocked-state case fails when the guard it covers is removed. A case that stays green against an unguarded script is measuring nothing, whatever it asserts.
- **check**: first, confirm the committed tests contain **all four** of: a case driving the attached, no-operation path and asserting the run commits normally; a detached-HEAD case; a rebase-in-progress case; and a merge-in-progress case. They may live in one new file or several. Any merge case must build its marker with `git rev-parse HEAD > .git/MERGE_HEAD`, and each case must get its own freshly built scratch repo — both for the reasons V-1 gives. A shared fixture leaves the merge case red under the merge-detector mutation for the same accumulated-marker reason, which costs a retry rather than admitting a defect, but costs it for nothing. Each requirement is independent, and none may be satisfied by the checker's own probes — V-4's and V-5's attached runs are transient, and V-1's nine cases are the checker's. Both halves of this list have to be named explicitly, because a mutation instruction phrased as "the cases covering that detector's state must go red" is vacuous over an empty set: a file holding only the attached case would satisfy it three times over and clear D-2's rising total besides.

  Then apply V-1's three per-detector mutations in turn, running the new test files after each, and require that the cases covering that detector's state report `not ok` while the others, including the attached case, stay green. Before the first mutation, copy the unmodified script to a path outside the repo; restore from that copy between mutations. Never `git checkout` — the job's work is uncommitted while this runs, so a checkout restores `298c8a6` and silently reverts the whole guard rather than the one detector under test. Name the case-to-mutation mapping in the verdict so the pairing is auditable.
- **severity**: blocker
- **failing example**: A case asserts `[ "$status" -ne 0 ]` against a run that also fails for an unrelated reason, such as a missing stub. It is red today, red with the guard removed, and red for the wrong reason in both.

### B-4: The probe harness reaches the commit phase honestly

- **text**: Six phases run before `cd "$SRC"` at `:128`, printing their headings at `:39`, `:57`, `:65`, `:75`, `:85` and `:103`, and any probe or test that does not neutralize them never reaches the guard at all. The harness stubs exactly what those phases need and nothing more, and every stub is named rather than assumed.
- **check**: the harness must satisfy all of the following, verifiable by reading it and by running a probe against an unmodified script and confirming it reaches `:130`:
  - `chezmoi` stubbed, handling `source-path` with no arguments (prints the scratch repo path), `re-add` (exit 0 — the call at `:66` is **not** guarded by `command -v` and aborts the run on failure), `status` (empty output, consumed by the loop at `:87-95`), and `source-path <path>` (exit non-zero, so the drift loop takes the `|| continue` at `:90`).
  - `code`, `brew`, `jq`, `claude-plugins-capture`, and `claude-settings-normalize` absent from the stub `PATH`, so each guarded phase takes its documented skip branch. `code` matters most, and not for the reason it might appear: a failed redirect there does **not** abort under `set -e`, it prints an error and the run continues. The hazard is that if `$SRC/dot_config/` happens to exist, the phase writes `vscode-extensions.txt` into the scratch repo and turns a clean case dirty, which silently collapses V-1's clean/dirty axis into one column.
  - `osascript` stubbed to a no-op that records **its full argument list**, not merely the fact that it ran, so a test run fires no desktop notifications and V-3 can read the notification's title back. A `touch "$REC"` stub satisfies "records its invocation" and makes V-3's title assertion uncheckable.
  - `DOTFILES_AUTO_PUSH` left unset, so the opt-in branch at `:159` runs as it ships. Pinning it to `0` produces the same behavior today but makes V-4 blind to a change in that default, which is a documented non-goal, and the harness should not be what decides whether a non-goal is observable.
  - `date` stubbed to a fixed value. `:142` builds the commit subject from `$(date -u +%Y-%m-%d)`, which no `GIT_*_DATE` variable reaches, and because that token is part of the commit message it changes the commit id: two commits identical but for the token hash differently. V-4 forbids normalizing the sha, so pinning the date at the source is the only way both its runs can match across a midnight boundary.
  - `HOME` redirected, so `$HOME/.local/state/dotfiles/last-sync.log` is a scratch path and V-5 reads the run it just made.
  - **The stub `PATH` is authoritative, not prepended.** `export PATH="$STUBS:/usr/bin:/bin"`, the form `tests/apps.bats:73` uses. `tests/doctor.bats:62` still writes `PATH="$STUBS:$PATH"` and is **not** the precedent to copy here: appending the inherited `PATH` means a tool this clause requires to be absent still resolves to the real binary, which is the exact defect #17's T-001 fixed in `apps.bats` after a removed `fzf` stub kept resolving and hung the suite. See `_working-memory/antipatterns.md`, 2026-08-05.
  - `$STUBS` and the redirected `$HOME` live **outside** the scratch repo. Nothing else forbids putting them inside it, and doing so leaves `?? stubs/` in the porcelain, which turns every clean case dirty and collapses V-1's clean/dirty axis exactly as the `code` hazard above would.
  - **A two-sided control runs before any V-1 case**, both halves against the baseline script at `298c8a6`, which has no guard, and **each half against its own freshly built repo**. Sharing one is the natural economy — after the positive half the repo is detached and clean, which is A2's construction — and it kills the negative half: with anything untracked left inside, the positive half commits it away, so the negative half prints `Nothing to commit` and passes for the wrong reason. **Positive:** against case A1 it must reach `:130` and create a commit. **Negative:** against case A2 it must print `==> Nothing to commit. Already in sync.` and create no commit. The positive half alone is not sufficient and this clause is not satisfied by it: a harness that silently dirties the scratch repo passes the positive half, fails nothing, and hides the defect that lets a guard placed after the clean-tree exit clear all nine V-1 cases and all three mutations. If either half misbehaves the harness is broken and every V-1 result afterward is meaningless. Under a prepending `PATH` the positive half has been observed to fail this way: exit 1, commit count unchanged, staged paths unchanged, all of V-1's assertions satisfied by a script containing no guard at all.
- **severity**: blocker
- **failing example**: A harness that stubs only `chezmoi source-path`, per revision 1's claim that it is "the seam." `chezmoi re-add` then runs for real against the developer's actual `$HOME`, and either mutates it or exits 1 and takes the whole probe with it, in which case every V-1 case reports a non-zero exit and passes for a reason that has nothing to do with the guard.

### B-5: The clean-tree refusal is covered by the shipped suite

- **text**: At least one committed case exercises a blocked state with a **clean** working tree and asserts the run refuses. The guard's placement before the clean-tree exit at `:130-133` is Phase 0 override 1, and it is the half of the fix that addresses `chezmoi update` being blocked rather than `git push`.
- **check**: read the committed test files and confirm at least one case reaches the script without writing anything into the scratch repo first, and asserts a refusal. Then prove it discriminates: move the guard below the clean-tree exit — the placement override 1 forbids — and require that case to report `not ok` while the dirty cases stay green. Restore from a copy taken outside the repo, never `git checkout`.
- **severity**: blocker
- **failing example**: Every committed case writes a file before invoking the script, so all of them are dirty. A later edit moves the guard below `:130-133`, the clean path silently stops being guarded, `chezmoi update` starts failing on a detached machine exactly as it did for six weeks, and the whole suite stays green. This is not hypothetical: it is the state T-002 shipped in, which B-3 permitted because B-3 enumerates cases by repo state and says nothing about the tree.

### D-1: Scope

- **text**: This job changes `dot_local/bin/executable_dotfiles-sync` and files under `tests/`. Nothing else. The push path at `:159-182` is correct as written and is not touched; `dotfiles-doctor`, `.chezmoidata.toml`, and every template stay untouched.
- **check**: three parts, all required.
  1. `git diff --name-only 298c8a6..HEAD` yields only `dot_local/bin/executable_dotfiles-sync` and paths under `tests/`.
  2. `.agent-guild/scripts/check-diff-scope.py dot_local/bin/executable_dotfiles-sync tests/` exits 0 against any uncommitted remainder. Part 1 does not subsume this: that script reads working-tree views only, so on a clean tree it reports `OK: 0 path(s) in scope` and proves nothing about what was committed.
  3. **The change to the script is purely additive**: `git diff 298c8a6..HEAD -- dot_local/bin/executable_dotfiles-sync | grep -c '^-[^-]'` returns 0. Parts 1 and 2 are both path-level, so neither can see an out-of-scope edit *inside* an allowlisted file, and every remaining non-goal lives exactly there. Flipping `${DOTFILES_AUTO_PUSH:-0}` to `:-1` and "fixing" the pre-existing bare compound at `:137` were both committed in an audit and passed every other check in this document, including B-1 and V-4. A guard is an insertion, so a correct implementation satisfies this for free; anything that needs to delete a line from this script is out of scope by construction and belongs in a different job.
- **severity**: blocker
- **failing example**: The worker also "fixes" the opt-in push default while it is in the file, since an auto-push would have surfaced the problem sooner. That is a documented non-goal and the reasoning behind the default is at `:153-158`. Committed, it is invisible to a working-tree scope check.

### D-4: Nothing out of scope rides along inside the script

- **text**: The lines this job adds to `dot_local/bin/executable_dotfiles-sync` implement the guard and nothing else. No new phase, no change to how any existing phase behaves, no edit to the push-failure classifier.
- **check**: checker-judgment: read every added line from `git diff 298c8a6..HEAD -- dot_local/bin/executable_dotfiles-sync` and answer whether each one is part of refusing an unpushable source dir. D-1's three parts are all mechanical and cannot see this: they are path-level plus a removed-line count, so a purely **additive** out-of-scope change is invisible to them and to V-4, which never executes the push path at `:159-182` and never sees a phase gated behind a tool B-4 makes absent. Two measured examples that clear every other clause in this document: an added `elif` arm in the push-failure classifier at `:169-177`, and a new phase guarded by `command -v brew` that writes into `$SRC`. Reject any added line whose justification is something other than the guard.
- **severity**: blocker
- **failing example**: The worker notices while in the file that the push-failure classifier has no arm for a shallow-clone rejection and adds one. Purely additive, plausibly useful, untested by anything here, and a change to a path the constitution declares correct as written and out of bounds.

  Severity matches D-1's rather than sitting below it: this clause is the half of scope enforcement that D-1's mechanical parts structurally cannot reach, so a job that satisfies D-1 and fails D-4 has an unreviewed behavior change shipping inside an allowlisted file.

### D-2: The suite stays green and no coverage is lost

- **text**: `bats tests/` exits 0 with nothing skipped or deleted, and every per-file floor holds at or above its current count: apps 18, doctor 11, font 44, install-failures 17, jsonc 9, licensed-fonts 7, lint 1, packages 13. The total rises above 120, because this job adds cases and removes none.
- **check**: `bats tests/` exits 0; `/usr/bin/grep -c '^@test'` per file against the floors above; `git diff 298c8a6..HEAD` adds no line matching `^\+\s*skip\b`; `bats --count tests/` is greater than 120; and `git diff 298c8a6..HEAD -- tests/ | grep -c '^-[^-]'` returns 0. New files contribute no removed lines, so this constrains only the pre-existing suite, which this job adds to rather than edits. The diff is taken against the baseline, not the working tree, for the same reason as D-1. The removed-line count is D-1 part 3's logic one directory over: an assertion deleted from inside an existing case is invisible to everything else here, because the floors count `@test` blocks, the skip check looks only at added lines, and a case with one fewer assert still reports `ok`.
- **severity**: blocker
- **failing example**: A new case needs the suite to run in a specific order, so an existing `font.bats` case gets `skip`ped to make it pass, and the skip is committed. The suite is green, one floor silently drops, and a working-tree diff sees nothing.

### D-3: The commits explain themselves

- **text**: Each commit stands alone, is green at checkout, and its message explains why the change exists rather than restating the diff. The issue is referenced with `Refs #19`, never a closing keyword, because the end-to-end verification on a real machine belongs to the user after this job ends. No `Co-Authored-By` trailer, and no hard-wrapped body lines.
- **check**: checker-judgment: read each commit message against the repo's own standard, and verify the standalone claim by checking out each sha and running `bats tests/`. Reject a message that narrates the diff, one that uses `Closes`/`Fixes`, and any trailer attributing co-authorship.
- **severity**: major
- **failing example**: One commit titled `fix: add guard to dotfiles-sync` whose body lists the functions added. It says what the diff already says, and a reader six months on still does not know that 26 commits were stranded for six weeks or that the clean-tree case was a deliberate choice.

## Protected content

None. This job ships no author copy, taglines, or legal text; the only user-visible strings it adds are the refusal messages, and V-2 and V-3 govern those by behavior rather than by verbatim wording.

## Non-goals

Carried from the spec, plus the two settled at Phase 0:

- **Auto-recovering.** Aborting a rebase, or picking which branch orphaned commits belong on, is a human decision. Refusing loudly is the fix.
- **Changing the opt-in push default.** Deliberate and documented at `:153-158`; an unattended push cannot reach the 1Password SSH agent, and a push-protection block should be seen rather than buried.
- **Rewriting the 26 existing commits.** Preserved on `origin/rescue-autosync`.
- **Making `chezmoi update` report a blocked pull.** Real and worth its own issue; the guard here is what would have caught this six weeks earlier.
- **Cherry-pick, revert, and bisect states.** Settled at Phase 0: same hazard class, no incident behind them, and bisect is already covered by the detached-HEAD check.
- **Any change to `dotfiles-doctor`.** Settled at Phase 0. #24 is about to rewrite its package section and two jobs in that file would collide.
- **Fixing the pre-existing bare compounds at `:88`, `:122`, `:137`.** Real instances of the bug #21 eliminated in the test suite, out of scope here, and B-1 is deliberately scoped to added lines so nobody is tempted.
