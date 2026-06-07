# Project Overview

## What This Is
Personal macOS dotfiles managed by [chezmoi](https://chezmoi.io) — one command takes a fresh Mac from zero to fully configured. _(README.md)_

## Stack
- Manager: chezmoi (dotfile management + Go text/template)
- Shell: zsh (Powerlevel10k prompt, Znap plugin manager)
- Packages: Homebrew via Brewfile (formulae, casks, `mas` App Store apps)
- Setup: bash scripts run by chezmoi naming convention
- Templating: Go templates (`.tmpl`) keyed on machine role
- No application language runtime — this is a config repo, not an app.

## Repository Structure
Source of truth is this repo at `~/.local/share/chezmoi`. Deployed targets:
- `~/.config/` — zsh, git, ghostty, gh, Brewfile, extension lists (XDG layout)
- `~/.local/bin/` — custom scripts, on `$PATH`
- `~/Library/Application Support/` — VS Code, Claude Desktop
- `~/.config/chezmoi/chezmoi.toml` — local-only machine role + email, never committed

_(README.md "Layout"; git ls-files)_

## Key Constraints
- chezmoi prompts once for `machine_role` (work / client / personal); the role drives conditional installs and git email and lives only in the local `chezmoi.toml`. _(.chezmoi.toml.tmpl, README.md "Machine roles")_
- Bootstrap a new machine: `sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply kendrick`; update existing: `chezmoi update`. _(README.md)_
- Edit managed files via `chezmoi edit` / `chezmoi re-add` + `chezmoi apply`; never edit deployed copies without pulling them back. _(README.md "Making changes")_
