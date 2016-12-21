#!/usr/local/bin/zsh

exec_with_status "Installing rvm" \
  curl -sSL https://get.rvm.io | bash -s stable --rails
exec_with_status "Installing ruby --latest" rvm use ruby --latest
exec_with_status "Installing system gems" bundle install --system
