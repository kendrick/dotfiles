# Open Questions

<!-- Things that are unresolved and should not be guessed at. -->
<!-- Agents encountering these should ask rather than assume. -->

- Should this repo have its own lint/format gate (shellcheck / shfmt on the bash scripts, prettier on templates)? AGENTS.md's Build/Test/Lint section is intentionally empty — there's currently no CI or pre-commit on the dotfiles themselves. _(AGENTS.md)_
- The deployed `.eslintrc` / `.prettierrc` / `.stylelintrc` are global *user* config, not tooling for this repo — confirm they're never meant to run against the dotfiles source. _(dot_eslintrc, dot_prettierrc, dot_stylelintrc)_
- The `.chezmoiignore` entries for the Claude Desktop config (`private_Library/…claude_desktop_config.json`) and `executable_awssso` use source paths, so they don't match — the Claude Desktop config still syncs and awssso isn't gated off non-work machines. Fix to target paths? _(chezmoi ignored lists neither)_
- App-owned managed files (encrypted settings.json / plugin manifests) prompt overwrite/skip on every `chezmoi update`, since chezmoi apply-writes them while the app rewrites the live copy. Cleaner mode wanted (auto-skip), or accept the churn?
- Should the scheduled auto-sync push at all? On 2026-08-04 it committed in-progress work mid-session and pushed a commit that was being held back for review. `dotfiles-undo` cleans up after the fact, but commit-without-push, or a guard that skips the run while the tree is mid-edit, may be the better default. _(dot_local/bin/executable_dotfiles-sync, com.k-arnett.dotfiles-auto-sync)_
