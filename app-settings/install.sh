#!/bin/sh

# If $APP_SETTINGS_BACKUP_PATH & $APP_SETTINGS_BACKUP_DIR are non-zero, ask to
# start Dropbox & restore from mackup
start_dropbox() {
  if [[ $PLATFORM == "Darwin" ]]; then
    DROPBOX_EXE=/Applications/Dropbox.app/Contents/MacOS/Dropbox
    $DROPBOX_EXE > /dev/null &
    disown
  elif [[ $PLATFORM == "Linux" ]]; then
    dropbox start > /dev/null &
    disown
    dropbox autostart > /dev/null &
    disown
  fi
}

e_header "Checking for extended app settings."
if [ ! -z "$APP_SETTINGS_BACKUP_PATH" ] && [ ! -z "$APP_SETTINGS_BACKUP_DIR" ]; then
  printf "Looks like you may have backed up extended application settings at $APP_SETTINGS_BACKUP_PATH/$APP_SETTINGS_BACKUP_DIR.\n\n"

  if [ -e $DROPBOX_EXE ] || test $(which dropbox); then
    printf "Press [D] to start the Dropbox sync client, or [S]kip: "
    read WANT_DROPBOX
    WANT_DROPBOX=$( echo $WANT_DROPBOX | tr '[:upper:]' '[:lower:]' )
    case $WANT_DROPBOX in
      "d" )
        start_dropbox
        e_success "Started Dropbox"
        ;;
      * )
        ;;
    esac
  else
    e_info "Didn't find Dropbox. Not restoring separate app settings."
  fi

  if test $(which mackup); then
    printf "\nTo restore the settings in $APP_SETTINGS_BACKUP_PATH/$APP_SETTINGS_BACKUP_DIR, wait for that directory to sync and run [M]ackup to restore them, or [S]kip: "
    read WANT_MACKUP
    WANT_MACKUP=$( echo $WANT_MACKUP | tr '[:upper:]' '[:lower:]' )
    case $WANT_MACKUP in
      "m" )
        exec_with_status "Restoring settings via Mackup" mackup restore
        ;;
      * )
        ;;
    esac
  else
    e_info "Didn't find Mackup. Not restoring extended app settings."
  fi
fi
