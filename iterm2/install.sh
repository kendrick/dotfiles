#!/usr/local/bin/zsh

exec_with_status "Using a better iTerm icon" \
  fileicon set \
    /Applications/iTerm.app \
    $DOTFILES/iterm2/iTerm2.icns
