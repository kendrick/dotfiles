#!/usr/local/bin/zsh

xcode-select -p > /dev/null

if [ $? -ne 0 ]; then
  xcode-select --install
  sudo xcodebuild -license accept
  e_success "Xcode command line tools successfully installed."
else
  e_info "Xcode command line tools already installed; skipping."
fi
