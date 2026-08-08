# Constitution: A false assertion must fail its test

Source: `kendrick/dotfiles#21` (`.agent-guild/state/spec.md`).

The job converts every bare `[[ ]]` assertion in `tests/` to a form whose failure propagates from any position, adds a check that stops the construct coming back, and proves each conversion still goes red when its condition is false. Everything below is measured against that, and nothing else.

Baseline commit: `61213fe`. Working tree clean at job start.

## Revision history, and what the CON-audits found

Three audits, three FAILs, and the same defect each time in a different clause: **a requirement stated in a clause's text that its check does not test.** Anyone revising this document should read that as the standing failure mode and check their own edits against it before submitting.

**CON-audit r3 passed revision 4.** The text below is not byte-identical to what r3 read: one major and five minors were folded in afterwards, all of them the auditor's own findings, and all tightening rather than loosening.

- **V-2 gained part 1a**, the only change the auditor asked for before dispatch rather than after. V-2's restore contract said "never `git checkout`" and nothing checked it. Part 1's status comparison was measured to catch that only pre-commit; post-commit on a clean tree a `git checkout` restore is byte-identical to a correct one. Part 1a's marker-survival probe discriminates in both states.
- V-1's block had a comment still describing the `git checkout` lines revision 4 removed, and was not re-runnable after a crashed worktree. Both fixed.
- V-2's cost was stated as one 6-minute pass when parts 1a, 3, and 4 each need their own. The script now takes an optional file argument so those three can be scoped, and the clause says to budget accordingly.
- Part 4's illustrative TAP output came from a two-case scratch file while the part now names `tests/jsonc.bats`, which has nine.
- **"Exactly 52" would have failed the better implementation.** An `if` for `doctor.bats:244` built out of helper calls counts as 53 to a literal checker. The number is a floor against inlined comparisons, not a ceiling, and now says so.

### Revision 4

- **V-1's mutation restored with `git checkout`, which silently defeated two of its three plantings.** Pre-commit the worktree sits at the baseline, so `git checkout tests/jsonc.bats` put two genuine bare `[[` back after planting 1; from planting 2 on, a `*.bats`-only guard — the clause's failing example verbatim — reported red off those, never off the canary. Planting 3's `git checkout tests/helpers.bash` failed outright, that path not existing in `HEAD` until D-3 commits. Restores are now copies from the working tree, and the prohibition on `git checkout` is stated in both clauses that mutate files.
- **V-2's check header said "three parts" and listed four** — the miscounted one being part 4, the whole of revision 3's fix, and by the clause's own words the only part that catches its second failing example.
- **V-2 never said how the script restores what it mutates.** A worker reaching for `git checkout` would have reverted every conversion to baseline the first time the script ran, and would discard a developer's uncommitted work every time after. The restore contract is now explicit, and part 1 additionally requires the tree to be unchanged afterwards.
- Minors: B-2 now states that it owns meaningfulness rather than only being named by V-2; part 4 names the file to plant in; the helper-call count is an equality, not a floor.

### Revision 3

The r1 audit closed three of revision 2's four blocker fixes and found one that only looked closed. It is worth stating plainly, because it is the third time this document has made the same mistake: **V-2's TAP requirement went into the clause text and never into the check.** A script with a correct form parser that still judged by file exit status — failing example 2, verbatim — passed all three parts. The auditor built the probe that discriminates, and it is now part 4: plant a failure unrelated to any mutation, and a script judging by exit status calls that run a success while the mutated case never appears in TAP at all.

Also corrected in revision 3:

- **V-2 told its reader a falsehood about its own reach.** It claimed nothing else in the constitution would catch a conversion that always passes. Measured: `assert_contains ""` reports `ok` unmutated and `not ok` inverted, so V-2 passes a tautology cleanly. Polarity inversion cannot distinguish a tautology from a live assertion by construction — that is a property of the rule, not a defect in it. V-2 now says what it actually proves (the assertion is wired in) and hands meaningfulness to B-2 by name.
- **V-3's hardening declared its own pass path blocked.** `grep -c` exits 1 when the count is zero, which is the passing case; the clause called non-zero `blocked`.
- **V-1's mutation assumed the work was already committed** — `git worktree add HEAD` with no `cp`, so a checker running before D-3's commit finds none of the three files and FAILs a correct worker. The previous job's V-1 wrote this lesson down and it did not come across with the rest of the fix.
- **B-2's helper-call arithmetic was off by one**: 52 sites call helpers, not 51. The only way to reconcile 51 was to count `packages.bats:146` among the 53 assertions, which contradicts the baseline table.

One r0 finding is withdrawn rather than fixed. The auditor reported that V-3's `skip` grep exits 2 with empty stdout under this host's ugrep shim; on re-run it could not reproduce that on demand, and neither could I. **The hardening stays because it is free, but it is a precaution taken, not a defect measured**, and no checker should cite it as one.

### Revision 2

