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
