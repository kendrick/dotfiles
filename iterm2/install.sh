#!/usr/bin/env zsh

if [[ -f $(which fileicon) ]]; then
  fileicon set /Applications/iTerm.app \
  $DOTFILES/iterm2/iTerm2.icns
else
    echo "Installing \`fileicon\` via homebrew..."
    brew install fileicon
    fileicon set /Applications/iTerm.app \
    $DOTFILES/iterm2/iTerm2.icns
fi