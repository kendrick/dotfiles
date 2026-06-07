# Antipatterns

<!-- Negative knowledge. Things the team tried that didn't work, captured so   -->
<!-- agents and humans don't re-litigate closed loops. Append-only, like        -->
<!-- decisionLog.md.                                                            -->
<!--                                                                            -->
<!-- Format: -->
<!-- ## YYYY-MM-DD — [Short title in imperative voice — what to avoid]         -->
<!-- **Tried:** What was attempted                                              -->
<!-- **What broke:** Observed failure mode                                      -->
<!-- **Why we backed out:** Root cause if known; otherwise the observed pain    -->
<!-- **Don't suggest:** Specific things agents should not re-propose            -->
<!--                                                                            -->
<!-- The last line is the agent-targeted lever. Be specific. "Don't suggest    -->
<!-- moving X to Y" beats "don't suggest big refactors."                       -->

## 2026-06-07 — Don't symlink VS Code settings.json into the repo
**Tried:** Managing `settings.json` as a chezmoi symlink so UI edits write straight to the source.
**What broke:** VS Code writes settings atomically (temp file + rename), which replaces the symlink with a regular file and silently breaks the link.
**Why we backed out:** Kept it a managed copy; `dotfiles-sync` captures it via `chezmoi re-add` instead.
**Don't suggest:** Converting `settings.json` (or other apps that rewrite files atomically) to `symlink_` chezmoi entries.

## 2026-06-07 — Don't auto-dump the Brewfile with `brew bundle dump`
**Tried:** Having `dotfiles-sync` run `brew bundle dump --force` to capture installed packages automatically.
**What broke:** The Brewfile is a chezmoi template with `{{ if eq .machine_role }}` guards and tap sections; a flat dump overwrites and destroys all of that.
**Why we backed out:** `dotfiles-sync`/`dotfiles-doctor` only *report* Brewfile drift; new packages get added to the right section by hand.
**Don't suggest:** Auto-writing or dumping the Brewfile, or flattening its machine-role conditionals.

## 2026-03-24 — Don't re-add deprecated macOS defaults
**Tried:** Carrying the full Mathias Bynens `set-defaults.sh` forward.
**What broke:** Many `defaults write` keys are no-ops or error on Sequoia+ Apple Silicon.
**Why we backed out:** Stripped to only settings that still take effect.
**Don't suggest:** Re-importing the old Bynens defaults wholesale or restoring commented-out keys. _(run_once_after_configure-macos.sh:2-3)_

## 2026-03-24 — Don't use `set -e` in the macOS-defaults script
**Tried:** `set -e` for fail-fast safety.
**What broke:** Safari sandbox `defaults write` calls error and aborted the whole run.
**Why we backed out:** A single non-fatal default shouldn't stop configuration.
**Don't suggest:** Adding `set -e` back to `run_once_after_configure-macos.sh`. _(commit 1f2a217)_
