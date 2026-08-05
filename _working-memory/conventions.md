# Conventions

<!-- Project-specific patterns agents must follow. -->
<!-- This is the "how we do things here" file. -->

## Naming
- chezmoi filename prefixes are load-bearing: `dot_` → `.`, `private_` → 0600, `executable_` → `+x`, `run_once_` → run once per machine, `run_onchange_` → re-run when content changes, `.tmpl` → Go-templated. _(git ls-files; README.md "How the automation works")_
- Commits follow Conventional Commits prefixes: `feat`, `fix`, `refactor`, `docs`. _(git log)_

## File Organization
- zsh config is split by concern under `~/.config/zsh/` (aliases, exports, functions, plugins, keybindings, options, styles), sourced from `~/.zshrc`. _(dot_config/zsh/, dot_zshrc.tmpl)_

## Templating / Machine Conditionals
- Machine-specific content uses Go-template guards on `.machine_role` (e.g. `{{ if eq .machine_role "work" }}`) inside a single file, not branched files. _(.chezmoitemplates/Brewfile, dot_gitconfig.tmpl, .chezmoi.toml.tmpl)_

## Shared shell code
- Helpers used by more than one script live in `.chezmoitemplates/` and come in through a Go template include, which is what turns a plain `.sh` script into a `.sh.tmpl`. Never write the include call inside the partial itself: chezmoi parses partials as templates too, so it recurses. _(.chezmoitemplates/sh-ui.sh)_
- Interactive waits gate on `[ -t 0 ]` and escape codes gate on `[ -t 1 ]`, checked separately. Output is captured into the auto-sync log and has to stay greppable, and an unattended apply must never block on a prompt or a spinner. _(run_once_before_install-prerequisites.sh.tmpl, run_before_provision-age-key.sh.tmpl)_

## Config-to-package coupling
- When a managed config names an external resource by string (a font family, a binary, a theme), the Brewfile needs a matching entry. Nothing checks this today, so it fails only on a fresh machine where the resource was never hand-installed. _(dot_config/ghostty/config font-family; GitHub #7)_

## Error Handling
- Setup scripts use `set -e` for fail-fast, with two deliberate exceptions: the macOS-defaults script omits it (non-fatal `defaults write` errors), and external-tool installers (`brew bundle`, `code --install-extension`, `open raycast://`) guard each call with `|| true` and skip cleanly if the CLI is absent. _(run_onchange_install-vscode-extensions.sh.tmpl, run_once_after_configure-macos.sh)_

## Cross-machine sync
- Capture local changes with `dotfiles-sync` (regenerates VS Code ext list, `chezmoi re-add`, commit + push); pull elsewhere with `chezmoi update`; spot drift with `dotfiles-doctor`. Brewfile and Raycast extensions are captured by hand. _(dot_local/bin/executable_dotfiles-sync)_

## chezmoi ignore + source-only data
- `.chezmoiignore` matches TARGET paths (home-relative), not source paths. A source-name entry (`private_Library/…`, `dot_local/bin/executable_x`) silently no-ops — use the deployed path (`Library/…`, `.local/bin/x`) and verify with `chezmoi ignored`. _(.chezmoiignore, chezmoi ignored)_
- Files generated from live state, or rendered purely as data for a script, are source-only: `.chezmoiignore` the target so the daily `chezmoi re-add` can't clobber the freshly-generated source with a stale deployed copy. _(VS Code ext list; the Brewfile is read inline by the installer)_
