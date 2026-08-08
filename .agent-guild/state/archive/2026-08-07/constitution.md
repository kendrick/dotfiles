# Constitution: Failed installs must name what failed

Source: `kendrick/dotfiles#17` (`.agent-guild/state/spec.md`).

The job converts four install-phase `run_` scripts so that "the tool isn't here, skip" and "the tool ran and couldn't do the job" stop producing identical output. Everything below is measured against that, and nothing else.

Baseline commit: `1dec91c`.

## Revision 5, and why the shape changed

Four audits failed revisions 1 through 4. Coverage was never the problem — every audit confirmed the acceptance criteria map. What kept failing was cross-clause consistency: the output contract was stated in three clauses, the test file constrained by four, and every repair to one contradicted a neighbour.

Revision 4 restructured around that: **B-2 is the only clause describing what the scripts print, and V-1 the only clause enumerating the test file's cases.** Revision 5 keeps that shape and fixes what the r3 audit found in it.

Two of those findings are worth carrying forward as warnings, because both were cases of the document asserting a measurement it had not taken:

- **Continuation already works at baseline.** `|| true` is what provides it. Revisions 2 through 4 all claimed the conversion adds it and expected the keeps-going tests to fail at baseline; measured, the rendered `install-vscode-extensions` attempts all 43 extensions and exits 0. What the job actually adds is the *collected end-of-run summary*. V-1's table now reflects that, and those cases are labelled regression guards.
- **`run_once_after_configure-macos.sh` has eight `|| true` guards, six of them on `defaults write`.** Three revisions called all eight `defaults write`. D-1 now names the other two.

Every per-site claim below was measured on this machine at `1dec91c`, not inferred. Where a site differs from its siblings, the difference is written down. Where an earlier revision asserted something false, the correction is left visible rather than quietly patched, so the next reader can tell which claims have been checked.

**Post-PASS amendments.** CON-audit r4 passed revision 5 with eight minor findings and no blockers. Those eight were then folded in, so the text below is not byte-identical to what r4 audited. All eight tighten rather than loosen, and all were the auditor's own findings:

- B-1's five greps are now written out. The version r4 read derived the raycast pattern from the baseline table, which renders the URL with a typographic ellipsis — that grep matched nothing and would have reported clean against a wholly unconverted raycast script.
- B-2 gained requirement 4, "a clean run says nothing about failures." It was previously implied only by V-1's case title and B-5's check, and lived nowhere in the clause that owns output requirements.
- D-3 gained an out-of-scope-path FAIL condition. D-1's script reads only the working tree, so it goes vacuous the moment the worker commits; D-3 is where the scope question now survives that handover.
- Three stale line citations corrected: `tests/apps.bats:256` (was `:255`, a blank line), `tests/doctor.bats:33` (was `:30-31`), and B-2's "three requirements" now reads five.

## Operational preconditions

The `com.k-arnett.dotfiles-auto-sync` LaunchAgent was unloaded for this job, on the user's instruction, at 2026-08-06 20:50 CDT:

```bash
launchctl bootout "gui/$UID/com.k-arnett.dotfiles-auto-sync"
```

It fires at 16:00 and 22:00, and `dot_local/bin/executable_dotfiles-sync:129` runs `git add -A` followed by a `[auto-sync from $HOST]` commit. Left loaded, it would sweep a worker's uncommitted work into a machine-authored commit: D-3's message rubric would fail on a commit no worker wrote, D-1 would inspect an emptied tree, and D-4's boltdb mtime could move. Commit `af8fe49` is this having already happened once.

**Reload it when the job ends.** This is orchestrator housekeeping, not a property of the artifact, so it belongs in the retrospective rather than in a clause:

```bash
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/com.k-arnett.dotfiles-auto-sync.plist
```

## Measured baseline

The four sites, as they stand at `1dec91c`. V-1's table depends on these, so they are recorded here once and referenced rather than repeated.

