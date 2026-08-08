---
source: github-issue
ref: kendrick/dotfiles#17
issue: 17
title: Failed installs exit 0, so chezmoi records the script as done and never retries
fetched_at: 2026-08-06T18:58:03Z
---

# Failed installs exit 0, so chezmoi records the script as done and never retries

## Problem

A failed package install is indistinguishable from a clean one, and because `run_onchange_` scripts record themselves as done by content hash, nothing ever retries it.

This happened on 2026-08-06. `fzf` was added to the `core` bundle, `chezmoi apply` ran, and `install-packages.sh` was recorded in chezmoi's `scriptState` at `18:28:36Z`. `fzf` was never installed. There was no error on screen, nothing in the state, and no second attempt, because from chezmoi's point of view the script had succeeded. The failure only surfaced later when a tool that depends on `fzf` refused to start.

The last line of the installer is what does it:

```bash
brew bundle --file=/dev/stdin <<<"$brewfile" || echo "Some Brewfile entries failed (MAS apps may need manual install)."
```

Reproduce on a clean checkout:

```bash
printf 'brew "definitely-not-a-real-formula-xyz"\n' > /tmp/bad.txt
brew bundle --file=/tmp/bad.txt          # fails loudly, non-zero
bash -c 'brew bundle --file=/tmp/bad.txt >/dev/null 2>&1 || echo "Some Brewfile entries failed (MAS apps may need manual install)."; echo "script exit: $?"'
```

**Observed:**

```
`brew bundle` failed! Failed to fetch definitely-not-a-real-formula-xyz
Error: No available formula with the name "definitely-not-a-real-formula-xyz".
--- with the installer's guard ---
Some Brewfile entries failed (MAS apps may need manual install).
script exit: 0
```

**Expected:** the run names `definitely-not-a-real-formula-xyz` as the thing that failed, and the failure is still visible after the apply finishes rather than scrolling past once.

The guard itself is deliberate and mostly right. `conventions.md` under "Error Handling" says external-tool installers guard each call with `|| true` so they skip cleanly when the CLI is absent, and that reasoning holds: a machine without `code` on `PATH` should not abort an apply. The defect is that "the tool isn't here, skip" and "the tool ran and could not do the job" are currently the same outcome. Only the second one is a problem, and it's the one being hidden.

The same shape appears at 28 sites across the `run_` scripts. Not all are wrong: the `defaults write ... || true` calls in `run_once_after_configure-macos.sh` are guarding keys that are genuinely no-ops on current macOS, which is a case the repo already decided on (antipatterns, 2026-03-24). The install paths are the ones that matter:

- `run_onchange_install-packages.sh.tmpl:31` — `brew bundle`, the incident above
- `run_onchange_install-vscode-extensions.sh.tmpl:21` — `code --install-extension ... 2>/dev/null || true`, which discards the error text as well as the exit code
- `run_onchange_configure-raycast.sh.tmpl:22` — `open raycast://... 2>/dev/null || true`
- `run_onchange_after_install-claude-plugins.sh.tmpl:33,40` — `claude plugin add/install ... 2>/dev/null || true`

## Proposed Behavior

Keep skipping when a tool is absent. Stop hiding it when a present tool fails.

Each install-phase script separates the two cases: if the CLI isn't on `PATH`, say so once and exit clean, exactly as today. If the CLI is there and an item fails, collect the item and keep going, then report the collected failures by name at the end of the script.

The apply itself should not abort. Installing 90 of 92 packages and naming the two that failed is more useful than stopping at the first one, and it matches how the VS Code extension loop already wants to behave.

A run with failures should also be visible after the fact rather than only in scrollback. `dotfiles-doctor` already answers "what's tracked but not installed" as of #4, so a failed install shows up there on the next run without new machinery. Worth confirming that's true rather than assuming it.

`run_onchange_after_restore-agent-skills.sh.tmpl:87` is the closest thing to the target shape already, and it names its source in the message.

## Acceptance Criteria

- [ ] With a deliberately bad entry in the package registry, the apply prints the failing item's name, not a generic "some entries failed"
- [ ] With the relevant CLI absent from `PATH`, the script still exits 0 and says it skipped, with no failure reported
- [ ] A failed install is distinguishable from a skip in the output, by wording rather than by exit code alone
- [ ] One failing item does not prevent the remaining items in the same script from being attempted
- [ ] After an apply where a package failed to install, `dotfiles-doctor` reports that package under "in a bundle you've enabled but not installed"
- [ ] `~/.local/state/dotfiles/last-sync.log` contains the failing item's name after an auto-sync run that hit a failure
- [ ] The four install-path sites listed in Problem are converted; the `defaults write` guards in `run_once_after_configure-macos.sh` are left alone
- [ ] `bats tests/` passes, with new coverage for both branches (tool absent, and tool present but failing) driven by stubs rather than by a real failed install

## Non-Goals

- **Aborting the apply on first failure.** Getting 90 of 92 packages and a list of the 2 that failed beats stopping at the first one.
- **Retrying failed installs automatically.** A transient network failure and a renamed formula look the same from here, and retrying the second one forever is its own kind of silence.
- **Making chezmoi re-run the script until it succeeds.** That would mean not recording `run_onchange` state on failure, which fights the tool's model. Reporting the failure and letting `dotfiles-doctor` carry it is the lighter path.
- **The `defaults write` guards in `run_once_after_configure-macos.sh`.** Those are guarding keys that no longer exist on current macOS, which is settled (antipatterns, 2026-03-24).
- **Progress display during the run.** That's #16, and the two shouldn't be tangled.

## For a Coding Agent

- **Verify with:** `bats tests/`
- **Start here:** `run_onchange_install-packages.sh.tmpl:31` is the incident. `run_onchange_after_restore-agent-skills.sh.tmpl:87` is the shape to copy. `run_onchange_install-vscode-extensions.sh.tmpl:21` is the worst of the four, since it throws away stderr too.
- **Read first:** `conventions.md` under "Error Handling" for why the guards exist, and under "bash 3.2" before writing any accumulator — expanding an empty array under `set -u` aborts, so guard every expansion with `[ "${#arr[@]}" -gt 0 ]`. `run_onchange_after_install-global-node-packages.sh.tmpl:32-33` documents a related trap: on bash 3.2, errexit fires on a failing external command even through `|| true`.
- **Environment:** macOS, `/bin/bash` is 3.2, `bats-core` is in the registry. `tests/doctor.bats` shows the stub-on-`PATH` harness these tests should use.
- **Done when:** every acceptance criterion passes, and a real apply with a deliberately broken registry entry has been run end to end and then reverted.
- **Out of scope:** everything in Non-Goals.

