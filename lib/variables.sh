export DEFAULT_USER='kmarnett'
export DOTFILES=$HOME/.dotfiles

export APP_SETTINGS_BACKUP_PATH=$HOME/Dropbox
export APP_SETTINGS_BACKUP_DIR='app-settings'

export ICON_FAILURE="❌ "
export ICON_SUCCESS="✅ "
export ICON_WARNING="⚠️ "
export ICON_INFO="ℹ️ "

for VARIABLES ($DOTFILES/*/variables.sh) do
  case $VARIABLES in
    *lib/variables.sh* ) continue;; # Avoid infinite recursion
    *) source $VARIABLES;;
  esac
done