Revision 1 failed audit with four blockers. Three were the same mistake in different places — a check that would report clean against the very artifact its own failing example describes — and the fourth was the cross-clause drift that took the previous job four audits to beat. All are fixed below, and the fixes are recorded here rather than quietly applied, so the next reader can tell which claims have been re-derived:

- **The guarded surface was defined three times at three scopes.** B-1 globbed two paths, V-1 said "anywhere under `tests/`", and V-2 then mandated a third file inside V-1's scope but outside B-1's — so a guard built to V-1's wording would flag the mutation script, turn `bats tests/` red, and fail V-3. **The surface is now defined once, in B-1, and every other clause cites it.**
- **V-1's mutation planted its canary only in a `.bats` file**, while its failing example was a guard that skips `helpers.bash`. It passed against its own failing example. It now plants in all three file kinds.
- **V-2 compared the script's HEAD line numbers against `61213fe` line numbers.** B-3's mandated `load` line shifts every baseline line by at least one, so the check could never pass against a correct implementation. It now cross-checks per-file counts, which are stable under line shifts.
- **V-2 accepted a file-level non-zero exit as proof a mutation worked** — the same reasoning its own failing example condemns one level up. It now requires the mutated case to report `not ok` by name in TAP output.
- **The naive-grep figure was wrong.** Revision 1 said `grep '\[\['` returns 57 with three false positives. It returns **59** with **five**: revision 1 had filtered comment lines before counting and then described the result as an unfiltered grep, missing the two lines of `tests/install-failures.bats` that document this very bug. Corrected in the Measured baseline. The conclusion — that 54 is the right number — is unaffected.

Two further audit findings changed what the job must build: nothing in revision 1 actually required a converted assertion to *call* a helper (B-1 only forbade a syntax, B-3 only required a file to exist), and the required replacement for `tests/packages.bats:146` lived only in descriptive prose with no clause behind it. Both now sit in B-2 and B-3.

## Operational preconditions

The `com.k-arnett.dotfiles-auto-sync` LaunchAgent was unloaded for this job, on the user's instruction, at 2026-08-08 10:52 CDT:

```bash
launchctl bootout "gui/$UID/com.k-arnett.dotfiles-auto-sync"
```

It fires at 16:00 and 22:00, and `dot_local/bin/executable_dotfiles-sync:129` runs `git add -A` followed by an `[auto-sync from $HOST]` commit. Left loaded, it would sweep a worker's uncommitted work into a machine-authored commit — D-3's message rubric would fail on a commit no worker wrote, and D-1 would inspect an emptied tree. Commit `af8fe49` is this having already happened once, during the #17 job.

**Reload it when the job ends.** Orchestrator housekeeping, not a property of the artifact, so it belongs in the retrospective rather than in a clause:

```bash
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/com.k-arnett.dotfiles-auto-sync.plist
```

## A note on `grep` for checkers

An agent checker on this host has a shell function named `grep` that shims to `ugrep`, which does not accept every GNU expression and can exit 2 with empty stdout. **A checker reading "no output" as "no match" will report clean on a check that never ran.** Every check below uses `/usr/bin/grep` explicitly and POSIX character classes (`[[:space:]]`) rather than `\s`. A checker must confirm the exit status, not only the output — for these greps, exit 1 means no match and exit 2 means the check failed to run and the clause is `blocked`.

## Measured baseline

Every number below was measured on this machine at `61213fe`, and re-derived independently by the CON-audit. Where the issue's own figures differ, the difference is recorded rather than quietly reconciled.

### What errexit actually does to each construct

bash 3.2.57(1)-release, `/bin/bash`, the shell bats runs test bodies under. Each row was run directly:

| Construct, failing mid-body | Result | Verdict |
| --- | --- | --- |
| `[[ 1 -eq 2 ]]` | prints `reached`, exits 0 | **swallowed** |
| `(( 1 == 2 ))` | prints `reached`, exits 0 | **swallowed** |
| `[ 1 -eq 2 ]` | exits 1 | propagates |
| `echo needle \| grep -qF haystack` | exits 1 | propagates |
| a function returning 1 | exits 1 | propagates |

Two findings here that the issue does not carry:

- **`(( ))` has the identical bug.** The issue names only `[[ ]]`. No test uses `(( ))` as a statement today, so this costs no conversion work, but the guard covers it so the trap cannot be walked into later.
- **Single-bracket `[ ]` is safe.** The suite's ~162 `[ ... ]` assertions need no conversion. This bounds the job: had `[ ]` been affected, scope would have quadrupled.

### Loop-carried masking, which the issue's exposure count misses

The issue defines a vulnerable position as "a further statement follows the assertion inside its block." That definition misses loops. Measured:

```bash
# early iterations fail, the last one passes
$ /bin/bash -c 'set -e; f() { for i in 1 2 3; do [[ $i -ge 3 ]]; done; }; f; echo "exit=$? REACHED"'
exit=0 REACHED

# [ ] and grep in the identical position both abort on the first failing iteration
$ /bin/bash -c 'set -e; f() { for i in 1 2 3; do [ $i -ge 3 ]; done; }; f; echo REACHED'
                                    # exits 1, correct
```

