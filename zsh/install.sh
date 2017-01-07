#!/usr/local/bin/bash

# Use Homebrew's zsh by default
exec_with_status "Changing default shell to zsh"\
  sudo dscl . -create /Users/$USER UserShell /usr/local/bin/zsh

# If Linux, `chsh -s /usr/local/bin/zsh` instead

# Install oh-my-zsh
exec_with_status "Installing oh-my-zsh" \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
