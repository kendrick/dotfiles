#!/usr/local/bin/zsh

e_header "Installing rvm"
curl -sSL https://get.rvm.io | bash -s stable --rails

e_header "Installing ruby --latest"
rvm use ruby --latest

e_header "Installing system gems"
bundle install --system
