# Turns .gitconfig aliases into shell aliases.
# cf. http://i.giphy.com/ms4x9Ipgego8g.gif
eval "$( \
  git config --global --get-regexp alias | \
  perl -pe 's/alias\./alias g/g;' | \
  perl -pe 's/(alias [\w]+)/$1=git/g' | \
  perl -pe 's/git !//g' | perl -pe 's/=(.*)$/="$1"/g' \
)"
