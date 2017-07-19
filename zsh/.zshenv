DOTFILES=$HOME/.dotfiles

for UTIL ($DOTFILES/lib/*.sh) do
  source $UTIL
done

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

add_to_path /bin
add_to_path $DOTFILES/bin

# Add pip packages to path if they exist
[[ -d $HOME/.local/bin ]] && add_to_path $HOME/.local/bin

# Include rvm
[[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"

# Path to your oh-my-zsh installation.
export ZSH=$HOME/.oh-my-zsh

# oh-my-zsh plugins
plugins=(bower brew dircycle encode64 fasd gitfast git-extras git-flow-completion grunt gulp jsontools npm osx zsh-syntax-highlighting)
ZSH_THEME="agnoster"

source $ZSH/oh-my-zsh.sh
source /usr/local/share/zsh-history-substring-search/zsh-history-substring-search.zsh

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='atom'
fi

$(which gem && gem which lunchy) >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  LUNCHY_DIR=$(dirname `gem which lunchy`)/../extras
  if [ -f $LUNCHY_DIR/lunchy-completion.zsh ]; then
    . $LUNCHY_DIR/lunchy-completion.zsh
  fi
fi

# added by travis gem
[ -f ~/.travis/travis.sh ] && source ~/.travis/travis.sh
