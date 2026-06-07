# Conventions

<!-- Project-specific patterns agents must follow. -->
<!-- This is the "how we do things here" file. -->

## Naming
- chezmoi filename prefixes are load-bearing: `dot_` → `.`, `private_` → 0600, `executable_` → `+x`, `run_once_` → run once per machine, `run_onchange_` → re-run when content changes, `.tmpl` → Go-templated. _(git ls-files; README.md "How the automation works")_
- Commits follow Conventional Commits prefixes: `feat`, `fix`, `refactor`, `docs`. _(git log)_

## File Organization
- zsh config is split by concern under `~/.config/zsh/` (aliases, exports, functions, plugins, keybindings, options, styles), sourced from `~/.zshrc`. _(dot_config/zsh/, dot_zshrc.tmpl)_

## Templating / Machine Conditionals
- Machine-specific content uses Go-template guards on `.machine_role` (e.g. `{{ if eq .machine_role "work" }}`) inside a single file, not branched files. _(dot_config/Brewfile.tmpl, dot_gitconfig.tmpl, .chezmoi.toml.tmpl)_

## Error Handling
- Setup scripts use `set -e` for fail-fast, with two deliberate exceptions: the macOS-defaults script omits it (non-fatal `defaults write` errors), and external-tool installers (`brew bundle`, `code --install-extension`, `open raycast://`) guard each call with `|| true` and skip cleanly if the CLI is absent. _(run_onchange_install-vscode-extensions.sh.tmpl, run_once_after_configure-macos.sh)_
