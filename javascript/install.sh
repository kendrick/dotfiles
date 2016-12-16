#!/usr/local/bin/zsh

PACKAGES=$(< ./npm-global-packages.txt)

npm install -g $PACKAGES --quiet

# Ensure the latest stable version of Node is installed
if type "n" > /dev/null; then
  n stable
else
  echo "n not found. 😵"
fi
