#!/usr/local/bin/zsh

PATH_TO_XCODE="/Applications/Xcode.app/Contents/MacOS/Xcode"

poll_for_xcode() {
  while [ ! -e "$PATH_TO_XCODE" ];
  do
    sleep 5
  done
}

# Install Xcode & the command line tools if they aren't already installed
if [ ! -e "$PATH_TO_XCODE" ]; then
  printf \
"Install the latest version of Xcode from the Mac App Store before continuing.
Launch the [A]pp Store, or [S]kip: "
  read WANT_XCODE
  WANT_XCODE=$( echo $WANT_XCODE | tr '[:upper:]' '[:lower:]' )
  case $WANT_XCODE in
    "a" )
      open "https://itunes.apple.com/us/app/xcode/id497799835"
      exec_with_status "Waiting for Xcode install" poll_for_xcode

      xcode-select -p > /dev/null

      if [ $? -ne 0 ]; then
        exec_with_status "Installing Xcode command line tools" xcode-select --install
        exec_with_status "Accepting Xcode license" sudo xcodebuild -license accept
      else
        e_info "Xcode command line tools already installed; skipping."
      fi
      ;;
    * )
      ;;
  esac
fi