| Site | Absent-tool path | Install call | Guarded |
| --- | --- | --- | --- |
| `run_onchange_install-packages.sh.tmpl` | `:12` prints "Homebrew not found — skipping package install." | `:31` `brew bundle` | `\|\| echo` |
| `run_onchange_install-vscode-extensions.sh.tmpl` | `:13` prints "VS Code CLI not found — skipping extension install." | `:21` `code --install-extension` | `\|\| true` |
| `run_onchange_configure-raycast.sh.tmpl` | `:12-13` **bare `exit 0`, prints nothing** | `:22` `open "raycast://…"` | `\|\| true` |
| `run_onchange_after_install-claude-plugins.sh.tmpl` | `:24` prints "claude CLI not found — skipping plugin install." | `:34` `marketplace add`, `:41` `plugin install` | `\|\| true` |

Raycast is the outlier: it skips silently. B-2 therefore *adds* a skip message there rather than preserving one, which is why V-1's table expects that one case to fail at baseline while its three siblings pass. Revisions 2 and 3 asserted the skip message was "today's behavior" for all four and were wrong.

Two further facts the clauses below depend on:

- **`run_onchange_after_install-claude-plugins.sh.tmpl` renders no install calls under a synthetic `$HOME`.** The template gates on `~/.config/chezmoi/key.txt` at `:62` and takes an `else` branch at `:76`. Measured: rendering with the real home emits 7 calls, with a fake home 0. Render and execution environments are therefore separate concerns — see V-1.
- **`bats tests/` does not currently terminate.** `tests/apps.bats` hangs on an interactive picker. V-2 covers the fix.

## Behaviour clauses

### B-1: All four install sites are converted

- **text**: All four sites in the Measured baseline table are converted, not a subset. This clause is what gives B-2 and B-3 their reach; without it they read "in each converted script" and are satisfied by converting one.
- **check**: checker-deterministic: `git diff --name-only 1dec91c..HEAD` contains all four paths, and each of these five greps returns nothing. Keyed to command names rather than line numbers, which move the moment a file is rewritten. The patterns are written out rather than derived from the baseline table, because the table renders the raycast URL with a typographic ellipsis and a grep built from it matches nothing — it would report clean against a wholly unconverted script.

```bash
grep -nE 'brew bundle.*\|\| (true|echo)'                 run_onchange_install-packages.sh.tmpl
grep -nE 'code --install-extension.*\|\| (true|echo)'    run_onchange_install-vscode-extensions.sh.tmpl
grep -nE 'open "raycast://.*\|\| (true|echo)'            run_onchange_configure-raycast.sh.tmpl
grep -nE 'claude plugin marketplace add.*\|\| (true|echo)' run_onchange_after_install-claude-plugins.sh.tmpl
grep -nE 'claude plugin install.*\|\| (true|echo)'       run_onchange_after_install-claude-plugins.sh.tmpl
```

  Each returns exactly one hit at `1dec91c` and none of them matches `brew trust`, so each detects its own failing example.

  One `|| true` legitimately survives: `brew trust --tap "$tap" 2>/dev/null || true` at `run_onchange_install-packages.sh.tmpl:27`. It is not an install call — it pre-trusts taps so `brew bundle` does not abort on the first tapped entry — and this clause does not require its removal.
- **severity**: blocker
- **failing example**: The worker converts `install-packages` alone, satisfying B-2 and B-3 as written while `install-vscode-extensions.sh.tmpl:21` — which `spec.md:86` calls the worst site — still discards both the exit code and stderr.
- **note**: `spec.md:50` cites the claude-plugins calls as `:33,40`. Those lines are `echo` statements; the guarded calls are `:34` and `:41`. A check keyed to the spec's numbers finds no guard and passes a script nobody converted.

### B-2: The output contract

