DOTFILES=$HOME/.dotfiles

for UTIL ($DOTFILES/lib/*.sh) do
  source $UTIL
done

add_to_path /bin
add_to_path /usr/local/bin
add_to_path $DOTFILES/bin

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

# Add n to path if it exists
[[ -d $HOME/.n ]] && add_to_path $HOME/.n/bin

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
  export EDITOR='code'
fi

# added by travis gem
[ -f ~/.travis/travis.sh ] && source ~/.travis/travis.sh
