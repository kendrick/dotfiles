# dotfiles

My macOS setup, managed by [chezmoi](https://chezmoi.io). One command gets a fresh Mac from zero to fully configured.

## New machine setup

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply kendrick
```

It'll ask whether this is a `work`, `client`, or `personal` machine, set the right git email, then install everything: Homebrew packages, VS Code extensions, Raycast extensions, macOS preferences, shell config.

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

### Scripts

Custom scripts in `~/.local/bin/` (which is on `$PATH`): `awssso`, `cless`, `cscreen`, `draw`, `e`, `imageoptim`, `imgmin`, `jd-git-init`, `overdrive`.

### macOS defaults

`defaults write` commands that run once on first setup. Mostly Finder, Dock, and screenshot behavior. I gutted the old Mathias Bynens script and kept only what still works on Sequoia.

### Other config

SSH config (1Password agent), Claude Code hooks, Claude Desktop config (excluded on client machines), GitHub CLI config, and the usual linting/formatting files (.editorconfig, .prettierrc, .stylelintrc, .eslintrc, .npmrc).

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

~/.local/share/chezmoi/       # source of truth (this repo)
```

## How the automation works

chezmoi runs scripts based on naming conventions:

- **`run_once_`** scripts run one time per machine. That's the Homebrew/Xcode install and the macOS defaults.
- **`run_onchange_`** scripts re-run whenever their content changes. Edit the Brewfile, the VS Code extension list, or the Raycast extension list, run `chezmoi apply`, and chezmoi picks up the diff and re-runs the relevant installer.
