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

## Error Handling
- Setup scripts use `set -e` for fail-fast, with two deliberate exceptions: the macOS-defaults script omits it (non-fatal `defaults write` errors), and external-tool installers (`brew bundle`, `code --install-extension`, `open raycast://`) guard each call with `|| true` and skip cleanly if the CLI is absent. _(run_onchange_install-vscode-extensions.sh.tmpl, run_once_after_configure-macos.sh)_

## Cross-machine sync
- Capture local changes with `dotfiles-sync` (regenerates VS Code ext list, `chezmoi re-add`, commit + push); pull elsewhere with `chezmoi update`; spot drift with `dotfiles-doctor`. Brewfile and Raycast extensions are captured by hand. _(dot_local/bin/executable_dotfiles-sync)_

## chezmoi ignore + source-only data
- `.chezmoiignore` matches TARGET paths (home-relative), not source paths. A source-name entry (`private_Library/…`, `dot_local/bin/executable_x`) silently no-ops — use the deployed path (`Library/…`, `.local/bin/x`) and verify with `chezmoi ignored`. _(.chezmoiignore, chezmoi ignored)_
- Files generated from live state, or rendered purely as data for a script, are source-only: `.chezmoiignore` the target so the daily `chezmoi re-add` can't clobber the freshly-generated source with a stale deployed copy. _(VS Code ext list; the Brewfile is read inline by the installer)_
