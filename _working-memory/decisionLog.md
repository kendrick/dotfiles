# Decision Log

<!-- Append-only. Most recent at top. -->
<!-- Format: -->
<!-- ## YYYY-MM-DD — [Short Title] -->
<!-- **Context:** Why this came up -->
<!-- **Decision:** What was decided -->
<!-- **Alternatives considered:** What was rejected and why -->

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
