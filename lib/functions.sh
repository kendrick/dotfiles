# Header logging
e_header() {
  printf "\n$(tput setaf 4)➤ \e[4m$(tput setaf 0)%s$(tput sgr0)\e[0m\n" "$@"
}
export e_header

# Success logging
e_success() {
  printf "$(tput setaf 64)$ICON_SUCCESS %s$(tput sgr0)\n" "$@"
}
export e_success

# Error logging
e_error() {
  printf "$(tput setaf 1)$ICON_FAILURE %s$(tput sgr0)\n" "$@"
}
export e_error

# Warning logging
e_warning() {
  printf "$(tput setaf 136)$ICON_WARNING %s$(tput sgr0)\n" "$@"
}
export e_warning

e_info() {
  printf "$(tput setaf 4)$ICON_INFO %s$(tput sgr0)\n" "$@"
}
export e_info

add_to_path() {
  [[ -d "$1" ]] && PATH="$1:$PATH"
}
export add_to_path

print_result() {
  [ $1 -eq 0 ] \
    && e_success "$2" \
    || e_error "$2"
}
export print_result

exec_with_status() {
  EWS_USER=$(id -un)
  MESSAGE=$1
  shift

  TMP=/tmp/$EWS_USER/dotfiles
  ! [[ -d $TMP ]] && mkdir -p $TMP

  FILENAME=execwithstatus.err
  OUTFILE=$TMP/$FILENAME
  touch $OUTFILE

  { $@ 2>$OUTFILE & disown; } 2> /dev/null
  PID=$! # Process id of the previous command

  SPIN='⢄⢂⢁⡁⡈⡐⡠'
  i=0
  while kill -0 $PID 2> /dev/null;
  do
    i=$(( (i+1) %7 ))
    printf "\r${SPIN:$i:1} $MESSAGE"
    sleep .08
  done

  printf "\r"

  if [[ -s $OUTFILE ]]; then
    MESSAGE_ERROR="Error: $( cat $OUTFILE | perl -pe 's/.*?:\d+:\s+//' )."
    e_error $MESSAGE_ERROR

    sed  -i "1i > $1" $OUTFILE
    mv $OUTFILE $TMP/$PID-$FILENAME
  else
    e_success $MESSAGE
    rm $OUTFILE
  fi
}
export exec_with_status
