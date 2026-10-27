# Remote Claude Bootstrap (#43) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A remote Claude Code container gets `~/.claude/CLAUDE.md` (plus `DELEGATION.md`, and `PROSE.md` and `VOICE.md` when an age key is present) from one pasted setup script. A fuller bootstrap also installs a named set of skills from the lockfile.

**Architecture:** Two self-contained bash scripts under `scripts/`, which `.chezmoiignore` already keeps out of `$HOME`. Both fetch from this public repo over `raw.githubusercontent.com`. `scripts/remote-bootstrap.sh` fetches and runs `scripts/env-setup.sh` rather than duplicating it. A base-URL override lets `tests/claude-bootstrap.bats` run them offline against a fixture directory through `file://` URLs.

**Tech Stack:** bash (Linux container and macOS), curl, git, jq, age, bats.

---

## Context

Issue #43 has the problem, the proposed behavior, the acceptance criteria and the non-goals. Implement against it, with the decisions below where the issue is silent or out of date. Facts checked at 499398c:

- `kendrick/dotfiles` is public, so raw fetches need no auth.
- `dot_claude/CLAUDE.md` is a plain file, not a template. It no longer contains an `@RTK.md` line, which an auto-sync removed in 74edf3f.
- `CLAUDE.md` tells agents to read `~/.claude/PROSE.md`, `~/.claude/VOICE.md` and `~/.claude/DELEGATION.md`. In the source tree these are `dot_claude/encrypted_private_PROSE.md.age`, `dot_claude/encrypted_private_VOICE.md.age` (both age-encrypted) and `dot_claude/private_DELEGATION.md` (plain).
- chezmoi's age identity lives at `~/.config/chezmoi/key.txt`. `.chezmoiignore:55-66` documents treating that file as absent when it's 0 bytes, because a failed `op read` leaves an empty file behind.
- The lockfile `dot_local/private_state/skills/dot_skill-lock.json` maps a skill name to `{source, sourceUrl, skillPath, ...}`, where `skillPath` points at the skill's `SKILL.md` inside its repo.
- Account-synced skills land under `~/.claude/skills/synced/<bucket>/<name>/`, and the bucket entry may be a symlink.

## Decisions

These are settled. Implement them as written.

1. **Base URL.** Both scripts read `DOTFILES_RAW_BASE`, defaulting to `https://raw.githubusercontent.com/kendrick/dotfiles/main`, and fetch `"$DOTFILES_RAW_BASE/<source path>"` with `curl -fsSL`. Tests point it at `file://<fixture dir>`. Nothing else is configurable.
2. **What `env-setup.sh` installs:**
   - `~/.claude/CLAUDE.md` from `dot_claude/CLAUDE.md`, with any line that is exactly `@RTK.md` removed. The strip is a guard today, since the line is gone, and the fixture test keeps it honest.
   - `~/.claude/DELEGATION.md` from `dot_claude/private_DELEGATION.md`. This goes beyond the issue's "CLAUDE.md and nothing else": `CLAUDE.md` tells every agent to read it before any subagent dispatch, and it's unencrypted, so leaving it out would recreate the "cites a file it can't read" problem the issue fixes for skills.
   - With a usable key (Decision 3): `~/.claude/PROSE.md` and `~/.claude/VOICE.md`, each fetched as `.age` and decrypted with `age -d -i ~/.config/chezmoi/key.txt`.
   - Without one: the amendment from Decision 4, appended to `CLAUDE.md`.
3. **A usable key** is `~/.config/chezmoi/key.txt` present with a size above 0 (`[ -s ]`), and `age` on PATH. A key without `age`, or a failed decrypt, counts as unusable for that run, so the amendment goes in. Never leave a partial `PROSE.md` or `VOICE.md` behind: decrypt to a temp file in `~/.claude`, then `mv`.
4. **The amendment**, appended as its own section:
   ```markdown
   ## Missing House Rules

   This container has no age key, so `~/.claude/PROSE.md` and `~/.claude/VOICE.md` were not installed. When a rule above says to read one of them, say that it's unavailable here and continue without it.
   ```
5. **Idempotent by construction.** Each run builds `CLAUDE.md` in full, as the fetched text plus the amendment when needed, in a temp file, then `mv`s it into place. It never appends to an existing `~/.claude/CLAUDE.md`. Two runs give byte-identical files.
6. **Failure handling:**
   - `env-setup.sh` always exits 0. If a fetch fails, it prints one line to stderr naming the path and leaves any existing file untouched, so a network failure can't wedge container startup.
   - `remote-bootstrap.sh` is run by hand, so it reports honestly. It attempts everything, names each failure on stderr, and exits 1 if anything failed.
7. **`remote-bootstrap.sh` usage:** `remote-bootstrap.sh <skill-name>...`. First it fetches `scripts/env-setup.sh` from the base and runs it with `bash`, passing `DOTFILES_RAW_BASE` through. Then, for each named skill:
   - Look the name up in the lockfile, fetched from the base. An unknown name is a failure.
   - If `~/.claude/skills/synced/*/<name>/SKILL.md` exists, following symlinks, skip it and say "synced".
   - Otherwise shallow-clone `sourceUrl` into a temp dir and copy the whole directory holding `skillPath`'s `SKILL.md` to `~/.claude/skills/<name>`, replacing any previous copy. Clone each source repo once per run, even when several skills share it.
   - With no arguments, it runs `env-setup.sh` only and prints the usage line, exit 0.
