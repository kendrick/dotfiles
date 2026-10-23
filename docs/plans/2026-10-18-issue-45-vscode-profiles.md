# VS Code Profiles Instead of One Flat Extension List (#45) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** chezmoi provisions a lean default VS Code profile plus `web`, `embedded`, and `docs` profiles, each from a tracked list, so a window loads only what its work needs, and the default activates fewer than 8 extensions at startup.

**Architecture:** The default profile keeps `dot_config/vscode-extensions.txt` and its removed file. Each extra profile is `dot_config/vscode-profiles/<name>.txt`, holding only what that profile adds, and every profile gets the default list plus its own. The installer registers missing profiles in VS Code's `storage.json`, but only while VS Code is closed, then installs per profile with `--profile`. `vscode-extensions-capture` merges every profile's list, and `vscode-extensions-update` updates every profile.

**Tech Stack:** bash 3.2, chezmoi templates, jq (`/usr/bin/jq` ships with macOS 15+), bats.

---

## Context

Issue #45. One list at `dot_config/vscode-extensions.txt` provisions every window, and 14 of 16 launches in the issue's log session logged `Extension host (LocalProcess) is unresponsive`. #75 (merged as 973c9eb) made capture a merge with tombstones, and this plan builds on it.

The list now holds 43 ids, not the 37 the issue counts. Ids were re-added since the issue was written, and #75 tombstoned the seven the issue removed.

## Verified Facts

These were measured on VS Code 1.141.0 on 2026-10-17, against an isolated `--user-data-dir` so no real profile was touched. Build against them and don't re-derive them from docs.

1. **The CLI never creates a profile.** `code --install-extension X --profile web` exits 1 with `Profile 'web' not found.` when `web` doesn't exist. `--list-extensions --profile web` and `--update-extensions --profile web` do the same. Only opening a window with `--profile` creates one, and the installer must not open windows.
2. **A profile registered in `storage.json` works.** Write `{"location": "<dir>", "name": "web"}` into the `userDataProfiles` array of `~/Library/Application Support/Code/User/globalStorage/storage.json`, and create `~/Library/Application Support/Code/User/profiles/<dir>/`. After that, `--install-extension --profile web` installs into it, writing that profile's own `extensions.json`. `--list-extensions --profile web` lists only it, and the default profile's list stays separate. `--uninstall-extension` and `--update-extensions` both honor `--profile`.
3. **The app keeps a profile registered while it was closed.** A VS Code launched afterward opened the folder in that profile and kept the entry. That included a `useDefaultFlags` object, so the profile shares the default profile's settings and keybindings. It didn't write a `settings.json` into the profile's directory.
4. **A running app drops a profile added while it runs.** An entry written to `storage.json` while VS Code was open was gone after the app wrote its own state. So the installer registers a profile only while no `Code` process is running, and `pgrep -x Code` finds the app's main process.
5. **Extension files are shared.** All profiles install into the one `~/.vscode/extensions` directory, and each profile only references them in its own `extensions.json`. Installing the default list into four profiles costs install calls, not disk.
6. **Startup activation, as the log records it.** In a real `exthost.log`, only `activationEvent: '*'` lines carry `startup: true`, and that includes built-ins (`vscode.git`, `vscode.git-base`, `vscode.github`). `onStartupFinished` lines carry `startup: false`. Acceptance criterion 5 names both events and counts `startup: true` lines, so this plan counts every non-`vscode.*` id activated by `*` or `onStartupFinished`. That bar is stricter than either half alone.
7. **`oxc.oxc-vscode`** (official, 1.64.1) covers both Oxlint and Oxfmt. Its manifest activates only on `onLanguage:*` events, never at startup. Its settings include `oxc.enable.oxfmt` and `oxc.fmt.experimental`.
8. **Templates can glob the source dir.** `{{ glob (joinPath .chezmoi.sourceDir "dot_config/vscode-profiles/*.txt") }}` returns absolute paths, and `include` reads them. A relative glob returns nothing.

