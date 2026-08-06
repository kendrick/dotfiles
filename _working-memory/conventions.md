# Conventions

<!-- Project-specific patterns agents must follow. -->
<!-- This is the "how we do things here" file. -->

## Naming
- chezmoi filename prefixes are load-bearing: `dot_` → `.`, `private_` → 0600, `executable_` → `+x`, `run_once_` → run once per machine, `run_onchange_` → re-run when content changes, `.tmpl` → Go-templated. _(git ls-files; README.md "How the automation works")_
- Commits follow Conventional Commits prefixes: `feat`, `fix`, `refactor`, `docs`. _(git log)_

## File Organization
- zsh config is split by concern under `~/.config/zsh/` (aliases, exports, functions, plugins, keybindings, options, styles), sourced from `~/.zshrc`. _(dot_config/zsh/, dot_zshrc.tmpl)_

## Templating / Machine Conditionals
- Machine-specific content uses Go-template guards on `.machine_role` (e.g. `{{ if eq .machine_role "work" }}`) inside a single file, not branched files. _(dot_gitconfig.tmpl, .chezmoi.toml.tmpl)_
- Where the list of things being gated is long enough to be data, gate on membership instead: the item declares what it belongs to, the role only picks a default set, and the machine can override. Roles are a coarse lever, and a machine that wants one exception has nowhere to say so under a role branch. _(.chezmoidata.toml bundles; GitHub #4)_
- A `[data]` key added after a machine last ran `chezmoi init` isn't in that machine's config, and `chezmoi apply` doesn't regenerate it; it warns and carries on. So every read of a newer key needs a fallback, or the first apply after a pull dies with "map has no entry for key". Use `hasKey` when an empty value is legal; `| default` only when it isn't, since empty lists and strings are both falsy. _(.chezmoitemplates/bundles, .chezmoiignore)_

## Shared shell code
- Helpers used by more than one script live in `.chezmoitemplates/` and come in through a Go template include, which is what turns a plain `.sh` script into a `.sh.tmpl`. Never write the include call inside the partial itself: chezmoi parses partials as templates too, so it recurses. _(.chezmoitemplates/sh-ui.sh)_
- Interactive waits gate on `[ -t 0 ]` and escape codes gate on `[ -t 1 ]`, checked separately. Output is captured into the auto-sync log and has to stay greppable, and an unattended apply must never block on a prompt or a spinner. _(run_once_before_install-prerequisites.sh.tmpl, run_before_provision-age-key.sh.tmpl)_

## bash 3.2
- Scripts here run under `/bin/bash`, which is 3.2 on macOS, so no associative arrays and no `${var^^}`. Expanding an empty array under `set -u` (`"${arr[@]}"`) aborts rather than yielding nothing, so guard every expansion with `[ "${#arr[@]}" -gt 0 ]`. The count form is safe on empty; the expansion isn't. _(dot_local/bin/executable_dotfiles-teardown.tmpl, .chezmoitemplates/sh-ui.sh)_

## Teardown declarations
- Any script that leaves state on the machine declares it as `# teardown:<class> <path>` in its header, using a literal `~`. Classes: `secret` (removed by default), `data` (`--full` only), `none` (leaves nothing). Required on every `run_*` script and enforced by `dotfiles-doctor`; optional but read on `dot_local/bin/*`. _(dot_local/bin/executable_dotfiles-teardown.tmpl)_
- Don't add paths to a central list in the teardown script. Anything chezmoi can enumerate should be queried from chezmoi; anything it can't should be declared where it's created. _(decisionLog 2026-08-05)_

## Config-to-package coupling
- When a managed config names an external resource by string (a font family, a binary, a theme), the package registry needs a matching entry in a bundle the machine has on, or it fails only on a fresh machine where the resource was never hand-installed. Fonts are the case that's closed: every half of every `dot_config/font/registry.json` entry declares the casks it needs, and `dotfiles-doctor`'s "Config dependencies" section asserts an enabled bundle carries them. Anything else named by string is still unchecked. _(dot_config/font/registry.json, dot_local/bin/executable_dotfiles-doctor; GitHub #7, #4)_
- Declare the dependency next to the config that names it and have the checker read the declaration. Don't teach the checker to parse resource names out of configs and map them to package names: cask names don't track family names (`font-monaspice-*` ships `MonaspiceNe`), so a resolver is a second table to keep in sync. A declaration that's missing reports itself; a lookup table that's stale still looks correct. _(decisionLog 2026-08-05)_

## Scripts that rewrite a managed config
- Build the new content in a `mktemp` file and move it into place, so a failed run can't leave a half-written config. Then restore the target's mode: `mktemp` creates 0600, and a bare `mv` tightens the file enough that `chezmoi re-add` records it as a `private_` source entry, which renames it and turns one edit into a delete plus an add. Stat the target before the move, `chmod` after. _(dot_local/bin/executable_font `replace_preserving_mode`)_
- Write into a marker-delimited region (`# BEGIN x (managed by \`y\`)` … `# END x`) when the rest of the file is hand-edited, and treat a missing marker as a hard error rather than guessing where the block belongs. _(dot_config/ghostty/config)_
- Prefer an anchored line replacement over parse-and-reserialize when a formatter also owns the file. Serializing normalizes away whatever the formatter will just put back, so the file churns on every write. Anchor on the key, and fail if the anchor matches zero times or more than once. _(dot_local/bin/executable_font `write_vscode_key`, decisionLog 2026-08-05)_
- After mutating a managed file in `$HOME`, `chezmoi re-add` it. Without that the next `chezmoi apply` reverts the change, so the script looks like it worked until it silently doesn't.

## Testing scripts with bats
- Drive the real script as a subprocess against a fake `$HOME` with its external tools stubbed on `PATH`, and assert on exit codes and resulting file bytes. Don't reach in for helper functions and don't assert on log wording: what matters is what the run left on disk and whether it refused when it should have. _(tests/font.bats, tests/licensed-fonts.bats)_
- `unset XDG_CONFIG_HOME` and `XDG_CACHE_HOME` in `setup()`. Both are set on this machine, and a script honoring them goes straight back to the real `~/.config` and `~/.cache` no matter what `$HOME` says.
- Derive expected values from the data file or the fixture, never from what a managed config currently holds. A test pinning a live setting breaks the moment the thing under test starts owning that setting, which has happened twice. _(tests/font.bats)_
- Stub anything slow or machine-dependent (`system_profiler` takes ten seconds and answers about whichever machine is running the suite) and have the stub log its invocations, which is the only way to assert a cache was actually used.

## Error Handling
- Setup scripts use `set -e` for fail-fast, with two deliberate exceptions: the macOS-defaults script omits it (non-fatal `defaults write` errors), and external-tool installers (`brew bundle`, `code --install-extension`, `open raycast://`) guard each call with `|| true` and skip cleanly if the CLI is absent. _(run_onchange_install-vscode-extensions.sh.tmpl, run_once_after_configure-macos.sh)_

## Cross-machine sync
- Capture local changes with `dotfiles-sync` (regenerates VS Code ext list, `chezmoi re-add`, commit + push); pull elsewhere with `chezmoi update`; spot drift with `dotfiles-doctor`. Packages and Raycast extensions are captured by hand. _(dot_local/bin/executable_dotfiles-sync)_

## chezmoi ignore + source-only data
- `.chezmoiignore` matches TARGET paths (home-relative), not source paths. A source-name entry (`private_Library/…`, `dot_local/bin/executable_x`) silently no-ops — use the deployed path (`Library/…`, `.local/bin/x`) and verify with `chezmoi ignored`. _(.chezmoiignore, chezmoi ignored)_
- Files generated from live state, or rendered purely as data for a script, are source-only: `.chezmoiignore` the target so the daily `chezmoi re-add` can't clobber the freshly-generated source with a stale deployed copy. _(VS Code ext list; the Brewfile is rendered inline by the installer)_
- A dot-prefixed source entry (`.chezmoidata.toml`, `.chezmoitemplates/`) is source-only for free, since chezmoi never gives it a target, so it needs no `.chezmoiignore` line at all. The rule above is for entries that would otherwise deploy. _(.chezmoidata.toml)_
