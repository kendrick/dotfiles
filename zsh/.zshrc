# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source $HOMEBREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
# source ~/.powerlevel10k/powerlevel10k.zsh-theme

autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# Download Znap, if it's not there yet.
[[ ! -d ~/.znap-repos/znap ]] || git clone --depth 1 -- https://github.com/marlonrichert/zsh-snap.git ~/znap-repos/znap
source ~/znap-repos/znap/znap.zsh  # Start Znap
znap source ohmyzsh/ohmyzsh plugins/colorize
znap source ohmyzsh/ohmyzsh plugins/gitfast
znap source zsh-users/zsh-syntax-highlighting
# znap source zsh-users/zsh-autosuggestions
# znap source zsh-users/zsh-completions
# znap source zsh-users/zsh-history-substring-search
# znap source marlonrichert/zsh-autocomplete

. /opt/homebrew/etc/profile.d/z.sh

alias bubu='brew update && brew outdated && brew upgrade && brew cleanup'
alias cat='ccat'

# Only interactive-specific aliases should go here. Aliases that don't
# depend on an interactive shell should go in .zshenv.
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

source $DOTFILES/zsh/aliases.zsh

export HISTCONTROL=ignoredups
# export HISTSIZE=50000
# export SAVEHIST=50000

setopt AUTO_MENU
setopt ALWAYS_TO_END
setopt ALIASES
setopt CORRECT
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt PROMPT_SUBST

WORDCHARS='*?\'
# autoload -Uz compinit
# compinit

# zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Add RVM to PATH for scripting. Make sure this is the last PATH variable change.
# export PATH="$PATH:$HOME/.rvm/bin"
# [[ -s "$HOME/.rvm/scripts/rvm" ]] && . "$HOME/.rvm/scripts/rvm"

# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
