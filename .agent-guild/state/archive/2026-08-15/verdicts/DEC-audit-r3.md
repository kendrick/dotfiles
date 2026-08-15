---
task: DEC-audit
checker: auditor
vendor: anthropic
model: claude-opus-5[1m]
verdict: PASS
checked_at: 2026-08-14T22:45:00Z
---

## Scope of this round

Three task files against `spec.md` (kendrick/dotfiles#22) and the constitution as it stands. Both of r2's findings were re-tested against the edited text, and the count claim was checked against the filesystem rather than against the orchestrator's summary of it — r2's finding was that a false statement about this repo's history had been asserted, so accepting a corrected statement on assertion would repeat the error. Everything r2 established by execution was re-derived this round rather than inherited, including the properties the two edits had no reason to disturb.

Apparatus at `.agent-guild/state/apparatus/DEC-audit-r3/`. It holds `state-baseline/` (an `rsync` copy of `state/` minus `apparatus/`), a `mutate.py` harness, and ten mutated copies — `v1`, `v1b`, `v2`, `v3`, `v3b`, `v4`, `v5`, `v6`, `v7`, `v8`, `v9` — each differing from the baseline in one expression. Every `check-job-spec.py` and `ready-set.py` run in this round pointed at a copy under that path with `--repo-root` on the real repo, so no rule ever read a task file it could also have written. No fixture was removed; every `rm -rf` this round targeted an explicit absolute path under `apparatus/DEC-audit-r3/` that had just been printed, and no `mktemp -d` fixture was needed.

**No file under `.agent-guild/state/tasks/`, `verdicts/` (other than this one) or `disputes/` was written at any point.** No lifecycle drill was run. One exception under `log/`, disclosed below.

Environment constraint honored. `chezmoi execute-template '{{ template "bundles" . }}'` printed `["core","fonts","dev","browsers","media","office","ai","personal-apps","cloud"]` at RC 0 before the first fixture and again after the last. `find .agent-guild/state/apparatus -name '.chezmoi*'` returns 0 files.

Baseline reproduced. `bats tests/` is 125/125. `check-job-spec.py --audit-id DEC-audit` exits 0. `ready-set.py` computes the wave as `[T-001, T-002]` with T-003 deferred on unmet deps. `git status --porcelain` reads ` M dot_claude/encrypted_private_settings.json.age` at the end exactly as it read at the start.

Task statuses as found and as left:

```
.agent-guild/state/tasks/T-001.md:status: pending
.agent-guild/state/tasks/T-002.md:status: pending
.agent-guild/state/tasks/T-003.md:status: pending
```

### One write under `log/`, disclosed

Running T-003's own C-4 `check_method` wrote two files into `.agent-guild/state/log/`. `check-build.sh:23-29` derives `LOG_DIR` from its own location and tees every run to `state/log/build-<TS>.log` unconditionally, so there is no way to execute that clause's check without landing a file there. The two are `build-20260814T213644.log` and `build-20260814T213858.log`; every other log in that directory carries a 17:xx timestamp and predates this round. I left them in place rather than run `rm` inside `state/`, per this round's second constraint.

They are inert. `.gitignore:17` ignores `.agent-guild/state/` outright, so `git status --porcelain` is unchanged by them, which is also the answer to a question worth asking about T-003 itself: its C-4 check writes into the tree its C-7 check then measures, and the two do not interfere because C-7 reads git and git cannot see `state/`. Verified by running both in sequence against the real tree.

## Per-task results

| task | routing | description | evidence |
| ---- | ------- | ------------ | -------- |
| T-001 | worker-standard/sonnet, checker-judgment | PASS. Unchanged since r1 and re-derived from the files rather than from r2. All five `check_method` segments track their clauses: C-1/C-2/C-3 are the constitution's own check lines verbatim, C-5 and C-8 compress their rubrics without dropping a disjunct. Mixed clause kinds under one judgment checker is the safe direction and the house pattern. `owns` disjoint from both peers, and the wave groups it with T-002. | archive/2026-08-09/tasks/T-001.md:5-8 |
| T-002 | worker-craft/opus, checker-judgment | PASS. Two judgment clauses, routed per the table's taste-work row. Citations re-resolved by hand this round: `doctor:17` and `:58` are the only two `next apply` lines in the file and carry the parentheticals verbatim, `doctor.bats:99` is exactly `assert_contains "in a bundle you've enabled but not installed"`, and `doctor.bats:15-16` resolves `$SCRIPT` to T-002's own artifact, which `:262` then executes. | doctor:17,58; doctor.bats:99,262 |
| T-003 | worker-standard/sonnet, checker-deterministic | PASS. **Both r2 findings are closed, and both repairs are correct on their merits, not merely present.** The count at `:60` is now true against the filesystem — verified below by enumerating the archive rather than by reading the fix. `artifacts:` now carries `_working-memory/decisionLog.md` and `_working-memory/activeContext.md` alongside the report, matching the shape of both prior working-memory tasks. r1's major finding stays closed; nothing in section 4 moved except the one sentence. | T-003.md:60; T-003.md:26-29 |

## r2's two findings, re-tested

**Finding 1 — the false count. CLOSED, and independently confirmed.**

`T-003.md:60` now reads:

> `AGENTS.md:34` obliges an update to `_working-memory/activeContext.md` and to any on-demand file the change touches, once a feature lands. **Two of the three prior guild jobs in this repo carried this — #17 and #21 did, #19 did not.**

I did not take that on assertion. Enumerating `state/archive/` gives four directories; reading each one's `spec.md` for its `ref:` line gives the mapping:

| archive dir | issue | has `tasks/` | task files matching `working.memory\|decisionLog\|activeContext` |
| --- | --- | --- | --- |
| `2026-08-07` | kendrick/dotfiles#17 | yes, 6 tasks | 3 — T-002, T-005, T-006 |
| `2026-08-08` | kendrick/dotfiles#21 | yes, 9 tasks | 2 — T-008, T-009 |
| `2026-08-09` | kendrick/dotfiles#19 | yes, 4 tasks | 0 |
| `2026-08-14` | kendrick/dotfiles#17 | **no `tasks/` at all** | 0 |

So three prior jobs, of which #17 and #21 carried a working-memory task and #19 did not — exactly the sentence as written. The fourth directory holds only `constitution.md`, `spec.md`, and `verdicts/`, which is what an aborted re-run of #17 looks like and is why it is not a fourth job. The negative half of the claim was checked the same way as the positive half: `2026-08-09`'s four tasks are the guard, the harness, the commits, and one added case; their `artifacts:` fields name `dot_local/bin/executable_dotfiles-sync`, `tests/sync.bats`, and two commit SHAs, and its `retrospective.md` never mentions working memory.

**Finding 2 — the missing artifacts. CLOSED.**

`T-003.md:26-29` now lists three artifacts where it listed one. The precedent r2 cited holds on re-reading: `archive/2026-08-08/tasks/T-008.md` carries `_working-memory/conventions.md` and `_working-memory/decisionLog.md` in a block-style `artifacts:`, and `archive/2026-08-07/tasks/T-005.md` carries the same pair inline. Both new entries sit inside T-003's own `owns: _working-memory/` prefix, so nothing about the addition puts a declared artifact outside a declared claim.

## What discriminates, and what only reading does

Every variant below was built to violate one property, and each was run against `check-job-spec.py` pointed at its own copy. The controls matter as much as the misses: without v3, v6, v7 and v9 going red, a green run on the real decomposition would prove nothing.

| variant | mutation | result | what it establishes |
| --- | --- | --- | --- |
| control | none | RC 0 | the baseline copy is clean |
| v1 | `:60` reverted to r2's false "Both prior guild jobs" | **RC 0** | the count fix is machine-invisible; my filesystem enumeration above is the only check on it |
| v1b | `:60` replaced with "Five prior guild jobs" — plural noun adjacent to the number, R10's own shape | **RC 0** | R10 does not reach this sentence even in the form it was written to catch, because it has no list to count against |
| v2 | both working-memory `artifacts:` entries deleted | **RC 0** | the artifacts fix is machine-invisible too; reading is the only check |
| v3 | T-002's `dep_rationale` entry deleted | RC 1 — `R14 dep-rationale: tasks/T-003.md depends on T-002 but dep_rationale names no rationale for it` | R14 discriminates on absence |
| v3b | T-002's rationale replaced with a plausible falsehood ("T-003 imports the doctor's exit-code table from T-002") | **RC 0** | R14 cannot tell a true rationale from an invented one — exactly the gap the auditor contract names, and the reason both edges are read against the deps' artifacts below |
| v4 | `T-002 deps: [T-003]` | RC 1 — `R7 dag: dependency cycle among T-003, T-002, T-003` | R7 discriminates on cycles |
| v5 | T-003 also owns `tests/install-failures.bats` (its own dep's path) | **RC 0**, and `ready-set.py` also clean | an `owns` overlap between a task and its dependency is unguarded end to end: check-job-spec has no rule, and ready-set never compares them because the dep relation defers T-003 out of the wave |
| v6 | T-003's `clauses:` cut to `[C-4]` | RC 1 — `R6 clause-wiring: constitution.md clause C-7 is never cited by any task` | R6 discriminates on orphaned clauses |
| v7 | archive precedent repointed at a nonexistent `T-018.md` | RC 1 — `R1 citation-resolves` | R1 discriminates, and the one section-4 citation inside the rules' reach is not vacuous |
| v8 | T-002's `checker:` set to `checker-deterministic` on two judgment-only clauses | **RC 0** | routing is entirely unchecked by the linter; the routing verdict below is a reading |
| v9 | T-002 also owns `tests/install-failures.bats` (a wave peer's path) | `ready-set.py` defers T-002 with `"reason": "owns overlap with T-001", "kind": "owns"` | the wave's `owns` check discriminates between peers, so the green `[T-001, T-002]` wave on the real decomposition is earned |

v5 is worth keeping in view but is not a finding here: the real `owns` sets are disjoint, so nothing exploits it. It is the reason I read the three `owns` blocks directly rather than trusting the green wave, since the green wave only ever tested one of the three pairs.

## Everything else, re-derived

**Coverage** — complete, derived from the spec's own section headings rather than carried over from r2's table.

| spec item | clause | task |
| --- | --- | --- |
| Problem — fetch phase aborts the whole bundle | C-1 | T-001 |
| Secondary — the doctor's next-apply promise | C-6 | T-002 |
| Observed vs. Expected — dropped entry set aside, survivors install | C-1 | T-001 |
| Proposed Behavior — drop, retry once, report by name | C-1 | T-001 |
| Proposed Behavior — a second failure reports and stops | C-3 | T-001 |
| Proposed Behavior — the happy path is untouched | C-2 | T-001 |
| AC1 survivors install in the same run | C-1 | T-001 |
| AC2 dropped entry named, exit 0 | C-1 | T-001 |
| AC3 no extra brew calls, by stub invocation count | C-2 | T-001 |
| AC4 a second failure reports and stops | C-3 | T-001 |
| AC5 doctor's next-apply wording | C-6 | T-002 |
| AC6 `bats tests/` green | C-4 | T-003 |
| AC6 new coverage stub-driven, not from a real failed install | C-5 | T-001 |
| Non-goal: registry reported on, never edited | C-7 | T-003 |
| For a Coding Agent — verify with `bats tests/` | C-4 | T-003 |
| For a Coding Agent — bash 3.2 array guard | C-4 | T-003, with T-001.md:90 carrying the instruction |
| For a Coding Agent — read `installer.rb:81-114` first | C-8 | T-001.md:100 |

No spec requirement is uncovered. All eight clauses are cited — C-1/2/3/5/8 by T-001, C-6/8 by T-002, C-4/7 by T-003 — and R6 confirms no orphan, with v6 proving R6 discriminates.

One coverage seam I chased and cleared: the spec's Setup bullet asks for `[ "${#arr[@]}" -gt 0 ]` around every array expansion, and `tests/lint.bats:38` guards only `*.bats`, `helpers.bash`, and `mutation-check.sh` — not the installer template. So no linter catches an unguarded expansion in the artifact this job actually edits. It is still covered, because the failure mode is a red suite and C-4's own failing example is that exact scenario: "the new drop-and-retry branch expands an empty array under the existing fetch-phase parser, and `install-packages: a fetch failure where every entry exists names the whole batch` starts failing." Indirect, but real.

**`check_method` against clause text** — T-003's C-4 segment is `check-build.sh 'bats tests/'`, the constitution's C-4 check line. Its C-7 segment is the full `check-diff-scope.py` invocation with all five allowlist paths and the `--ignore`, matching C-7's check line word for word. I ran both against the real tree: C-4 exits 0 at 125/125, C-7 reports `OK: 1 path(s) in scope` at RC 0. C-7's allowlist includes `_working-memory/`, which is what keeps T-003's own section-4 writes from turning its own C-7 red.

**DAG** — `T-003 → {T-001, T-002}`, nothing else. Both referenced tasks exist, T-001 and T-002 declare `deps: []`, acyclic. v4 confirms R7 would say so if it weren't.

**`dep_rationale`, read against what the deps actually produce** — both hold, and v3b is why I read them rather than trusting RC 0.

- *T-001: "the installer and its new bats cases must exist before the whole suite can be run over them."* T-001 owns `run_onchange_install-packages.sh.tmpl` and `tests/install-failures.bats`. `render_script()` at `tests/install-failures.bats:33-37` pipes `$SRC/$tmpl` through `chezmoi execute-template`, and all five existing `install-packages` cases call it on T-001's template. The suite cannot be run over an installer T-001 has not written, and the four new cases it adds are inside `bats tests/`, which is C-4's whole check. Holds.
- *T-002: "the reworded doctor must exist before the whole suite can be run over it."* T-002 owns `dot_local/bin/executable_dotfiles-doctor` and `tests/doctor.bats`. `doctor.bats:15-16` resolves `$SCRIPT` to that exact path and `:68`, `:73`, `:262` execute it across 11 cases. `T-002.md:62` also puts the `doctor.bats:99` assertion in play, which is the case where the dep edge is load-bearing rather than merely chronological: if T-002 changes the prefix, the assertion it owns must move with it, and only a suite run after both have landed sees the pair. Holds.

**`owns`** — disjoint across all three, read directly: T-001 takes the installer and its bats file, T-002 the doctor and its bats file, T-003 `.agent-guild/state/reports/` and `_working-memory/`. `T-001.md:94` and `T-002.md:68` each forbid `_working-memory/` by name and say why. T-003's three artifacts all sit under its own two prefixes.

**Routing** — conforms, and this is a reading, since v8 shows the linter has no opinion. T-002's two judgment-only clauses go to worker-craft/opus with checker-judgment, the table's taste-work row. T-003's two script-checked clauses go to checker-deterministic. T-001 mixes three script clauses with two rubrics under checker-judgment, the safe direction; the harmful direction — a deterministic checker handed a rubric — appears nowhere. The precedent r2 named was re-read and is what it claimed: `archive/2026-08-09/tasks/T-001.md:5-8` runs `[V-1..V-5, B-1, D-4]` under `worker-standard`/`sonnet`/`checker-judgment`, five of them deterministic.

**Citations, re-resolved rather than inherited** — every one in section 4 and every one r2 listed was read again at its stated line. `AGENTS.md:34/35/36/37` say what the three bullets claim, in that order. `decisionLog.md:39` is the B-3 falsification line and does point at #22. `archive/2026-08-08/tasks/T-008.md:45` reads "**`_working-memory/decisionLog.md`** gains a dated entry (today, 2026-08-08)". `_working-memory/activeContext.md` is 21 lines by `wc -l`, over the `:37` cap as the bullet says. `tests/install-failures.bats:74-181` holds exactly five `install-packages` cases at lines 74, 81, 107, 141, and 164, with the fifth closing on `}` at 181 and the next suite starting at 185 — the range is exact to the line, and the five descriptions match C-4's list one for one. `install-failures.bats:130-131` is the summary-text-trap comment. `run_onchange_install-packages.sh.tmpl:2-5`, `:30-35`, `:62-67`, and `:94-95` all carry the content cited against them.

Note that most of this is outside the linter's reach: `is_excluded_citation_path` (`check-job-spec.py:526-537`) drops any citation whose path has no `/`, so every `AGENTS.md:NN` and the `decisionLog.md:39` reference are invisible to R1/R2/R3. Only the archive precedent is inside, and v7 shows it discriminates there.

## The accepted gap — I agree with accepting it, with one thing recorded

You asked whether the acceptance is wrong. It is not, and r2's measurement of it reproduces: `grep -rn '_working-memory' tests/` is still empty, `.gitignore` does not touch `_working-memory/`, and C-7 passes on a dirty `decisionLog.md` because the path is in its own allowlist. A worker that skips section 4 outright gets green from both of T-003's checks. That is a real hole, and it is now a documented one rather than a drifted one, which is the distinction that matters.

The prose is not misreadable. I read section 4 fresh, after the edit, against the standard you set: `:60` says the update is *obliged*, `:60` says *record what shipped*, and the three bullets that follow are imperatives with the rule, the citation, the current measurement, and the target each spelled out — *answer it by appending*, *evicting that is part of this update, not a separate chore*, *land it under the cap*. A worker cannot get from that to "optional."

One thing worth recording, because the repair changed the paragraph's rhetoric even though it improved its accuracy. The sentence now tells the worker in plain text that the most recent prior job skipped this deliverable. That is true and stating it was the right call — a task file that lies to save an argument is worse than one that argues honestly — but it does mean the precedent clause no longer supports the obligation, and the whole weight now rests on the imperatives around it. They carry it. If you ever trim those bullets, this sentence stops being neutral context and starts being a documented exemption, so trim them together or not at all.

I also concur with r2's correction to your routing argument, and with your acceptance of it: a `checker-judgment` runs scripts fine, T-001 in this job proves it, and the CON-round cost was the only real reason. Recorded so the next job's derivation inherits the right reason rather than the wrong one.

## Three notes, not findings

- **`expect 129` remains unchecked arithmetic.** `T-003.md:40` predicts 129 from a measured 125 plus T-001's four cases. I re-measured the 125 (`bats -c tests/`). The arithmetic is right as decomposed, but T-002 owns `tests/doctor.bats` and `T-002.md:62` leaves it free to update or add an assertion there; if it adds a case the real number is 130 and nothing fails, because C-4's check is "the suite passes," not "the suite has 129 cases." Guidance, not an assertion. No action.
- **`antipatterns.md` is still append-only and still unnamed.** `AGENTS.md:36` names two files; section 4's bullet restates the rule for `decisionLog.md` alone, and `:60` obliges "any on-demand file the change touches," which the on-demand table includes `antipatterns.md` in. The worker is pointed at `:36` itself and will read both names there. Thin, and unchanged since r2 — repeating it only so it does not drop out of the record.
- **`activeContext.md:17` is stale in a way the rewriting worker will read as true.** It lists as a Known Risk that `.agent-guild/scripts/__pycache__/` "matches no `.gitignore` entry." `git check-ignore -v` resolves it to `.gitignore:15:__pycache__/`. The worker rewriting that file under the 20-line cap is the natural person to drop the line, and nothing tells it the risk is retired. Also unchanged since r2.

Unrelated to the decomposition: `.agent-guild/state/STALLED.md` still exists. Nothing in this audit touched it.

## What this PASS covers

Both r2 findings are closed and both repairs are correct on their merits — the count checked against the filesystem, the artifacts checked against both precedents. r1's finding stays closed. Coverage is complete against the spec's own sections, every clause is cited by a task whose `check_method` matches its check line, both dep rationales survive reading against the deps' real artifacts, the DAG is acyclic, `owns` is disjoint, and routing conforms. Where the linter cannot see any of that — the counts, the artifacts list, the routing, the false-but-well-formed rationale — the variant table says so explicitly, and those properties were established by reading with the evidence written down.

The unchecked working-memory write is a known, accepted, and now twice-documented gap, out of #22's scope and instructed in prose a worker cannot misread. It does not block this decomposition.

Workers are clear to dispatch. The wave is `[T-001, T-002]`.
