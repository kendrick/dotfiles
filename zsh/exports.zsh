export DOTFILES=$HOME/.dotfiles
export EDITOR=code

# Increase Bash history size. Allow 32³ entries; the default is 500.
export HISTSIZE='32768';
export HISTFILESIZE="${HISTSIZE}";
export HISTCONTROL=ignoredups
export HOMEBREW_PREFIX=/opt/homebrew
export NVM_DIR="$HOME/.nvm"
export PATH="$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:$DOTFILES/bin:$HOME/.local/bin:$PATH"
export WORDCHARS='*_-.[]~;!$%^(){}<>'

autoload -Uz select-word-style
select-word-style normal

# `unset` fixes this issue: https://github.com/romkatv/powerlevel10k/issues/1554#issuecomment-1701598955
unset ZSH_AUTOSUGGEST_USE_ASYNC
