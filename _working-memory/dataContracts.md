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

## Teardown declarations
`# teardown:<class> <path>`, one per line in a script's header comment. `<class>` is `secret` (removed at the default teardown level), `data` (`--full` only), or `none` (the script leaves nothing behind). `<path>` is literal and uses `~`, expanded by the consumer, so no template rendering is needed to read it; `none` takes no path. Two consumers: `dotfiles-teardown` greps `run_*` and `dot_local/bin/*` with `-I` so it skips the binaries in there, and treats an unrecognized class as a hard error rather than a silent skip; `dotfiles-doctor` requires a declaration on every `run_*` script and reports the ones missing it. _(dot_local/bin/executable_dotfiles-teardown.tmpl, dot_local/bin/executable_dotfiles-doctor)_

## Font roster (Phase 0 verified facts)
Inputs to the `font` switcher's registry (#8). Every family string below was copied from `system_profiler SPFontsDataType` on this machine after the cask installed, and every feature tag was read out of the font's own GSUB table. Nothing here came from documentation, because the documentation was wrong twice (see decisionLog 2026-08-05).

| key | cask | family, verbatim | ligature tags | stylistic sets |
| --- | --- | --- | --- | --- |
| `fantasque` | `font-fantasque-sans-mono-nerd-font` | `FantasqueSansM Nerd Font` | `calt` | ss01 |
| `maple` | `font-maple-mono-nf` | `Maple Mono NF` | `calt` | ss01–ss11 |
| `monaspace` | `font-monaspice-nerd-font` | `MonaspiceNe Nerd Font` | `calt`, `liga` | ss01–ss10 |
| `monaspace-xenon` | `font-monaspice-nerd-font` | `MonaspiceXe Nerd Font` | `calt`, `liga` | ss01–ss10 |
| `victor` | `font-victor-mono-nerd-font` | `VictorMono Nerd Font` | `calt` | ss01–ss08 |
| `cascadia` | `font-caskaydia-cove-nerd-font` | `CaskaydiaCove Nerd Font` | `calt`, `rlig` | ss02, ss19, ss20 |
| `recursive` | `font-recursive-mono-nerd-font` | `RecMonoCasual Nerd Font` | `calt` | none |
| `recursive-linear` | `font-recursive-mono-nerd-font` | `RecMonoLinear Nerd Font` | `calt` | none |
| icons | `font-symbols-only-nerd-font` | `Symbols Nerd Font` | n/a | n/a |

`blex` was struck: `BlexMono Nerd Font` carries ss01 through ss07 and no ligature feature at all.

Three traps live in that table. Cask names don't track family names (`font-monaspice-*` yields `MonaspiceNe`, `font-caskaydia-cove-*` yields `CaskaydiaCove`), Maple ships its own Nerd Font build so it's `-nf` rather than `-nerd-font` and the family keeps a space, and Maple's `-nl` casks mean "no ligatures" and would silently defeat the roster's one requirement. One cask can also serve several keys: `font-monaspice-nerd-font` installs Ar/Kr/Ne/Rn/Xe, `font-recursive-mono-nerd-font` installs Casual/Duotone/Linear/SmCasual.

Every Nerd Font cask registers three families, the base name plus a ` Mono` and a ` Propo` suffix, which differ in glyph advance width rather than in features. Maple is the exception with one. Picking the wrong one changes spacing without erroring. _(system_profiler SPFontsDataType, 2026-08-05)_

Tier C's patcher has nothing to run on this machine: `docker` is only a zsh alias pointing at podman (`dot_config/zsh/aliases.zsh:15`) and neither podman nor Docker nor FontForge is installed. The alias also can't help a `run_onchange` script, since aliases don't survive into non-interactive shells. `op` is present and `op account list` succeeds against two accounts, so the vault half of Tier C is reachable. _(2026-08-05)_

## sh-ui.sh (shared shell helpers)
`.chezmoitemplates/sh-ui.sh` is the terminal-chrome interface the before-phase scripts include. It defines `say` / `ok` / `warn`, `elapsed`, `progress_bar`, `spin_until`, `spin_on_log`, `show_cursor`, and the `SPINNER_FRAMES` array. Consumers pull it in with a Go template include and set their own EXIT trap that calls `show_cursor`, since each has its own temp files to clear. Targets bash 3.2, because the before phase runs ahead of Homebrew. _(.chezmoitemplates/sh-ui.sh, run_once_before_install-prerequisites.sh.tmpl, run_before_provision-age-key.sh.tmpl)_
