# Retrospective: #22, the Fetch Phase That Aborted Every Install

**Job weight**: standard, the bats harness and its stub conventions already exist but need extending, and the artifact is a `run_onchange` script that fires unattended during apply.

The user did not correct the derivation. The document reached exactly 8 clauses against a ceiling of 8, the first time in this repo's archive that a job has landed on the number rather than under it. That reads as a correct weight against a tight budget, so the next standard job should expect to spend its whole allowance.

Audit rounds: CON 3 (r0 FAIL, r1 PASS, r2 PASS), DEC 4 (r0, r1, r2 FAIL, r3 PASS). Sixteen dispatches, three tasks, ten verdicts, zero disputes, zero retries, zero escalations. No courier was dispatched, so there are no second opinions to report.

## The Catches, and Where They Landed

Four FAILs, and every one came from the auditor reading my work. Not one checker turned back a worker, and all three tasks passed on the first attempt.

That asymmetry is the finding. The org chart puts the auditor above the orchestrator on the theory that the boss's work needs verifying too, and this run is the argument for it: the specification held every defect, and by the time workers were dispatched there was nothing left to catch. Had the auditor been advisory, four defects would have shipped, two of them green.

**CON r0, the check that passed against the bug.** C-1's script check went green on the *unfixed* installer. The pre-existing code already printed the unresolvable entry with a two-space indent, so any assertion resting on summary text alone passed whether or not a retry branch existed. The auditor didn't argue this. It built the plausible-looking test pair and watched it go green, which meant C-1's own failing example passed C-1's own check. Fixed by count-gating the check and requiring assertions to read a recorded log of `brew bundle` invocations.

**DEC r0, the task that could not return.** T-003 was decomposed as pure verification, with `artifacts: []` and an excerpt saying it writes no files. `subagent-return` refuses any `worker-*` return with an empty artifacts list. Executed both directions: RC 2 empty, RC 0 with one entry. That would have surfaced only after both building tasks had shipped, with nothing left to overlap the stall, and the improvisation it invites fails C-7, because a worker told to list what it produced writes a report, and anywhere outside `.agent-guild/state/` is out of scope on the very clause T-003 exists to check.

The same round found my reason for parking C-4 and C-7 on T-003 was right by accident. I claimed a diff-scope check from T-001 would flag T-002's in-flight writes. It wouldn't, because the allowlist already contains the peer's paths. The conclusion survives on attribution instead: a stray write turns C-7 red on both tasks with nothing to say which one did it.

**DEC r1, the fix that introduced the defect.** Giving T-003 ownership of `_working-memory/` meant telling it what to write there, and I wrote "close that loop rather than opening a new entry beside it." `AGENTS.md:36`, three lines below the line I had cited, says decisionLog is append-only and past entries are never edited. Closing a loop in an append-only log *is* opening a new entry beside it, so my sentence ruled out the only compliant move.

**DEC r2, the false claim about our own history.** I wrote that both prior guild jobs in this repo carried a working-memory update. There are three, and the most recent carried none. False in the direction that weakens the obligation it was written to support, on the one deliverable nothing verifies.

## What the Constitution Missed

The working-memory write is instructed and never verified. Measured rather than asserted: editing a past decisionLog entry leaves C-7 at RC 0, a 33-line `activeContext.md` never reaches git because it is gitignored, and `grep -rn '_working-memory' tests/` is empty. A worker that skipped section 4 entirely would still have gone `complete`. I accepted this knowingly, since the deliverable sits outside #22's scope and closing it needs a clause and therefore a fresh CON round, but it is scope that C-7's allowlist admitted without admitting the obligation that came with it. The next job touching working memory should carry a clause the way #21's T-008 did.

One judgment clause carried the job's central property. C-1's deterministic check passes against a broken implementation, so C-5's rubric was the only thing standing between this job and a green suite over a broken fix. Three audit rounds confirmed it holds, and a fourth attack survived to the end: a suite sharing its invocation log across cases, green on the unfixed installer, closed only because it is also red against a *correct* implementation and so cannot arrive by accident. A deterministic check that cannot fail on the bug it targets should say so in the clause, so nobody reads its green as evidence.

