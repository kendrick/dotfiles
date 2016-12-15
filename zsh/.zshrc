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

EMOJI_FAILURE="❌ "
EMOJI_SUCCESS="✅ "

# Include Z
. ~/.z.sh

# Include rvm
[[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"

# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# oh-my-zsh plugins
plugins=(bower brew dircycle encode64 fasd gitfast git-extras git-flow-completion grunt gulp jsontools npm osx)
ZSH_THEME="agnoster"

source $ZSH/oh-my-zsh.sh

export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$HOME/.rvm/bin"
export PATH="$PATH:/usr/local/Cellar/terminal-notifier/1.7.1/bin"

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='atom'
fi

# added by travis gem
[ -f ~/.travis/travis.sh ] && source ~/.travis/travis.sh