`tests/font.bats:554` is exactly this shape: a `[[ ]]` as the last statement of a `for` body, iterating over every key in the font registry. Nothing follows it in its block, so the issue's definition calls it safe. It is not — any key that fails is masked by any later key that passes.

The issue's figure of 24 vulnerable assertions is therefore an undercount. **No corrected total is stated here.** Producing a trustworthy one means classifying each site by its position within its enclosing block and loop. V-2's script does need to locate assertions, but not to reason about what follows them or how many times their block runs, which is the harder half. B-1 converts all 54 regardless of position, so the number gates nothing. An unmeasured number is left unmeasured rather than guessed at.

### The 54 sites

A site is a line whose **first non-whitespace token** is `[[` or `((`:

```bash
/usr/bin/grep -nE '^[[:space:]]*(\[\[|\(\()' tests/*.bats
```

| file | sites | assertions | `@test` cases | file runtime |
| --- | --- | --- | --- | --- |
| `tests/apps.bats` | 11 | 11 | 18 | ~6s |
| `tests/doctor.bats` | 20 | 20 | 11 | ~7s |
| `tests/font.bats` | 12 | 12 | 44 | ~12s |
| `tests/install-failures.bats` | 0 | 0 | 17 | ~6s |
| `tests/jsonc.bats` | 2 | 2 | 9 | ~1s |
| `tests/licensed-fonts.bats` | 5 | 5 | 7 | ~1s |
| `tests/packages.bats` | 4 | 3 | 13 | ~2s |
| **total** | **54** | **53** | **119** | 34.7s |

All 54 are `[[`; the count of `((` statements is zero. Runtimes are approximate and vary by a second between runs; they are here to size V-2's mutation pass, and no clause checks them.

**Why first-token, and not a bare `/usr/bin/grep '\[\['`.** The naive pattern returns **59** and is wrong five times over — none of these is a `[[` command:

- `tests/apps.bats:50` — `\[[^]]*\]` inside a `grep -oE` regex
- `tests/font.bats:460` — `[[:space:]]` character classes inside a single-bracket `[ ]` test
- `tests/packages.bats:105` — the same
- `tests/install-failures.bats:68` and `:71` — the comment block that documents this very bug, quoting `[[ ]]` in prose

A checker running the naive pattern should expect five false positives, not three. Removing them reproduces the issue's per-file table exactly (apps 11, doctor 20, font 12, jsonc 2, licensed-fonts 5, packages 4). **The issue's count of 54 is correct.**

**53 assertions, plus one that is not.** `tests/packages.bats:146` is `[[ -n "$cask" ]] || continue` — control flow inside a `while read` loop, whose failure `||` consumes, so the errexit bug cannot reach it. It is still converted, because leaving it would force B-1's check to carry an exemption a checker could misapply. Its required form is fixed by B-2, not by this descriptive section. Every mutation requirement in V-2 counts **53**, not 54.

### Case-count drift

The issue's acceptance criteria give per-file floors (apps 18, doctor 11, font 44, install-failures 15, jsonc 9, licensed-fonts 7, packages 13) and a total of 117. `install-failures.bats` now has 17 cases and the suite has 119. The floors are stated as minimums ("stay at or above") and all still hold; only the total drifted, as #17 landed two more cases after #21 was filed. V-3 binds the measured 119.

### What the suite does today

`bats tests/` exits 0, 119 cases, 34.7s, none skipped. There is no shared helper file and no test file calls `load`. `assert_contains` and `assert_not_contains` are defined once, locally, at `tests/install-failures.bats:73-83`.

Both were measured to propagate from every position this job depends on — mid-body, and inside a loop where a later iteration passes:

```bash
assert_contains() { local n="$1" h="${2-$output}"; grep -qF -- "$n" <<<"$h"; }
f() { assert_contains "absent" "haystack"; echo "REACHED (BAD)"; }
( set -e; f )                       # exits 1, nothing printed
h() { for w in absent present; do assert_contains "$w" "present"; done; }
( set -e; h )                       # exits 1 — the case [[ ]] gets wrong
```

The same helpers, driven through bats with `load`, report `not ok` for both a failing `assert_contains` and a failing `assert_not_contains` mid-body; the `[[ ]]` equivalent reports `ok`. That is B-3's probe, and it was run before this document was written.

## Behaviour clauses

### B-1: No bare compound statement survives, anywhere on the guarded surface