## Decisions

Settled with the user. Implement them as written.

1. **Taxonomy: a lean default plus `web`, `embedded`, `docs`** (the issue's option 1). It won because each heavy group maps to one kind of work, and the default only has to carry what every window needs. Themes stay in the default, so `theme`'s installed-extension check and doctor's theme-registry check keep reading the default list.
2. **Removal stays add-only.** The installer never uninstalls. Profiles drift visibly instead, through capture and doctor.
3. **A profile is the default list plus its own list.** `dot_config/vscode-profiles/<name>.txt` holds only what that profile adds, and the installer installs the default list into every profile too. The issue says the default carries what "earns its place in every window", so it belongs in every profile as well.
4. **The split.** The issue's mapping, plus three changes the user chose, and the user accepted these changes to the extension set as overriding the issue's "sorting only" non-goal:
   - `web`: `bradlc.vscode-tailwindcss`, `stylelint.vscode-stylelint`, `vunguyentuan.vscode-css-variables`, `jaspernorth.vscode-pigments`, `radhakantaroy.vs-color-preview`, `csstools.postcss`, `unifiedjs.vscode-mdx`, `formulahendry.auto-rename-tag`, `dbaeumer.vscode-eslint`, `esbenp.prettier-vscode`
   - `embedded`: `platformio.platformio-ide`, `ms-vscode.cpptools`
   - `docs`: `shd101wyy.markdown-preview-enhanced`, `yzhang.markdown-all-in-one`, `robole.markdown-snippets`, `bierner.markdown-mermaid`
   - Replaced in the default: `dbaeumer.vscode-eslint` and `esbenp.prettier-vscode` by `oxc.oxc-vscode`. The two stay in `web` as the fallback for repos still configured for ESLint or Prettier.
   - Dropped: `orta.vscode-jest` and `crystal-spider.jsdoc-generator`.
   - Everything else stays in the default: 26 ids. Seven of those activate at startup per their manifests: better-comments, claude-code, catppuccin, gitlens, indent-rainbow, chatgpt, errorlens.
5. **Every id that leaves the default gets a tombstone** in `dot_config/vscode-extensions-removed.txt`: the 16 that move to a profile and the 2 that are dropped. Without one, the next capture on any machine where the default profile still has them would merge them back. The installer is add-only, so they stay installed there.
6. **Tombstone rules.**
   - A default tombstone keeps an id out of the default list. It also keeps capture from adding the id to any profile list just because it's installed there.
   - A tombstone doesn't override an id a profile list already names. A tracked profile list is explicit membership, and that's what lets a moved id sit in `web.txt` while tombstoned in the default.
   - A profile's own removed file, `dot_config/vscode-profiles/<name>-removed.txt`, created on demand, keeps the id out of that profile's list only.
   - Without the second rule, every id uninstalled from the default would reappear as an extra in all three profiles, because the installer put it there as part of the default list.
7. **Registration.**
   - A missing profile gets `{"location": "chezmoi-<name>", "name": "<name>", "useDefaultFlags": {"settings": true, "keybindings": true, "snippets": true, "tasks": true, "prompts": true, "mcp": true, "languageModels": true}}`. `extensions` is left out, since separate extensions are the point.
   - A profile already registered under that name keeps its entry, whatever its location. The installer never edits an existing entry.
   - Writes go through a temp file in the same dir and `mv`.
   - If `storage.json` is absent, as when VS Code was never launched, the installer creates it as `{"userDataProfiles": [...]}`. Verified fact 3 started from such a file.
8. **When VS Code is running, the profile waits.** If a profile needs registering while `pgrep -x Code` finds a process, the installer skips that profile's installs. It writes the profile's name to `~/.local/state/dotfiles/vscode-profiles-pending`, settles `step_warn "vscode ext" "…"`, and prints `Quit VS Code, then run 'chezmoi apply' again to create: <names>`. The run still exits 0, because an open editor isn't a reason to fail an apply.
   - A `run_onchange_` script normally reruns only when its content changes, so the template adds a header line only while the marker file exists:
     ```
     {{- $pending := joinPath .chezmoi.homeDir ".local/state/dotfiles/vscode-profiles-pending" }}
     {{- if stat $pending }}
     # pending profiles: {{ include $pending | trim }} (VS Code running at render: {{ output "sh" "-c" "pgrep -x Code >/dev/null && echo yes || echo no" | trim }})
     {{- end }}
     ```
   - The line's content changes when the open-or-closed state does, so the first apply with VS Code closed reruns the script. That run registers the profiles and deletes the marker. Measured against real chezmoi 2.73 (`run_onchange_` compares the last run's bytes by name): the first apply after the marker appears reruns once, because it's the first render with the line, and later applies with VS Code still open don't. The apply after registration reruns once more, because the line is gone. The user accepted those two one-time extra passes over this design's alternative, rendering from `storage.json`, on 2026-10-19.
