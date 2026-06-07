# Open Questions

<!-- Things that are unresolved and should not be guessed at. -->
<!-- Agents encountering these should ask rather than assume. -->

- Should this repo have its own lint/format gate (shellcheck / shfmt on the bash scripts, prettier on templates)? AGENTS.md's Build/Test/Lint section is intentionally empty — there's currently no CI or pre-commit on the dotfiles themselves. _(AGENTS.md)_
- The deployed `.eslintrc` / `.prettierrc` / `.stylelintrc` are global *user* config, not tooling for this repo — confirm they're never meant to run against the dotfiles source. _(dot_eslintrc, dot_prettierrc, dot_stylelintrc)_
