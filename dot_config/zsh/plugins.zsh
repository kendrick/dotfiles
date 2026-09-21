znap source zsh-users/zsh-syntax-highlighting
znap source zsh-users/zsh-history-substring-search
znap source "marlonrichert/zsh-autocomplete"
znap source grigorii-zander/zsh-npm-scripts-autocomplete
znap source "ael-code/zsh-colored-man-pages"
znap source "clarketm/zsh-completions"
znap source "MichaelAquilina/zsh-auto-notify"
znap source "hlissner/zsh-autopair"
znap source "MohamedElashri/eza-zsh"

ZSH_AUTOSUGGEST_STRATEGY=( history )
znap source zsh-users/zsh-autosuggestions

# zsh-autocomplete puts the menu widgets on autosuggestions' ignore list, so the ghost text
# is neither cleared nor recomputed when Tab inserts a completion. What you get is the old
# suggestion still appended to the new buffer: `cd Applications//Users/k.arnett/repos`.
# Ignore wins over clear inside _zsh_autosuggest_bind_widgets, which skips ignored widgets
# before it ever checks the other lists, so the widgets have to move across and be rebound.
# Both lists are filled during the first precmd, which is why this waits for one.
_zsh_clear_ghost_on_menu() {
  add-zsh-hook -d precmd _zsh_clear_ghost_on_menu
  unfunction _zsh_clear_ghost_on_menu
  local w
  for w in menu-select menu-complete reverse-menu-complete; do
    ZSH_AUTOSUGGEST_IGNORE_WIDGETS=( ${ZSH_AUTOSUGGEST_IGNORE_WIDGETS:#$w} )
    ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=( $w )
  done
  (( $+functions[_zsh_autosuggest_bind_widgets] )) && _zsh_autosuggest_bind_widgets
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _zsh_clear_ghost_on_menu
