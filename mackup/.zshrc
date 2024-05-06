# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Download Znap, if it's not there yet.
[[ ! -d ~/.znap-repos/znap ]] || git clone --depth 1 -- https://github.com/marlonrichert/zsh-snap.git ~/znap-repos/znap
source ~/znap-repos/znap/znap.zsh  # Start Znap

export DOTFILES=$HOME/.dotfiles

source $DOTFILES/zsh/exports.zsh && \
# =-=-=- Lazy load these?? -=-=-=
source $DOTFILES/zsh/plugins.zsh

. $HOMEBREW_PREFIX/etc/profile.d/z.sh

# =-=-=- Lazy load this! -=-=-=
source ~/.iterm2_shell_integration.zsh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
source $HOMEBREW_PREFIX/share/powerlevel10k/powerlevel10k.zsh-theme

source $DOTFILES/zsh/keybindings.zsh
source $DOTFILES/zsh/styles.zsh
source $DOTFILES/zsh/aliases.zsh
source $DOTFILES/zsh/options.zsh

# =-=-=- Lazy load this! -=-=-=
# NVM_DIR is set in ./exports.zsh
# [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
# [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion
. "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" # This loads nvm
. "$HOMEBREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm" # This loads nvm bash_completion
znap source Sparragus/zsh-auto-nvm-use