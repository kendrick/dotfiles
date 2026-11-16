# Canonical `~/.agents` Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close #105 by moving the user-level rules into `dot_agents/` (deployed to `~/.agents/`), pointing Claude Code, OpenCode, and Codex at `~/.agents/AGENTS.md` through chezmoi-managed symlinks, and rewording the rules so no single harness's paths, tools, or model names appear in them.

**Architecture:** `git mv` the documents into `dot_agents/` and keep their `encrypted_`/`private_` attributes, since age encryption doesn't depend on the path. Each adapter is a `symlink_` source holding a **relative** target (`../.agents/AGENTS.md`, `../../.agents/AGENTS.md` for OpenCode), so it resolves under any `$HOME` without a template. `.chezmoiremove` deletes the stale `~/.claude/DELEGATION.md` that existing machines keep after the move. `env-setup.sh` installs the same layout in remote containers: real files in `~/.agents`, symlinks in `~/.claude`.

**Tech Stack:** chezmoi (`symlink_`, `.chezmoiignore`, `.chezmoiremove`), bash 3.2, age, bats ≥1.5.

**Spec:** GitHub issue #105 (`gh issue view 105`). Parent: #104. Downstream: #107 fills the OpenCode column of the rung mapping, #108/#109 build conformance probes against this layout.

**Read first:** `AGENTS.md` (test commands), `tests/helpers.bash:1-25` (`assert_contains` is the form `tests/mutation-check.sh` can invert; no bare `[[ ]]`), `tests/claude-bootstrap.bats` (fixture layout via `DOTFILES_RAW_BASE=file://…`), `_working-memory/conventions.md` "Always-loaded policy files" (before editing AGENTS.md or DELEGATION.md), `_working-memory/antipatterns.md` 2026-06-07 (symlinks vs atomic-rename writers).

**Facts verified on this machine (2026-11-16), so don't re-derive them:**

- In a temp source/destination with chezmoi, relative `symlink_` sources in `dot_claude/`, `dot_codex/`, and `dot_config/opencode/` all resolved to `.agents/AGENTS.md`. The root-level `AGENTS.md` line in `.chezmoiignore` did not hide `.agents/AGENTS.md`, and no `~/AGENTS.md` was created. `.chezmoiremove` with `.claude/DELEGATION.md` deleted a pre-seeded stale copy, and a second apply followed by `chezmoi status` printed nothing.
- `dot_claude/CLAUDE.md` has no `@RTK.md` line today, and nothing else references `RTK.md`.
- Skill bodies under `~/.agents/skills`, `~/.claude/skills`, and the plugin cache reference `~/.claude/CLAUDE.md` (9×), `~/.claude/PROSE.md` (2×), and `~/.claude/VOICE.md` (2×). None reference `~/.claude/DELEGATION.md`.
- `VOICE.md` links its samples by relative path (`[voice-samples-work.md](voice-samples-work.md)`), so a reader that arrives through `~/.claude/VOICE.md` looks for the samples in `~/.claude/`.
- Live `PROSE.md`, `VOICE.md`, and the sample files contain no `~/.claude`, `Skill tool`, `AskUserQuestion`, `Task tool`, or model names.
- `~/.codex/config.toml` sets `model = "gpt-6.1-terra"`. OpenCode has no model configured.
- The working clone (`~/code/dotfiles`) and chezmoi's source (`~/.local/share/chezmoi`) are separate clones of the same remote, so live acceptance checks run only after merge and pull (Task 5).

## Global Constraints

- No `~/AGENTS.md`, ever. The root `AGENTS.md` line in `.chezmoiignore` stays.
- Adapters are real symlinks, never `@`-imports.
- Every symlink target is relative, so nothing hardcodes `/Users/kendrick`.
- The move, the new symlink sources, and the `.chezmoiignore` key-guard update land in one commit (Task 1).
- `settings.json` and upstream skill bodies are out of scope.
- Rung names, in order: `quick`, `standard`, `deep`, `frontier`. #108's probes expect exactly these.
- Keep DELEGATION.md's irreversibility rule, floor, and inheritance list word-for-word, except where a model name becomes a rung name.
- Tests never touch the live `$HOME` or the network: `HOME` is a temp dir, fetches use `file://`, and chezmoi runs with `--source "$SRC" --destination "$HOME" --config <temp> --exclude scripts`.
- Prose routing: commit messages, code comments, README, and repo `CLAUDE.md` go through the `technical-writing` skill. `AGENTS.md`, `DELEGATION.md`, and `harness-notes.md` are agent instructions, so they go through `writing-for-agents`. Working-memory files and this plan get neither.

