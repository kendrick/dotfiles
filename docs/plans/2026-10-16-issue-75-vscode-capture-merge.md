# VS Code Extension Capture Merges Instead of Overwriting (#75) Implementation Plan

**Goal:** Capturing VS Code extensions merges the local install set into `dot_config/vscode-extensions.txt` and respects a tracked removed-list. One machine's sync can no longer put back an extension another machine removed, or drop one this machine never installed.

**Tech Stack:** bash, zsh (the `code()` wrapper), chezmoi, bats.

---

## Context

Issue #75. Two writers each overwrite the whole list with the local `code --list-extensions`: `dot_local/bin/executable_dotfiles-sync:187-199`, and the `code()` wrapper at `dot_config/zsh/functions.zsh:127-142`. The last machine to sync wins, so removals made by hand (#46) keep coming back from other machines (9a4afde, d76b621, f28ca65).

## Decisions

These are settled. Implement them as written.

1. **One helper, `dot_local/bin/executable_vscode-extensions-capture`** (deploys as `~/.local/bin/vscode-extensions-capture`), modeled on `dot_local/bin/executable_vscode-extensions-update`: a bash script with `set -euo pipefail` and its own usage. It is the only code that writes either list. Its interface:
   - `vscode-extensions-capture` with no arguments merges and writes.
   - `vscode-extensions-capture --removed <id>` records `<id>` as removed, then merges.
   - `vscode-extensions-capture --restored <id>` takes `<id>` out of the removed-list, then merges.
   - `-h|--help` prints usage. Any other argument prints usage to stderr and exits 2.
   - It finds the source dir with `chezmoi source-path`. If `code` isn't on `PATH`, it prints `code CLI not found, skipping` and exits 0, which is today's sync behavior.
2. **The removed-list is `dot_config/vscode-extensions-removed.txt`.** Its header is `# VS Code extensions removed on purpose. Capture never adds these back.` followed by `# Remove a line (or run \`code --install-extension <id>\`) to allow it again.`, then one id per line, sorted with `sort -f`. Add `.config/vscode-extensions-removed.txt` to `.chezmoiignore` directly under `.config/vscode-extensions.txt` at `:29`, so the file stays source-only.
3. **Merge rule.** Comments and blank lines are ignored when reading either file. The new list is (ids in the list ∪ ids from `code --list-extensions`) minus the removed ids. It is sorted with `sort -f`, de-duplicated case-insensitively, and written under the existing two header lines byte for byte (`# VS Code extensions to install` / `# Edit this list and run \`chezmoi apply\` to sync.`). Removed wins: an id in both files is dropped from the list. Compare ids case-insensitively, because the marketplace treats them that way.
4. **`--removed <id>`** appends the id to the removed-list if it isn't there yet, compared case-insensitively. **`--restored <id>`** deletes it from the removed-list, and the merge then adds it back from the local install set. When the removed file doesn't exist yet, `--removed` creates it with the header, and a plain merge treats it as empty.
5. **Write only on change.** Write each file to a temp file in the same directory and `mv` it into place only when the content differs. A no-op sync then leaves the file untouched, and its mtime doesn't change.
6. **`dotfiles-sync:187-199`** becomes a call to `vscode-extensions-capture`. Keep the `==> Regenerating VS Code extension list` and `    updated dot_config/vscode-extensions.txt` echo lines; the second prints only when the helper reports a change. The helper exits 0 after a write and 0 after a no-op, so the change report goes on stdout as the line `updated`. Don't use exit codes for it.
7. **The `code()` wrapper** keeps running `command code "$@"` first and keeps its `rc`. It then calls the helper:
   - When the argument list contains `--uninstall-extension <id>`, it calls `vscode-extensions-capture --removed <id>`, once per id.
   - When it contains `--install-extension <id>`, it calls `--restored <id>`.
   - Parse the arguments in order instead of matching on `$*`: the value is the next argument after the flag, and the flag can repeat.
   - It still returns `rc`.
   - When `command code` failed, it calls no helper, so a failed uninstall records nothing.
