# Open Questions

<!-- Things that are unresolved and should not be guessed at. -->
<!-- Agents encountering these should ask rather than assume. -->

- Should this repo have its own lint/format gate (shellcheck / shfmt on the bash scripts, prettier on templates)? AGENTS.md's Build/Test/Lint section is intentionally empty — there's currently no CI or pre-commit on the dotfiles themselves. _(AGENTS.md)_
- The deployed `.eslintrc` / `.prettierrc` / `.stylelintrc` are global *user* config, not tooling for this repo — confirm they're never meant to run against the dotfiles source. _(dot_eslintrc, dot_prettierrc, dot_stylelintrc)_
- The `.chezmoiignore` entries for the Claude Desktop config (`private_Library/…claude_desktop_config.json`) and `executable_awssso` use source paths, so they don't match — the Claude Desktop config still syncs and awssso isn't gated off non-work machines. Fix to target paths? _(chezmoi ignored lists neither)_
- App-owned managed files (encrypted settings.json / plugin manifests) prompt overwrite/skip on every `chezmoi update`, since chezmoi apply-writes them while the app rewrites the live copy. Cleaner mode wanted (auto-skip), or accept the churn?