## Review Focus

1. **Keyless machine.** With no age key, `~/.claude/PROSE.md` and `VOICE.md` must not become dangling symlinks. Their symlink targets join the keyless block in `.chezmoiignore` (Task 1 test 2).
2. **Existing machine migration.** The first apply after pull meets a regular file at `~/.claude/CLAUDE.md` and a stale `~/.claude/DELEGATION.md`. The apply has to replace the first with the symlink and remove the second (Task 1 test 3, which pre-seeds both).
3. **A reader arriving through `~/.claude/VOICE.md`** follows the relative sample links into `~/.claude/`, so the sample files need symlinks there too (Task 1 test 1).
4. **Container references.** Every `~/.agents/*.md` path that the installed rules cite must exist after `env-setup.sh` runs against the real source tree, including `harness-notes.md` (Task 4).
5. **Atomic-rename writers.** If Claude Code ever rewrites `~/.claude/CLAUDE.md` with a temp-file rename, the symlink becomes a regular file, as happened with VS Code (see antipatterns). No test can drive Claude's internals, so Task 5 checks that `chezmoi status` stays clean after a Claude session. Record the result in `decisionLog.md`.

---

### Task 1: Move the documents and add the adapters

**Files:**
- Move (`git mv`): `dot_claude/CLAUDE.md` → `dot_agents/AGENTS.md`; `dot_claude/private_DELEGATION.md` → `dot_agents/private_DELEGATION.md`; `dot_claude/encrypted_private_{PROSE,VOICE,voice-samples-work,voice-samples-personal}.md.age` → `dot_agents/` (same names)
- Create symlink sources. Each holds one line, the relative target:
  - `dot_claude/symlink_CLAUDE.md` → `../.agents/AGENTS.md`
  - `dot_claude/symlink_PROSE.md`, `symlink_VOICE.md`, `symlink_voice-samples-work.md`, `symlink_voice-samples-personal.md` → `../.agents/<same name>`
  - `dot_codex/symlink_AGENTS.md` → `../.agents/AGENTS.md`
  - `dot_config/opencode/symlink_AGENTS.md` → `../../.agents/AGENTS.md`
- Create: `.chezmoiremove` containing `.claude/DELEGATION.md`, with a one-line comment saying why (stale copy left by the move)
- Modify: `.chezmoiignore` keyless block. Replace the four `.claude/{VOICE,PROSE,voice-samples-*}.md` lines with `.agents/` equivalents, and also list the four `.claude/` symlink targets so a keyless machine gets no dangling links.
- Modify: `dot_agents/AGENTS.md`. Replace `~/.claude/PROSE.md`, `~/.claude/VOICE.md`, and `~/.claude/DELEGATION.md` with `~/.agents/…` paths, so DELEGATION's removal never leaves a dangling reference.
- Test: `tests/agents-layout.bats` (new)

**Interfaces:**
- Produces: target paths `~/.agents/{AGENTS,DELEGATION,PROSE,VOICE,voice-samples-work,voice-samples-personal}.md` and adapters `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md`. Source paths `dot_agents/AGENTS.md`, `dot_agents/private_DELEGATION.md`, `dot_agents/encrypted_private_{PROSE,VOICE}.md.age` are what Task 4 fetches.