- **text**: **This clause defines the guarded surface, and it is the only clause that does.** Every other clause referring to "the guarded surface" means exactly this and must not restate it:

  > `tests/*.bats`, `tests/helpers.bash`, and `tests/mutation-check.sh`.

  Nothing on that surface has `[[` or `((` as the first non-whitespace token of a line. All 54 baseline sites are converted, including `tests/packages.bats:146`. There is no exempt position, no exempt file, and no "safe by position" carve-out, because position-safety is exactly the property a later edit silently removes.

  The surface deliberately includes the two non-`.bats` files. `helpers.bash` is where a single `[[` would disarm every call site in the suite at once. `mutation-check.sh` runs under the same bash 3.2 and is subject to the same bug, and excluding it would reintroduce the scope drift that failed revision 1's audit. Both may still *contain* the characters `[[` inside a quoted pattern or a comment — the first-token rule is what distinguishes a search string from a command, and `tests/lint.bats` necessarily relies on that to avoid flagging itself.

  Heredoc bodies are on the surface too. A stub script written inside a `<<'EOF'` block within a test file is text to bash, but it is also shell that will be executed, and a bare `[[` there has the same bug. **This is prospective, not work: zero of the 54 baseline sites sits inside a heredoc**, verified. The rule exists so that the first stub someone writes with a `[[` in it fails the guard rather than quietly reintroducing the bug in a file the guard was thought to cover.
- **check**: checker-deterministic:

```bash
/usr/bin/grep -nE '^[[:space:]]*(\[\[|\(\()' tests/*.bats tests/helpers.bash tests/mutation-check.sh
```

  must exit 1 with no output. It returns 54 lines at `61213fe` (where the two non-`.bats` files do not yet exist, so run it against `tests/*.bats` alone to reproduce that figure), so it detects its own failing example. Exit 2 means a file is missing or the pattern failed to compile — that is `blocked`, not a pass. A checker that substitutes the naive `grep '\[\['` will see five false positives that are regexes, character classes, and comments, not commands; see the Measured baseline.

  This check reads the working tree. Once the worker commits, D-3 carries the same question over the commit range.

- **severity**: blocker
- **failing example**: The worker converts `doctor.bats`'s 20 sites — the largest file, and the one the issue's table leads with — and leaves `tests/apps.bats:135` as `[[ "$(registry_line 'owner/repo/x')" == *'bundles = ["media"]'* ]]`. The suite is green either way, which is the whole problem.

### B-2: Conversion changes the form, never the condition — and every conversion calls a helper

- **text**: This is a mechanical conversion of how a condition is expressed, not a review of whether the condition is right — the issue's third non-goal. Every converted assertion keeps the same needle, the same haystack, and the same polarity: `==` becomes a containment assertion, `!=` becomes its negation, and neither silently becomes the other.

  **Form is constrained, not just syntax.** The issue asks that each site be "replaced with a helper... following the `assert_contains` and `assert_not_contains` pattern." Forbidding `[[` alone would be satisfied by inlining a bare `grep -qF` at all 53 sites, which passes B-1 and B-3 while producing exactly the scattered, drift-prone assertion logic B-3 exists to prevent. So: **every containment assertion calls a shared helper from `tests/helpers.bash` by name.** There are exactly two exceptions, both fixed here:

  1. `tests/packages.bats:146` becomes `[ -n "$cask" ] || continue`. Single-bracket, because it is control flow rather than an assertion and `[ ]` is measured safe; this exact idiom is already what `tests/font.bats:552` uses for the identical construct two files away.
  2. `tests/doctor.bats:244` is `[[ "$output" == *"undeclared"* || "$output" == *"casks"* ]]`, the suite's only disjunction. It is restructured into an explicit form whose failure propagates and whose intent stays visible — an `if` testing both substrings that returns 1 when neither matches. Both substrings survive; the disjunction is not narrowed to whichever arm happens to pass today.

  The arithmetic, since an off-by-one here misdirects every checker: **54 sites = 53 assertions + `packages.bats:146`**, which is not an assertion. Of the 53, one is `doctor.bats:244`, which becomes an `if`. So **52 of the 53 are single helper calls**, and all 53 are mutated by V-2.

  Counting the 53rd is a judgment call, not an arithmetic one: the better implementation of `doctor.bats:244` builds its `if` out of helper calls, which a literal checker would count as 53 helper-calling assertions rather than 52. **That implementation is correct and must not be failed on the count.** What the number is guarding is the floor — no assertion may inline its own comparison — not a ceiling on how many call a helper.

  **This clause owns whether an assertion is meaningful.** V-2 proves each converted assertion is still wired in; it cannot prove the condition can fail, because polarity inversion turns a tautology into a falsehood and reports it red. The two rubric conditions below — a changed needle, and a condition that cannot fail — are the only place in this constitution that a live-looking but empty assertion is caught. A checker treating them as boilerplate removes the job's last line of defence against exactly the bug it exists to fix.
- **check**: checker-judgment: for each of the 53 converted assertions, read the baseline line (`git show 61213fe:<file>`) beside the converted line. FAIL if any conversion changes the needle, changes the haystack expression, flips polarity, drops one arm of `doctor.bats:244`'s disjunction, or replaces a condition with one that cannot fail. FAIL if any containment assertion inlines its own comparison instead of calling a shared helper. FAIL if `tests/packages.bats:146` was deleted rather than converted, or converted to anything other than a `[ -n ... ] || continue` guard preserving the loop's skip behaviour. A grep cannot decide any of this — it is a reading of 53 before/after pairs, which is why it is a judgment clause.
- **severity**: blocker
- **failing example**: `tests/doctor.bats:140`'s `[[ "$output" != *"terminal"* ]]` becomes `assert_contains "terminal"`. The polarity is inverted, the suite stays green because the doctor's output does contain that word, and the case now asserts the opposite of what it was written to prove. Or `tests/packages.bats:146` is simply deleted: B-1 goes green, the loop silently stops skipping blank lines, and no other clause looks at it.