8. **Seed** the removed-list with these seven ids and drop them from `dot_config/vscode-extensions.txt`: `adamerose.markdown-wysiwyg`, `bierner.markdown-preview-github-styles`, `ms-azuretools.vscode-docker`, `ms-vscode-remote.remote-wsl`, `ms-vsliveshare.vsliveshare`, `webhint.vscode-webhint`, `xyc.vscode-mdx-preview`. Edit both data files by hand in the worktree; don't produce them by running capture against this machine.
9. **Comments carry the WHY:**
   - at the helper's top: whole-list overwrite let the last machine to sync win, and removals kept coming back (#75)
   - at the merge: why removed wins
   - at the sync call site: one line naming the helper

## Task: merge-based capture with a removed-list

**Files:** dot_local/bin/executable_vscode-extensions-capture, dot_local/bin/executable_dotfiles-sync, dot_config/zsh/functions.zsh, dot_config/vscode-extensions.txt, dot_config/vscode-extensions-removed.txt, .chezmoiignore, tests/vscode-extensions-capture.bats

### Tests: new tests/vscode-extensions-capture.bats

Follow `tests/vscode-extensions-update.bats` (`load 'helpers'`, a synthetic `$HOME`, stubs on `PATH`, `CALL_LOG`):

- A `chezmoi` stub answers `source-path` with a temp source dir that holds seeded copies of both lists.
- A `code` stub answers `--list-extensions` from `$INSTALLED`, a file each case writes, and logs every call.

Settle each expected value from the issue's Done-when, not from the new code. Assert on the files as written, which is what the installer's `include` reads.

1. List `{a, b}`, nothing removed, installed `{a}`. The list stays `{a, b}`.
2. List `{a}`, removed `{b}`, installed `{a, b, c}`. The list becomes `{a, c}`. Falsifier: the same case with `b` absent from the removed file writes `{a, b, c}`.
3. List `{a, b}`, removed `{b}`. The list becomes `{a}`.
4. Case-insensitive match: removed `{Foo.Bar}`, installed `{foo.bar}`. The id isn't added.
5. `--removed b` run twice. `b` appears in the removed file exactly once and isn't in the list.
6. `--restored b` with `b` removed and installed. `b` leaves the removed file and is in the list.
7. A merge that changes nothing leaves both files' bytes and mtimes unchanged, and prints no `updated` line.
8. The header's two lines are preserved byte for byte.
9. `code` absent from `PATH`. The helper exits 0 and prints `code CLI not found, skipping`.
10. An unknown flag gets exit 2.
11. Wrapper: source `dot_config/zsh/functions.zsh` in `zsh -c` with the stubs on `PATH`, run `code --uninstall-extension b`, and assert the removed file gains `b`. Run the same with a `code` stub that exits 1, and assert the removed file is unchanged and the wrapper returns 1. Run `code --install-extension b` and assert `b` leaves the removed file.
12. Static checks:
    - `grep -c 'list-extensions' dot_local/bin/executable_dotfiles-sync dot_config/zsh/functions.zsh` reports `0` for both files.
    - The seeded removed file holds exactly the seven ids in decision 8, and none of them appears in `dot_config/vscode-extensions.txt`.
    - `.chezmoiignore` lists `.config/vscode-extensions-removed.txt`.

## Verification

- `bats tests/vscode-extensions-capture.bats` passes.
- `bats tests/` exits 0. `tests/sync.bats` and `tests/sync-guard.bats` must stay green with the sync's call site changed, and `tests/install-failures.bats` reads the list through `first_extension`.
- `chezmoi managed | grep vscode-extensions-removed` prints nothing.
- After merge, run a targeted `chezmoi apply ~/.local/bin/vscode-extensions-capture ~/.local/bin/dotfiles-sync ~/.config/zsh/functions.zsh`, per conventions. This is a post-merge step for the human; the lane itself doesn't apply.

## Out of Scope

- Uninstalling anything. The installer stays add-only, and the seven stay installed until removed by hand.
- `dotfiles-doctor`. Its existing "here but not in your dotfiles" line reports a removed-but-installed extension. The #67 lane owns that file in this wave.
- `tests/mutation-check.sh`, which the #74 lane owns in this wave. Registering `tests/vscode-extensions-capture.bats` in `ALL_FILES` is a one-line follow-up after both merge.
- VS Code profiles (#45, which builds on this).
- The npm and pnpm wrappers.
- `_working-memory/`.