- **text**: This is the only clause describing what the converted scripts print. Five requirements:

  1. **Tool absent.** The script prints a message naming the missing tool and saying it skipped, then exits 0. Three sites already do this; `configure-raycast` does not, and gains one.
  2. **Tool present, item failed.** The script's own summary names the failing item. The CLI's raw stderr alone does not satisfy this, nor does a count, nor "some entries failed". Per-site identifier:
     - `install-packages` — the formula, cask, or `mas` entry name, parsed out of `brew bundle`'s output, since the single invocation covers the whole rendered Brewfile.
     - `install-vscode-extensions` — the extension id.
     - `install-claude-plugins` — the plugin spec, or the marketplace name and repo.
     - `configure-raycast` — the `raycast://` URL or its slug, and **only** for `open` itself refusing the URL. This site never reports a per-extension install outcome; B-4 explains why.
  3. **The two read differently.** A reader can tell a skip from a failure by wording alone, without inspecting exit codes. The failure wording says the tool ran and the item did not install; the skip wording says the tool was absent. Neither borrows the other's phrasing.
  4. **A clean run says nothing about failures.** When every item installs, the script prints no failure summary at all — not an empty one, not a heading with nothing under it, not "0 failed". This is the requirement B-5's empty-array defect violates, and V-1's four `all items succeed prints no failure summary` cases are what prove it. It lives here because it is an output requirement, and B-2 is where output requirements are written down.
  5. **The reason survives.** The converted install calls no longer discard the tool's own error output. Three of the four sites currently end `2>/dev/null`, and `spec.md:48` singles out `install-vscode-extensions.sh.tmpl:21` for discarding "the error text as well as the exit code" — `spec.md:86` calls it the worst of the four for exactly this. Naming the item while still swallowing the reason answers "what failed" and leaves "why" as invisible as before. Either the tool's stderr reaches the run's output, or the script captures it and includes it in the summary alongside the item name.
- **check**: checker-judgment: read the exact skip line and the exact failure line each converted script emits, and the identifier each failure line carries. FAIL if a reader seeing only one line could not say which case it was, if both cases share a message, or if any failure line omits the identifier its site owes. For requirement 4, read the output of V-1's four `all items succeed` cases and FAIL on any failure summary, heading, or zero-count. For requirement 5, `grep -n '2>/dev/null' <each converted script>` — FAIL if any surviving occurrence sits on an install call whose failure the script reports, since that is the reason being thrown away. The mechanical proof that these lines are actually produced lives in V-1; this clause judges their content.
- **severity**: blocker
- **failing example**: A script prints `claude plugin install superpowers@x didn't complete` for both an absent `claude` CLI and a `claude` that ran and returned non-zero. Or `install-packages` prints "Some Brewfile entries failed (MAS apps may need manual install)." with the formula name nowhere in its output.

### B-3: Collect, continue, and still exit 0

- **text**: Two requirements that must hold together, because satisfying either alone breaks the job.

  1. **Keep going, and say so once at the end.** A single failing item does not prevent the remaining items in the same script from being attempted, and the script reports the collected set in a single summary when it finishes. This governs the three multi-call sites — `install-vscode-extensions` and `configure-raycast`, which loop, and `install-claude-plugins`, which renders a flat sequence of 7 `add_marketplace`/`install_plugin` calls rather than a loop. "Item" means one such call: one extension id, one `raycast://` URL, one plugin or marketplace spec. `install-packages` is exempt: it is one `brew bundle` invocation over the whole Brewfile, and `brew bundle` already continues past a failing entry internally. Its obligation is B-2's naming requirement alone.

     Continuation itself already works at every site — `|| true` is what provides it. The collected end-of-run summary is the part this job adds, which is why V-1's keeps-going cases are regression guards rather than discriminators.
  2. **Exit 0 anyway.** Having collected and named its failures, the script exits 0. Every branch: tool absent, everything succeeded, some items failed. `spec.md:58` requires it directly, and the non-goal at `spec.md:79` explains why — withholding `run_onchange` state on failure fights chezmoi's model, and `dotfiles-doctor` carries the failure forward instead.

  The second requirement exists because the issue's title reads "Failed installs exit 0" as a description of the bug. A worker who fixes the title rather than the issue makes the script exit non-zero, aborts every apply on any machine missing any package, and satisfies B-1 and B-2 while doing it.