### B-3: The helpers exist, are shared, and are built only from constructs that propagate

- **text**: `tests/helpers.bash` defines the shared assertion helpers, and every pre-existing test file loads it with bats `load`. It defines at minimum `assert_contains` and `assert_not_contains`, with the signatures the call sites use. `tests/install-failures.bats`'s two local definitions are removed in favour of the shared ones, so the suite has exactly one definition of each helper name. Seven copies of a helper is how the semantics drift apart and how this bug class returns.

  Helper bodies use only constructs measured to propagate under bash 3.2 errexit — `grep`, `case`, `[ ]`, or a plain `return` — and never `[[` or `(( ))`. B-1's surface covers `helpers.bash` for exactly this reason.
- **check**: checker-deterministic, three parts:
  1. `tests/helpers.bash` exists and defines both names, counted with `/usr/bin/grep -cE '^[[:space:]]*(function[[:space:]]+)?(assert_contains|assert_not_contains)[[:space:]]*(\(\))?[[:space:]]*\{' tests/helpers.bash`, which must return 2. The pattern accepts either bash spelling of a definition — `name() {` or `function name` — so a valid file is not failed on style. Each of the **seven pre-existing** `.bats` files loads it: `/usr/bin/grep -l '^[[:space:]]*load ' tests/*.bats` lists at least those seven. `tests/lint.bats` is new and need only load the helpers if it uses them.
  2. The same pattern against `tests/install-failures.bats` finds nothing (exit 1) — the local copies are gone.
  3. The issue's probe, rewritten against the shared helpers, reports `not ok` for both cases. Outside `tests/`, write a two-case probe that loads `tests/helpers.bash`, each body calling a helper that must fail and then running a succeeding command, and run it with `bats --formatter tap`. Both cases must report `not ok`. Then run the same probe with `[[ ]]` in place of the helper call: that variant must report `ok`. Both halves are required — the second is what proves the probe discriminates rather than failing for an unrelated reason.
- **severity**: blocker
- **failing example**: A helper written as `assert_contains() { [[ "$2" == *"$1"* ]]; }`. Every call site now looks converted, the suite is green, and every assertion in the suite is swallowed exactly as before — the bug relocated into one function instead of fixed. B-1's surface catches this one; part 3's probe catches it even if the helper is written to dodge a first-token grep.

## Verification clauses

### V-1: The construct cannot come back

- **text**: A bats case in `tests/lint.bats` fails the suite if a bare `[[` or `((` statement is reintroduced anywhere on **B-1's guarded surface** — which B-1 defines and this clause does not restate. It lives inside the suite rather than in a standalone script so that `bats tests/` alone catches a regression, with no second entry point for a contributor or a CI job to forget.

  The case resolves the paths it scans relative to `BATS_TEST_DIRNAME`, never through `$PWD` or an absolute path, so it scans the tree it lives in. Without that, the mutation below silently scans the real working tree from inside the worktree copy and passes green — the lesson the previous job's V-1 wrote down after hitting it.

  The case must not flag its own source. Its pattern necessarily contains `[[` as literal text; the first-token rule is what keeps that from matching.
- **check**: checker-deterministic, two parts. First, `bats tests/lint.bats` exits 0 against the converted suite. Second, the mutation — without it, a case that greps for a pattern nothing produces passes forever and proves nothing. **Plant the canary in each of the three file kinds on the surface, one at a time**, because a guard that scans only `*.bats` is this clause's stated failing example and a single `.bats` planting would pass it:

