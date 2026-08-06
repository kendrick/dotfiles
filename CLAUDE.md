
## Working Memory

**AGENT INSTRUCTION:** before deciding what to read, scan the on-demand table under `## Working Memory` in [`AGENTS.md`](AGENTS.md). If your task matches a row, that file is required reading before you proceed.

Always read `_working-memory/activeContext.md` on session start. AGENTS.md is the canonical source for the on-demand table and update rules.
To sync working memory, run `/update-working-memory` or invoke the `working-memory-synchronizer` agent.

## Two Kinds of Claude Config in This Repo

This repo is also the chezmoi source dir, so it carries two Claude config trees that look alike but behave differently. Don't conflate them.

- `dot_claude/` is the chezmoi source for `~/.claude`. Edit it and it deploys to your home dir as user-level config: global CLAUDE.md, RTK.md, settings, plugin seeds.
- `.claude/` is this repo's own project config, holding the working-memory agents (`hydrator`, `working-memory-synchronizer`) and the `hydrate-*` skills. It loads only when you work inside this repo, and chezmoi skips it because it's dot-prefixed.

The working-memory toolkit is project-scoped on purpose. Don't "fix" `.claude/` by moving it into `dot_claude/`, which would push those agents and skills into every project you open. User-level skills are managed by `npx skills`, not by dropping skill bodies into `dot_claude/skills/`.

<!-- agent-guild:claude:start -->
<!-- Added by the Agent Guild project installer. -->
@.agent-guild/CLAUDE.md
<!-- agent-guild:claude:end -->
