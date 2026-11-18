# Harness notes

Skills and older rules are written for Claude Code and name its tools and paths. When one does, find the row below and do what it means in the harness you're running in.

| What a skill says (Claude Code) | What it means | OpenCode | Codex |
| --- | --- | --- | --- |
| `Skill` tool, "invoke the skill" | Load the skill and follow its body | `skill` tool | Open the skill's `SKILL.md` (path is in the skill list) and follow it |
| `AskUserQuestion` | Ask the user and wait for the answer | `question` tool | `request_user_input` where the mode offers it; otherwise ask in your reply and stop |
| `Task` tool, `Agent` tool, "dispatch a subagent" | Delegate using the harness's subagent mechanism | `task` tool | `spawn_agent` |
| `WebFetch` | Fetch the page | `webfetch` tool | `web_search`, or `curl` from the shell |
| `~/.claude/CLAUDE.md` | The global rules | `~/.agents/AGENTS.md` | `~/.agents/AGENTS.md` |
| `~/.claude/PROSE.md` | House prose rules | `~/.agents/PROSE.md` | `~/.agents/PROSE.md` |
| `~/.claude/VOICE.md` | Voice process for messages to people | `~/.agents/VOICE.md` | `~/.agents/VOICE.md` |
| `~/.claude/DELEGATION.md` | Delegation routing | `~/.agents/DELEGATION.md` | `~/.agents/DELEGATION.md` |

Claude Code uses the `~/.agents/` paths too. They hold the canonical copies, and `~/.claude/DELEGATION.md` no longer exists.