```bash
REPO="$(git rev-parse --show-toplevel)"
git worktree add /tmp/agc-lint HEAD
# Copy the working-tree versions in. Without this the check runs against HEAD,
# which is the *baseline* until D-3's commit lands — none of the three files
# exists there, all three plantings error, and a correct worker gets FAILed for
# it. The previous job's V-1 hit exactly this and wrote it down.
cp tests/*.bats tests/helpers.bash tests/mutation-check.sh /tmp/agc-lint/tests/
cd /tmp/agc-lint

# Restores below are copies from the working tree. NEVER `git checkout` here —
# the paragraph after this block explains how that silently defeats plantings
# 2 and 3. If a previous run crashed, `git worktree prune` first.

# 1. a .bats file
printf '\n@test "canary" {\n\t[[ 1 -eq 1 ]]\n}\n' >> tests/jsonc.bats
bats --formatter tap tests/lint.bats     # MUST report "not ok"
cp "$REPO/tests/jsonc.bats" tests/       # restore from the WORKING TREE

# 2. the shared helpers — the one place a [[ disarms every call site at once
printf '\ncanary() {\n\t[[ 1 -eq 1 ]]\n}\n' >> tests/helpers.bash
bats --formatter tap tests/lint.bats     # MUST report "not ok"
cp "$REPO/tests/helpers.bash" tests/

# 3. the mutation script
printf '\n[[ 1 -eq 1 ]]\n' >> tests/mutation-check.sh
bats --formatter tap tests/lint.bats     # MUST report "not ok"
cp "$REPO/tests/mutation-check.sh" tests/

cd "$REPO" && git worktree remove /tmp/agc-lint --force
```

  **Restoring with `git checkout` breaks this check, and does it silently.** Measured pre-commit: the worktree is checked out at `HEAD`, which is still the *baseline*, where `tests/jsonc.bats` has two genuine bare `[[`. The `cp` overwrites that with the converted file, so planting 1 is honest — but `git checkout tests/jsonc.bats` then restores the baseline, putting those two real sites back. From planting 2 on, a guard that scans only `tests/*.bats` reports `not ok` off the baseline's own `[[`, not off the `helpers.bash` canary, and passes all three plantings. That guard is this clause's failing example word for word. Planting 3 compounds it: `git checkout tests/helpers.bash` fails outright, since that path is not in `HEAD` until D-3 commits, and planting 2's canary survives into planting 3.

  Repeat planting 1 with `(( 1 == 1 ))` in place of the `[[` line; the guard must report `not ok` for that too.

- **severity**: blocker
- **failing example**: A guard case that scans only `tests/*.bats` and never `tests/helpers.bash`, so a `[[` added to a helper — the one place it disarms the entire suite at once — passes the guard cleanly. Planting 2 is what catches this, and revision 1 of this clause did not have it.

### V-2: Every converted assertion still goes red when it is false

- **text**: This clause proves each converted assertion is **wired in** — that it is still evaluated, and that a false condition still turns its own case red. It does **not** prove the assertion is meaningful. Polarity inversion cannot tell a tautology from a live assertion by construction: measured, `assert_contains ""` reports `ok` unmutated and `not ok` inverted, so it satisfies this clause cleanly while checking nothing. **B-2 owns meaningfulness** — its reading of 53 before/after pairs is what catches a needle that cannot fail, and this clause is not a substitute for it. B-1 sees a converted line and V-3 sees a green suite; between them and B-2, this clause covers the one property neither can: that the wiring survived the conversion.

  `tests/mutation-check.sh` is committed and reusable. For each of the **53** converted assertions it inverts that one assertion, runs the containing file, and requires **that specific case** to report `not ok`.

  **The mutation rule is fixed here, so that neither the worker nor the checker has to invent one:**

  - A call to `assert_contains` becomes a call to `assert_not_contains` with the same arguments, and vice versa. Polarity inversion, which is exactly what `spec.md`'s AC4 asks for, and decidable by name.
  - The restructured disjunction from `tests/doctor.bats:244` is inverted by replacing both needles with a sentinel string guaranteed absent from the output. The script locates it by its enclosing `@test` name and its needle strings, **not by line number** — a line-pinned reference in a script advertised as reusable goes stale on the next edit to that file.
  - Any converted assertion whose form the script does not recognise is **reported by `file:line` and the script exits non-zero.** Silently skipping an unrecognised site is the one failure mode that would let a dead assertion through, so it is an error, not a warning.

  `tests/packages.bats:146` is excluded and the script says so: it is a `|| continue` guard, not an assertion, and inverting it changes which loop iterations run rather than making a test fail.

  **Exit status is not the proof.** The script parses `bats --formatter tap` output and confirms the mutated case itself reports `not ok`. A file-level non-zero exit is not enough: a mutation that breaks bash parsing, or that trips some other case in the same file, produces a non-zero exit while the mutated case never failed. That is the reasoning this clause's own failing example condemns, and revision 1 committed it.

  The script mutates one assertion at a time, restores the file before the next, and runs only the file it mutated. Measured against the baseline runtimes that is roughly 6 minutes for a full pass over all 53; re-running the whole suite per mutation would be about 31. **The script accepts an optional file argument** and, given one, mutates only that file's assertions — parts 1a, 3, and 4 each need a scoped run, and without that they cost a full pass apiece. Budget three passes plus a scoped one for the whole check, not one.

  **How it restores is part of the contract, not an implementation detail.** The script copies the original file to a temporary location before mutating and copies it back afterwards, including on interrupt or error. It must never restore with `git checkout`: this is a committed, reusable tool that a developer will run against a dirty working tree, and `git checkout` there discards their uncommitted work — and during this job, before D-3 commits, it would revert every conversion to the baseline the first time the script ran. V-1 carries the same prohibition for the same reason.
