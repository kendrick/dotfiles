#!/usr/local/bin/zsh

DOCKUTIL=$(which dockutil)
DOCKUTILADD="$DOCKUTILBIN --add"

killall Dock

# First, remove all items from the Dock

$DOCKUTIL --remove all

# Then, add in the apps that I prefer to have there:

$DOCKUTILADD /Applications/iTerm.app
$DOCKUTILADD /Applications/Sketch.app
$DOCKUTILADD /Applications/Tweetbot.app
$DOCKUTILADD /Applications/Messages.app
$DOCKUTILADD /Applications/Slack.app

$DOCKUTILADD '~' --view grid --display stack
$DOCKUTILADD '~/Downloads' --view fan --display stack