- **check**: checker-deterministic. `bats tests/install-failures.bats` passes, whose contents V-1 binds. Requirement 1's continuation is carried by the three `keeps going` cases and its end-of-run summary by the four `names the item` cases. Requirement 2 is carried by V-1's check part 2, which greps for the `status -eq 0` assertion in every case — running the suite alone cannot prove the assertion is present, which is why the grep exists rather than a claim about what the cases contain.
- **severity**: blocker
- **failing example**: A stubbed `code` fails on the second of three extensions and the stub's invocation log shows only two calls. Or `install-vscode-extensions` collects two failed ids, prints both correctly, and ends `exit 1` — naming the items, distinguishing skip from failure, keeping going, and aborting the user's entire apply.

### B-4: The Raycast site claims only what it can see

- **text**: `open raycast://...` hands the URL to macOS and returns before any install happens, so per-extension outcomes are invisible from the script. Its conversion distinguishes an absent `open` from `open` itself refusing the URL, and says nothing about whether an extension installed. A comment records why that site can go no further.
- **check**: checker-judgment: read `run_onchange_configure-raycast.sh.tmpl`. FAIL if the script reports extension install success or failure, since it can observe neither.
- **severity**: major
- **failing example**: The script prints `Installed 12 Raycast extensions.` after 12 `open` calls returned 0.

### B-5: bash 3.2 safety

- **text**: New code runs under `/bin/bash` 3.2. Every expansion of an array the code introduces is guarded by a count test (`[ "${#arr[@]}" -gt 0 ]`) before `"${arr[@]}"`. None of the four scripts sets `-u`, so an unguarded empty expansion does not abort — it prints a blank line, which is the live defect: an empty failure summary on a clean run reads as a failure with no name attached, contradicting B-2. The guard also keeps the code correct if `-u` is ever added. Separately, no accumulator depends on `errexit` behaving through `|| true`, which is unreliable for external commands on 3.2 and is documented at `run_onchange_after_install-global-node-packages.sh.tmpl:32-33`.
- **check**: checker-judgment: grep the changed scripts for `[@]`, `set -e`, and `set -u`. FAIL on any unguarded expansion of an array that can be empty, on associative arrays, or on `${var^^}`. Then read the output of V-1's four `all items succeed prints no failure summary` cases — the only cases that exercise the empty-accumulator path — and FAIL if any carries an empty or headerless failure summary.
- **severity**: blocker
- **failing example**: `printf '%s\n' "${failed[@]}"` at the end of a script where everything installed, which on bash 3.2 without `-u` prints a bare blank line under the failure heading, so a clean run appears to report an unnamed failure.

### B-6: Comments carry weight

- **text**: Comments added to the scripts explain why the code has this shape: the incident, the constraint, the thing a reader would otherwise reintroduce. A comment restating what the line does fails. The existing headers on these scripts are the register to match.
- **check**: checker-judgment: read every added comment. FAIL if any one of them could be deleted without losing information the code does not already carry.
- **severity**: major
- **failing example**: `# loop over the extensions and install each one` above the extension loop.

## Verification clauses

### V-1: The new test file is bound to what it must prove