- [ ] **Step 1: Write the failing tests** in `tests/agents-layout.bats`. Mirror the setup of `claude-bootstrap.bats`: temp `HOME`, `REAL_CHEZMOI`, and a config file holding `[data] machine_role = "work"`. Define `cz() { "$REAL_CHEZMOI" --source "$SRC" --destination "$HOME" --config "$cfg" "$@"; }`. Skip when chezmoi is missing.
  1. `"with a key, chezmoi managed lists the canonical docs and every adapter"`: write a non-empty `$HOME/.config/chezmoi/key.txt`, run `cz managed`, and assert with `grep -cxF` that each of these is listed exactly once: `.agents/AGENTS.md`, `.agents/DELEGATION.md`, `.agents/PROSE.md`, `.agents/VOICE.md`, `.agents/voice-samples-work.md`, `.agents/voice-samples-personal.md`, `.claude/CLAUDE.md`, `.claude/PROSE.md`, `.claude/VOICE.md`, `.claude/voice-samples-work.md`, `.claude/voice-samples-personal.md`, `.codex/AGENTS.md`, `.config/opencode/AGENTS.md`. Also assert `count=0` for the exact line `AGENTS.md`.
  2. `"without a key, PROSE and VOICE and their adapters are not managed"`: run `cz managed` with no key file. `.agents/AGENTS.md` and `.agents/DELEGATION.md` are present. `.agents/PROSE.md`, `.agents/VOICE.md`, `.claude/PROSE.md`, and `.claude/VOICE.md` are each `count=0`.
  3. `"apply on a non-kendrick home links every adapter to ~/.agents/AGENTS.md, and a second apply is clean"`: pre-seed a regular `~/.claude/CLAUDE.md` (`old`) and `~/.claude/DELEGATION.md` (`stale`). Run `cz apply --force --exclude scripts "$HOME/.agents" "$HOME/.claude" "$HOME/.codex" "$HOME/.config/opencode"` twice. For each of the three adapters, assert `readlink -f` equals `"$HOME/.agents/AGENTS.md"` and its bytes equal `$SRC/dot_agents/AGENTS.md`. Assert `$HOME/.claude/DELEGATION.md` and `$HOME/AGENTS.md` are `absent`, and `cz status` with the same targets prints nothing. `HOME` lives under `$BATS_TEST_TMPDIR`, so it is never `/Users/kendrick`.
- [ ] **Step 2:** `bats tests/agents-layout.bats` → all three fail (no `.agents` entries).
- [ ] **Step 3:** Make the moves and edits listed under **Files**.
- [ ] **Step 4:** `bats tests/agents-layout.bats` → 3 pass. Also run `bats tests/claude-bootstrap.bats tests/macos-defaults.bats tests/sync-guard.bats` → pass. Their `.claude/CLAUDE.md` managed-listing assertions still hold because the symlink is still managed.
- [ ] **Step 5: Commit** `feat(agents): make ~/.agents canonical for the global rules, with harness symlinks`

### Task 2: Neutral wording and the harness-notes table

**Files:**
- Modify: `dot_agents/AGENTS.md`
- Create: `dot_agents/harness-notes.md`
- Test: `tests/agents-docs.bats` (new)

**Interfaces:**
- Produces: `~/.agents/harness-notes.md`, which `AGENTS.md` cites. Task 4 must fetch it.

- [ ] **Step 1: Write the failing tests** in `tests/agents-docs.bats`. They read the plaintext sources and need no chezmoi.
  1. `"AGENTS.md and DELEGATION.md name no ~/.claude path"`: `grep -c '~/.claude'` over `dot_agents/AGENTS.md dot_agents/private_DELEGATION.md` totals 0.
  2. `"only harness-notes.md names harness tools"`: `grep -l 'Skill tool\|AskUserQuestion\|Task tool'` over `dot_agents/*.md` prints exactly `dot_agents/harness-notes.md`.
  3. `"AGENTS.md cites harness-notes.md"`: assert `~/.agents/harness-notes.md` appears in `dot_agents/AGENTS.md`.
- [ ] **Step 2:** Run → tests 1 and 2 fail on `Skill tool` in AGENTS.md, and test 3 fails.
- [ ] **Step 3:** Edit `AGENTS.md`:
  - "invoke the skill via the Skill tool" → "load the `humanizer` skill using the harness's skill mechanism". Fix every other sentence that names a harness tool the same way.
  - Add one line: where a skill or rule names a harness-specific tool or path, translate it with `~/.agents/harness-notes.md`.
  - Add a `## Claude Code Only` section, last in the file, saying that Claude Code rewrites shell commands through the `rtk` hook and that `RTK.md` in Claude Code's config directory documents it. Don't write a `~/.claude` path there, because test 1 forbids it.

  Write `harness-notes.md` as a table with columns: what a skill says (Claude Code), what it means, and how OpenCode and Codex do it. It needs at least these rows: `Skill` tool → "load the skill"; `AskUserQuestion` → "ask the user"; `Task`/`Agent` tool → "delegate using the harness's subagent mechanism"; `WebFetch` → "fetch"; and `~/.claude/<file>` → `~/.agents/<file>` for CLAUDE (as AGENTS), PROSE, VOICE, and DELEGATION. Run the `writing-for-agents` skill over both files.
- [ ] **Step 4:** `bats tests/agents-docs.bats` → pass.
- [ ] **Step 5: Commit** `refactor(agents): drop Claude Code tool names from the global rules`

### Task 3: Capability rungs in DELEGATION.md

**Files:**
- Modify: `dot_agents/private_DELEGATION.md`
- Test: `tests/agents-docs.bats` (append)

