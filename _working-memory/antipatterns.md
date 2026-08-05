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

## 2026-08-04 — Don't poll `op read` as a readiness check
**Tried:** Using `op read` itself as the predicate for "is 1Password ready yet," which is the obvious shape since it's the call we actually want to succeed. Rejected at design time rather than shipped, but verified against the real CLI first.
**What broke:** `op read` resolves a secret, so it triggers a Touch ID prompt on every invocation. `spin_until` re-runs its predicate every couple of seconds, which would have put a biometric prompt on screen continuously for the length of the wait.
**Why we backed out:** `op account list --format=json` returns the account set the desktop app is exposing with no prompt at all (confirmed: exit 0, no Touch ID), and stays empty until the CLI integration is switched on. That makes it a clean readiness signal, with the single `op read` saved for after the wait.
**Don't suggest:** Polling `op read`, `op item get`, or any `op` subcommand that resolves a secret. Probe with `op account list` and read once. _(run_before_provision-age-key.sh.tmpl, commit 50443df)_

## 2026-08-04 — Don't try to script the 1Password CLI integration toggle
**Tried:** Looking for a way to enable Settings > Developer > Integrate with 1Password CLI from the bootstrap, so the age-key fetch could be fully unattended.
**What broke:** 1Password stores that setting inside its signed group-container settings. Writing it externally is unsupported and gets tamper-detected, and the toggle exists precisely so the user consents to CLI access.
**Why we backed out:** Accepted it as a manual step and designed around it. The script installs the app, opens it, and blocks on a readiness probe until you flip it, so the one unautomatable step is at least obvious and in your way rather than discovered later.
**Don't suggest:** `defaults write com.1password.1password`, editing the group-container settings JSON, or any other scheme to skip the toggle. If a headless path is genuinely needed, the answer is `OP_SERVICE_ACCOUNT_TOKEN`, which bypasses the desktop app entirely (considered and declined; see decisionLog 2026-08-04).

## 2026-06-15 — Don't deploy a file that's generated into source
**Tried:** Tracking the VS Code extension list (and a rendered `~/.config/Brewfile`) as normal deployed managed files while dotfiles-sync / the code() wrapper regenerate them into source.
**What broke:** The blanket `chezmoi re-add` captures the stale deployed copy back over the freshly-generated source, so every regenerate is silently undone.
**Why we backed out:** Made them source-only via `.chezmoiignore` — nothing reads the deployed copies (the installer renders the Brewfile inline; the VS Code list is `include`d from source).
**Don't suggest:** Deploying a generated/rendered data file as a managed target, or "fixing" its drift by reordering sync or writing both source and target. Keep it source-only. _(commits fba602b, f5769cc)_

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
