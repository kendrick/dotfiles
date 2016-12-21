#!/bin/sh

printf "
       ●               ●           ● ●   ●   ●
   ● ● ●     ● ●     ● ● ● ●     ●           ●     ● ●       ● ● ●
 ●     ●   ●     ●     ●       ● ● ● ●   ●   ●   ● ● ● ●   ● ●
 ●     ●   ●     ●     ●         ●       ●   ●   ●             ● ●
   ● ● ●     ● ●         ● ●     ●       ●   ●     ● ● ●   ● ● ●

 ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ http://git.io/kdots ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦ ◦

"

for UTIL in lib/*.sh; do
  source $UTIL
done

# Check for Xcode
if [ ! -e "/Applications/Xcode.app/Contents/MacOS/Xcode" ]; then
  printf "Install the latest version of Xcode from the Mac App Store before continuing. Launch the [A]pp Store, or [S]kip: "
  read WANT_XCODE
  WANT_XCODE=$( echo $WANT_XCODE | tr '[:upper:]' '[:lower:]' )
  case $WANT_XCODE in
    "a" )
      open "https://itunes.apple.com/us/app/xcode/id497799835"
      ;;
    * )
      ;;
  esac
fi

poll_for_xcode() {
  while [ ! -e "/Applications/Xcode.app/Contents/MacOS/Xcode" ];
  do
    sleep 5
  done
}
exec_with_status "Waiting for Xcode install" poll_for_xcode

DOTFILES_REPO="git@github.com:kendrick/dotfiles.git"

# Ask for dotfiles directory
printf "Enter a name for your dotfiles directory. [Enter for '.dotfiles'] "
read DOTFILES_DIR

if [ -z "$DOTFILES_DIR" ]; then DOTFILES_DIR='.dotfiles'; fi
DOTFILES_DIR=$HOME/$DOTFILES_DIR

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
./app-settings/install.sh

./zsh/install.sh
./iterm2/install.sh
./javascript/install.sh
./ruby/install.sh
./xcode/install.sh # Xcode commandline tools
