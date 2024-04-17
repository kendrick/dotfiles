export DOTFILES=$HOME/.dotfiles

# for UTIL ($DOTFILES/lib/*.sh) do
#   source $UTIL
# done

# add_to_path /bin
export PATH=$PATH:$DOTFILES/bin

# oh-my-zsh plugins
# plugins=(brew dircycle encode64 fasd gitfast git-flow-completion gulp jsontools npm osx zsh-autosuggestions zsh-syntax-highlighting)

# source $ZSH/oh-my-zsh.sh
# source /usr/local/share/zsh-history-substring-search/zsh-history-substring-search.zsh

# bindkey '^[[A' history-substring-search-up
# bindkey '^[[B' history-substring-search-down

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='code'
# fi
