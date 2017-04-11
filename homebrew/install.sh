#!/bin/bash

# Only install homebrew for macOS
if test "$(uname)" = "Darwin"
then
  # Check for Homebrew
  if test ! $(which brew)
  then
    e_header "Installing Homebrew"
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

    # TODO: Create 2 Brewfiles - 1 for macOS, 1 for Linux
    ln -s $DOTFILES/homebrew/Brewfile $HOME/Brewfile

    e_header "Updating Homebrew"
    brew update

    e_header "Tapping homebrew/bundle"
    brew tap homebrew/bundle

    e_header "Installing from Brewfile (this could take a while)"
    brew bundle

    e_header "Cleaning up Homebrew packages"
    brew cleanup
  else
    e_success "Homebrew already installed"
  fi
fi

exit 0
