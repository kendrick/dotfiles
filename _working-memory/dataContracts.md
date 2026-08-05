# Data Contracts

<!-- Canonical shapes for data flowing through the application. -->
<!-- Agents must consume data through these contracts. -->
<!-- When mocking data, conform to these shapes exactly. -->

## Brewfile (package manifest)
Declares `tap` / `brew` / `cask` / `mas` entries. Canonical list is `.chezmoitemplates/Brewfile`; `dot_config/Brewfile.tmpl` includes it via `{{ template "Brewfile" . }}`. Edit the canonical file, not the deployed copy. _(.chezmoitemplates/Brewfile)_

## Extension lists
`dot_config/vscode-extensions.txt` and `dot_config/raycast-extensions.txt` are newline-delimited id lists (leading `#` and blank lines skipped) consumed by `run_onchange_` installers on `chezmoi apply`. _(README.md "Editor"/"Apps")_ `dotfiles-sync` regenerates the VS Code list as a full snapshot of installed extensions; both lists are additive on `chezmoi apply` (removals aren't propagated — see `dotfiles-doctor`).

## chezmoi template data
`.chezmoi.toml.tmpl` `[data]` exposes three variables to every `.tmpl`: `machine_role` (work/client/personal), `email`, `name`. _(.chezmoi.toml.tmpl)_

## sh-ui.sh (shared shell helpers)
`.chezmoitemplates/sh-ui.sh` is the terminal-chrome interface the before-phase scripts include. It defines `say` / `ok` / `warn`, `elapsed`, `progress_bar`, `spin_until`, `spin_on_log`, `show_cursor`, and the `SPINNER_FRAMES` array. Consumers pull it in with a Go template include and set their own EXIT trap that calls `show_cursor`, since each has its own temp files to clear. Targets bash 3.2, because the before phase runs ahead of Homebrew. _(.chezmoitemplates/sh-ui.sh, run_once_before_install-prerequisites.sh.tmpl, run_before_provision-age-key.sh.tmpl)_
