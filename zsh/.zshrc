alias changelog='conventional-changelog -p angular -i CHANGELOG.md -s'
alias h='history'
alias ssid='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '"'"'/ SSID/ {print substr($0, index($0, $2))}'"'"''
alias dfh='ssh kendrick@designedforhumans.co'
alias bulkerase='drutil bulkerase quick'
alias ws='wstorm'
alias o='open .' # Open '.' in Finder
alias cls='clear && fortune | cowsay | lolcat'
alias cdg='cd ~/Dropbox/dev/git-repos'
alias rmdstore="find . -name '*.DS_Store' -type f -delete"
alias fake='faker-cli'
alias xkp='xkp "-/:;$&@.,?" -p wswswsddp -n 10'
alias top='htop'
alias oops='TF_CMD=$(TF_ALIAS=oops PYTHONIOENCODING=utf-8 TF_SHELL_ALIASES=$(alias) thefuck $(fc -ln -1 | tail -n 1)) && eval $TF_CMD && print -s $TF_CMD'

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
export PATH="$PATH://usr/local/Cellar/terminal-notifier/1.7.1/bin"

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='atom'
fi

# added by travis gem
[ -f ~/.travis/travis.sh ] && source ~/.travis/travis.sh
