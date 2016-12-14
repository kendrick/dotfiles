#!/bin/bash

# Use Homebrew's zsh by default
sudo dscl . -create /Users/$USER UserShell /usr/local/bin/zsh

# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
