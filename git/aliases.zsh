alias g="git"

if [[ $(uname -a ) -eq "Darwin" ]]; then
  CRED_HELPER=osxkeychain;
else
  CRED_HELPER=cache;
fi

git config --global credential.helper $CRED_HELPER

# Turns .gitconfig aliases into shell aliases.
# cf. http://i.giphy.com/ms4x9Ipgego8g.gif
if type -p perl > /dev/null; then
  eval "$( \
    git config --global --get-regexp alias | \
    perl -pe 's/alias\./alias g/g;' | \
    perl -pe 's/(alias [\w]+)/$1=git/g' | \
    perl -pe 's/git !//g' | perl -pe 's/=(.*)$/="$1"/g' \
  )"
else
  e_error "perl must be installed to generate shell aliases from gitconfig."
fi