- **text**: This is the only clause that enumerates the contents of `tests/install-failures.bats` — its cases, their titles, and their baseline outcomes. Two other clauses add fixture requirements without redefining the case set: B-5 reads the output of the four happy-path cases, and D-4 requires a recording `defaults` stub wherever the raycast script is executed. Any requirement about *which cases exist* belongs here and nowhere else.

  The file does not exist yet, so a check that merely runs it would pass against any file of that name holding one trivial case.

  The file contains at least these fifteen cases, titled so a checker can find them:
  - `<script>: absent tool skips clean` — one per site, four total
  - `<script>: present tool failing names the item` — one per site, four total
  - `<script>: one failure does not stop the rest` — one per multi-call site, three total
  - `<script>: all items succeed prints no failure summary` — one per site, four total. These are what B-5 runs against, and they are the only cases that exercise the empty-accumulator path.

  Each case drives the real script as a subprocess with its CLI stubbed on `PATH`, following the harness in `tests/doctor.bats`, and asserts `status -eq 0`. That assertion is what carries B-3's second requirement, so it is checked explicitly in part 1 below rather than left to inspection.

  **Render and execution environments are separate.** Templates are rendered first with `chezmoi execute-template`, the pattern `tests/licensed-fonts.bats:22` already uses; no case asserts against a raw `.tmpl`. Rendering happens under the **real** `$HOME`, because `install-claude-plugins` gates on `~/.config/chezmoi/key.txt` at `:62` and renders zero install calls without it — measured, 7 calls with the real home and 0 with a fake one. The rendered script is then *executed* under the synthetic `$HOME` with stubs on `PATH`. Conflating the two is why the claude-plugins cases would otherwise have nothing to drive.

  **Script resolution is relative.** The file locates the repo as `SRC="${BATS_TEST_DIRNAME}/.."`. It must not resolve scripts through `chezmoi source-path` — which `tests/doctor.bats:33` itself stubs — nor through any absolute path. Without this, the mutation step below silently renders HEAD's scripts inside the baseline worktree and passes green.

  **Per-case baseline expectations.** Run against the four scripts at `1dec91c`, each case must land exactly as follows. These follow from the Measured baseline table, not from assumption:

  | Case | At `1dec91c` | Why |
  | --- | --- | --- |
  | `install-packages: absent tool skips clean` | **pass** | `:12` already prints a skip message |
  | `install-vscode-extensions: absent tool skips clean` | **pass** | `:13` already prints one |
  | `install-claude-plugins: absent tool skips clean` | **pass** | `:24` already prints one |
  | `configure-raycast: absent tool skips clean` | **fail** | `:12-13` exits 0 silently; B-2 adds the message |
  | all four `present tool failing names the item` | **fail** | the summary naming the item is what the conversion adds |
  | all three `one failure does not stop the rest` | **pass** | see below — continuation already works |
  | all four `all items succeed prints no failure summary` | **pass** | a clean run is already silent about failures |

  **The keeps-going cases are regression guards, and they pass at baseline by design.** `|| true` is exactly what makes those loops continue today. Measured at `1dec91c`: the rendered `install-vscode-extensions` with a failing `code` stub attempts all 43 extensions and exits 0. Continuation is not what this job adds — the *collected summary at the end* is, and the `names the item` cases carry that.

  Revisions 2 through 4 all expected these three cases to fail at baseline. That was wrong, and it forced a contradiction: a case written to B-3's first requirement passes at baseline, so making it fail required smuggling in B-2's naming assertion, duplicating a case that already exists. Guarding behavior that already works is a legitimate job for a test, and it matters here precisely because the rewrite could break it.

  A file-level "the suite fails at baseline" is not enough: one real case plus fourteen trivial ones satisfies that while proving nothing about the other fourteen.
- **check**: checker-deterministic, four parts. First, `grep -c '^@test' tests/install-failures.bats` is at least 15 and every required title appears. Second, the exit-status assertion that carries B-3's second requirement: the count of lines matching `status" -eq 0` is at least the number of `@test` blocks, and no line matches `status" -ne 0` or `status" -eq 1`. Without this, a worker can make the scripts `exit 1` after collecting failures and satisfy every other check in this constitution. Third, `grep -n 'chezmoi source-path' tests/install-failures.bats` returns nothing and `SRC="${BATS_TEST_DIRNAME}/.."` is present. Fourth, the per-case mutation, comparing each case against the table above:

```bash
git worktree add /tmp/agc-baseline 1dec91c
cp tests/install-failures.bats /tmp/agc-baseline/tests/
cd /tmp/agc-baseline && bats --formatter tap tests/install-failures.bats
git worktree remove /tmp/agc-baseline --force
```

  The exit code alone is not the check — compare the TAP `ok`/`not ok` line for each case against its expected outcome.

- **severity**: blocker
- **failing example**: A file with one case asserting `[ 1 -eq 1 ]`, which exits 0 and satisfies B-2 and B-3 as revision 1 checked them. Or a file with one genuine failure case and ten stubs, which fails at baseline as a whole and so satisfies revision 2's file-level requirement while ten clauses go unproven. Or a file whose raycast skip case passes at baseline, proving it never asserted on the message B-2 requires.

### V-2: The suite runs, and is green

