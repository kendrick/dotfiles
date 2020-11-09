# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# https://getantibody.github.io/usage/
source <(antibody init)
antibody bundle < ~/.zsh_plugins.txt
# antibody bundle < ~/.zsh_plugins.txt > ~/.zsh_plugins.sh && source ~/.zsh_plugins.sh

# Only interactive-specific aliases should go here. Aliases that don't
# depend on an interactive shell should go in .zshenv.
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

export HISTCONTROL=ignoredups
export HISTSIZE=50000
export SAVEHIST=50000

setopt AUTO_MENU
setopt ALWAYS_TO_END
setopt ALIASES
setopt CORRECT
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt PROMPT_SUBST

# Initialize fasd & fzf
eval "$(fasd --init auto)"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

export N_PREFIX="$HOME/util/n"; [[ :$PATH: == *":$N_PREFIX/bin:"* ]] || PATH+=":$N_PREFIX/bin"  # Added by n-install (see http://git.io/n-install-repo).

autoload -Uz compinit
compinit

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
source ~/.powerlevel10k/powerlevel10k.zsh-theme
