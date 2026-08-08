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

## 2026-08-07 — Don't assume `brew bundle` reports failures in one shape
**Tried:** Reading the failed Brewfile entries back out of brew's output by matching one message, `Installing <entry> has failed!`.
**What broke:** It passed its own tests and failed the first real end-to-end run. brew emits five distinct failure strings across two phases (`installer.rb:85,112,213`, `parallel_installer.rb:250,309`), and the fetch phase returns before the install phase runs, so on a fetch abort none of the per-entry lines exist at all. The verb also varies (Installing, Upgrading, Tapping), so even within the install phase a literal match misses cases. `deskflow` had been aborting every package install on this machine for an unknown stretch while the parser found nothing to report.
**Why we backed out:** The fetch phase emits one line naming every entry that needed downloading, guilty or not — six names for one bad formula in the observed case. There is nothing in it to parse. `1bc1fb5` re-derives instead, asking `brew info` which of the batch actually resolves, which answers the question without depending on any message shape.
**Don't suggest:** Matching a literal verb in brew's failure lines. Parsing the `Failed to fetch` batch line to name a guilty entry, or blaming the first name in it. Treating `brew bundle`'s non-zero exit as a single failure mode. And don't touch this parsing without reading `/opt/homebrew/Library/Homebrew/bundle/installer.rb` first: assuming a shape is what produced both the original bug and its first fix's failure. _(decisionLog 2026-08-07; GitHub #17, #22)_

## 2026-08-06 — Don't dump packages over the registry, and don't hand-edit the rendered Brewfile
**Tried:** Nothing new broke. This scopes the 2026-06-07 entry below, whose reasoning stopped being true when GitHub #4 landed.
**What broke:** That entry says not to dump the Brewfile because it's a template with `machine_role` guards. There are no guards left. `.chezmoitemplates/Brewfile` holds no package names at all, and the Brewfile never exists on disk. The conclusion survives its reasoning: `brew bundle dump` produces a flat list, and which bundles a package belongs to is a judgement nothing in Homebrew's output encodes.
**Why we backed out:** `dotfiles-sync` and `dotfiles-doctor` still only report. A tool that files a package into a bundle is wanted, and is GitHub #5, but it writes `.chezmoidata.toml` after asking, not by dumping.
**Don't suggest:** Auto-dumping into `.chezmoidata.toml`. Editing `.chezmoitemplates/Brewfile` to add a package: it's a render, and the edit vanishes on the next apply. Reading Brewfile text to find out what's tracked; ask `chezmoi execute-template` for `.pkg.packages` instead.

## 2026-08-05 — Don't decide a font has ligatures from its GSUB feature tags
**Tried:** Two cheap proxies for "is this font ligature-bearing," which the roster requires of every entry. First the feature tags (`calt`, `liga`, `dlig`, `rlig`), then a count of GSUB type 4 `LigatureSubst` rules when the tags proved too loose.
**What broke:** Both are wrong in opposite directions. SF Mono carries a `calt` tag that substitutes nothing, so tags alone would have admitted a font with no ligatures at all. The rule count then reported Fantasque and Recursive as having none — Fantasque being a font whose ligatures had been watched rendering on screen minutes earlier. Both implement ligatures as chained contextual substitutions rather than type 4, so the count reads zero for fonts that ligate perfectly well.
**Why we backed out:** Glyph names settle it. Coding fonts name their ligature glyphs `.liga` (`colon_colon.liga`, `hyphen_greater.liga`) or `.code` for Recursive, readable from the `post` table with no dependencies. Three signals agreeing (no tags, no rules, no ligature-shaped glyph names) is what struck SF Mono; a font failing only the rule count is a contextual implementation, not a ligature-free font.
**Don't suggest:** Concluding anything about ligatures from feature tags or `LigatureSubst` counts on their own, and don't read a stylistic set as an obvious win either — Maple's and Lilex's ssXX sets are named "Broken _X_ ligatures" and turn them **off**. Read the set's UI name out of the GSUB FeatureParams before enabling it. _(dataContracts "Stylistic sets are not interchangeable with ligatures")_

## 2026-08-05 — Don't assert on a value the code under test is about to own
**Tried:** Writing tests against values read from the live managed config: `editor.fontLigatures` pinned to `true`, and the roster listing asserting Fantasque was the active font.
**What broke:** Both broke within the same session. The switcher started writing `editor.fontLigatures` as a feature string, and the "active font" is whatever was selected the last time someone switched and `chezmoi re-add` captured it. Neither failure meant anything was wrong; the tests were just describing a moving target.
**Why we backed out:** Derive expectations from the data file or the fixture. The listing test now reads the active family out of the fixture's Ghostty block and looks up its registry key; the ligature test asserts the key survives the parse rather than what it holds.
**Don't suggest:** Hardcoding a font name, a size, or any other value a managed config owns into a test, or "fixing" such a test by updating the constant. Read it from the registry or the fixture. _(tests/font.bats, tests/jsonc.bats)_

## 2026-08-05 — Don't trust a PATH stub to isolate this repo's scripts
**Tried:** Testing scripts by putting stub `npx` / `op` / `chezmoi` / `launchctl` binaries first on `PATH`, and testing chezmoi itself by pointing `-S` and `-D` at a scratch tree.
**What broke:** Twice, the script under test re-prepended a real bin directory partway through and the stubs stopped applying. `nvm use default` did it in the skills restore, `eval "$(brew shellenv)"` in the age-key script. Both times the real binary ran: one cloned repos through the live `gh`, the other called the real `op` against the actual vault. Separately, an isolated `chezmoi purge` looked like it had deleted `$HOME` along with an unrelated file at its top level. It hadn't found a bug in the script: purge removes the config file's *parent directory*, and the harness had put the test config at the root of a tree that also contained the fake home and source.
**Why we backed out:** Neuter the PATH-mutating lines in the test copy (`sed` the nvm and shellenv lines to `:`), and give a test chezmoi config its own directory the way a real machine does (`$ISO/home/.config/chezmoi/chezmoi.toml`). With those two fixes the isolation actually holds, confirmed by asserting `chezmoi source-path` resolves inside the scratch tree before running anything destructive.
**Don't suggest:** PATH-stubbing on its own for any script that sources nvm or `brew shellenv`, or placing a test chezmoi config anywhere but its own directory. And don't report a `$HOME` deletion as a script bug before checking where the harness put that config. _(commits 469a2c1, 8b13d0d)_

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