**Interfaces:**
- Produces: the section heading `## Rungs by Harness`. The checker's boundary is that heading through the next `## ` heading. #107 fills the OpenCode column under it.

- [ ] **Step 1: Write the failing tests.** Add helper `models_outside_mapping <file>`, which prints every line outside the `## Rungs by Harness` section that matches `grep -inwE 'haiku|sonnet|opus|fable|claude-[a-z0-9.-]+|gpt-[0-9][a-z0-9.-]*'`. Use awk to track whether a line falls inside the section.
  1. `"model names appear only in the per-harness mapping table"`: `models_outside_mapping dot_agents/private_DELEGATION.md` prints nothing. Assert the section also exists and contains `haiku`, so an empty or missing section can't pass vacuously.
  2. `"the rung table names no models"`: the rows of the `## The Rungs` table contain no match for the regex above, and their first cells are `quick`, `standard`, `deep`, and `frontier`, in that order.
  3. `"a planted model name outside the mapping table fails the check"`: copy the file to a temp path and append `Route this to sonnet.` after the first paragraph. `models_outside_mapping` on the copy prints that line. This is the falsifier the AC asks for.
- [ ] **Step 2:** Run → 1 and 2 fail on today's `haiku`/`sonnet`/… rows, and 3 passes. Test 3 must also go red under `tests/mutation-check.sh`.
- [ ] **Step 3:** Edit DELEGATION.md. In the rung table and in all prose, `haiku`→`quick`, `sonnet`→`standard`, `opus`→`deep`, `fable`→`frontier`. Keep "stays in session" as the first row. Add `## Rungs by Harness` with columns `Rung | Claude Code | OpenCode | Codex`. The Claude Code column holds `haiku`/`sonnet`/`opus`/`fable`. The OpenCode and Codex cells read "session model", which #107 replaces for OpenCode. Move the "today's lineup… re-check what each rung points at" paragraph under that table. Reword "Name the rung on every dispatch that picks a model" so the dispatch picks the model the mapping gives for its rung. Don't change the irreversibility rule, the floor, or the inheritance list beyond the name swap. Before committing, follow `conventions.md` "Always-loaded policy files": walk the three failure paths with the new names. Then run `writing-for-agents`.
- [ ] **Step 4:** `bats tests/agents-docs.bats` → pass.
- [ ] **Step 5: Commit** `refactor(delegation): route by capability rung, with models mapped per harness`

### Task 4: Remote bootstrap follows the move

**Files:**
- Modify: `scripts/env-setup.sh`, `tests/claude-bootstrap.bats`, `README.md` ("How Remote Claude Containers Get the Rules")

**Interfaces:**
- Consumes: the source paths from Task 1 and `dot_agents/harness-notes.md` from Task 2.
- Produces: in a container, real files `~/.agents/{AGENTS,DELEGATION,harness-notes}.md`, plus `{PROSE,VOICE}.md` when a key is present. Also symlinks `~/.claude/CLAUDE.md` → `../.agents/AGENTS.md` and, when a key is present, `~/.claude/{PROSE,VOICE}.md` → `../.agents/…`. `remote-bootstrap.sh` needs no change because it fetches only `scripts/env-setup.sh` and the skill lockfile. Confirm that with test 5 below.

- [ ] **Step 1: Update the fixture and write the failing tests.** In `setup()`, move the fixture tree to `$FX/dot_agents/` (`AGENTS.md`, `private_DELEGATION.md`, `harness-notes.md`, `encrypted_private_*.md.age`). Make the fixture rules cite `~/.agents/PROSE.md`, `~/.agents/VOICE.md`, `~/.agents/DELEGATION.md`, and `~/.agents/harness-notes.md`. Update `EXPECTED` and `AMENDMENT_BODY` to the `~/.agents/` paths. Point every existing `$HOME/.claude/{PROSE,VOICE,DELEGATION}.md` assertion at `$HOME/.agents/`, and point the blocker directory at `~/.agents/DELEGATION.md`. Leave `$HOME/.claude/CLAUDE.md` as is, since reads follow the symlink. Add:
  1. `"env-setup.sh links ~/.claude/CLAUDE.md to ../.agents/AGENTS.md"`: `readlink` prints exactly `../.agents/AGENTS.md`.
  2. `"with a key, every ~/.agents path the installed rules cite exists"`: extract `grep -oE '~/\.agents/[A-Za-z0-9_.-]+\.md'` from `~/.claude/CLAUDE.md`. Each one is `present` under `$HOME`, and `~/.claude/PROSE.md` resolves (`readlink -f`) to `$HOME/.agents/PROSE.md`.
  3. `"without a key, every cited path except PROSE and VOICE exists, and no dangling adapter is left"`: same extraction. PROSE and VOICE are `absent`, and so are `~/.claude/{PROSE,VOICE}.md` (test with `-L`, so a dangling link counts as present).
  4. `"against the real source tree, strict env-setup exits 0"`: `DOTFILES_RAW_BASE="file://$SRC"`, a non-empty key, and an `age` stub that copies its last argument to the path after `-o`. Then `ENV_SETUP_STRICT=1` gives `status=0`. Every path the script fetches must exist in this repo, or the run exits 1.
  5. `"remote-bootstrap.sh against the real source tree finds env-setup and the lockfile"`: `DOTFILES_RAW_BASE="file://$SRC"`, run with the name `nosuchskill`. `$stderr` contains `unknown skill: nosuchskill` and does not contain `could not fetch`.
