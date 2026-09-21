# From https://github.com/marlonrichert/zsh-autocomplete#configuration
# The menuselect pair is the part that's easy to drop. That keymap binds ^I to
# accept-line by default, so without it Tab takes the highlighted entry and starts
# completing inside it. On a directory that walks you down a level per press, instead
# of cycling through the list.
bindkey              '^I' menu-select
bindkey "$terminfo[kcbt]" menu-select
bindkey -M menuselect              '^I'         menu-complete
bindkey -M menuselect "$terminfo[kcbt]" reverse-menu-complete
bindkey -M menuselect  '^[[D' .backward-char  '^[OD' .backward-char
bindkey -M menuselect  '^[[C'  .forward-char  '^[OC'  .forward-char
