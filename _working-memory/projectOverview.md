# Project Overview

## What This Is
Personal macOS dotfiles managed by [chezmoi](https://chezmoi.io) — one command takes a fresh Mac from zero to fully configured. _(README.md)_

## Stack
- Manager: chezmoi (dotfile management + Go text/template)
- Shell: zsh (Powerlevel10k prompt, Znap plugin manager)
- Packages: Homebrew, from a registry in `.chezmoidata.toml` rendered into a Brewfile per machine
- Setup: bash scripts run by chezmoi naming convention
- Templating: Go templates (`.tmpl`) keyed on machine role
- No application language runtime — this is a config repo, not an app.

## Repository Structure
Source of truth is this repo at `~/.local/share/chezmoi`. Deployed targets:
- `~/.config/` — zsh, git, ghostty, gh (XDG layout). The package registry + VS Code ext list are source-only data, not deployed.
- `~/.local/bin/` — custom scripts, on `$PATH`
- `~/Library/Application Support/` — VS Code, Claude Desktop
- `~/.config/chezmoi/chezmoi.toml` — local-only machine role + email, never committed

`.chezmoitemplates/` holds partials that are never deployed anywhere: the Brewfile (rendered inline by the installer from `.chezmoidata.toml`), `bundles` (which package bundles this machine has on), and `sh-ui.sh` (shared bash helpers, included by the before-phase scripts). It isn't only a data directory.

`docs/` holds design specs that drive later implementation work, currently just `docs/superpowers/specs/`. It carries a `.chezmoiignore` line, unlike the dot-prefixed source-only trees, because `docs` has no leading dot and would otherwise deploy to `~/docs`. _(02ff72f)_

`.agent-guild/` is the repo-side half of an agent-guild install: the verdict and vendor-call schemas, the check scripts a task's `check_method` names, and the templates Phase 0 and Phase 1 render from. Dot-prefixed, so it never deploys. Its `state/` subdirectory is a running job's scratch and is gitignored. _(.agent-guild/CLAUDE.md; decisionLog 2026-08-06)_

_(README.md "Layout"; git ls-files)_

## Key Constraints
- chezmoi prompts once for `machine_role` (work / client / personal); the role drives conditional installs and git email and lives only in the local `chezmoi.toml`. _(.chezmoi.toml.tmpl, README.md "Machine roles")_
- Bootstrap a new machine: `sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply kendrick`; update existing: `chezmoi update`. _(README.md)_
- Edit managed files via `chezmoi edit` / `chezmoi re-add` + `chezmoi apply`; never edit deployed copies without pulling them back. _(README.md "Making changes")_
- Cross-machine sync: capture with `dotfiles-sync`, pull with `chezmoi update`. Extension/package lists are additive — `chezmoi update` never uninstalls; run `dotfiles-doctor` to catch removals. _(dot_local/bin/)_
