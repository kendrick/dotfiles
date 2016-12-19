DOTFILES=$HOME/.dotfiles

# Source ALLTHETHINGS
for CONFIG_FILE ($DOTFILES/**/*.zsh) do
  source $CONFIG_FILE
done

# Keep secret stuff in .localrc that you
# don't want in your public, versioned repo
if [[ -a $HOME/.localrc ]]
then
  source $HOME/.localrc
fi

DEFAULT_USER='kmarnett'

APP_SETTINGS_BACKUP_PATH=$HOME/Dropbox
APP_SETTINGS_BACKUP_DIR='app-settings'

ICON_FAILURE="❌ "
ICON_SUCCESS="✅ "
ICON_WARNING="⚠️ "
ICON_INFO="ℹ️ "

# Include rvm
[[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"

# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# oh-my-zsh plugins
plugins=(bower brew dircycle encode64 fasd gitfast git-extras git-flow-completion grunt gulp jsontools npm osx)
ZSH_THEME="agnoster"

source $ZSH/oh-my-zsh.sh

export PATH="$PATH:/usr/local/bin:$DOTFILES/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.rvm/bin"

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='atom'
fi

# added by travis gem
[ -f ~/.travis/travis.sh ] && source ~/.travis/travis.sh
