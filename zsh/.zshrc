alias changelog='conventional-changelog -p angular -i CHANGELOG.md -s'
alias gc='git cz'
alias h='history'
alias ssid='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '"'"'/ SSID/ {print substr($0, index($0, $2))}'"'"''
alias dfh='ssh kendrick@designedforhumans.co'
alias bulkerase='drutil bulkerase quick'
alias ws='wstorm'
alias o='open .' # Open '.' in Finder
alias cls='clear && fortune | cowsay | lolcat'
alias cdg='cd ~/Dropbox/dev/git-repos'
alias jshint='jshint --reporter /usr/local/lib/node_modules/jshint-stylish/stylish.js'
alias rmdstore="find . -name '*.DS_Store' -type f -delete"
alias gs='git status'
alias ga='git add'
alias gca='git cz --amend'
alias gb='git branch'
alias gui='git update-index --assume-unchanged'
alias c='git cz -m'
alias fake='faker-cli'
alias xkp='xkp "-/:;$&@.,?" -p wswswsddp -n 10'
alias top='htop'
alias oops='TF_CMD=$(TF_ALIAS=oops PYTHONIOENCODING=utf-8 TF_SHELL_ALIASES=$(alias) thefuck $(fc -ln -1 | tail -n 1)) && eval $TF_CMD && print -s $TF_CMD'

DEFAULT_USER='kmarnett'

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

export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='atom'
fi

export PATH="$PATH:$HOME/.rvm/bin" # Add RVM to PATH for scripting

# added by travis gem
[ -f ~/.travis/travis.sh ] && source ~/.travis/travis.sh
