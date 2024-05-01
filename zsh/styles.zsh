zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# Color completion for some things.
# http://linuxshellaccount.blogspot.com/2008/12/color-completion-using-zsh-modules-on.html
# zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Formatting and messages
# http://www.masterzen.fr/2009/04/19/in-love-with-zsh-part-one/
# zstyle ':completion:*' verbose yes
# zstyle ':completion:*:descriptions' format "$fg[yellow]%B--- %d%b"
# zstyle ':completion:*:messages' format '%d'
# zstyle ':completion:*:warnings' format "$fg[red]No matches for:$reset_color %d"
# zstyle ':completion:*:corrections' format '%B%d (errors: %e)%b'
# zstyle ':completion:*' group-name ''

zstyle ':autocomplete:*complete*:*' insert-unambiguous yes # Tab widgets
zstyle ':autocomplete:*history*:*' insert-unambiguous yes # History widgets
zstyle ':autocomplete:menu-search:*' insert-unambiguous yes # ^S