---
task: DEC-audit
checker: auditor
vendor: anthropic
model: claude-opus-5[1m]
verdict: FAIL
checked_at: 2026-08-14T23:40:00Z
---

## Scope of this round

Three task files against `spec.md` (kendrick/dotfiles#22) and the constitution at the text CON-audit r2 passed. Read all three CON rounds first; r1's name-sourcing note and r2's `v13-sharedlog` note are the two findings this decomposition was built around, and both were re-derived here rather than taken on r2's word.

Apparatus at `.agent-guild/state/apparatus/DEC-audit-r0/`: the current installer rendered to `unfixed.sh`, two reference implementations of the drop-and-retry (`ref.sh`, `ref-b.sh`, differing only in what gates the retry), `probe.bats` (the four cases built from T-001's spec excerpt and nothing else), and `v13-sharedlog.bats` (round 2's surviving construction, rebuilt to test whether the excerpt closes it). Git-state and diff-scope properties ran in a throwaway `git init` repo under `mktemp -d`; the return-gate execution ran against a scratch `CLAUDE_PROJECT_DIR` under `mktemp -d`. Both removed.

Environment constraint honored. `chezmoi execute-template '{{ template "bundles" . }}'` printed `["core","fonts","dev","browsers","media","office","ai","personal-apps","cloud"]` RC 0 before the first fixture and again after the last. `find .agent-guild/state/apparatus -name '.chezmoi*'` returns 0. `bats tests/` is 125/125, exit 0, matching the stated baseline. `git status --porcelain` reads what it read at start (` M dot_claude/encrypted_private_settings.json.age`); nothing moved, nothing restored.

Mechanical gates: `check-job-spec.py --audit-id DEC-audit` exits 0 (R6 clause wiring, R7 DAG, R13 ownership overlap, R14 dep-rationale pairing, R15 owns shape). `ready-set.py` computes the wave as `[T-001, T-002]` with T-003 deferred on unmet deps, confirming the concurrency premise the decomposition rests on.

## Per-task results

| task | routing | description | evidence |
| ---- | ------- | ------------ | -------- |
| T-001 | worker-standard/sonnet, checker-judgment | PASS. Clauses C-1, C-2, C-3, C-5, C-8, each with a `check_method` segment matching the constitution's own check text. Mixed clause kinds under one judgment checker is the safe direction and has house precedent (`archive/2026-08-09/tasks/T-001.md` runs six deterministic clauses under `checker-judgment`); the harmful direction is a deterministic checker handed a rubric. Combining implementation and tests is correct and not merely convenient — C-1, C-2 and C-3 each run bats against the implementation, so a split would put each half's check behind the other half's artifact, which is a dependency cycle rather than a DAG. Size is one branch in a 111-line template plus four cases; within a sonnet dispatch. `owns` disjoint from T-002. | check-job-spec exit 0; ready-set groups T-001 with T-002; archive/2026-08-09/tasks/T-001.md |
| T-002 | worker-craft/opus, checker-judgment | PASS. C-6 and C-8, both judgment clauses, both routed per the table's "taste work to worker-craft with checker-judgment". Not over-routed: the work is deciding whether new wording is *true* of `run_onchange`'s hash model and actionable for a reader, which is the judgment C-6's rubric asks a checker to re-derive. Line count is not the routing discriminator. Every citation in the excerpt resolves — `:17` and `:58` carry the two parentheticals verbatim and are the file's only two occurrences, `:25-32` and `:76-94` are substantive why-comments in the register the excerpt names, and `tests/doctor.bats:99` asserts exactly the prefix the excerpt quotes. | doctor:17,58; doctor:25-32, :76-94; tests/doctor.bats:99 |
| T-003 | worker-bulk/haiku, checker-deterministic | **FAIL — blocker.** Routing is right (two script-checked clauses, mechanical work, deterministic checker) and both `dep_rationale` entries hold on reading. But the task cannot complete its lifecycle: `artifacts: []` plus an excerpt that says "It writes no files" is refused by `subagent-return`, which blocks any `worker-*` return whose `artifacts` is empty. Executed, both directions. Second finding: the excerpt's stated reason for parking C-4 and C-7 here is false as written for C-7, verified against the check itself. Third: no whole-suite check sits on T-001 or T-002, so the first task that can observe a regression is the one that cannot repair it. | gate RC 2 on `artifacts: []`, RC 0 with one entry; diff-scope V1 exit 0 under simulated concurrent wave writes; T-001/T-002 `check_method` carry no `bats tests/` |

## Coverage

Every acceptance criterion traces, and every constitution clause is cited by at least one task.

| spec item | clause | task |
| --- | --- | --- |
| AC1 survivors install in the same run | C-1 | T-001 |
| AC2 dropped entry named, exit 0 | C-1 | T-001 |
| AC3 clean run makes no extra brew calls | C-2 | T-001 |
| AC4 second failure reports and stops | C-3 | T-001 |
| AC5 doctor's next-apply wording | C-6 | T-002 |
| AC6 `bats tests/` green, coverage from stubs | C-4, C-5 | T-003, T-001 |
| Non-goal: registry never edited | C-7 | T-003 |
| "For a Coding Agent": bash 3.2 guard, Homebrew `installer.rb:81-114` | C-4 (behaviorally), C-8 | T-001 |

Clauses cited: C-1/2/3/5/8 by T-001, C-6/8 by T-002, C-4/7 by T-003. All eight, none orphaned. `deps` form a DAG (`T-003 → {T-001, T-002}`, nothing else). Both of T-003's `dep_rationale` entries survive reading against what the dep actually produces: T-001's artifacts are the installer plus `tests/install-failures.bats`, and T-002's are the doctor plus `tests/doctor.bats` — all four are inside `bats tests/`, and C-7 needs both landed before whole-tree scope means anything.

## What the round 2 transmission check found

Reproduced `v13-sharedlog` from r2's description and ran it both ways. Against the installer as it stands today it is **green, 2/2**, and `bats -c -f "drop-and-retry"` reads `2`, so C-1's deterministic gate exits 0 on it. Against a correct implementation it goes **red** at `[ "$(count_calls bundle)" -eq 2 ]`, because the shared log reaches three. Round 2's account is exact.

T-001's excerpt closes it, and closes it with the one sentence that matters: "The log must be per-case, not shared across cases via `BATS_SUITE_TMPDIR`." That names move 1 by its mechanism. Blocking move 1 alone kills the construction — `probe.bats`, written to the excerpt with a per-case log, is red against `unfixed.sh` at `[ "$(count_calls bundle)" -eq 2 ]` on both `drop-and-retry` cases and on `reports and stops`, and green 4/4 against a correct implementation. Move 2, the trailing-space vacuity, cannot stand alone: the count assertion fires before any grep runs.

The four traps the excerpt claims are all present and all accurate: the summary-text trap cites `:94-95`, which is where the two-space indent is printed; the invented-name vacuity is stated with its reason; the one-run-per-case rule is stated with the inflation mechanism; the bash 3.2 guard carries the `[ ]`-not-`[[ ]]` corollary r1 established. Every line citation in the excerpt resolves exactly — `:62-105` is the fetch-phase handling, `:107-162` the two existing fetch-phase cases, `:130-131` the comment that already names the trap, `:74-181` the five `install-packages` cases.

Not transmitted: r2's other half of the closing idiom, that the survivor and dropped-name patterns be exact matches. Verified non-load-bearing above, so this is a note, not a finding. It costs test strength rather than correctness — a loose negative assertion is green for the wrong reason against a *correct* implementation, which C-5(c) gives the judgment checker latitude to call.

A worker reading only T-001 and the constitution cannot innocently write any of the four named shapes. It can still write one thing the excerpt leaves undetermined — see finding 4.

## Diagnosis

- **T-003** (blocker): the task cannot return. `subagent-return` blocks any `worker-*` agent whose task has an empty `artifacts` list, and T-003 declares `artifacts: []` while its excerpt instructs the worker that "It writes no files."

  Executed, not read. A scratch `CLAUDE_PROJECT_DIR` holding T-003 at `status: needs-check` with `artifacts: []`, driven with `agent_type: worker-bulk`:

  ```
  Protocol incomplete for T-003: status is 'needs-check' but `artifacts` is empty.
  List the repo-relative paths you produced so the checker knows what to verify.
  RC=2
  ```

  The same file with one entry added returns RC 0, so the block is about `artifacts` and nothing else. `worker-bulk` is in `WORKER_AGENTS` (`hooks/_lib.py:85`), and the check at `hooks/subagent-return.py:506-521` is unconditional for that set.

  This lands at the worst point in the job: T-003 runs only after both building tasks have shipped, so the stall arrives at the end with nothing left to overlap it. The improvisation the block invites is worse than the block. A worker told to "list the repo-relative paths you produced" will produce one, and if it writes a report anywhere outside `.agent-guild/state/` it fails C-7 — the clause this very task exists to check — because `check-diff-scope.py` exempts only `state/`. The other improvisation, listing a note under `state/notes/`, gets through the gate and lists an artifact the orchestrator is contractually forbidden to read.

  What closes it: give T-003 something real to produce and own. A written verification report at a path under `.agent-guild/state/` (or an owned, allowlisted repo path), named in `artifacts` and in `owns`, turns the task into one that satisfies the protocol without inventing anything. Cite it in the excerpt so the worker does not have to guess.

- **T-003** (major): the excerpt's stated reason for parking C-4 and C-7 here is false for C-7, and the true reason is a different one that happens to hold.

  The excerpt says: "a diff-scope check dispatched from either would see its peer's in-flight writes and flag them." Executed in a throwaway repo with all four wave-scope paths dirty at once — T-001's installer and `install-failures.bats` plus T-002's doctor and `doctor.bats` — the check invoked exactly as C-7 writes it reports `OK: 4 path(s) in scope`, exit 0. It does not flag the peer, because the whole-job allowlist already contains the peer's paths. The `--task-file` failure mode `check-diff-scope.py`'s docstring describes is specific to scoping the check to *one task's* `owns` list, which is not the invocation C-7 uses.

  The conclusion still holds, for the reason #162 actually gives: attribution. Editing `.chezmoidata.toml` from either task, or dropping a stray file, turns the check red on *both* — verified, exit 1 naming `.chezmoidata.toml` and `peer-scratch.txt` — with nothing to say which task did it. A C-7 run from T-001's checker would rework T-001 for a write T-002's worker made.

  For C-4 the concurrency hazard the excerpt describes *is* real, and it is the stronger argument of the two: `bats tests/` run from T-001's checker while T-002's worker is mid-edit of `dot_local/bin/executable_dotfiles-doctor` fails on a half-written file. That argument is about the suite, not the diff, and the excerpt never makes it. Fix the prose so a checker re-deriving this reaches the same place for the right reason.

- **T-001, T-002** (major): a regression is detectable only by the task that cannot repair it, and the retry ladder has no path back.

  Neither building task carries a whole-suite check. T-001's `check_method` runs three `bats -f` filters; T-002's runs two rubrics. So T-001's worker can plant C-4's own stated failing example — an unguarded empty-array expansion under `set -u`, which the spec's "For a Coding Agent" section warns about by name — break `install-packages: a fetch failure where every entry exists names the whole batch`, and pass its own check. T-001 goes `complete`. T-003 catches it.

  Then nothing moves. The retry ladder runs FAIL → diagnosis into *this* task → re-dispatch *this* task's executor. T-003's worker owns no paths and is told in its own excerpt not to fix anything, so the identical FAIL returns, twice at haiku, then again at each rung up the ladder, ending at "no rung above fable." Invalidation runs the other direction only: dep FAILs, descendant reworks. There is no descendant-FAILs-so-rework-the-dep move in the contract, so the orchestrator has to improvise one, and nothing in the decomposition tells it that it will need to.

  Two ways out, either sufficient. Say in T-003's excerpt and in the orchestrator-facing part of the task that a FAIL here is an invalidation signal naming T-001 or T-002, not a rework of T-003 — which makes the improvisation a written instruction. Or give T-001 and T-002 a narrower green-suite obligation they can each check alone, accepting the flake risk the concurrent wave introduces. The first is cheaper and does not touch the wave.

- **T-001** (minor): case 2's retry gate is undetermined, and the excerpt inherits the ambiguity from C-1 without resolving it.

  "Every name fails `brew info`. Assert the log holds exactly one `bundle` invocation — the script reports them all rather than retrying against an empty Brewfile." The rationale only follows if the fetch batch *is* the whole Brewfile. It is not: `fetch_batch` holds the entries brew needed to download, which on a real machine is a handful out of 88. Two readings follow, and they are different implementations.

  Built both. `ref.sh` gates the retry on "the survivor set is non-empty" — the natural reading of the excerpt's own "drop those lines from the rendered Brewfile, run `brew bundle` once more with what is left." Against a three-name batch drawn from the render it retries with the other 85 entries and case 2 fails at `[ "$(count_calls bundle)" -eq 1 ]`. `ref-b.sh` gates on "every batched name was unresolvable" and is 4/4 green. Same excerpt, same constitution, two implementations, one of which fails a case the excerpt requires.

  It resolves on first run, the way r1's name-sourcing ambiguity did, so it is minor rather than blocking. It costs a debugging cycle in a task whose retry budget the finding above may already be spending. One sentence in the excerpt fixes it: the retry is skipped when every name in the failed fetch batch is unresolvable, not merely when the Brewfile would be empty.

- **Decomposition** (minor): `_working-memory/` is allowlisted by C-7, owned by no task, and asked for by no excerpt.

  `AGENTS.md:34` obliges an update to `activeContext.md` and the relevant on-demand file after completing a feature, and both prior guild jobs in this repo carried a dedicated working-memory task (`archive/2026-08-07/tasks/T-005.md`, `archive/2026-08-08/tasks/T-008.md`). C-7's allowlist anticipates the write; the decomposition never assigns it.

  This is not a spec-coverage failure — #22 says nothing about working memory — but it has a live edge under this wave. An unowned path is invisible to R13 and to `ready-set.py`'s collision check, so T-001 and T-002 riding together can both append to `_working-memory/activeContext.md` with nothing to detect the clobber, and `check-diff-scope.py` waves it through because the prefix is allowed. Either assign the update to one task and put the path in its `owns`, or drop `_working-memory/` from C-7's allowlist so a write there is caught rather than permitted.

## What this FAIL does and does not say

It does not say the decomposition is wrong in shape. Coverage is complete, every clause is cited by a task that can check it, the DAG is sound, both `dep_rationale` entries survive reading against their dep's real artifacts, `owns` is disjoint across the one wave that exists, and three of the four judgment calls put up for testing hold under execution: implementation-with-tests is forced rather than chosen, `worker-craft` for T-002 is routed on the judgment and not the diff size, and T-001's excerpt does transmit what round 2 learned — measured against a rebuilt `v13-sharedlog`, not taken on trust.

What it says is that T-003 as written cannot finish, and that the reasoning parking two clauses on it is right by accident rather than by derivation. Fix the artifact contract, correct the C-7 rationale, and say what a T-003 FAIL means for its deps. The other two findings are cheap and can ride along.
