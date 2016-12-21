#!/usr/local/bin/zsh

PACKAGES=$(< ./npm-global-packages.txt)

exec_with_status "Installing global npm packages" npm install -g $PACKAGES --quiet

# Ensure the latest stable version of Node is installed
if type "n" > /dev/null; then
  exec_with_status "Installing the latest version of node" n stable
fi