9. **The `code()` wrapper forwards `--profile <name>`** to `vscode-extensions-capture`. Absent, or `Default`, means the default profile. A profile name with no tracked list records nothing and prints `code: profile <name> is not tracked in dotfiles, list not updated` to stderr.
10. **`settings.json`.** Set `editor.defaultFormatter` to `oxc.oxc-vscode`, replacing `esbenp.prettier-vscode` at `:12`. Replace `"source.fixAll.eslint": "explicit"` at `:5` with `"source.fixAll.oxc": "explicit"`. oxc's language server registers that code-action kind (`apps/oxlint/src/lsp/code_actions.rs` in oxc-project/oxc, and its `crates/oxc_language_server/README.md`). Add no `oxc.*` settings: the 1.64.1 manifest defaults `oxc.enable.oxlint`, `oxc.enable.oxfmt`, and `oxc.fmt.experimental` to `true`. Leave the XML override at `:42` alone.

## Waves

| Wave | Task | Owns |
|---|---|---|
| 0 | T1 data split | dot_config/vscode-extensions.txt, dot_config/vscode-extensions-removed.txt, dot_config/vscode-profiles/, .chezmoiignore, private_Library/private_Application Support/Code/User/settings.json, tests/vscode-profiles.bats |
| 1 | T2 installer | run_onchange_install-vscode-extensions.sh.tmpl, tests/install-failures.bats |
| 1 | T3 capture and wrapper | dot_local/bin/executable_vscode-extensions-capture, dot_config/zsh/functions.zsh, dot_local/bin/executable_dotfiles-sync, tests/vscode-extensions-capture.bats |
| 1 | T4 update | dot_local/bin/executable_vscode-extensions-update, tests/vscode-extensions-update.bats |
| 2 | T5 docs | README.md, _working-memory/dataContracts.md, tests/mutation-check.sh |

T1 is the contract: the file layout and the tombstone rules everything else reads. T2, T3 and T4 own disjoint files and build against it.

## Task T1: data split

**Files:** `dot_config/vscode-extensions.txt`, `dot_config/vscode-extensions-removed.txt`, `dot_config/vscode-profiles/web.txt`, `dot_config/vscode-profiles/embedded.txt`, `dot_config/vscode-profiles/docs.txt`, `.chezmoiignore`, `private_Library/private_Application Support/Code/User/settings.json`, `tests/vscode-profiles.bats` (new)

