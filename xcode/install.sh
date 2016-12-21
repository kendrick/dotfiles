#!/usr/local/bin/zsh

xcode-select -p > /dev/null

if [ $? -ne 0 ]; then
  exec_with_status "Installing Xcode command line tools" xcode-select --install
  exec_with_status "Accepting Xcode license" sudo xcodebuild -license accept
else
  e_info "Xcode command line tools already installed; skipping."
fi