- **check**: checker-deterministic, **four parts. Part 4 is the only one that catches this clause's second failing example, so a check that stops at three has verified nothing about how the script reaches its verdict.** Parts 3 and 4 mutate files and must run in a scratch worktree; part 1 may run on the working tree, but only because the script is required above to restore what it touches without `git checkout`.
  1. `bash tests/mutation-check.sh` exits 0, and its output names 53 distinct `file:line` sites. Capture `git status --porcelain tests/` before and after the run and require the two to be identical — a script that leaves a mutation behind has failed regardless of what it printed.
  1a. **Confirm the restore is a copy-aside and not a `git checkout`.** Part 1's status comparison does not settle this: measured, it catches a `git checkout` restore only pre-commit, where reverting to baseline drops the file's modified entry from the listing. Post-commit on a clean tree, `git checkout` restores the committed content and the status is byte-identical either way, so part 1 passes a defective script and a correct one alike. This probe discriminates in both states — in a scratch worktree, append an unrelated line to a file the pass will mutate, run the script, and require the line to survive:

```bash
echo '# scratch marker' >> tests/jsonc.bats
bash tests/mutation-check.sh
/usr/bin/grep -q '# scratch marker' tests/jsonc.bats   # MUST still be there
```

  A copy-aside restore preserves the marker; `git checkout` destroys it. Verified post-commit, where part 1 alone cannot tell the two apart.
  2. **Cross-check by count, not by line number.** Baseline line numbers are worthless here: B-3's mandated `load` line shifts every line in every file, and B-2 turns one assertion into a multi-line `if`. Group the script's reported sites by file and require exactly: apps 11, doctor 20, font 12, jsonc 2, licensed-fonts 5, packages 3 — the assertions column of the Measured baseline table, totalling 53. Any file short of its count means assertions were dropped from the pass.
  3. **Confirm the script rejects a form it cannot mutate.** In a scratch worktree, replace one converted assertion with the literal `true`, then re-run. `true` matches no recognised mutation form, so the script must report that site as unrecognised and exit non-zero. This probe is decidable, which the revision 1 version ("replace it with a tautology and expect it to be unmutable") was not — under polarity inversion a tautology inverts to a falsehood, the file goes red, and a correct script would have been failed for it.
  4. **Confirm the script judges by TAP and not by exit status.** Parts 1 through 3 are all passed by a script that has a correct form parser and still concludes from the file's exit code, which is this clause's second failing example. This part is the only one that separates them. In a scratch worktree, append an unterminated `@test` block to **`tests/jsonc.bats`** — the fastest file, and one the pass must mutate twice — then re-run the script scoped to that file:

```bash
# bats reports the harness failure, not the mutated case. Against jsonc.bats
# (9 cases) the run collapses to a single synthetic failure:
#   not ok 1 setup_file failed
#   bats warning: Executed 1 instead of expected 9 tests
# Exit status is non-zero, and the mutated case never appears in TAP at all.
```

  A script reading exit status calls that mutation a success. A script reading TAP finds no `not ok` line for the case it named and must report failure. Require the latter.

- **severity**: blocker
- **failing example**: A script that mutates only the seven sites in the two fastest files, prints "all mutations red", and exits 0 — satisfying a checker who reads the exit code and not the site list; part 2 catches it. Or one that mutates every site correctly but concludes from the file's exit status alone, so a mutation that introduces a syntax error counts as a success while the assertion it was probing was never evaluated; **only part 4 catches that one**, which is why it exists.

### V-3: The suite is green, and nothing was dropped to get there

- **text**: `bats tests/` exits 0 with no case deleted, skipped, or renamed out of existence. Per-file `@test` counts stay at or above the measured baseline: apps 18, doctor 11, font 44, install-failures 17, jsonc 9, licensed-fonts 7, packages 13. The seven pre-existing files therefore contribute at least 119 cases, which is the measured figure and two above the 117 the issue states. `tests/lint.bats` is new and additional to those floors, so the suite total will exceed 119.

  Green alone is not evidence here and never was: the whole premise of the issue is that this suite runs green while assertions inside it check nothing. V-2 is what makes green mean something; this clause only ensures nothing was thrown overboard on the way.
- **check**: checker-deterministic:
  - `timeout 300 bats tests/` exits 0.
  - `/usr/bin/grep -c '^@test' tests/<file>` meets each floor above, for each of the seven pre-existing files, and their sum is at least 119.
  - `git diff 61213fe..HEAD -- tests/ | /usr/bin/grep -qE '^\+[[:space:]]*skip\b'` finds nothing. **Exit 1 is the passing case** — `grep` exits 1 on no match, and with `-c` it exits 1 while printing `0`. Only exit 2 means the check itself failed to run, and only exit 2 is `blocked`. B-1's check has the same semantics for the same reason.
- **severity**: blocker
- **failing example**: A stubborn conversion in `font.bats` is resolved by deleting its case, dropping the file from 44 to 43 while the suite goes green.

## Delivery clauses

### D-1: Scope

