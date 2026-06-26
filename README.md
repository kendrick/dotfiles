# dotfiles

My macOS setup, managed by [chezmoi](https://chezmoi.io). One command gets a fresh Mac from zero to fully configured.

## New machine setup

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply kendrick
```

It'll ask whether this is a `work`, `client`, or `personal` machine, set the right git email, then install everything: Homebrew packages, VS Code and Raycast extensions, macOS preferences, shell config, node and its global packages, and your agent skills.

A handful of Claude config files (`~/.claude/settings.json` and the plugin manifests) are age-encrypted, and the private key isn't in this public repo. The bootstrap fetches it from 1Password: a `run_before` script reads the age identity into `~/.config/chezmoi/key.txt`, as long as the 1Password app is unlocked with CLI integration on (Settings > Developer). chezmoi builds its ignore list before that script runs, so the encrypted files don't decrypt on the first pass; they land on the next apply:

```bash
chezmoi apply   # second pass deploys the now-decryptable Claude config
```

If 1Password isn't reachable, the script says so and the rest of the setup still finishes. To seed the key by hand instead:

```bash
mkdir -p ~/.config/chezmoi
op read "op://Personal/chezmoi age key/key.txt" > ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt
chezmoi apply
```

On a machine that's already set up:

```bash
chezmoi update    # pull latest + apply
```

## What's in here

### Shell (zsh)

Powerlevel10k prompt, Znap plugin manager, a pile of aliases I've accumulated over the years. The zsh config lives at `~/.config/zsh/` and gets sourced by `~/.zshrc`.

Files: `aliases.zsh`, `exports.zsh`, `functions.zsh`, `plugins.zsh`, `keybindings.zsh`, `options.zsh`, `styles.zsh`

### Git

A trimmed `.gitconfig` with delta as the pager, a reasonable set of aliases (the ones I actually use), and shell aliases for the `g`-prefixed versions (`gco`, `gd`, `gs`, etc.) in `~/.config/git/git-aliases.sh`.

The global gitignore lives at `~/.config/git/ignore`.

### Terminal

Ghostty. Config at `~/.config/ghostty/config`. Dark theme is Synthwave Everything, light theme is Light Owl, font is FantasqueSansM Nerd Font at 14px.

### Editor

VS Code settings, keybindings, and snippets deployed to `~/Library/Application Support/Code/User/`. Extensions managed via a text file list that chezmoi installs on apply.

### Apps

A Brewfile handles Homebrew formulae, casks, and Mac App Store apps. Some are conditional on machine role (Claude Desktop doesn't go on client machines, work-specific CLI tools only install on the work machine, etc.).

Raycast extensions are also managed via a text file list.

### Node

Node runs through nvm (installed by Homebrew). nvm ships without a node of its own, so the bootstrap installs one and floors the default at 24, which is what current npm and pnpm expect; it also turns on pnpm through corepack. Global packages come from two lists, `~/.config/npm-globals.txt` and `~/.config/pnpm-globals.txt`, which the `npm` and `pnpm` shell wrappers re-add whenever you install or remove a global.

### Scripts

Custom scripts in `~/.local/bin/` (which is on `$PATH`): `awssso`, `cless`, `cscreen`, `dotfiles-doctor`, `dotfiles-sync`, `draw`, `e`, `imageoptim`, `imgmin`, `jd-git-init`, `overdrive`.

`dotfiles-sync` and `dotfiles-doctor` handle syncing changes between machines (see [Keeping machines in sync](#keeping-machines-in-sync)).

### macOS defaults

`defaults write` commands that run once on first setup. Mostly Finder, Dock, and screenshot behavior. I gutted the old Mathias Bynens script and kept only what still works on Sequoia.

### Other config

SSH config (1Password agent), Claude Code hooks, Claude Desktop config (excluded on client machines), GitHub CLI config, and the usual linting/formatting files (.editorconfig, .prettierrc, .stylelintrc, .eslintrc, .npmrc).

### Agent skills

Skills for Claude Code and other agents are managed with [`skills`](https://github.com/vercel-labs/skills) (`npx skills`). `npx skills add <repo>` pulls a skill from a GitHub repo, drops it in `~/.agents/skills/`, and symlinks it into each agent's directory (`~/.claude/skills/` and the rest).

The repo tracks the lockfile, not the skill bodies. The skills themselves live in their source repos and re-fetch on demand; `~/.local/state/skills/.skill-lock.json` records which ones, each pinned to a content hash. A `skills` shell function in `functions.zsh` wraps the CLI so any `add`, `remove`, or `update` re-adds that lockfile into chezmoi right then, so the manifest stays current on its own.

Not everything under a `.claude/skills/` directory is user-level, though. This repo's own `.claude/skills/` holds the working-memory skills (`hydrate-*`, `update-working-memory`), which are project-scoped and never deploy to `~/.claude` or go through `npx skills`. The npx-managed skills above are the global set; the repo-local `.claude/` toolkit is separate, and loads only when you work in this repo.

Restore runs on its own. A `run_after` script replays the lockfile on a new machine: it diffs `.skill-lock.json` against what's in `~/.agents/skills/` and re-adds anything missing straight from its source repo, so a fresh machine ends up with the same set without any hand-run `npx skills add`. It's keyed off the lockfile, so adding a skill on one machine reinstalls it on the others at the next `chezmoi update`. The private `kendrick/*` repos prompt for `gh` auth rather than skipping. One limit worth knowing: the CLI can't restore to a pinned hash, so each skill comes back at its source's latest, and an upstream change rides along with it. The lockfile also only captures what went through the shell function, so a skill installed some other way won't show up, and it's worth a reconcile pass now and then.

## Machine roles

chezmoi prompts for a role on first init:

| Role | Git email | What's different |
|------|-----------|-----------------|
| `work` | prompted | AWS CLI tools, work-specific brew packages, Claude Desktop |
| `client` | prompted | Minimal. No Claude Desktop, no work-specific packages |
| `personal` | kmarnett@gmail.com | Screen Studio, superwhisper, codex |

The role and email are stored locally in `~/.config/chezmoi/chezmoi.toml` and never committed to the repo.

## Making changes

```bash
# Edit a managed file, then pull changes back into chezmoi
vim ~/.config/zsh/aliases.zsh
chezmoi re-add ~/.config/zsh/aliases.zsh

# Or edit the source directly
chezmoi edit ~/.config/zsh/aliases.zsh
chezmoi apply

# Add a brew package
chezmoi edit ~/.config/Brewfile
chezmoi apply   # triggers brew bundle automatically

# Add a VS Code extension
chezmoi edit ~/.config/vscode-extensions.txt
chezmoi apply   # installs it

# Add a Raycast extension
chezmoi edit ~/.config/raycast-extensions.txt
chezmoi apply   # opens raycast://extensions/install/...

# Commit and push
chezmoi cd
git add -A && git commit -m "whatever"
git push
```

## Keeping machines in sync

The repo is the source of truth. Make a change on one machine, push it up, pull it down on the others.

```bash
# on the machine where you changed something
dotfiles-sync

# on every other machine
chezmoi update
```

`dotfiles-sync` regenerates the VS Code extension list from what's installed, re-adds every changed managed file in one pass (settings, zsh, git config, and the rest), flags any Homebrew packages that aren't in the Brewfile yet, then commits and pushes. It won't touch the Brewfile itself, on purpose: the Brewfile is a template with machine-role conditionals, and dumping a flat list over it would wipe those out. Raycast extensions stay manual for a similar reason, since there's no CLI to list what's installed.

One catch: `chezmoi update` only adds. If you remove an extension or uninstall a package on one machine, the others keep it, because the extension and package lists are additive. That's what `dotfiles-doctor` is for:

```bash
dotfiles-doctor    # read-only; run it after chezmoi update
```

It lists anything installed locally that isn't in your dotfiles (either something you installed ad-hoc and want to keep, or something you removed elsewhere and should uninstall here), plus anything in your lists that isn't installed yet. It changes nothing. You decide what to act on.

## Layout

```
~/.config/
├── chezmoi/chezmoi.toml     # local-only, never committed
├── ghostty/config
├── gh/config.yml
├── git/ignore, .gitattributes, git-aliases.sh
├── zsh/aliases, exports, functions, plugins, ...
├── Brewfile
├── raycast-extensions.txt
└── vscode-extensions.txt

~/.local/bin/                 # custom scripts

~/.agents/skills/             # agent skills, installed by the `skills` CLI
~/.local/state/skills/        # .skill-lock.json, the tracked skills manifest

~/.local/share/chezmoi/       # source of truth (this repo)
```

## How the automation works

chezmoi runs scripts based on naming conventions:

- **`run_once_`** scripts run one time per machine. That's the Homebrew/Xcode install and the macOS defaults.
- **`run_onchange_`** scripts re-run whenever their content changes. Edit the Brewfile, the VS Code extension list, or the Raycast extension list, run `chezmoi apply`, and chezmoi picks up the diff and re-runs the relevant installer.
- **`run_before_`** and **`run_after_`** set ordering around the file-copy step. The age-key fetch is a `run_before` so the key is in place before chezmoi decrypts; node setup, Claude plugins, and the skill restore are `run_after`, since they need Homebrew and node from the package step.
