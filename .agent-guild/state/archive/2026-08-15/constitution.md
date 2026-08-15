# Constitution: drop-and-retry the unresolvable Brewfile entry (#22)

**Job weight**: standard, the bats harness and its stub conventions already exist but need extending, and the artifact is a `run_onchange` script that fires unattended during apply.

## Clauses

### C-1: the retry installs the survivors
- **text**: When `brew bundle` fails in its fetch phase and `brew info` resolves some of the batched names but not others, the installer removes only the unresolvable entries' lines from the rendered Brewfile and invokes `brew bundle` a second time with what remains, names every dropped entry in its own summary using the existing two-space indent, and exits 0. `tests/install-failures.bats` carries exactly two cases whose descriptions contain the string `drop-and-retry`, and **both prove their claim from a recorded log of every `brew bundle` invocation and the Brewfile each one received** — never from the summary text alone, which `run_onchange_install-packages.sh.tmpl:94-95` already prints today and which therefore cannot distinguish a fixed installer from the bug:
  - a batch of three names where one fails `brew info`, asserting the log holds two `bundle` invocations and that the second one's Brewfile carries both survivors and not the dropped name. All three names are read out of the rendered Brewfile rather than invented, so that dropping one is observable — against a fixture name the render never contained, "not the dropped name" is vacuously true and the case proves nothing.
  - a batch where every name fails `brew info`, asserting the log holds exactly one `bundle` invocation, so the script reports all of them rather than retrying against an empty Brewfile
- **check**: .agent-guild/scripts/check-build.sh '[ "$(bats -c -f "drop-and-retry" tests/install-failures.bats)" -eq 2 ] && bats -f "drop-and-retry" tests/install-failures.bats'
- **severity**: blocker
- **failing example**: the installer prints the unresolvable name and exits, leaving the stub's bundle-invocation log with exactly one entry and every survivor uninstalled — the behavior #22 reports.

### C-2: the happy path costs nothing
- **text**: A run in which `brew bundle` exits 0 makes no `brew info` call and exactly one `brew bundle` call, which is what the script does today. `tests/install-failures.bats` carries a case whose description contains `no extra brew calls`, driving a stub that logs every invocation by subcommand and asserting the `info` count is 0 and the `bundle` count is 1.
- **check**: .agent-guild/scripts/check-build.sh 'bats -f "no extra brew calls" tests/install-failures.bats'
- **severity**: blocker
- **failing example**: the installer resolves each entry with `brew info` up front to decide what to send, so a clean apply on this machine spends 88 extra `brew` calls to guard against a case that almost never fires — the up-front validation the issue rules out.

### C-3: a second failure reports and stops
- **text**: When the retry in C-1 fails for any reason other than an unresolvable name, the script reports that failure and makes no third `brew bundle` call. `tests/install-failures.bats` carries a case whose description contains `reports and stops`, where the first `bundle` dies in the fetch phase with one unresolvable name and the second dies in the install phase, asserting the stub's bundle-invocation count is exactly 2 and the script still exits 0.
- **check**: .agent-guild/scripts/check-build.sh 'bats -f "reports and stops" tests/install-failures.bats'
- **severity**: blocker
- **failing example**: the retry loops on each new failure, so a locked network turns one apply into an unbounded series of `brew bundle` invocations.

### C-4: the whole suite stays green
- **text**: `bats tests/` passes end to end — 125 cases green on the clean tree this job starts from. This job must not regress the bash 3.2 bare-compound guard in `tests/lint.bats`, nor any of the five existing `install-packages` cases at `tests/install-failures.bats:74-181`. Those five are:
  - absent tool skips clean
  - present tool failing names the item
  - a fetch-phase failure names only the entry that doesn't exist
  - a fetch failure where every entry exists names the whole batch
  - all items succeed prints no failure summary
- **check**: .agent-guild/scripts/check-build.sh 'bats tests/'
- **severity**: blocker
- **failing example**: the new drop-and-retry branch expands an empty array under the existing fetch-phase parser, and `install-packages: a fetch failure where every entry exists names the whole batch` starts failing on the path it used to cover.

