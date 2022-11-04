alias g="git"

cdf() {
  finderPath=`osascript -e 'tell application "Finder"
      try
          set currentFolder to (folder of the front window as alias)
      on error
          set currentFolder to (path to desktop folder as alias)
      end try
      POSIX path of currentFolder
  end tell'`;
  cd "$finderPath"
}

# Jog my memory for CHANGELOGs
gch() {
  if [[ -d .git ]]; then
    TAG=$(git describe --tags --abbrev=0)
    git log --oneline --no-merges ${TAG}..
  fi
}

# Show a diff of all unpushed changes
gdu() {
  if [[ -d .git ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD);
    git diff origin/$BRANCH..HEAD;
  fi
}

# Localize a PR
gpr() {
  if [[ -d .git ]]; then
    git fetch -fu ${2:-$(git remote |grep -s ^upstream || echo origin)} refs/pull/$1/head:pr/$1
    git checkout pr/$1;
  fi
}

gpr-d() {
  if [[ -d .git ]]; then
    git branch --list 'pr/*' | \
    sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | \ # Remove ANSI color codes from output
      while read branch ; do
        git branch -D $branch ;
      done
  fi
}

$DOTFILES/git/gitconfig.sh

# Turns .gitconfig aliases into shell aliases.
# cf. http://i.giphy.com/ms4x9Ipgego8g.gif
if type -p perl > /dev/null; then
    echo "#!/bin/bash
# These aliases were generated via ~/.dotfiles/git/aliases.zsh.
# Edit that file to make changes to these aliases!" > $DOTFILES/git/git-aliases.sh

    git config --global --get-regexp alias | \
    perl -pe 's/alias\./alias g/g;' | \
    perl -pe 's/(alias [\w]+)/$1=git/g' | \
    perl -pe 's/git !//g' | perl -pe 's/=(.*)$/="$1"/g' >> $DOTFILES/git/git-aliases.sh
else
  e_error "perl must be installed to generate shell aliases from gitconfig."
fi
