alias add-dock-spacer="defaults write com.apple.dock persistent-apps -array-add '{\"tile-type"="spacer-tile\";}'; killall Dock"
alias bulkerase='drutil bulkerase quick'
alias bubu='brew update && brew outdated && brew upgrade && brew cleanup'
alias brewup='brew -v update && brew -v upgrade && brew upgrade --cask && brew -v cleanup --prune=5 && brew doctor'
alias cat='ccat'
alias changelog='conventional-changelog -p angular -i CHANGELOG.md -s'

# Only interactive-specific aliases should go here. Aliases that don't
# depend on an interactive shell should go in .zshenv.
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

alias cls='clear && fortune | cowsay | lolcat'
alias docker='podman'
alias fake='faker-cli'
alias fhere='find . -name'
alias h='history'
alias hg='history | grep'
alias less='cless'
alias la='eza -al --icons'
alias ls='eza --icons || ls -hG'
alias l='eza -l --icons || ls -alhAFG'
alias ll='eza -l --icons || ls -alhAFG'
alias mkdir='mkdir -pv'
alias o='open .'
alias oops='TF_CMD=$(TF_ALIAS=oops PYTHONIOENCODING=utf-8 TF_SHELL_ALIASES=$(alias) thefuck $(fc -ln -1 | tail -n 1)) && eval $TF_CMD && print -s $TF_CMD'
alias path='realpath'
alias pip='pip3'
alias python='python3'
alias rmdsstore="find . -name '*.DS_Store' -type f -delete"
alias sshh='ssh $SSH_HOME'
alias ssid='/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '"'"'/ SSID/ {print substr($0, index($0, $2))}'"'"''
alias top='htop'
alias xkp='xkp "-/:;$&@.,?" -p wswswsddp -n 10'
alias youtube-mp3='youtube-dl --extract-audio --audio-format mp3 --audio-quality 0'

. $DOTFILES/git/git-aliases.sh
