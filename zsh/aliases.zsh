alias add-dock-spacer="defaults write com.apple.dock persistent-apps -array-add '{\"tile-type"="spacer-tile\";}'; killall Dock"
alias bulkerase='drutil bulkerase quick'
alias changelog='conventional-changelog -p angular -i CHANGELOG.md -s'
alias cls='clear && fortune | cowsay | lolcat'
alias fake='faker-cli'
alias fhere='find . -name'
alias h='history'
alias hg='history | grep'
alias ls='ls -hG'
alias l='ls -alhAFG'
alias ll='ls -alhAFG'
alias mkdir='mkdir -pv'
alias o='open .'
alias oops='TF_CMD=$(TF_ALIAS=oops PYTHONIOENCODING=utf-8 TF_SHELL_ALIASES=$(alias) thefuck $(fc -ln -1 | tail -n 1)) && eval $TF_CMD && print -s $TF_CMD'
alias path='realpath'
alias rmdsstore="find . -name '*.DS_Store' -type f -delete"
alias sshh='ssh $SSH_HOME'
alias ssid='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '"'"'/ SSID/ {print substr($0, index($0, $2))}'"'"''
alias top='htop'
alias sketchtool='/Applications/Sketch.app/Contents/Resources/sketchtool/bin/sketchtool'
alias xkp='xkp "-/:;$&@.,?" -p wswswsddp -n 10'
alias youtube-mp3='youtube-dl --extract-audio --audio-format mp3 --audio-quality 0'

. $DOTFILES/git/git-aliases.sh
