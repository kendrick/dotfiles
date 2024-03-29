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

# Add pip packages to path if they exist
add_to_path $HOME/.local/bin

# Add mozjpeg to path
#add_to_path /usr/local/opt/mozjpeg/bin

# Path to your oh-my-zsh installation.
# export ZSH=$HOME/.oh-my-zsh

# Fix oh-my-zsh's horribly slow pasting:
# https://github.com/robbyrussell/oh-my-zsh/issues/6338
DISABLE_MAGIC_FUNCTIONS=true

# oh-my-zsh plugins
# plugins=(brew dircycle encode64 fasd gitfast git-flow-completion gulp jsontools npm osx zsh-autosuggestions zsh-syntax-highlighting)

# source $ZSH/oh-my-zsh.sh
# source /usr/local/share/zsh-history-substring-search/zsh-history-substring-search.zsh

# bindkey '^[[A' history-substring-search-up
# bindkey '^[[B' history-substring-search-down

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='code'
fi