- **text**: `bats tests/` terminates and exits 0 with the new coverage in place. It does not terminate today, which makes the spec's own `Verify with: bats tests/` and acceptance criterion 8 unsatisfiable until it is fixed.

  The cause is pre-existing and unrelated to this issue: `tests/apps.bats:58` prepends the stub directory to `$PATH` without scrubbing the rest, so the case at `tests/apps.bats:256` — which writes a stub `fzf` and then `rm`s it — still finds the real `/opt/homebrew/bin/fzf`. The guard at `dot_local/bin/executable_dotfiles-apps:35` passes, `main()` defaults `mode="move"` at `:258`, and the run blocks forever on `cmd_move`'s picker at `:144`. It is latent on a machine without `fzf` installed and fires on one with it — `fzf` was installed here on 2026-08-06, which is what surfaced it, and is also what triggered the incident behind this issue.

  This job fixes it. The fix is in scope by the user's decision, is confined to `tests/apps.bats`, and does not touch `dot_local/bin/executable_dotfiles-apps`.

  No existing case is deleted or skipped to reach green.
- **check**: checker-deterministic:
  - `timeout 300 bats tests/` exits 0. It exits 124 at baseline, so this check detects its own failing example.
  - `grep -c '^@test' tests/<file>` is at least the baseline count for each pre-existing file: `apps` 18, `doctor` 10, `font` 44, `jsonc` 9, `licensed-fonts` 7, `packages` 13.
  - `git diff 1dec91c..HEAD -- tests/` adds no line matching `^\+\s*skip\b`. Anchored to added lines so it cannot collide with V-1's mandated case titles, which contain the word "skips".
- **severity**: blocker
- **failing example**: `tests/install-failures.bats` passes while `bats tests/` still hangs at `apps.bats`, and the worker reports done on the strength of the new file alone. Or `apps.bats` is made to terminate by deleting the offending case, dropping it from 18 to 17.

### V-3: The doctor still catches what the apply missed

- **text**: `tests/doctor.bats` gains at least one case, titled `doctor: a tracked but uninstalled formula is reported`, exercising the `-- in a bundle you've enabled but not installed` branch that `dot_local/bin/executable_dotfiles-doctor:58-68` emits.

  This job does **not** modify the doctor — the issue asks for the behavior to be confirmed, not built, and `dot_local/` is outside D-1's allowlist. The doctor is therefore byte-identical at baseline and HEAD, so a baseline checkout proves nothing. The proof that the case truly reaches the branch is a mutation of the doctor itself.

  The existing harness already stubs `brew` as `:` at `tests/doctor.bats:52`, so nothing reads as installed; reaching the branch needs only a `packages.json` fixture entry the stubbed `brew list` does not return.
- **check**: checker-deterministic, two parts. First, `bats tests/doctor.bats` passes at HEAD including the new case. Second, the mutation — note the `cp`, without which the worktree carries HEAD's unmodified `doctor.bats` and the step is inert:

```bash
git worktree add /tmp/agc-mut HEAD
cp tests/doctor.bats /tmp/agc-mut/tests/
sed -i '' '58,68d' /tmp/agc-mut/dot_local/bin/executable_dotfiles-doctor
cd /tmp/agc-mut && bats --formatter tap tests/doctor.bats   # the new case MUST report "not ok"
git worktree remove /tmp/agc-mut --force
```

- **severity**: major
- **failing example**: A case that stubs `brew list` to return the tracked formula, so the branch is never reached — it passes at HEAD and passes again with the branch deleted, which the mutation catches. Or the mutation run reports `ok` for the new case, meaning the `cp` was omitted and the step tested nothing.

## Delivery clauses

### D-1: Scope

- **text**: The diff touches only the four scripts B-1 names, `tests/`, and the working-memory files D-2 covers. `run_once_after_configure-macos.sh` is not modified: of its eight `|| true` guards, six protect `defaults write` keys that are no-ops or errors on Sequoia and later, settled 2026-03-24 at `_working-memory/antipatterns.md:71-75`, alongside the companion decision at `:77-82` not to reintroduce `set -e` there. The other two guard `osascript` at `:14` and `killall` at `:165`; they are equally out of scope. Revisions 2 through 4 called all eight `defaults write` guards, which was wrong.

  `tests/apps.bats` is in scope, per V-2. `dot_local/` is not: neither the doctor nor `dotfiles-apps` is modified by this job.
