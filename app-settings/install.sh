#!/bin/sh

# If $APP_SETTINGS_BACKUP_PATH & $APP_SETTINGS_BACKUP_DIR are non-zero, ask to
# start Dropbox & restore from mackup
DROPBOX_EXE=/Applications/Dropbox.app/Contents/MacOS/Dropbox
start_dropbox() {
  $DROPBOX_EXE > /dev/null &
  disown
}

if [ ! -z "$APP_SETTINGS_BACKUP_PATH" ] && [ ! -z "$APP_SETTINGS_BACKUP_DIR" ]; then
  printf "Environment variables indicate you may have backed up extended application settings at $APP_SETTINGS_BACKUP_PATH/$APP_SETTINGS_BACKUP_DIR.\n\n"

  if [ -e $DROPBOX_EXE ]; then
    printf "If they're synced up via Dropbox, press [D] to start the Dropbox sync client, or [S]kip: "
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
    printf "If you'd like to try to restore the settings in $APP_SETTINGS_BACKUP_PATH/$APP_SETTINGS_BACKUP_DIR, wait for that directory to sync and run [M]ackup to restore them, or [S]kip: "
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
