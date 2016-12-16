#!/usr/local/bin/zsh

# Header logging
e_header() {
  printf "\n➤ \e[4m$(tput setaf 0)%s$(tput sgr0)\e[0m\n" "$@"
}

# Success logging
e_success() {
  printf "$(tput setaf 64)$ICON_SUCCESS %s$(tput sgr0)\n" "$@"
}

# Error logging
e_error() {
  printf "$(tput setaf 1)$ICON_FAILURE %s$(tput sgr0)\n" "$@"
}

# Warning logging
e_warning() {
  printf "$(tput setaf 136)$ICON_WARNING %s$(tput sgr0)\n" "$@"
}

e_info() {
  printf "$(tput setaf 4)$ICON_INFO %s$(tput sgr0)\n" "$@"
}
