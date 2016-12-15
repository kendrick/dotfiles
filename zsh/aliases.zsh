alias bulkerase='drutil bulkerase quick'
alias changelog='conventional-changelog -p angular -i CHANGELOG.md -s'
alias cls='clear && fortune | cowsay | lolcat'
alias dfh='ssh kendrick@designedforhumans.co'
alias fake='faker-cli'
alias fhere='find . -name'
alias h='history'
alias hg='history | grep'
alias l='ls -alhAF'
alias ll='ls -alhAF'
alias mkdir='mkdir -pv'
alias o='open .'
alias oops='TF_CMD=$(TF_ALIAS=oops PYTHONIOENCODING=utf-8 TF_SHELL_ALIASES=$(alias) thefuck $(fc -ln -1 | tail -n 1)) && eval $TF_CMD && print -s $TF_CMD'
alias rmdsstore="find . -name '*.DS_Store' -type f -delete"
alias ssid='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '"'"'/ SSID/ {print substr($0, index($0, $2))}'"'"''
alias top='htop'
alias ws='wstorm'
alias xkp='xkp "-/:;$&@.,?" -p wswswsddp -n 10'

alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

export HISTCONTROL=ignoredups
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
export HISTSIZE=50000
export SAVEHIST=50000