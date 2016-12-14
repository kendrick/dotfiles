#!/usr/local/bin/bash

curl -sSL https://get.rvm.io | bash -s stable --rails
rvm use ruby --latest
bundle install --system
