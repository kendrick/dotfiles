#!/bin/bash

# Check for Homebrew
if test ! $(which brew)
then
  # Install the correct homebrew for each OS type
  if test "$(uname)" = "Darwin"
  then
    exec_with_status "Installing Homebrew" \
      ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  elif test "$(expr substr $(uname -s) 1 5)" = "Linux"
  then
    exec_with_status "Installing Homebrew" \
      ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Linuxbrew/install/master/install)"
  fi
else
  e_success "Homebrew already installed"
fi

ln -s Brewfile $HOME/Brewfile

exec_with_status "Updating Homebrew" brew update
exec_with_status "Tapping homebrew/bundle" brew tap homebrew/bundle
exec_with_status "Installing from Brewfile (this could take a while)" brew bundle
exec_with_status "Cleaning up Homebrew packages" brew cleanup

exit 0