- **check**: `python3 .agent-guild/scripts/check-diff-scope.py --ignore dot_claude/encrypted_private_settings.json.age run_onchange_install-packages.sh.tmpl run_onchange_install-vscode-extensions.sh.tmpl run_onchange_configure-raycast.sh.tmpl run_onchange_after_install-claude-plugins.sh.tmpl tests/ _working-memory/conventions.md _working-memory/decisionLog.md` — verified to exit 1 on an out-of-scope path and 0 otherwise. It reads the working tree only and has no commit-range option, so it runs before D-3's commit; afterwards `git diff --name-only 1dec91c..HEAD` carries the same question.
- **severity**: blocker
- **failing example**: A worker also converts `run_onchange_after_install-global-node-packages.sh.tmpl`, or removes a `|| true` from `run_once_after_configure-macos.sh`, or edits `dot_local/bin/executable_dotfiles-apps` to fix V-2's hang from the wrong side.
- **note**: `dot_claude/encrypted_private_settings.json.age` was already modified in the working tree at job start, is user-owned, and is excluded by name rather than silently tolerated.

### D-2: Working memory stops contradicting the code

- **text**: Two passages in `_working-memory/conventions.md` contradict what this job builds, and both are updated:
  1. The "Error Handling" bullet at `:46` prescribes that external-tool installers "guard each call with `|| true` and skip cleanly if the CLI is absent", citing `run_onchange_install-vscode-extensions.sh.tmpl` — the very file this job converts. It states the rule this job establishes instead: absence is skipped, a present tool's failure is named.
  2. The bats bullet at `:40` says "don't assert on log wording: what matters is what the run left on disk and whether it refused when it should have." B-2 and V-1 require exactly those output assertions. It is amended to carve out output assertions where the output *is* the contract under test, without licensing wording assertions generally.

  `_working-memory/decisionLog.md` gains a dated entry recording the decision and the incident behind it. Left stale, these are what the next agent reads before reintroducing the bug.
- **check**: checker-judgment: read both bullets and the new decisionLog entry against the converted scripts and the new test file. FAIL if the Error Handling bullet still tells a reader to guard install calls with `|| true`, if it does not distinguish absence from failure, if the bats bullet still forbids the assertions `tests/install-failures.bats` makes, or if `decisionLog.md` has no entry.
- **severity**: major
- **failing example**: The Error Handling bullet is left as-is, still citing `run_onchange_install-vscode-extensions.sh.tmpl` as the example of the `|| true` convention this job just removed from that file.

### D-3: Committed, unpushed, and each commit stands alone

- **text**: The work lands as commits that each stand on their own, none pushed. Messages cover why the change was made, carry no `Co-Authored-By` or similar trailer, and are not hard-wrapped. The working tree is clean of this job's paths when the job ends.
- **check**: checker-judgment, over:
  - `git log --format=%B 1dec91c..HEAD` for the messages. The range starts at this job's baseline, so it contains this job's commits and nothing else.
  - `git rev-list 1dec91c..HEAD`, each sha through `git branch -r --contains <sha>`. Any commit naming a remote branch has been pushed — FAIL. This replaces `git log origin/main..HEAD`, which cannot detect a push at all, since pushing removes a commit from that range rather than adding it.
  - `git status --porcelain`, disregarding `dot_claude/encrypted_private_settings.json.age`.
  - `git diff --name-only 1dec91c..HEAD` for post-commit scope, since D-1's script cannot read a commit range.

  FAIL on a dirty tree in this job's paths, on any commit reachable from a remote branch, on a trailer, on hard-wrapped body lines, on a message that only restates the diff, or **on any path in that range outside D-1's allowlist**. That last condition is not redundant with D-1: `check-diff-scope.py` reads only the working tree, so once the worker commits it reports OK no matter what the commits touched. D-1 is a blocker whose check goes vacuous exactly when D-3 is satisfied, and this is where the scope question survives that handover. A commit whose message begins `[auto-sync from` is not a worker's and means the LaunchAgent ran despite the precondition: report `blocked`, not a worker failure.
