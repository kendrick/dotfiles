#!/bin/bash

if test "$(expr substr $(uname -s) 1 5)" = "Linux"
then
  curl -sL https://deb.nodesource.com/setup_7.x | sudo -E bash - nodejs
  sudo add-apt-repository ppa:aacebedo/fasd
  sudo apt-get update

  PACKAGES=$(tr '\n' ' ' < ./apt-packages.txt)

  exec_with_status "Installing apt packages" echo $PACKAGES | xargs sudo apt-get install -y
fi
