# Decision Log

<!-- Append-only. Most recent at top. -->
<!-- Format: -->
<!-- ## YYYY-MM-DD — [Short Title] -->
<!-- **Context:** Why this came up -->
<!-- **Decision:** What was decided -->
<!-- **Alternatives considered:** What was rejected and why -->

## 2026-06-13 — Encrypt settings.json; flag template drift re-add can't capture
**Context:** Follow-on from the plugin backup. settings.json was tracked as a template, but `chezmoi re-add` can't reverse-render a template, so it silently skipped the file. Claude rewrites settings.json constantly, so the live copy drifted far ahead of source and the daily sync never noticed. The only template-able content was the home-dir path; the rest is literal.
**Decision:** Encrypt settings.json (drop the `.tmpl`) so re-add captures it again — re-encrypting keeps the work-only plugin names private, and it resurrects the SessionStart hook that re-adds settings.json each session, so permissions auto-capture hands-off. Same age key as the plugin manifests. For files that must stay templated (`.zshrc`, `.gitconfig`, Brewfile), re-add will always skip them, so dotfiles-doctor and dotfiles-sync now detect and report template drift instead of silently dropping it.
**Alternatives considered:** Keep it a readable template and reconcile by hand — rejected, reintroduces the manual capture dotfiles-sync exists to kill. Encrypt only the private bits via an injected fragment — rejected, a file is template-or-not wholesale, so any template still wouldn't auto-capture. A custom scrub-and-templatize capture script — rejected for now, a scrub bug leaks permanently to a public repo, where encryption can't.

## 2026-06-13 — Back up Claude Code plugins (encrypted) like skills
**Context:** Plugin state had no cross-machine backup. A first pass tracked the two manifests as `create_` files, which `chezmoi re-add` skips, so the daily sync never captured new installs. The manifests and settings.json.tmpl also carried a work-only marketplace's repo and plugin names in plaintext, and this repo is public.
**Decision:** Mirror the skills setup (daily re-add captures the manifests; a manifest-driven run_onchange replays them on a fresh machine), but age-encrypt the manifests so the work-only names stay out of the public repo. The run_onchange decrypts at render time and gates installs by a public-marketplace allowlist, so personal machines get public plugins only and the committed template names no private org. Added a `claude()` wrapper mirroring `skills()`. Forward-only: prior plaintext stays in git history; version reproduction is fuzzy (install grabs latest vs the recorded SHA, self-heals on re-add).
**Alternatives considered:** Plaintext manifests with a capture-time filter to scrub work-only entries — rejected, fights the blanket re-add. A separate private overlay repo — rejected, second repo to sync and still needs the filter. Accepting the exposure — rejected by preference, though the marketplace repo is SSO-gated.

## 2026-06-07 — Add dotfiles-sync / dotfiles-doctor for cross-machine sync
**Context:** Repo is the source of truth, but capturing edits back was manual and easy to forget, and `chezmoi update` only adds — it never removes extensions/packages dropped on another machine.
**Decision:** Added `dot_local/bin/executable_dotfiles-{sync,doctor}`. `dotfiles-sync` regenerates the VS Code extension list, bare `chezmoi re-add`s all changed files, reports Brewfile drift, then commits + pushes. `dotfiles-doctor` is a read-only drift report for the receiving end (installed-but-not-listed = removal/capture candidates).
**Alternatives considered:** chezmoi `autoCommit`/`autoPush` — rejected (generic off-convention commit messages, no review gate); settings.json symlink and `brew bundle dump` — rejected (see antipatterns). _(commit 383e75e)_

## 2026-03-24 — Remove `set -e` from macOS-defaults script
**Context:** Some `defaults write` calls (Safari sandbox) error on Sequoia.
**Decision:** Drop `set -e` so a single failing default doesn't abort the whole run.
**Alternatives considered:** Per-command `|| true` guards — rejected as noisier. _(commit 1f2a217)_

## 2026-03-24 — XDG-standard layout, eliminate ~/.dotfiles
**Context:** Legacy `~/.dotfiles` directory predated the chezmoi adoption.
**Decision:** Move everything to XDG paths (`~/.config`, `~/.local`) and drop `~/.dotfiles`.
**Alternatives considered:** Keeping the old path for compatibility — rejected. _(commit ea53c2d)_

## 2026-03-23 — Allow `brew bundle` to fail gracefully
**Context:** Mac App Store (`mas`) apps need interactive sudo auth and break unattended installs.
**Decision:** Let `brew bundle` fail without failing the installer script.
**Alternatives considered:** Splitting MAS apps into a separate manual step — deferred. _(commit c8e897e)_

## 2026-03-23 — Adopt chezmoi as the dotfile manager
**Context:** Project inception; needed reproducible, multi-machine dotfile management.
**Decision:** Use chezmoi (templating + run scripts + role prompts).
**Alternatives considered:** GNU Stow / bare git repo — not chosen (no templating/role logic). _(commit 4adc89d)_
