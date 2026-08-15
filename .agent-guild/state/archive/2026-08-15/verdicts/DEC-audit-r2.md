---
task: DEC-audit
checker: auditor
vendor: anthropic
model: claude-opus-5[1m]
verdict: FAIL
checked_at: 2026-08-14T00:00:00Z
---

## Scope of this round

Three task files against `spec.md` (kendrick/dotfiles#22) and the constitution as it stands. r1's single major finding was re-tested against the edited text; everything r1 established by execution was re-derived rather than inherited, including the properties the edit had no reason to disturb.

Apparatus at `.agent-guild/state/apparatus/DEC-audit-r2/`. It holds `state-baseline/` (an `rsync` copy of `state/` minus `apparatus/`) and eight mutated copies, `v1`–`v8`, each differing from the baseline in one expression. Every `check-job-spec.py` run in this round pointed at a copy under that path with `--repo-root` on the real repo, so no rule ever read a task file it could also have written. The one fixture needing git state is a throwaway repo at `/var/folders/zz/jwg0lvm10hbfv_zq5q8cf7jw0000gn/T/tmp.NbgwrpW1CM`, created with `mktemp -d` and **left in place** rather than removed — after r1's cleanup incident I am not running `rm` against anything under `$TMPDIR`. Every `rm -rf` this round targeted an explicit absolute path under `apparatus/DEC-audit-r2/` that had just been printed.

**No file under `.agent-guild/state/tasks/`, `verdicts/` (other than this one), `disputes/` or `log/` was written at any point.** No lifecycle drill was run.

Environment constraint honored. `chezmoi execute-template '{{ template "bundles" . }}'` printed `["core","fonts","dev","browsers","media","office","ai","personal-apps","cloud"]` at RC 0 before the first fixture and again after the last. `find .agent-guild/state/apparatus -name '.chezmoi*'` returns 0 files.

Baseline reproduced. `bats tests/` is 125/125. `check-job-spec.py --audit-id DEC-audit` exits 0. `ready-set.py` computes the wave as `[T-001, T-002]` with T-003 deferred on unmet deps. `git status --porcelain` reads ` M dot_claude/encrypted_private_settings.json.age` at the end exactly as it read at the start — nothing moved, nothing was restored.

Task statuses as found and as left:

```
.agent-guild/state/tasks/T-001.md:status: pending
.agent-guild/state/tasks/T-002.md:status: pending
.agent-guild/state/tasks/T-003.md:status: pending
```

## Per-task results

| task | routing | description | evidence |
| ---- | ------- | ------------ | -------- |
| T-001 | worker-standard/sonnet, checker-judgment | PASS. Unchanged since r1 and re-derived. `check_method` segments for C-1/C-2/C-3 are the constitution's own check lines; C-5 and C-8 compress their rubrics faithfully. Mixed clause kinds under one judgment checker is the safe direction and the house pattern — `archive/2026-08-09/tasks/T-001.md` runs V-1..V-5 (all script harnesses) plus B-1 and D-4 under `checker-judgment` with the same worker-standard/sonnet executor. `owns` disjoint from both peers. | archive/2026-08-09/tasks/T-001.md:5-8 |
| T-002 | worker-craft/opus, checker-judgment | PASS. Two judgment clauses, routed per the table's taste-work row. Citations re-resolved by hand this round: `doctor:17` and `:58` carry the two `next apply installs these` parentheticals verbatim, `doctor.bats:99` is exactly `assert_contains "in a bundle you've enabled but not installed"`, and `doctor.bats:15-16` executes the doctor out of `$SRC`. | doctor:17,58; doctor.bats:99 |
| T-003 | worker-standard/sonnet, checker-deterministic | **FAIL — two minor findings.** r1's major finding is **closed**: section 4 no longer instructs an append-only violation, and all three governing `AGENTS.md` lines are now stated with their citations correct. The `:64` contradiction r1 swept is closed too. What remains is a false factual claim in the same paragraph the fix touched, and an `artifacts:` list that omits the deliverable those three bullets exist to produce. Neither ships a wrong artifact; both are cheap, and both sit on the one deliverable in this job that nothing checks. | T-003.md:58; T-003.md:26-27 |

## r1's finding, re-tested

**CLOSED.** Section 4 now says, across three bullets, that `decisionLog.md` is append-only per `AGENTS.md:36`, that the worker **appends a new dated entry** closing the loop `:39` opened, and that the 2026-08-07 entry is left exactly as it is. Every line it cites was read directly and every one says what the task claims:

| citation | what the line actually says | machine-checked? |
| --- | --- | --- |
| `AGENTS.md:34` | "After completing a feature or making a significant decision, update `activeContext.md` and the relevant on-demand file." | no |
| `AGENTS.md:35` | "`activeContext.md` is a queue: evict completed items to `decisionLog.md`." | no |
| `AGENTS.md:36` | "`decisionLog.md` and `antipatterns.md` are both append-only. Never edit past entries." | no |
| `AGENTS.md:37` | "Never let `activeContext.md` exceed 20 lines." | no |
| `decisionLog.md:39` | the B-3 falsification line, pointing at #22 | no |
| `.agent-guild/state/archive/2026-08-08/tasks/T-008.md:45` | "**`_working-memory/decisionLog.md`** gains a dated entry (today, 2026-08-08)" | **yes** |

The "machine-checked" column matters, because `check-job-spec.py`'s exit 0 covers far less of this section than it looks like it does. `is_excluded_citation_path` drops any citation whose path has no `/` (`check-job-spec.py:530`), so every `AGENTS.md:NN` and the `decisionLog.md:39` reference are invisible to R1/R3/R2. Only the archive precedent is inside the rules' reach, and there it is not vacuous: repointing it at a nonexistent `T-018.md` fires `R1 citation-resolves` (v1), and moving it one line to blank line 46 fires `R3 citation-shape` (v2). The other six were verified by reading, and all six hold.

The supporting facts hold too. `activeContext.md` is 21 lines (`wc -l`), so it is over `AGENTS.md:37`'s cap as the task says; its Current Focus is indeed stale #17 content describing a job that is long finished. The precedent at `T-008.md:45` really is an append, and `T-008.md:47` adds the ordering convention the log follows.

**So: the wording fix closes it, and the clause is not required.** A worker following section 4 as now written cannot produce an append-only violation — the rule is stated three ways, the exempt entry is named, and the precedent shows the compliant shape — and cannot leave `activeContext.md` over its cap without ignoring a bullet that gives it the rule, the current count, and the instruction to land under it. Do not re-open the constitution on my account.

Two things to record alongside that ruling.

**Your second reason for declining the clause does not hold.** You wrote that C-4 and C-7 are both script-checked so "the checker would have to become judgment for one unclause-checked deliverable." A `checker-judgment` runs scripts perfectly well — T-001 in this very job hands one three script-checked clauses and two rubrics, and `archive/2026-08-09/tasks/T-001.md` hands one five script harnesses plus two rubrics. Mixing is the house pattern and the safe direction. The obstacle you actually face is the CON gate re-closing for another round, and that reason is sufficient by itself. The routing argument isn't, and it would be worth not carrying it forward into the next job's reasoning.

**Nothing checks the write, and I measured how completely.** In a throwaway git repo seeded with the real `decisionLog.md`, `activeContext.md`, and `.gitignore`:

| variant | tree state | C-7 result |
| --- | --- | --- |
| control | clean | `OK: 0 path(s) in scope`, RC 0 |
| A — the 2026-08-07 entry edited in place | ` M _working-memory/decisionLog.md` | `OK: 1 path(s) in scope`, **RC 0** |
| B — `activeContext.md` padded to 33 lines | not reported by git at all | `OK: 1 path(s) in scope`, **RC 0** |
| C — `.chezmoidata.toml` touched | ` ?? .chezmoidata.toml` | `out of scope: .chezmoidata.toml`, RC 1 |

C is the control that proves the check discriminates on what it is for; A and B prove it is blind to exactly the two properties you asked me about. `grep -rn '_working-memory' tests/` returns nothing, so `bats tests/` is blind too. A worker that skips section 4 outright gets a green run from both of T-003's checks and a `complete`. That is a knowing gap now rather than a drifted one, which is the whole point of writing it down.

## Diagnosis

- **T-003** (minor): `T-003.md:58` states a false count about this repo's own history, in the paragraph that motivates the unchecked deliverable.

  The sentence reads:

  > `AGENTS.md:34` obliges an update to `_working-memory/activeContext.md` and to any on-demand file the change touches, once a feature lands. **Both prior guild jobs in this repo carried this.**

  There are three prior guild jobs, not two: `archive/2026-08-07` (#17), `archive/2026-08-08` (#21), and `archive/2026-08-09` (#19), each with its own constitution, tasks, verdicts, and retrospective. A fourth archive, `2026-08-14`, holds the aborted #17 re-run. Two of the three carried a working-memory task — `2026-08-07/tasks/{T-002,T-005,T-006}.md` and `2026-08-08/tasks/{T-008,T-009}.md`. The most recent one did not: `grep -ril 'working memory\|decisionLog\|activeContext'` over `2026-08-09/tasks/` returns nothing, its four tasks are the guard, the harness, the commits, and one added case, and its retrospective never mentions working memory either.

  So the claim is false, and it is false in the direction that weakens the obligation it was written to support. A worker that checks it finds the most recent precedent skipping the deliverable entirely — and skipping it is invisible to both of T-003's checks, per the table above. This repo's own standard for this file class is `archive/2026-08-08/tasks/T-008.md:51`: "These files are read by agents as ground truth, so a wrong number does more damage than a clumsy sentence."

  `check-job-spec.py` cannot catch it. R10 is the right rule and it misses by one word: `_governs_plural_noun` requires the plural noun adjacent to the number, so `'Four rules constrain how:'` fires R10 against three bullets while `'Four further rules constrain how:'` passes clean (v4, v4b). The same blind spot means section 4's own "Three further rules" count is unchecked — it is correct, verified by hand against its three bullets, but nothing would have told you if it weren't.

  Fix: say what is true. "Two of the three prior guild jobs in this repo carried this (#17 and #21); #19 did not." Verified green at v8.

- **T-003** (minor): `artifacts:` omits the working-memory files, against this repo's own convention in both prior working-memory tasks.

  `T-003.md:26-27` lists one artifact, `.agent-guild/state/reports/T-003-verification.md`. Section 4 now spends three bullets producing writes to `_working-memory/decisionLog.md` and `_working-memory/activeContext.md`, and neither appears anywhere in the task's machine-readable fields. Both prior working-memory tasks list them: `archive/2026-08-08/tasks/T-008.md` carries `_working-memory/conventions.md` and `_working-memory/decisionLog.md` in `artifacts:`, and `archive/2026-08-07/tasks/T-005.md` carries the same pair.

  I am not claiming this would catch a skipped section 4 — it wouldn't, since `decisionLog.md` exists either way and the return gate only checks existence. What it does is make the deliverable enumerable at all. Right now the only trace of it outside prose is `owns: _working-memory/`, which records permission rather than obligation, and on a task whose deliverable nothing verifies, the artifact list is the last place a later reader could learn the deliverable exists. It costs two lines. Verified green at v7.

## Everything else, re-derived

**Coverage** — complete, derived from the spec's own sections rather than carried over.

| spec item | clause | task |
| --- | --- | --- |
| AC1 survivors install in the same run | C-1 | T-001 |
| AC2 dropped entry named, exit 0 | C-1 | T-001 |
| AC3 clean run makes no extra brew calls, by stub invocation count | C-2 | T-001 |
| AC4 a second failure reports and stops | C-3 | T-001 |
| AC5 doctor's next-apply wording | C-6 | T-002 |
| AC6 `bats tests/` green, new coverage stub-driven | C-4 / C-5 | T-003 / T-001 |
| Problem + Observed vs. Expected | C-1 | T-001 |
| Secondary (doctor) | C-6 | T-002 |
| Proposed Behavior (drop, retry once, report) | C-1, C-3 | T-001 |
| Non-goal: registry reported on, never edited | C-7 | T-003 |
| For a Coding Agent: bash 3.2 guard, `installer.rb:81-114` | C-4, C-8 | T-003, T-001 |

All eight clauses cited — C-1/2/3/5/8 by T-001, C-6/8 by T-002, C-4/7 by T-003 — none orphaned, no spec requirement uncovered.

**check_method against clause text** — T-003's C-4 segment is `check-build.sh 'bats tests/'`, the constitution's C-4 check line. Its C-7 segment is the full `check-diff-scope.py` invocation with all five allowlist paths and the `--ignore`, matching the constitution's C-7 check line word for word. I ran the C-7 command against the real tree: `OK: 1 path(s) in scope`, RC 0.

**DAG** — `T-003 → {T-001, T-002}`, nothing else, every referenced task exists, acyclic.

**`dep_rationale`, read against what the deps actually produce** — both hold. T-001 owns `run_onchange_install-packages.sh.tmpl` and `tests/install-failures.bats`; `install-failures.bats:35` renders that template through `chezmoi execute-template` and every install-packages case calls `render_script` on it, so the suite cannot run over an installer that doesn't exist yet. T-002 owns `dot_local/bin/executable_dotfiles-doctor` and `tests/doctor.bats`; `doctor.bats:15-16` resolves `$SCRIPT` to that path and executes it. Both are inside `bats tests/`, which is C-4's whole check.

**`owns`** — disjoint across all three: T-001 the installer and its bats file, T-002 the doctor and its bats file, T-003 `.agent-guild/state/reports/` and `_working-memory/`. T-001:94 and T-002:68 each forbid `_working-memory/` by name. T-003's artifact sits inside its own `owns` prefix. `ready-set.py` still groups T-001 with T-002.

**Routing** — conforms. T-002's judgment-only clauses to worker-craft with checker-judgment. T-003's two script clauses to checker-deterministic. T-001 mixes kinds under checker-judgment, the safe direction, with precedent named above. The harmful direction — a deterministic checker handed a rubric — appears nowhere.

**T-003's remaining citations** — `tests/install-failures.bats:74-181` really does hold exactly five `install-packages` cases, at lines 74, 81, 107, 141, and 164, with the next case (`install-vscode-extensions`) starting at 185; their descriptions match C-4's list one for one. `tests/lint.bats:30` is the bash 3.2 bare-compound guard. The 125-case baseline is measured, not asserted.

## Three notes, not findings

- **`expect 129` is unchecked arithmetic.** `T-003.md:38` predicts 129 from 125 plus T-001's four cases. Correct as decomposed, but T-002 owns `tests/doctor.bats` and `T-002.md:62` leaves it free to update an assertion there — if it adds a case instead, the real number is 130 and nothing fails, since C-4's check is "the suite passes," not "the suite has 129 cases." No action needed; it's guidance, not an assertion.
- **`antipatterns.md` is append-only too.** `AGENTS.md:36` names two files; section 4's bullet restates the rule for `decisionLog.md` only. `T-003.md:58` also obliges "any on-demand file the change touches," and `antipatterns.md` is on that table. The worker is pointed at `:36` itself and will read both names there, so this is thin, but if you touch section 4 again it's a free word.
- **`activeContext.md:17` is stale in a way the worker will read as true.** It lists as a Known Risk that `.agent-guild/scripts/__pycache__/` "matches no `.gitignore` entry" and that running any check script dirties the tree. `git check-ignore -v` resolves it to `.gitignore:15:__pycache__/`. The worker rewriting that file under the 20-line cap is the natural person to drop the line, and nothing in the task tells it the risk is already retired.

Also, unrelated to the decomposition: `.agent-guild/state/STALLED.md` exists. Nothing in this audit touched it and it is yours to resolve or delete.

## What this FAIL does and does not say

It does not reopen r1's finding, which is genuinely closed and closed by the cheaper of the two remedies r1 offered. The wording fix works; the clause is not required; the CON round you declined to spend was the right call for the reason you gave, if not for both reasons you gave. Coverage is complete, every clause is cited by a task that can check it, both dep rationales survive reading against the deps' real artifacts, the DAG is sound, `owns` is disjoint, and routing conforms — all re-derived this round rather than inherited.

What it says is that the paragraph you edited still contains one false statement about this repo's history, and that the deliverable that paragraph governs is absent from the only machine-readable field that could name it. One sentence and two YAML lines. Both repairs were tested and both leave `check-job-spec.py --audit-id DEC-audit` at exit 0.
