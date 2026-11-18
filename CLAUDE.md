
## Working Memory

**AGENT INSTRUCTION:** before deciding what to read, scan the on-demand table under `## Working Memory` in [`AGENTS.md`](AGENTS.md). If your task matches a row, that file is required reading before you proceed.

Always read `_working-memory/activeContext.md` on session start. AGENTS.md is the canonical source for the on-demand table and update rules.
To sync working memory, run `/update-working-memory` or invoke the `working-memory-synchronizer` agent.

## Three Config Trees in This Repo

This repo is also the chezmoi source dir, so it carries three config trees that look alike but behave differently. Don't conflate them.

- `dot_agents/` is the chezmoi source for `~/.agents`, which holds the user-level rules every harness reads: `AGENTS.md`, `DELEGATION.md`, `harness-notes.md`, and the encrypted PROSE, VOICE, and voice-sample files. Edit the rules here.
- `dot_claude/` is the chezmoi source for `~/.claude`. Its `CLAUDE.md` is a symlink to `~/.agents/AGENTS.md`. PROSE and VOICE get links there too, because skills cite them as `~/.claude/PROSE.md` and `~/.claude/VOICE.md`. The voice samples get links because VOICE.md links them by relative path, so a reader who opens `~/.claude/VOICE.md` looks for them in `~/.claude`. The rest is Claude Code's own config: settings, the status line, commands, and plugin seeds. `dot_codex/` and `dot_config/opencode/` carry the same `AGENTS.md` link for Codex and OpenCode.
- `.claude/` is this repo's own project config, holding the working-memory agents (`hydrator`, `working-memory-synchronizer`) and the `hydrate-*` skills. It loads only when you work inside this repo, and chezmoi skips it because it's dot-prefixed.

The working-memory toolkit is project-scoped on purpose. Don't "fix" `.claude/` by moving it into `dot_claude/`, which would push those agents and skills into every project you open. User-level skills are managed by `npx skills`, not by dropping skill bodies into `dot_claude/skills/`.
