#!/usr/local/bin/zsh

packages=$(< ./npm-global-packages.txt)

npm install -g $packages

# Ensure the latest stable version of Node is installed
if type "n" > /dev/null; then
  n stable
else
  echo "n not found. 😵"
fi
