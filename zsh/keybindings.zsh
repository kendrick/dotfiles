# From https://github.com/marlonrichert/zsh-autocomplete#configuration
bindkey '^I' menu-complete
bindkey "$terminfo[kcbt]" reverse-menu-complete
bindkey -M menuselect  '^[[D' .backward-char  '^[OD' .backward-char
bindkey -M menuselect  '^[[C'  .forward-char  '^[OC'  .forward-char