- **severity**: major
- **failing example**: One commit titled `fix: update scripts` whose body lists the four files changed, with the branch already pushed — caught by `git branch -r --contains`, invisible to the range check it replaced.

### D-4: No worker mutates real machine state

- **text**: Every claim about failure behavior is proven with stubs on `PATH`. No worker runs `chezmoi apply` or `chezmoi update`, edits `.chezmoidata.toml` to inject a bad entry, installs or uninstalls a package, writes real user defaults, or pushes. The end-to-end apply against a deliberately broken registry entry is the user's step, after the job ends.

  `run_onchange_configure-raycast.sh.tmpl:30` runs `defaults write com.raycast.macos`, which ignores `$HOME` and lands in the real `~/Library/Preferences` — verified. Any test executing that script must stub `defaults`, or the suite rewrites the user's Raycast hotkey on every run.
- **check**: split by what the evidence demands.

  checker-deterministic:
  - `git diff 1dec91c..HEAD -- .chezmoidata.toml` and `git status --porcelain .chezmoidata.toml` are both empty. This catches the clause's own failing example, which had to edit the registry.
  - `git rev-list 1dec91c..HEAD` yields no commit contained in a remote branch (shares D-3's push check).
  - `~/.config/chezmoi/chezmoistate.boltdb` has an mtime no later than the job's first task file, proving no `apply` recorded new script state.
  - `tests/install-failures.bats` provides a `defaults` stub on `PATH` for every case that executes the rendered raycast script, and that stub records its invocations. A before/after value comparison does not work here: the script writes `Command-49`, which is already the stored value, so an unstubbed run is indistinguishable from a stubbed one by reading the key. The proof has to be that the real `defaults` was never reached, not that the value survived.

  checker-judgment, because it is reading comprehension rather than a grep result:
  - Every occurrence of `chezmoi apply`, `chezmoi update`, `brew install`, `brew bundle`, `code --install-extension`, `claude plugin install`, `defaults write`, or `git push` under `tests/` is a stub definition or a stubbed invocation, never a call reaching the real tool. A grep alone cannot decide this: the required stubs contain those exact strings, so it is guaranteed to hit.

  The residual — a worker running `brew install` interactively and leaving no trace — is unprovable from any artifact and is a worker instruction rather than a checked clause.
- **severity**: blocker
- **failing example**: A worker adds `brew "definitely-not-a-real-formula-xyz"` to `.chezmoidata.toml`, runs `chezmoi apply` to capture output, and reverts — caught by the boltdb mtime even though the revert cleans the diff. Or a new test executes the rendered raycast script without stubbing `defaults`, silently rewriting the user's global hotkey.

## Protected content

None. No passage in this job has to ship verbatim, so there is no manifest.

## Non-goals

- **Aborting the apply on the first failure.** 90 of 92 packages installed plus a named list of the 2 that failed beats stopping at the first one. B-3 enforces this, since a non-goal alone is not checked.
- **Retrying failed installs.** A flaky network and a renamed formula look identical from inside the script.
- **Making chezmoi re-run the script until it succeeds.** That means withholding `run_onchange` state on failure, which fights the tool's model.
- **The `defaults write` guards in `run_once_after_configure-macos.sh`.** Settled 2026-03-24; D-1 enforces leaving them alone.
- **Modifying `dotfiles-doctor` or `dotfiles-apps`.** V-3 confirms the doctor's existing behavior with a test; V-2 fixes the hang from the test side. `dot_local/` stays outside D-1's allowlist.
- **Progress display during the run.** That is #16, and tangling the two makes both harder to review.
- **Acceptance criterion 6, the failing item's name in `~/.local/state/dotfiles/last-sync.log`.** Unsatisfiable by these scripts. `dotfiles-sync` never runs `chezmoi apply`: its phases are regenerate-extension-list, `re-add`, drift report, then commit and push, and the only LaunchAgent runs that script alone. The installers execute under `apply`, whose output the sync log never sees. Sync also truncates the log every run at `:23`. V-3 carries the durability this criterion was reaching for. All three prior audits re-derived and confirmed this independently.
- **The live end-to-end apply.** The user runs it after the job, per D-4.
