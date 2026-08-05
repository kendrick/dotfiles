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

## Font roster: Tier A, the patched statics (Phase 0 verified facts)
The terminal half of every `font` registry entry (#8, #12). Every family string below was copied from `system_profiler SPFontsDataType` on this machine after the cask installed, and every feature tag was read out of the font's own GSUB table. Nothing here came from documentation, because the documentation was wrong twice (see decisionLog 2026-08-05).

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
| `lilex` | `font-lilex-nerd-font` | `Lilex Nerd Font` | `calt` | ss01–ss04 |
| icons | `font-symbols-only-nerd-font` | `Symbols Nerd Font` | n/a | n/a |

`blex` was struck: `BlexMono Nerd Font` carries ss01 through ss07 and no ligature feature at all.

Three traps live in that table. Cask names don't track family names (`font-monaspice-*` yields `MonaspiceNe`, `font-caskaydia-cove-*` yields `CaskaydiaCove`), Maple ships its own Nerd Font build so it's `-nf` rather than `-nerd-font` and the family keeps a space, and Maple's `-nl` casks mean "no ligatures" and would silently defeat the roster's one requirement. One cask can also serve several keys: `font-monaspice-nerd-font` installs Ar/Kr/Ne/Rn/Xe, `font-recursive-mono-nerd-font` installs Casual/Duotone/Linear/SmCasual.

## Font roster: Tier B, the variable builds
The editor half, for the six keys where VS Code keeps the unpatched build and takes icons from `Symbols Nerd Font Mono` instead of the patch. These are separate casks from the Tier A ones and separate binaries, so their GSUB tables were read again after install rather than inherited from the static. _(2026-08-05)_

| key | cask | family, verbatim | ligature tags | axes (default) |
| --- | --- | --- | --- | --- |
| `maple` | `font-maple-mono` | `Maple Mono` | `calt` | wght 100–800 (400) |
| `monaspace` | `font-monaspace-var` | `Monaspace Neon Var` | `calt`, `liga`, `rlig` | wght 200–800 (**200**), wdth, slnt |
| `monaspace-xenon` | `font-monaspace-var` | `Monaspace Xenon Var` | `calt`, `liga`, `rlig` | wght 200–800 (**200**), wdth, slnt |
| `cascadia` | `font-cascadia-code` | `Cascadia Code` | `calt`, `rlig` | wght 200–700 (400) |
| `recursive` / `recursive-linear` | `font-recursive` | `Recursive` | `liga`, `dlig` | MONO 0–1 (**0**), CASL 0–1 (**0**), wght 300–1000 (**300**), slnt, CRSV |
| `lilex` | `font-lilex` | `Lilex` | `calt` | wght 100–700 (400) |

Two of these diverge from their patched static, which is why the re-read was worth insisting on. Monaspace's variable build adds `rlig` the static doesn't have, and Recursive's variable build has no `calt` at all: it carries `liga` and `dlig` where the `RecMono*` statics carry `calt` and nothing else. Copying the static's string to the editor half would render correctly with the feature silently inactive, the exact failure mode #8 was written to prevent.

The bolded defaults are the ones that bite. A Tier B entry with an empty `variations` gets Monaspace at ExtraLight and Recursive as a proportional sans, both of which read as a broken font rather than a missing setting. `'MONO' 1` is what makes Recursive monospaced, and `'CASL'` is the only thing separating the `recursive` and `recursive-linear` editor halves, since both name the same family.

`font-lilex` ships ten statics and two variables under one `Lilex` family, so the axis is there but macOS may resolve a static first; the axis is `wght` only, which the statics already cover, so nothing is lost either way.

### Stylistic sets are not interchangeable with ligatures
A font's ssXX features carry their own UI names in the `name` table, reachable through the GSUB FeatureParams. Reading them settles what a set actually does, and the answer differs per family in a way that inverts the obvious assumption:

- Monaspace ss01–ss10 are ligature groups (Equal Symbols, Comparisons, Arrows, HTML Tags, F# Shapes, Markdown Strings, Double Arrows, Other Tags), so enabling them adds ligatures.
- Maple ss01–ss11 are almost all named "Broken _X_ ligatures", meaning they remove ligatures rather than add them.
- Lilex ss01–ss04 are the same shape: "Broken equals ligatures", "Broken number signs".
- Recursive ss01–ss12 and ss20 are letterform alternates (single-story `a`, dotted zero) with no ligature content.
- Cascadia's ss02, ss19 and ss20 ship with empty name strings, so the font says nothing about them.

So Monaspace is the only family whose stylistic sets belong in a feature string. Enabling the recorded sets across the board, which is what the ticket's table reads like an instruction to do, would defeat ligatures on two of the nine fonts. _(GSUB FeatureParams + name table, 2026-08-05)_

Hand-placed `MonaspaceNeonVarVF[…].ttf` and `MonaspaceXenonVarVF[…].ttf` still sit in `~/Library/Fonts` and register the same families as `font-monaspace-var`, so those two families resolve from two sources. Same shape as the Fantasque collision in decisionLog 2026-08-04, and it needs the hand-placed copies removed to settle.

Every Nerd Font cask registers three families, the base name plus a ` Mono` and a ` Propo` suffix, which differ in glyph advance width rather than in features. Maple is the exception with one. Picking the wrong one changes spacing without erroring. _(system_profiler SPFontsDataType, 2026-08-05)_

Tier C's patcher has nothing to run on this machine: `docker` is only a zsh alias pointing at podman (`dot_config/zsh/aliases.zsh:15`) and neither podman nor Docker nor FontForge is installed. The alias also can't help a `run_onchange` script, since aliases don't survive into non-interactive shells. `op` is present and `op account list` succeeds against two accounts, so the vault half of Tier C is reachable. _(2026-08-05)_

## sh-ui.sh (shared shell helpers)
`.chezmoitemplates/sh-ui.sh` is the terminal-chrome interface the before-phase scripts include. It defines `say` / `ok` / `warn`, `elapsed`, `progress_bar`, `spin_until`, `spin_on_log`, `show_cursor`, and the `SPINNER_FRAMES` array. Consumers pull it in with a Go template include and set their own EXIT trap that calls `show_cursor`, since each has its own temp files to clear. Targets bash 3.2, because the before phase runs ahead of Homebrew. _(.chezmoitemplates/sh-ui.sh, run_once_before_install-prerequisites.sh.tmpl, run_before_provision-age-key.sh.tmpl)_
