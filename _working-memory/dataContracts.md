# Data Contracts

<!-- Canonical shapes for data flowing through the application. -->
<!-- Agents must consume data through these contracts. -->
<!-- When mocking data, conform to these shapes exactly. -->

## Brewfile (package manifest)
Declares `tap` / `brew` / `cask` / `mas` entries. Canonical list is `.chezmoitemplates/Brewfile`; `dot_config/Brewfile.tmpl` includes it via `{{ template "Brewfile" . }}`. Edit the canonical file, not the deployed copy. _(.chezmoitemplates/Brewfile)_

## Extension lists
`dot_config/vscode-extensions.txt` and `dot_config/raycast-extensions.txt` are newline-delimited id lists (leading `#` and blank lines skipped) consumed by `run_onchange_` installers on `chezmoi apply`. _(README.md "Editor"/"Apps")_

## chezmoi template data
`.chezmoi.toml.tmpl` `[data]` exposes three variables to every `.tmpl`: `machine_role` (work/client/personal), `email`, `name`. _(.chezmoi.toml.tmpl)_