### C-5: the new coverage is driven from stubs
- **text**: Every case this job adds drives the installer as a real subprocess with `brew` stubbed on PATH, reaching no real Homebrew and installing nothing, and asserts against the script's own summary rather than against text a stub echoed — the trap `tests/install-failures.bats:130-131` already names, where a bare package name appears in both brew's batch line and the script's report.
- **check**: checker-judgment: read each case added to tests/install-failures.bats; FAIL if any (a) invokes real brew or mutates machine state; (b) proves its claim only by matching a string the stub itself printed rather than the script's own indented summary or reworded report line; (c) omits the assertion its own clause names — specifically, a `drop-and-retry` case that does not read a recorded log of `brew bundle` invocations (and, for the mixed-batch case only, the Brewfile the second invocation received) per C-1, a `no extra brew calls` case that does not assert both the `info` and `bundle` counts per C-2, or a `reports and stops` case that does not assert the `bundle` count is exactly 2 per C-3; or (d) drives the installer more than once within a single case, which inflates the invocation log until a count assertion passes on an installer that never retried.
- **severity**: blocker
- **failing example**: a `drop-and-retry` case stubs brew, drives the script as a subprocess, and asserts `[ "$status" -eq 0 ]` plus `assert_contains "  fixture-nonexistent-xyz"` — plausible on review, and green against the installer as it stands today with no retry branch at all, because the existing `brew info` re-derivation already prints that exact indented line.

### C-6: the doctor stops promising a retry it can't deliver
- **text**: Both `next apply installs these` parentheticals in `dot_local/bin/executable_dotfiles-doctor` (lines 17 and 58) are reworded to describe what `run_onchange`'s hash model actually does: apply has already run these and will not re-run until the rendered input changes. The rewording says what the reader should do instead, and no wording anywhere in the file claims an automatic retry.
- **check**: checker-judgment: read both parentheticals against the run_onchange hash comment at run_onchange_install-packages.sh.tmpl:2-5; FAIL if either still promises the next apply will install the listed items, if either is merely deleted rather than replaced with something a reader can act on, or if the new wording asserts behavior the script does not have.
- **severity**: major
- **failing example**: the parenthetical is trimmed to `-- in a bundle you've enabled but not installed:` with nothing in its place, so the list is still there and the reader has less idea than before about what to do with it.

### C-7: the registry is reported on, never edited
- **text**: The working-tree diff touches only these five paths, with `.chezmoidata.toml` unmodified so a package that vanished upstream is reported for a human to rule on rather than silently dropped:
  - `run_onchange_install-packages.sh.tmpl`
  - `dot_local/bin/executable_dotfiles-doctor`
  - `tests/install-failures.bats`
  - `tests/doctor.bats`
  - `_working-memory/`
- **check**: .agent-guild/scripts/check-diff-scope.py run_onchange_install-packages.sh.tmpl dot_local/bin/executable_dotfiles-doctor tests/install-failures.bats tests/doctor.bats _working-memory/ --ignore dot_claude/encrypted_private_settings.json.age
- **severity**: blocker
- **failing example**: the worker deletes the `deskflow` line from `.chezmoidata.toml` to make a test pass, resolving a question — renamed, moved to a tap, or genuinely gone — that the issue reserves for a human.

### C-8: added comments explain why
- **text**: Every comment this job adds to the installer or the doctor explains a constraint, a past incident, or an invariant a reader would otherwise miss, matching the density and voice of the comments already in those files. No comment restates what the adjacent line does.
- **check**: checker-judgment: diff each added comment against the surrounding file; FAIL if any comment paraphrases its own code, if the drop-and-retry branch and the no-third-attempt stop carry no explanation of why they are shaped that way, or if the added prose reads as machine-generated against the voice of run_onchange_install-packages.sh.tmpl:30-35 and :62-67.
- **severity**: minor
- **failing example**: `# Remove the failed entries from the Brewfile` sits above the line that removes the failed entries from the Brewfile, while nothing anywhere records that the retry is capped at one attempt because an unbounded loop turns a locked network into a hang.

## Protected content

- none — this job ships no verbatim author copy.

## Non-goals

- Removing dead entries from `.chezmoidata.toml` automatically. Whether a vanished package was renamed, moved to a tap, or dropped is a human call.
- Making `run_onchange` retry until it succeeds. Settled as a non-goal in #17 and unchanged here.
- Aborting the apply on failure. Also settled in #17: the script exits 0 by design.
- Progress display. #16 owns that.
- Pre-validating entries before the fetch. The issue rules this out on cost: 88 `brew info` calls on every apply to guard a case that almost never fires.