Two gaps in the linters, both mapped by execution. `check-job-spec.py`'s R10 needs the plural noun adjacent to the number, so "Four rules constrain how:" fires above three bullets while "Four further rules constrain how:" passes clean, which is how the false count survived. And an `owns` overlap between a task and its own dependency is unguarded end to end: no rule covers it, and `ready-set.py` never compares them, because the dep relation defers the task out of the wave before the collision check runs.

## Where the Run Strained

No task retried and nothing escalated, so the strain was all in the harness rather than the work.

**A fixture broke the whole repo.** A CON r0 auditor built a throwaway repo at `apparatus/CON-audit-r0/c7repo/` containing a `.chezmoidata.toml`. This repo is a chezmoi source directory and chezmoi walks it recursively, so that one file broke `chezmoi execute-template` tree-wide and silently invalidated every template-rendering test, including the ones the auditor was relying on. `git status` stayed clean throughout, because apparatus is gitignored, so nothing pointed at the cause.

**An auditor corrupted live job state.** The first attempt at DEC r1 ran its lifecycle drill against the real task files rather than scratch copies, set two tasks to `complete` and one to `checking` for work no worker had done, then died on a session limit before restoring them. Ground truth was three independent signals: the dispatch log held only auditor dispatches, `git status` was unchanged, and no worker verdict existed at any stem. A task cannot be `complete` with none of those.

**An auditor deleted the wrong tree.** DEC r1 disclosed that a `dirname` in its cleanup resolved one level too high and it ran `rm -rf` against the macOS per-user `$TMPDIR` root instead of its own fixture beneath it. The repo was verifiably untouched; other processes' temp state may not have been. Later dispatches required every `rm` to name an explicit absolute path already printed.

**A stale in-flight marker read as a dead worker.** T-001's first dispatch appeared to have died writing nothing, with a marker over an hour old and no changes on its paths. It hadn't. It was still working, and its writes landed later. I re-dispatched on that read, and two workers ran concurrently on the same owned paths. Nothing was clobbered, because the second found the work done and made no edits, but the wave's `owns` machinery cannot protect against an orchestrator dispatching the same task twice. A clean `git status` plus a stale marker is not proof of death.

**A worker stalled mid-task and resumed cleanly.** T-002's first dispatch did the substantive work and died during its humanizer pass. The partial artifact was sound, with `bash -n` clean and `doctor.bats` at 11/11, so it resumed rather than restarted and no retry budget was spent. Dead dispatches are not FAILs and should not be charged as retries.

## The One Ruling

No disputes were filed, but a checker raised a finding against my own dispatch instruction and was right. I had told it C-5 fails if any of the three filtered checks passes against the unfixed installer. `no extra brew calls` passes there by design, because C-2's own text says the clean run makes no `info` call and exactly one `bundle` call, "which is what the script does today." Requiring it red at HEAD would contradict the clause it implements.

Ruled for the checker: the clause text governs and my dispatch prose does not. It then established the non-vacuity properly, by mutation. Weakening the retry gate to the "Brewfile still non-empty" trap turns the all-unresolvable case red, and neutralizing the drop loop turns the mixed-batch case red. That is stronger evidence than red-at-HEAD would have given.

## Check-Infra Debt

No ERROR verdicts, and every check ran. Three items for whoever goes next:

- Guild fixtures in a chezmoi source dir need the `mktemp -d` rule stated in the agent definitions rather than in each dispatch. It has cost one audit round already and could cost a whole job.
- The auditor needs the same treatment for lifecycle drills. Two separate incidents in this run came from an auditor writing where it should have copied.
- `check-build.sh` writes its log into `.agent-guild/state/log/` on every run, including from a checker. Harmless here because the directory is gitignored, but it means a read-only check is not.
