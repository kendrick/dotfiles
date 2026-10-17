# dotfiles-doctor --fix (#67) Implementation Plan

**Goal:** `dotfiles-doctor --fix` installs the tracked, enabled Homebrew formulae and casks that are missing, after showing the exact commands and getting a yes. Plain `dotfiles-doctor` stays a report.

**Tech Stack:** bash (`set -euo pipefail`), Homebrew, jq, bats.

---

## Context

Issue #67. `run_onchange_install-packages.sh.tmpl` exits 0 by design (`:355-357`), so a package that failed on its one apply, or was removed by hand later, is never retried. `dot_local/bin/executable_dotfiles-doctor:104-114` already finds those packages and prints them under `-- in a bundle you've enabled but not installed (install by hand; …)`. The script takes no arguments today (no `usage`, no parsing), and its header at `:2-5` promises "Read-only".

## Decisions

These are settled. Implement them as written.

1. **Argument parsing** follows `dot_local/bin/executable_dotfiles-apps:21-26,261-272`. It adds a `usage()` that documents `--fix` and a `while`/`case` loop handling `-h|--help` (print usage, exit 0) and `--fix`. Any other argument prints usage to stderr and exits 2. That last rule is a deliberate change: an unknown flag is silent today.
2. **Collect while reporting.** The missing-package loops at `:107-114` already decide each missing name. Have them also append to two arrays, `missing_brew` and `missing_cask`, so `--fix` acts on exactly what the report printed. Nothing is recomputed. The source lists are `tracked_brew_installable` and `tracked_cask_installable`, which already leave out OS-held entries.
3. **The fix runs after the whole report.** Plain output is unchanged except for decision 6. With `--fix`, a final section follows:
   - If `brew` or `jq` is missing, print that the fix needs both, and exit 1. The Homebrew section never ran, so "nothing missing" would be a lie.
   - If both arrays are empty, print `-- nothing to install`, run no `brew` command, and exit 0.
   - Otherwise, print the commands it will run: `brew install <formulae…>` when `missing_brew` is non-empty, and `brew install --cask <casks…>` when `missing_cask` is non-empty. Formulae keep their tap-qualified names exactly as the report prints them. Then ask `Install these? [y/N] ` with `read -r` from stdin. Only `y` or `yes` (any case) proceeds. Anything else, including EOF, is a decline: print `-- nothing installed`, and exit 1. A piped answer is accepted, so tests and a deliberate `echo y |` work. A run with no stdin declines, which exits non-zero, so an unattended caller can't confuse it with a clean machine. There is no `--yes`, because the issue doesn't ask for one.
   - Before installing, trust each tap named by a qualified formula with `brew trust --tap <tap> 2>/dev/null || true`, as the installer does at `run_onchange_install-packages.sh.tmpl:28-30`. Homebrew 6 refuses untrusted taps.
   - Run each command with its status captured, so `set -e` can't skip the second command or the summary. Exit 1 if either command fails, and 0 otherwise.
4. **Install only.** `--fix` never removes anything. It never touches the installed-but-untracked list, which belongs to `dotfiles-apps --adopt`. App Store apps and VS Code extensions are out of scope.
5. **Header comment** at `:2-5` changes to say the script is read-only unless `--fix` is given, and that `--fix` only installs.
6. **The word `uninstall` leaves the file,** because the acceptance criterion `grep -c 'uninstall' dot_local/bin/executable_dotfiles-doctor` must print `0`. Reword the occurrences at `:15`, `:35`, `:89` and `:167`, using "remove it" in the two printed headings. Those two printed headings are the only change to plain output. No test asserts on those words (checked: `grep -n uninstall tests/doctor.bats` matches only a test name and a comment).
7. **The heading at `:104` keeps its text.** A test asserts on its `in a bundle you've enabled but not installed` substring, and the issue wants plain output unchanged.
8. **README** `README.md:142` updates the `dotfiles-doctor` row so it no longer says "read-only". It names the report and the `--fix` install offer.

## Task: add --fix to dotfiles-doctor

**Files:** dot_local/bin/executable_dotfiles-doctor, tests/doctor.bats, README.md

### Tests in tests/doctor.bats

Replace the no-op `brew` stub for these cases with a stateful one, following `stub_brew_info` at `:168-180`:

- It keeps installed formulae and casks in two files under the test's temp dir.
- `list --formula` and `list --cask` print those files.
- `leaves` prints the formula file.
- `install [--cask] <names…>` appends each bare name (the part after the last `/`) to the right file and logs the full argv to `$BREW_LOG`. A name listed in `$BREW_REFUSE` exits 1 without adding.
- `trust` exits 0 and logs.

Update the header comment at `:3-4`, which says doctor never fixes.

Settle each expected value from the issue's acceptance criteria, not from the new code. Assert against what the stub's `list` reports, not against doctor's printed log.

1. **`--help` documents `--fix`.** The output contains `--fix`, and the exit is 0.
2. **An unknown flag is refused.** Exit 2, and stderr contains the usage.
3. **Plain run installs nothing.** With one tracked formula missing, `brew list --formula` and `brew list --cask` output is byte-identical before and after, and `$BREW_LOG` has no `install` line.
4. **`--fix` plus `y` installs the formula.** The formula then appears in the stub's `list --formula`.
5. **Decline.** Piping `n`, or no stdin at all (`</dev/null`), leaves `list --formula` unchanged and exits non-zero.
6. **Nothing missing.** No `install` in `$BREW_LOG`, and exit 0.
7. **One formula and one cask missing.** One `--fix` run installs both. The formula's install line has no `--cask`, and the cask's line has `--cask`.
8. **A refused install.** The name is in `$BREW_REFUSE`, and the run exits non-zero.
9. **A tap-qualified formula.** It is passed to `brew install` qualified, and `trust --tap <tap>` is logged before the install.
10. **Static criterion.** `grep -c uninstall` on the script prints `0`.

## Verification

- `bats tests/doctor.bats` passes.
- `bash tests/mutation-check.sh tests/doctor.bats` reports every new site killed. `doctor.bats` is already in `ALL_FILES`, so this lane doesn't edit `tests/mutation-check.sh`. The #74 lane owns that file in this wave. Run it in the foreground and expect about 30 minutes.
- `grep -c 'uninstall' dot_local/bin/executable_dotfiles-doctor` prints `0`.
- `bats tests/` exits 0.

## Out of Scope

- App Store apps (`mas install`) and VS Code extensions (#45).
- `run_onchange_install-packages.sh.tmpl`, which keeps its `exit 0`.
- The VS Code section of the doctor (`:10-25`, `:264-290`). The #45 lane keeps the default profile's list where those lines read it.
- `tests/mutation-check.sh` and `_working-memory/`.
