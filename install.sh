#!/bin/bash

printf "
       ●               ●           ◼︎ ◼︎   ◼︎   ◼︎
   ● ● ●     ● ●     ● ● ● ●     ◼︎           ◼︎     ◼︎ ◼︎       ◼︎ ◼︎ ◼︎
 ●     ●   ●     ●     ●       ◼︎ ◼︎ ◼︎ ◼︎   ◼︎   ◼︎   ◼︎ ◼︎ ◼︎ ◼︎   ◼︎ ◼︎
 ●     ●   ●     ●     ●         ◼︎       ◼︎   ◼︎   ◼︎             ◼︎ ◼︎
   ● ● ●     ● ●         ● ●     ◼︎       ◼︎   ◼︎     ◼︎ ◼︎ ◼︎   ◼︎ ◼︎ ◼︎

 ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ http://git.io/kdots ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦

"

DOTFILES_REPO="https://github.com/kendrick/dotfiles.git"

for UTIL in lib/*.sh; do
  source $UTIL
done

# Install Xcode first so we can use mas-cli to install from the App Store
./xcode/install.sh

# Ask for dotfiles directory
printf "Enter a name for your dotfiles directory. [Enter for '.dotfiles'] "
read DOTFILES_DIR

if [ -z "$DOTFILES_DIR" ]; then DOTFILES_DIR='.dotfiles'; fi
export DOTFILES_DIR=$HOME/$DOTFILES_DIR

# Check for existence of directory
if [ -d "$DOTFILES_DIR" ]; then
  # In a future update there should be 3 options:
  # 1) Use existing repo
  # 2) Delete existing repo
  # 3) Merge w/ upstream (below)
  git fetch upstream
  git checkout master
  git merge upstream/master
else
  exec_with_status "Cloning dotfiles repo" git clone -q $DOTFILES_REPO $DOTFILES_DIR
fi

cd $DOTFILES_DIR

# Create symlinks to dotfiles
symlink_files() {
  for FILE in ./[^.]**/\.[^.]*;
  do
    rm $HOME/$( basename $FILE )
    ln -s $DOTFILES_DIR/${FILE:2} $HOME/$( basename $FILE )
  done
}

exec_with_status "Creating symlinks to dotfiles" symlink_files

./homebrew/install.sh
./apt-get/install.sh
./app-settings/install.sh

./zsh/install.sh
./iterm2/install.sh
./javascript/install.sh
./ruby/install.sh

./macos/set-defaults.sh
./macos/dock-icons.sh
