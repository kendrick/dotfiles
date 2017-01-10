#!/bin/bash

# Only install homebrew for macOS
if test "$(uname)" = "Darwin"
then
  # Check for Homebrew
  if test ! $(which brew)
  then
    exec_with_status "Installing Homebrew" \
      ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"

    # TODO: Create 2 Brewfiles - 1 for macOS, 1 for Linux
    ln -s $DOTFILES_DIR/Brewfile $HOME/Brewfile

    exec_with_status "Updating Homebrew" brew update
    exec_with_status "Tapping homebrew/bundle" brew tap homebrew/bundle
    exec_with_status "Installing from Brewfile (this could take a while)" brew bundle
    exec_with_status "Cleaning up Homebrew packages" brew cleanup
  else
    e_success "Homebrew already installed"
  fi
fi

exit 0