1. Write the three profile lists, each under a two-line header in the style of the default list's: `# VS Code extensions for the <name> profile, on top of vscode-extensions.txt` and `# Edit this list and run `chezmoi apply` to sync.` Ids follow, sorted with `sort -f`.
2. Remove the 18 ids from the default list and add `oxc.oxc-vscode`, keeping the existing header and `sort -f` order.
3. Add the 18 ids to the removed file, keeping its two header lines byte for byte and its sort order. `tests/vscode-extensions-capture.bats:533` (T3's file) pins that header, and the helper's `REMOVED_HEADER` constant has to match it, so neither changes in this run.
4. `.chezmoiignore`: add `.config/vscode-profiles` and `.config/vscode-profiles/**` beside `.config/vscode-extensions-removed.txt` at `:30`, under the existing comment.
5. `settings.json` per Decision 10.
6. `tests/vscode-profiles.bats` pins the data:
   - Every id in each profile list is absent from the default list.
   - No id appears in two of the three profile lists.
   - The default list holds `oxc.oxc-vscode` and none of `dbaeumer.vscode-eslint`, `esbenp.prettier-vscode`, `orta.vscode-jest`, `crystal-spider.jsdoc-generator`.
   - `web.txt` holds `dbaeumer.vscode-eslint` and `esbenp.prettier-vscode`.
   - Every id named in Decision 4 as leaving the default is in the removed file.
   - Every profile file name matches `^[a-z0-9-]+\.txt$`.
   - `chezmoi managed --source "$SRC"` prints no `vscode-profiles` path.
   - Default startup budget: take the ids that are in the default list and also installed (`~/.vscode/extensions/<id>-*/package.json`, matched case-insensitively). Fewer than 8 of them have `*` or `onStartupFinished` in `activationEvents`. Use `skip` with a reason when `~/.vscode/extensions` is absent, which keeps CI and fresh machines green. An id missing from disk counts as not starting, so the test also prints which ids it couldn't read.
   - `editor.defaultFormatter` in `settings.json` is `oxc.oxc-vscode`, read through the JSONC filter `theme` uses (`dot_config/font/jsonc.jq`, which `executable_theme:27` loads as `$CONFIG_HOME/font/jsonc.jq`).

## Task T2: per-profile installer

**Files:** `run_onchange_install-vscode-extensions.sh.tmpl`, `tests/install-failures.bats`

Keep every existing comment (the issue's out-of-scope rule) and the `failed=()` pattern.

1. **Hash headers.** Under the existing default-list hash line, add one line per profile list, each with the file's base name and its `sha256sum`, iterating the Verified fact 8 glob and skipping `-removed.txt` names with `hasSuffix`. Then add Decision 8's pending block. A profile file name that fails `regexMatch "^[a-z0-9-]+\\.txt$"` makes the render `fail` with the bad name.
2. **Embedding.** A bash array `profiles=( web embedded docs )`, rendered from the glob in glob order, and a `profile_list <name>` function: a `case` with one quoted heredoc per profile holding `{{ include . }}`, the same quoting as the default list's `EXTEOF`.
3. **Functions.**
   - `STORAGE="$HOME/Library/Application Support/Code/User/globalStorage/storage.json"` and `PROFILES_DIR="$HOME/Library/Application Support/Code/User/profiles"`.
   - `profile_registered <name>` is `jq -e --arg n "$1" '(.userDataProfiles // []) | any(.name == $n)'` on `$STORAGE`, false when the file is absent.
   - `register_profile <name>` per Decision 7 returns non-zero on any failure, and never leaves a temp file behind.
   - `install_into <profile> <list>` runs the existing loop. An empty profile means the default and passes no `--profile`. Otherwise it appends `--profile "$profile"` after `--force`, so `$2` stays the id for the existing stubs. A failure is recorded as `"$ext"` for the default and `"$ext ($profile)"` for a profile.
4. **Flow.**
   - Install the default list into the default profile, unchanged.
   - Then, for each profile: if registered, install the default list and then its own list into it. If unregistered and `pgrep -x Code` finds nothing, register it, then install. A failed register lands in `failed` as `profile <name>`. If unregistered and VS Code is running, add it to the pending set.
   - After the loop, write the pending set to the marker, or delete the marker when the set is empty. `mkdir -p` the marker's dir first.
   - When `jq` is absent, every profile is skipped with `step_warn "vscode ext" "jq not found, profiles skipped"`, and the default still installs.
   - `ext_total` counts every install the run will attempt for the default and registered or registrable profiles. Compute it after deciding which profiles go.
   - The summary keeps today's shape: `N of M refused` plus the list, or `M installed`. Pending profiles print their own line, Decision 8's.
5. **Tests**, in the existing `# ---- install-vscode-extensions ----` block.
   - The `code` stub logs `$*` to `$CALL_LOG`. A `pgrep` stub exits by `$PGREP_RC`. `/usr/bin/jq` stays reachable, since `PATH="$STUBS:/usr/bin:/bin"` already includes it.
   - Build a synthetic `$HOME/Library/Application Support/Code/User/globalStorage/storage.json` per case.
   - Update "one failure does not stop the rest" to expect one call per default id plus, for each profile, the default count plus that profile's count. Derive every count from the files, never a literal.
   - New cases:
     - A registered profile gets the default list and its own, each call carrying `--profile <name>`.
     - With VS Code closed, an unregistered profile is registered with `location` `chezmoi-<name>` and `useDefaultFlags.settings == true` (read back with jq). `profiles/chezmoi-<name>/` exists, and its installs run.
     - An existing `userDataProfiles` entry and every other top-level key in `storage.json` survive registration byte-equal. Compare with `jq -S` on the untouched keys.
     - With VS Code running (`PGREP_RC=0`), an unregistered profile gets no install calls, `storage.json` is unchanged, the marker names it, output contains `Quit VS Code`, and the status is 0.
     - An absent `storage.json` with VS Code closed is created holding all three profiles.
     - A marketplace refusal inside a profile is named as `<id> (<profile>)`, and the remaining ids in that profile are still attempted. This is the issue's acceptance case.
     - With no pending profiles, the marker is deleted.
     - The rendered script has a hash line per profile list, and has the pending line only when the marker exists. Render it twice with `HOME` pointed at a temp dir, with and without a marker file. Then assert in the consumer's units: rendering with the marker present and `pgrep` stubbed to each state gives two different scripts.
   - **Consumer case.** With real `chezmoi apply` under `--persistent-state`, follow `ui_apply_venue` in `tests/helpers.bash`, copying the template plus `dot_config/vscode-extensions*.txt` and `dot_config/vscode-profiles/`.
     - Apply 1, VS Code "running": pending written, no profile installs.
     - Apply 2, still running: it reruns once (the first render with the pending line) and makes no `--profile` call. Apply 2b, still running: it doesn't rerun, so `$CALL_LOG`'s line count is unchanged.
     - Apply 3, closed: it reruns, registers, installs, and deletes the marker.
     - Falsifier: delete the pending block from the copied template, and apply 3 does not rerun.
     - The template renders `output "sh" ... pgrep` at render time. Put the `pgrep` stub first on the `PATH` chezmoi itself runs under.

## Task T3: capture and wrapper

**Files:** `dot_local/bin/executable_vscode-extensions-capture`, `dot_config/zsh/functions.zsh`, `dot_local/bin/executable_dotfiles-sync`, `tests/vscode-extensions-capture.bats`

Keep the lock, the read-before-write ordering, `write_if_changed`, and the traps as they are.

1. **Interface.**
   - `vscode-extensions-capture [--profile <name>] [--removed <id> | --restored <id>]`. `--profile` takes a value and may come before or after the action. `--profile Default` means no profile.
   - An unknown profile name exits 0 after printing `profile <name> is not tracked, nothing recorded` to stderr. A profile is tracked when `$SRC/dot_config/vscode-profiles/<name>.txt` exists.
   - Usage errors keep exit 2.
2. **Every run merges every list.** First the default, exactly as today. Then each tracked profile, in `ls` order of `$SRC/dot_config/vscode-profiles/*.txt` minus `-removed.txt`, that is registered in `storage.json` (the same jq test as T2).
   - An unregistered profile is skipped and its files are left alone. This is the normal state of a machine that never applied, or that has a profile pending.
   - Each `code --list-extensions --profile <name>` runs before the lock, like today's default listing. A failure dies before any write, naming the profile.
   - When jq is absent, profiles are skipped with a stderr note, and the default still merges.
3. **Profile merge rule**, Decision 6, written as a comment above the code:
   `new = normalize( profile_list ∪ (installed_profile − default_removed) ) − default_merged − profile_removed`
   - `default_merged` is the default list this run just computed, so an id that's in the default never also sits in a profile list.
   - `profile_removed` is read from `<name>-removed.txt`, or is empty when the file is absent.
4. **Actions with `--profile <name>`.**
   - `--removed`: tombstone the id in `<name>-removed.txt`, creating it with its header (`# Extensions removed from the <name> VS Code profile on purpose. Capture never adds these back.`, then the restore line in the default removed file's style). Then merge, which drops the id from `<name>.txt`.
   - `--restored`: take the id out of `<name>-removed.txt` if present. Add it to `<name>.txt` explicitly, unless it's in `default_merged`, because Decision 6 keeps a default-tombstoned id out of the "installed" half.
   - Without `--profile`, actions behave as today.
5. **Errors.** Every grep filter that today ends `|| true` keeps status 1 and dies on status 2, the way `ids_of` does. That covers the two #80 sites at `:182` and `:198` and every new filter. This closes #80 too, so cite it in the commit message.
6. **Output.** Print `updated` once when any file changed, the same contract as today. `dotfiles-sync:195` prints `updated dot_config/vscode-extensions.txt`. Change that line to `updated VS Code extension lists`, and change nothing else in sync.
7. **Wrapper** (`functions.zsh` `code()`, `:146-161`). Scan the args once for `--profile <name>` and pass `--profile <name>` to `_code_record_extension`, which forwards it to the helper. Keep every existing rule: a failure records nothing, a `.vsix` path records nothing, a `@version` suffix is stripped, and failures are named on stderr.
8. **Tests** (new cases. The existing ones must stay green unchanged).
   - Register profiles through a synthetic `storage.json` in the `setup()` `$HOME`.
   - Make the `code` stub answer `--list-extensions --profile <p>` from `$INSTALLED_<p>`.
   - Cases:
     - An id installed only in `web` and absent from every list is added to `web.txt`.
     - An id in `web.txt` but not installed on this machine stays.
     - An id in the default list and installed in `web` stays out of `web.txt`.
     - A default-tombstoned id installed in `web` is not added to `web.txt`. A default-tombstoned id already in `web.txt` stays. These two together falsify Decision 6: drop the first rule and the first case fails, drop the second and the second fails.
     - `--removed x --profile web` creates `web-removed.txt` holding `x` and drops `x` from `web.txt`, leaving the default lists alone.
     - `--restored x --profile web` puts `x` in `web.txt` even while `x` is default-tombstoned.
     - An unregistered tracked profile's files are byte-identical after a run.
     - An untracked `--profile foo` writes nothing and exits 0.
     - A failing `--list-extensions --profile web` exits non-zero and writes no file, including the default list.
     - #80's two reproduction cases, from its issue body.
     - Wrapper: `code --uninstall-extension x --profile web` calls the helper with `--removed x` and `--profile web`. `code --install-extension x` with no profile passes no `--profile`.

## Task T4: update every profile

**Files:** `dot_local/bin/executable_vscode-extensions-update`, `tests/vscode-extensions-update.bats`

1. After the stamp check, run `code --update-extensions` for the default. Then run `code --update-extensions --profile <name>` for each `userDataProfiles` name in `storage.json` whose `location` doesn't start with `builtin/`. Updating hand-made profiles too is deliberate, since the issue says "every profile, not only the default".
2. Any failure means no stamp and exit 1, after the remaining profiles are still attempted. Name each failed profile on stdout as `    ! code --update-extensions failed for <name>`, with `default` for the default. Absent jq or an absent `storage.json` updates only the default and still stamps on success.
3. Update the header comment's first paragraph to say it updates every profile.
4. **Tests:**
   - Two registered profiles plus a `builtin/agents` entry produce three calls, the builtin one skipped.
   - One profile failing leaves the stamp untouched and still updates the others.
   - An absent `storage.json` produces one call and a stamp.
   - The existing cases stay green.

## Task T5: docs and suite registration

**Files:** `README.md`, `_working-memory/dataContracts.md`, `tests/mutation-check.sh`

1. `README.md` "Editor" section:
   - The three profiles and what each holds.
   - That every profile also gets the default list.
   - How to open a folder in one: `code --profile web <folder>`. VS Code remembers the folder-to-profile association after that.
   - The "quit VS Code and re-apply" note.
   - That eslint and prettier live in `web` as a fallback, while oxc is the default.
2. `dataContracts.md` "Extension lists" (`:45-46`):
   - Describe the profile lists and the per-profile removed files.
   - Describe the merge and tombstone rules (Decision 6) and the pending marker.
   - Fix the stale "full snapshot of installed extensions" sentence, which has been wrong since #75.
3. Add `tests/vscode-profiles.bats`, plus `tests/vscode-extensions-capture.bats` (missed by #75), to `ALL_FILES` in `tests/mutation-check.sh`, and update the count in the comment above it.

## Verification

- `bats tests/vscode-profiles.bats tests/install-failures.bats tests/vscode-extensions-capture.bats tests/vscode-extensions-update.bats` passes.
- `tests/mutation-check.sh` on each changed test file reports every assertion killed. Run it with `bash` if it's still mode 644 (#49).
- `bats tests/` exits 0.
- The plan's own falsifiers fail as stated:
  - Without the pending block, apply 3 doesn't rerun.
  - Without each Decision 6 rule, its capture case goes red.
  - Without `--profile` on the installer's profile calls, the per-profile case goes red.

**After merge, on this machine (a human, not the run):**

1. Quit VS Code, then run `chezmoi apply`. `~/Library/Application Support/Code/User/profiles` then holds `chezmoi-web`, `chezmoi-embedded`, and `chezmoi-docs`.
2. Uninstall the 18 ids from the default profile, with VS Code closed: `for x in <the 18>; do code --uninstall-extension "$x"; done`. The wrapper records each as a default tombstone it already has, so nothing in source changes. Run `git status`, which should be clean apart from auto-sync.
3. Open one window in the default profile, then measure the newest `exthost.log`. Count `_doActivateExtension` lines with `startup: true` plus those with `activationEvent: 'onStartupFinished'`, minus `vscode.*` ids. The count must be fewer than 8.
4. Watch a fresh log session's launches for `Extension host (LocalProcess) is unresponsive`. This one depends on the machine, so record what you see in the PR rather than gating the merge on it.
5. Open a web repo with `code --profile web <repo>` and check that eslint and prettier load there and oxc formats on save in the default.
6. Post the taxonomy comment on #45: Decision 1's reason, plus the eslint, prettier and oxc choice.

## Out of Scope

- Any change to `window.restoreWindows`, VS Code's update channel, or Gatekeeper.
- Profile UI state beyond the `useDefaultFlags` registration, such as per-profile themes, layouts and keybindings.
- Uninstalling anything from the installer (Decision 2).
- Per-profile checks in `dotfiles-doctor`. Its VS Code section keeps comparing the default profile against the default list.
- `raycast-extensions.txt`, and the npm and pnpm wrappers.
- Profiles created by hand in VS Code that have no tracked list. Capture and the installer ignore them, and only the update helper (T4) touches them.
