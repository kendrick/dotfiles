#!/bin/bash

cat > $HOME/.gitconfig <<'EOF'
# This .gitconfig was generated via ~/.dotfiles/git/gitconfig.sh.
# Edit that file to make changes to this .gitconfig!
[user]
  name = Kendrick Arnett
  email = kmarnett@gmail.com
[core]
  editor = "code --wait"
  excludesfile = ~/.gitignore
  pager = delta --diff-so-fancy | less --tabs=2 -RFX
[color]
  ui = always
[color "diff"]
  meta = yellow
  commit = green
  frag = magenta
  old = red
  new = green
  whitespace = red reverse
[color "diff-highlight"]
  oldNormal = red
  oldHighlight = red 52
  newNormal = green
  newHighlight = green 22
[color "branch"]
  current = yellow reverse
  local = yellow
  remote = green
[color "status"]
  added = yellow
  changed = green
  untracked = cyan
[delta]
  features = decorations
[decorations]
  commit-decoration-style = blue ol
[interactive]
  diffFilter = delta --color-only --features=interactive
[push]
  default = simple
  followTags = true
[url "https://"]
  insteadOf = git://
[alias]
  # Cobbled together from my existing .zshrc aliases and
  # http://durdn.com/blog/2012/11/22/must-have-git-aliases-advanced-examples/

  # DO IT LIVE!
  ac = !git add . && git commit -am

  # Show full diff of a given revision
  dr  = "!fn() { git diff "$1"^.."$1"; }; fn"
  lc  = "!fn() { git ll "$1"^.."$1"; }; fn"

  # History of a given file w/ diffs
  fl = log -u

  # Undo the last commit, keep changes
  un = "!git reset --soft HEAD^"

  # `log` variations...
  # Short form with branches/tags
  ls = log --pretty='format:"%C(yellow)%h%Cred%d %Creset%s%Cblue [%cn]"' --decorate
  # With relative time
  ld = log --pretty='format:"%C(yellow)%h %ad%Cred%d %Creset%s%Cblue [%cn]"' --decorate --date=relative
  # With graph
  lg = log --color --graph
  # With changed files
  ll =  log --pretty='format:"%C(yellow)%h%Cred%d %Creset%s%Cblue [%cn]"' --decorate --numstat

  # Files modified in last commit
  dl = "!git ll -1"

  # Diff of last commit
  dlc = diff --cached HEAD^
  fall = fetch --all -p

  # Find a file
  f = "!git ls-files | grep -i"

  # Find a string in any file
  gr = grep -Ii

  # List aliases
  la = "!git config -l | grep alias | cut -c 7-"
  ga = "!git la | grep"

  # Merge ours/theirs
  ours = "!fn() { git checkout --ours $@ && git add $@; }; fn"
  theirs = "!fn() { git checkout --theirs $@ && git add $@; }; fn"

  # Stashes
  sl = stash list
  sa = stash apply
  ss = stash save
  unstash = stash pop

  # Resets
  r = reset
  r1 = reset HEAD^
  r2 = reset HEAD^^
  rh = reset --hard
  rh1 = reset HEAD^ --hard
  rh2 = reset HEAD^^ --hard

  c="cz"
  ca="cz --amend"
  co="checkout"
  d="diff"
  s="status"
  sb="status -sb"
  a="add"
  b="branch"
  h="open"
  p="push"

  #nb = "!sh -c \"git checkout -b $(superb | tr ' ' '-' | tr -d '\\047')-$(pokemon | tr '[:upper:]' '[:lower:]' | tr ' ' '-')\""

[core]
  attributesfile = ~/.gitattributes
[diff]
  tool = meld
[diff "sketchtool"]
  textconv = "sketchtool dump"
  cachetextconv = true
  binary = true
[diff "spaceman-diff"]
  command = ~/.dotfiles/bin/spaceman-diff
[difftool]
  prompt = false
[difftool "meld"]
  trustExitCode = true
  cmd = open -W -a Meld --args \"$LOCAL\" \"$PWD/$REMOTE\"
[help]
  autocorrect = 1
[merge]
  tool = meld
[mergetool]
  prompt = false
  keepBackup = false
[mergetool "meld"]
  trustExitCode = true
  cmd = open -W -a Meld --args --auto-merge \"$PWD/$LOCAL\" \"$PWD/$BASE\" \"$PWD/$REMOTE\" --output=\"$PWD/$MERGED\"
[diff-so-fancy]
  stripLeadingSymbols = false
[filter "lfs"]
  clean = git-lfs clean -- %f
  smudge = git-lfs smudge -- %f
  process = git-lfs filter-process
  required = true
[init]
	defaultBranch = main
EOF

if [[ "$(uname)" == Darwin ]]; then
  CREDENTIAL_HELPER="osxkeychain"
else
  CREDENTIAL_HELPER="cache"
fi

if [[ -n "$CREDENTIAL_HELPER" ]]; then
  cat >> $HOME/.gitconfig <<EOF
[credential]
  helper = $CREDENTIAL_HELPER
EOF
fi
