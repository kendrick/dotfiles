#!/usr/bin/env zsh

killall Dock

dockutil --remove all

dockutil --add /Applications/Firefox.app
dockutil --add "/Applications/Google Chrome.app"
dockutil --add /Applications/Slack.app
dockutil --add "/Applications/Visual Studio Code.app"
dockutil --add /Applications/Notion.app
dockutil --add /Applications/Figma.app
dockutil --add /Applications/iTerm.app

# Add a li'l spacer
defaults write com.apple.dock persistent-apps -array-add '{"tile-type"="small-spacer-tile";}' && killall Dock

dockutil --add /Applications/Spotify.app
dockutil --add /System/Applications/Messages.app

dockutil --add '~' --view grid --display stack
dockutil --add '~/Downloads' --view fan --display stack
