#!/usr/local/bin/zsh

PACKAGES=$(tr '\n' ' ' < ./npm-global-packages.txt)

exec_with_status "Installing global npm packages" echo $PACKAGES | xargs npm install -g --quiet

if test "$(uname)" = "Darwin"
then
  MACOS_PACKAGES=$(tr '\n' ' ' < ./npm-global-packages.macos.txt)
  exec_with_status "Installing macOS-specific npm packages" echo $MACOS_PACKAGES | xargs npm install -g --quiet
elif test "$(expr substr $(uname -s) 1 5)" = "Linux"
then
fi

# Ensure the latest stable version of Node is installed
if type "n" > /dev/null; then
  exec_with_status "Installing the latest version of node" n stable
fi
