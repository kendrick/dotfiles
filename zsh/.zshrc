# Only interactive-specific aliases should go here. Aliases that don't
# depend on an interactive shell should go in .zshenv.
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

export HISTCONTROL=ignoredups
export HISTSIZE=50000
export SAVEHIST=50000

setopt ALIASES
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt CORRECT
