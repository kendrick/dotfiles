alias g="git"

# Jog my memory for CHANGELOGs
gch() {
  if [[ -d .git ]]; then
    TAG=$(git describe --tags --abbrev=0)
    git log --oneline --no-merges ${TAG}..
  fi
}

$DOTFILES/git/gitconfig.sh

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