- **text**: The diff touches `tests/` and the two working-memory files D-2 covers, and nothing else. No script under `dot_local/`, no `.chezmoidata.toml`, no `run_onchange_*` template, and no change to what any script under test does. This job changes how tests assert, not what the code does.
- **check**: `python3 .agent-guild/scripts/check-diff-scope.py tests/ _working-memory/conventions.md _working-memory/decisionLog.md` exits 0, and exits 1 on any out-of-scope path — verified before this document was written by touching a file under `dot_local/bin/` and confirming exit 1 with the offending path named. It reads the working tree only and has no commit-range option, so it runs before D-3's commit; afterwards `git diff --name-only 61213fe..HEAD` carries the same question. The tree is clean at `61213fe`, so no `--ignore` is needed.
- **severity**: blocker
- **failing example**: A worker finds that `dot_local/bin/executable_dotfiles-doctor` genuinely emits neither `undeclared` nor `casks` in some path, and "fixes" the doctor so `doctor.bats:244`'s converted assertion passes — changing production behaviour to satisfy a test conversion.

### D-2: The bash 3.2 rule is written down where the next agent reads it

- **text**: `_working-memory/conventions.md` already carries this repo's bash 3.2 rules; it gains the one this job establishes — assert with the shared helpers, never with a bare `[[` or `(( ))`, because their failure is discarded anywhere but a function's last statement, and a later iteration of a loop can mask an earlier failure. `_working-memory/decisionLog.md` gains a dated entry recording the decision and the incident behind it: this surfaced during #17, when a draft of `install-failures.bats` had an early failing assertion masked by a later passing one, and was caught only because that file was required to fail against the pre-fix scripts.

  Comments added to the test files and to `helpers.bash` explain why the code has this shape — the constraint, the measurement, the thing a reader would otherwise reintroduce. The comment already at `tests/install-failures.bats:67-72` is the register to match; it explains the bug better than the issue does. A comment restating what a line does fails.
- **check**: checker-judgment: read the conventions bullet, the decisionLog entry, and every added comment against the converted suite. FAIL if conventions does not name both `[[` and `(( ))`, if it does not say why (failure discarded except as the last statement), if `decisionLog.md` has no dated entry for this job, or if any added comment could be deleted without losing information the code does not already carry. Working memory is machine-first: judge these on factual accuracy against the measurements in this constitution, not on tone.
- **severity**: major
- **failing example**: A conventions bullet reading "prefer `assert_contains` over `[[ ]]` in tests" — true, unexplained, and so exactly the kind of rule the next agent overrides when it seems inconvenient.

### D-3: Committed, unpushed, and each commit stands alone

- **text**: The work lands as commits that each stand on their own, none pushed. Messages cover why the change was made, carry no `Co-Authored-By` or any other attribution trailer, and are not hard-wrapped. The working tree is clean when the job ends.
- **check**: checker-judgment, over:
  - `git log --format=%B 61213fe..HEAD` for the messages. The range starts at this job's baseline, so it holds this job's commits and nothing else.
  - `git rev-list 61213fe..HEAD`, each sha through `git branch -r --contains <sha>`. Any commit naming a remote branch has been pushed — FAIL. `git log origin/main..HEAD` cannot detect a push at all, since pushing removes a commit from that range rather than adding one.
  - `git status --porcelain` for the clean tree.
  - `git diff --name-only 61213fe..HEAD` for post-commit scope, since D-1's script cannot read a commit range. FAIL on any path outside D-1's allowlist. This is not redundant with D-1: `check-diff-scope.py` reads only the working tree, so it goes vacuous the moment the worker commits, and this is where the scope question survives that handover.

  FAIL on a dirty tree, on any commit reachable from a remote branch, on a trailer, on hard-wrapped body lines, or on a message that only restates the diff. A commit whose message begins `[auto-sync from` is not a worker's and means the LaunchAgent ran despite the precondition: report `blocked`, not a worker failure.
- **severity**: major
- **failing example**: One commit titled `test: use helpers` whose body lists the seven files changed, with the branch already pushed — caught by `git branch -r --contains`, invisible to the range check it replaces.

## Protected content

None. No passage in this job has to ship verbatim, so there is no manifest.

## Non-goals

- **Requiring bash 4+ for the suite.** `/bin/bash` is 3.2 on every stock macOS and the scripts under test run under it. Testing on a different shell than production trades this bug for a worse one.
- **Auditing whether any assertion is currently masking a real failure.** Worth knowing, and V-2's mutation pass will incidentally surface any conversion that cannot go red — but running down a masked failure in the code under test is a separate job, and this one does not depend on the answer.
- **Changing what any assertion checks.** B-2 enforces this. The one restructured site, `doctor.bats:244`, keeps both substrings precisely so the restructuring does not become a rewrite.
- **Converting single-bracket `[ ]` assertions.** Measured safe under bash 3.2 errexit, mid-body and in a loop. All ~162 stay as they are.
- **Fixing anything the tests test.** D-1 keeps `dot_local/` and the templates out of the diff.
- **The `(( ))` conversion.** There is nothing to convert; the guard covers it prospectively and that is the whole of its scope here.
- **A corrected count of vulnerable-by-position assertions.** The issue's 24 is an undercount, and this document says so and stops there. B-1 converts all 54 regardless of position, so the number gates nothing.