- [ ] **Step 2:** `bats tests/claude-bootstrap.bats` → the new cases and the moved-path cases fail.
- [ ] **Step 3:** Change `env-setup.sh`. Stage in `$HOME/.agents/.env-setup.XXXXXX`. Fetch `dot_agents/private_DELEGATION.md`, `dot_agents/harness-notes.md`, `dot_agents/encrypted_private_{PROSE,VOICE}.md.age`, and `dot_agents/AGENTS.md`, and install each into `~/.agents/`. Keep the existing `@RTK.md` strip, the amendment logic with `~/.agents` paths, and the rc/strict semantics. After a successful `AGENTS.md` install, `mkdir -p ~/.claude && ln -sfn ../.agents/AGENTS.md ~/.claude/CLAUDE.md`. With a key, link `~/.claude/{PROSE,VOICE}.md` the same way. Without one, `rm -f` both the `~/.agents` and `~/.claude` copies. Update the header comment and the README section to describe the new layout, and run `technical-writing` on both.
- [ ] **Step 4:** `bats tests/claude-bootstrap.bats` → pass. `bash tests/mutation-check.sh tests/claude-bootstrap.bats` → every new assertion goes red when inverted.
- [ ] **Step 5: Commit** `fix(bootstrap): install the rules under ~/.agents, matching chezmoi's layout`

### Task 5: Docs, working memory, and live acceptance

**Files:**
- Modify: `CLAUDE.md` ("Two Kinds of Claude Config"), `_working-memory/conventions.md` ("Always-loaded policy files" paths), `_working-memory/decisionLog.md` (append)

- [ ] **Step 1:** Rewrite the repo `CLAUDE.md` paragraph so `dot_agents/` is the canonical user-level tree (rules for every harness), `dot_claude/` is the Claude adapter plus settings, `RTK.md`, and plugin seeds, and `.claude/` is project-scoped as before. Run `technical-writing`. In `conventions.md`, change the paths to `dot_agents/AGENTS.md` and `dot_agents/private_DELEGATION.md`. Append a `decisionLog.md` entry covering relative symlinks over templates, rung names, the `.chezmoiremove` for DELEGATION, and the sample-file symlinks.
- [ ] **Step 2:** `bats tests/` → exit 0.
- [ ] **Step 3: Commit** `docs: describe dot_agents as the canonical rules tree`
- [ ] **Step 4: Live acceptance (after merge, once the user has pulled into `~/.local/share/chezmoi`).** Run each check and paste its output into the PR:
  - `chezmoi apply && chezmoi apply && chezmoi status` → empty
  - `chezmoi managed | grep -E '^\.agents/(AGENTS|DELEGATION|PROSE|VOICE)'` → 4 lines
  - `grep -rn '~/.claude' ~/.agents/AGENTS.md ~/.agents/DELEGATION.md` → nothing
  - `grep -rln 'Skill tool\|AskUserQuestion\|Task tool' ~/.agents/*.md` → only `harness-notes.md` (this also covers the decrypted PROSE and VOICE)
  - `cd /tmp && opencode --standalone --print-logs --log-level debug run --agent plan "Say OK and nothing else." 2>&1 | grep -F 'AGENTS.md'` → shows `~/.config/opencode/AGENTS.md` loaded
  - OpenCode in `/tmp`, then a fresh Claude Code session: "Do you push without being asked?" → no. "What trailer must never appear on a commit?" → Co-Authored-By.
  - After that Claude session, `chezmoi status` is still empty and `~/.claude/CLAUDE.md` is still a symlink (Review Focus 5).