8. **No shared library.** `env-setup.sh` is pasted into an environment's setup field on its own, so it has to be self-contained. `remote-bootstrap.sh` reuses it by fetching it, never by sourcing a third file.
9. **Portability:** plain bash with no bash-4-only features in paths a Mac would run, `mktemp -d` without GNU-only flags, and no `sed -i`. Containers are Linux and tests run on macOS bash 3.2.
10. **Register the new test file** in `ALL_FILES` in `tests/mutation-check.sh:89`, and extend the comment above it that lists files by issue to name #43.
11. **README:** one short subsection under the existing scripts or Claude material saying what each script is for, the `curl … | bash` line for `env-setup.sh`, and that it belongs in a Claude Code environment's setup-script field. Find the right place by reading the README; don't add a new top-level section.

## Task 1: Test harness

**Files:**
tests/claude-bootstrap.bats

`setup()` builds a fixture base dir laid out like the repo:
- `dot_claude/CLAUDE.md` holding a few lines plus an `@RTK.md` line.
- `dot_claude/private_DELEGATION.md`.
- `dot_claude/encrypted_private_PROSE.md.age` and `encrypted_private_VOICE.md.age`, encrypted to a key made with `age-keygen` in the test's tmp dir.
- `scripts/env-setup.sh` and `scripts/remote-bootstrap.sh`, copied from the repo.
- A lockfile naming two skills from one fixture git repo (made with `git init`, `file://` `sourceUrl`). One skill carries `references/x.md` and the other `scripts/y.sh`.

It also sets `HOME` to a tmp dir and `DOTFILES_RAW_BASE=file://<fixture>`. Skip the key cases with a reason when `age` or `age-keygen` is missing. Follow `tests/helpers.bash` and the `assert_contains` style, since this file joins the mutation check.

## Task 2: Failing cases

**Files:**
tests/claude-bootstrap.bats

One case per acceptance criterion, plus the decisions above. Settle each expected value from the issue and the Decisions, never from the scripts.

1. `env-setup.sh` writes `~/.claude/CLAUDE.md` equal to the fixture's minus the `@RTK.md` line, and writes `DELEGATION.md`.
2. Fetch failure: a base pointing at a missing dir makes `env-setup.sh` exit 0, print the failure on stderr, and leave a pre-seeded `~/.claude/CLAUDE.md` byte-identical.
3. Idempotency: two runs of each script with no key give a byte-identical `CLAUDE.md` (`cmp`), with the amendment present once. Repeat with a key.
4. Key present and non-empty: `PROSE.md` and `VOICE.md` match the fixture plaintexts, and `CLAUDE.md` has no amendment.
5. Key absent, and separately a 0-byte key: no `PROSE.md` or `VOICE.md`, and the amendment is present. Falsifier: a check by existence instead of size fails the 0-byte case.
6. `remote-bootstrap.sh <both skills>` installs each one's whole folder, including `references/x.md` and `scripts/y.sh`.
7. A skill present at `~/.claude/skills/synced/<bucket>/<name>/SKILL.md`, where `<bucket>` is a symlink to a real dir, is skipped and not copied.
8. An unknown skill name makes `remote-bootstrap.sh` exit 1 and name it, while the known one still installs.
9. Neither script deploys: run the real chezmoi against this repo with `--source` and `managed`, and check that neither path appears. Capture the real binary before any stub, using the `REAL_CHEZMOI` idiom from `tests/doctor.bats`.

Run `bats tests/claude-bootstrap.bats`. Expected: every case fails, because the scripts don't exist yet. Case 9 may pass already, which is fine, since `.chezmoiignore` covers `scripts/`.

## Task 3: Implement

**Files:**
scripts/env-setup.sh
scripts/remote-bootstrap.sh
tests/mutation-check.sh
README.md

**Step 1:** Write both scripts to Decisions 1–9. Mark them executable in git (`git update-index --chmod=+x`). Each opens with a short comment saying what it's for and where it runs.

**Step 2:** Apply Decisions 10 and 11.

**Step 3:** Run `bats tests/claude-bootstrap.bats`. Expected: all pass.

**Step 4:** Run `bash tests/mutation-check.sh tests/claude-bootstrap.bats`. Expected: every site killed, which is the issue's "reports `not ok` when inverted" criterion.

**Step 5:** Run `TMPDIR=$(mktemp -d /tmp/v43.XXXX) bats tests/` in the background. Expected: 0 not ok.

**Step 6:** Commit: `feat(claude): bootstrap CLAUDE.md and named skills into remote containers (#43)`. The body says why: remote containers start without the global rules, and chezmoi isn't there to replay them.

## Verification

- `bats tests/claude-bootstrap.bats`, its mutation check and `bats tests/` pass.
- By hand, on this Mac, in a scratch `HOME`: run `DOTFILES_RAW_BASE=file://$PWD bash scripts/env-setup.sh`, then diff the resulting `CLAUDE.md` against `dot_claude/CLAUDE.md`.
- Not tested: a real remote container, and the real `raw.githubusercontent.com` path, which only works once this merges to main. Say so in the PR.

## Out of Scope

- The issue's non-goals: settings, hooks and permissions, replacing account-level skill sync, a `gh` shim, deploying either script to `$HOME`, and any edit to `dot_claude/CLAUDE.md`.
- The voice-samples files `VOICE.md` draws on. Without them it still states its process, and adding them is a follow-up if the samples turn out to matter remotely.
- Every `encrypted_*.age` file's content, and `run_onchange_after_restore-agent-skills.sh.tmpl`.
