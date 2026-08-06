# dotfiles

One command takes a fresh Mac from zero to fully configured, managed with [chezmoi](https://chezmoi.io).

## Contents

- [Setup](#setup)
- [Daily Use](#daily-use)
- [What's Here](#whats-here)
- [Machine Roles](#machine-roles)
- [Keeping Machines in Sync](#keeping-machines-in-sync)
- [Gotchas](#gotchas)
- [How the Automation Works](#how-the-automation-works)
- [Layout](#layout)

## Setup

### New Machine

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply --use-builtin-git=on kendrick
```

Don't drop the `--use-builtin-git=on`. A factory Mac needs it, for the reason under [Gotchas](#gotchas).

It prompts for the machine role (`work` / `client` / `personal`) and an auto-sync schedule, sets the git email to match, then installs the lot: Homebrew packages, VS Code and Raycast extensions, macOS preferences, shell config, node and its globals, and the agent skills.

> [!NOTE]
> **The encrypted Claude config needs a second apply.** `~/.claude/settings.json` and the plugin manifests are age-encrypted, and the key isn't in this public repo. A `run_before` script pulls it from 1Password into `~/.config/chezmoi/key.txt`: it installs the 1Password app and the CLI, opens the app, and waits up to ten minutes while you sign in and switch on Settings > Developer > Integrate with 1Password CLI. That toggle is the one step nothing can automate. chezmoi builds its ignore list _before_ that script runs, so the encrypted files don't decrypt on the first pass regardless. They land on the next one:
>
> ```bash
> chezmoi apply   # second pass deploys the now-decryptable Claude config
> ```
>
> No 1Password on hand? Let the wait time out, or run the bootstrap non-interactively and it won't wait at all. Either way the rest of setup still finishes. To seed the key by hand: `op read "op://Personal/chezmoi age key/key.txt" > ~/.config/chezmoi/key.txt && chmod 600 ~/.config/chezmoi/key.txt && chezmoi apply`.

### Existing Machine

```bash
chezmoi update    # pull latest, then apply
```

## Daily Use

The loop for changing a managed file:

```bash
chezmoi edit ~/.config/zsh/aliases.zsh   # edit the source
chezmoi apply                            # deploy it
```

Or edit the live file and pull it back with `chezmoi re-add ~/.config/zsh/aliases.zsh`. Editing the package registry, the VS Code list, or the Raycast list and running `chezmoi apply` re-runs the matching installer on its own.

To capture and commit in one step, skip the manual `chezmoi cd && git commit` and run `dotfiles-sync` instead (see [Keeping Machines in Sync](#keeping-machines-in-sync)).

## What's Here

| Area         | What                                                                                               | Where                                           |
| ------------ | -------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| Shell (zsh)  | Powerlevel10k prompt, Znap plugin manager, aliases/functions/exports                               | `~/.config/zsh/`, sourced by `~/.zshrc`         |
| Git          | delta pager, the aliases I actually use, `g*` shell shortcuts (`gco`, `gd`, `gs`)                  | `~/.config/git/`, `~/.gitconfig`                |
| Terminal     | Ghostty. Synthwave Everything (dark), Light Owl (light); FantasqueSansM Nerd Font 14px             | `~/.config/ghostty/config`                      |
| Editor       | VS Code settings, keybindings, snippets; extensions from a tracked text list                       | `~/Library/Application Support/Code/User/`      |
| Apps         | Formulae, casks, and Mac App Store apps, each filed into bundles a machine opts into               | `.chezmoidata.toml`                             |
| Node         | nvm (via Homebrew), default floored at 24, pnpm through corepack, two globals lists                | `~/.config/npm-globals.txt`, `pnpm-globals.txt` |
| Scripts      | custom bins on `$PATH`                                                                             | `~/.local/bin/`                                 |
| macOS        | one-time `defaults write` for Finder, Dock, screenshots                                            | `run_once_after_configure-macos.sh`             |
| Agent skills | Claude/agent skills via `npx skills`, tracked by a lockfile                                        | `~/.agents/skills/`                             |
| Other config | SSH (1Password agent), Claude Code hooks, gh, and the usual editorconfig/prettier/stylelint/eslint | across `~/.config/`                             |

<details>
<summary>Scripts in <code>~/.local/bin</code></summary>

`awssso`, `cless`, `cscreen`, `dotfiles-apps`, `dotfiles-doctor`, `dotfiles-sync`, `dotfiles-teardown`, `dotfiles-undo`, `draw`, `e`, `font`, `imageoptim`, `imgmin`, `jd-git-init`, `overdrive`

</details>

<details>
<summary>How agent skills are managed</summary>

`npx skills add <repo>` pulls a skill into `~/.agents/skills/` and symlinks it into each agent's directory. The repo tracks the lockfile, not the skill bodies. `~/.local/state/skills/.skill-lock.json` records which skills, each pinned to a content hash. A `skills` shell wrapper re-adds that lockfile into chezmoi on every `add`/`remove`/`update`, so the manifest stays current on its own. On a new machine, a `run_after` script replays the lockfile and re-fetches anything missing.

The restore targets a named list of agents (`claude-code`, `codex`), set as an `AGENTS` array in `run_onchange_after_restore-agent-skills.sh.tmpl`. Add an agent there and the next apply backfills it from the lockfile. Passing `-a '*'` instead would reach every agent the CLI knows about, currently 75, a couple of which don't do global skills and say so once per skill.

This repo's own `.claude/skills/` is separate: it holds the project-scoped working-memory skills (`hydrate-*`, `update-working-memory`), which never deploy to `~/.claude` or go through `npx skills`.

</details>

## Machine Roles

chezmoi prompts for a role on first init. Role and email live in `~/.config/chezmoi/chezmoi.toml` and never hit the repo. The role still drives a few things directly—the auto-sync default, whether `awssso` gets deployed—but for packages it only picks a starting set of bundles.

### Package Bundles

Every package in `.chezmoidata.toml` declares which bundles it belongs to, and a machine installs the union of the bundles it has turned on. `.chezmoitemplates/Brewfile` renders a Brewfile from that on each apply; there's no flat list to maintain.

| Bundle          | What's in it                                                            |
| --------------- | ----------------------------------------------------------------------- |
| `core`          | the CLI base, 1Password, Ghostty, Raycast, VS Code, Slack, Zoom         |
| `fonts`         | the `font` command's roster, all 13 casks                               |
| `dev`           | toolchains and build tools: go, nvm, cmake, pre-commit                  |
| `browsers`      | Brave, Chrome, Edge, Firefox                                            |
| `media`         | ffmpeg, ImageMagick, Tesseract, Spotify, Shottr, superwhisper           |
| `office`        | pandoc, marp, Grammarly, Obsidian, TickTick                             |
| `ai`            | Claude, Claude Code, Conductor, MacWhisper                              |
| `personal-apps` | LibreOffice, Notion, Reader                                             |
| `cloud`         | AWS, Azure, and Databricks CLIs, plus Deskflow and Zappy                |

Roles seed the list:

| Role       | Bundles on by default                                          |
| ---------- | -------------------------------------------------------------- |
| `client`   | `core fonts dev browsers media office`                         |
| `personal` | those, plus `ai personal-apps`                                 |
| `work`     | all nine                                                       |

`chezmoi init` prompts for the list with the role's defaults preselected, and writes the answer to `bundles` under `[data]` in `~/.config/chezmoi/chezmoi.toml`. The seed is only a starting point: edit that list and re-apply, and a client machine that wants LibreOffice this one time can have it without touching the repo. Because the answer lives in config, a re-apply reproduces it and `dotfiles-doctor` reconciles against it.

A machine that hasn't re-run `chezmoi init` since bundles landed has no `bundles` key, so it falls back to its role's defaults and installs exactly what it did before. chezmoi will warn on every apply that the config template changed; `chezmoi init` once clears it and keeps every other answer you already gave.

Moving a package between bundles is a repo edit, in `.chezmoidata.toml`. It affects every machine, which is the point.

`dotfiles-apps` does all of this without hand-editing TOML: the bare command moves packages between bundles, `--adopt` files installed-but-untracked packages into one, and `--machine` picks which bundles this machine installs. It keeps the repo edit and the local edit on separate screens, because they look alike and don't mean the same thing. It writes, shows you the diff, and stops; you run `chezmoi apply` yourself.

## Keeping Machines in Sync

The repo is the source of truth. Change something on one machine, push it, pull it down on the others.

| Command             | What it does                                                                                                                             | When to run it                                 |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `dotfiles-sync`     | regenerates the VS Code list, re-adds every changed managed file, flags installed packages the registry doesn't track, then commits and pushes | on the machine you changed                     |
| `chezmoi update`    | pull, then apply                                                                                                                         | on every other machine                         |
| `dotfiles-doctor`   | read-only drift report: installed-but-untracked, tracked-but-not-installed, and configs naming a font no enabled bundle installs         | after a `chezmoi update`                       |
| `dotfiles-apps`     | move packages between bundles, adopt untracked ones, or pick which bundles this machine installs                                          | when an app is in the wrong place              |
| `dotfiles-undo`     | panic button that reverts the most recent `[auto-sync]` commit and pushes the revert                                                     | when auto-sync captured something it shouldn't |
| `dotfiles-teardown` | removes the secrets, and with `--full` the dotfiles and the repo too                                                                     | when handing a client machine back             |

### Scheduled Auto-Sync

A launchd agent runs `dotfiles-sync` on a schedule picked at init (each role has a default). Times live in `chezmoi.toml` under `[data.sync_times]`; edit them and `chezmoi apply` to reschedule.

| Preset    | Times               | Default for |
| --------- | ------------------- | ----------- |
| `workday` | 10:00, 16:00        | `work`      |
| `evening` | 16:00, 22:00        | `personal`  |
| `both`    | 10:00, 16:00, 22:00 | opt-in only |
| `off`     | none                | `client`    |

The scheduled run is push-only and never applies anything on its own. If the remote has moved ahead, it skips the push and fires a macOS notification telling you to `chezmoi update` first, so nothing lands behind your back.

## Teardown

Handing a machine back:

```bash
dotfiles-teardown              # dry run, shows exactly what would go
dotfiles-teardown --yes        # secrets only
dotfiles-teardown --full --yes # plus the dotfiles, the sync agent, and the repo
dotfiles-teardown --verify RECEIPT   # confirm a previous run actually cleaned up
```

Dry run is the default and the list it prints is the list it removes, so read it before adding `--yes`. Neither level touches Homebrew, the apps it installed, the macOS defaults, or `~/.nvm`.

`--full` has two extra gates, because it purges the repo. It refuses to run while the source has uncommitted or unpushed work, since that work is the one thing here you can't get back (`--force-dirty` overrides). And it asks you to type the hostname rather than accepting a `y`.

Every run that removes something writes a receipt listing the paths it took, to `~/dotfiles-teardown-<timestamp>.txt` unless you pass `--receipt`. Feed it back with `--verify` to confirm each path is gone. That's the only way to audit a `--full` run: by then chezmoi and the source tree are gone, so the list can't be rebuilt. The receipt records paths, not contents, but it's still a map of where the secrets were, so move it off the machine if that matters.

What counts as sensitive is derived rather than listed. Encrypted targets come straight from `chezmoi managed --include=encrypted`, so anything you encrypt later is covered without touching the teardown script. What chezmoi can't see, like the gh token or the AWS SSO cache, is declared by whichever script creates it:

```bash
# teardown:secret ~/.config/gh/hosts.yml
# teardown:data ~/.agents/skills
```

`secret` goes at the default level, `data` only under `--full`, and `none` is how a script says it leaves nothing behind. `dotfiles-doctor` flags any `run_` script that declares nothing, which is what keeps the list from quietly falling behind the repo.

One thing it can't do: the `quantified_claude_events` deploy key gets deleted from disk, but that doesn't revoke it on GitHub. The script prints the `gh repo deploy-key delete` command; you have to run it.

## Gotchas

The things I'll have forgotten by next quarter:

- **A factory Mac has a fake git, and it takes the bootstrap down with it.** `/usr/bin/git` on a machine with no Command Line Tools is a stub that fires the CLT installer and exits 1. chezmoi's `useBuiltinGit` defaults to `auto`, which only checks whether `git` is on `$PATH`. The stub is, so chezmoi reaches for it and the clone dies before a single script has run. That's what `--use-builtin-git=on` is for: it routes the first clone through chezmoi's own Go git. Only that first clone needs it, since by the time you're running `chezmoi update` there's a real git.
- **The encrypted Claude config takes two applies.** First pass can't decrypt it; the second one can. See the setup note above.
- **The extension and package lists are additive.** `chezmoi update` only adds, so removing a package on one machine leaves the others untouched. `dotfiles-doctor` is what surfaces the drift.
- **There's no Brewfile to edit.** It's rendered from `.chezmoidata.toml` on every apply. `dotfiles-sync` still won't write the registry on its own: which bundles a package belongs to is a judgement call, and a `brew bundle dump` has no way to make it.
- **Raycast extensions stay manual.** There's no CLI to list what's installed.
- **The skills lockfile only tracks what went through the `skills` wrapper**, and restore always pulls each skill at its source's latest (no pinned-hash restore), so an upstream change can ride along. Worth a reconcile pass now and then.

## How the Automation Works

chezmoi runs scripts based on naming conventions:

| Prefix                       | Runs                                  | Used for                                                            |
| ---------------------------- | ------------------------------------- | ------------------------------------------------------------------- |
| `run_once_`                  | once per machine                      | Homebrew/Xcode install, macOS defaults                              |
| `run_onchange_`              | whenever the script's content changes | packages, VS Code + Raycast lists, node globals                     |
| `run_before_` / `run_after_` | around the file-copy step             | age-key fetch (before); node, Claude plugins, skill restore (after) |

## Layout

```
~/.config/
├── chezmoi/chezmoi.toml        # local only, never committed
├── ghostty/config
├── gh/config.yml
├── git/                        # ignore, gitattributes, git-aliases.sh
├── zsh/                        # aliases, exports, functions, plugins, ...
├── npm-globals.txt, pnpm-globals.txt
├── raycast-extensions.txt
└── vscode-extensions.txt

~/.local/bin/                   # custom scripts
~/.agents/skills/               # agent skills, installed by the skills CLI
~/.local/state/skills/          # .skill-lock.json, the tracked manifest
~/.local/share/chezmoi/         # source of truth (this repo)
```

Packages are the exception. They live in the source repo at `.chezmoidata.toml`, not under `~/.config/`, because the installer renders a Brewfile from them inline rather than deploying one as a dotfile.

---

_Personal setup, unlicensed—borrow anything useful. Last reviewed 2026-07-10._
