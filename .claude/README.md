# Project-Scoped Claude Config

These agents and skills belong to this repo alone. They are the working-memory toolkit: the `hydrator` and `working-memory-synchronizer` agents, plus the `hydrate-*` and `update-working-memory` skills. They load when you work in the dotfiles repo and nowhere else.

None of this deploys to `~/.claude`. chezmoi skips the directory because it's dot-prefixed, and that's deliberate. User-level skills live elsewhere, managed through `npx skills` (see the repo README). Don't move these into `dot_claude/`, or a repo-local toolkit becomes global config.
