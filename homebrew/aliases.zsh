alias brews='brew list -1'
alias bubo='brew update && brew outdated'
alias bubc='brew upgrade && brew cleanup -s'
alias bubu='bubo && bubc'

if command -v brew >/dev/null 2>&1; then
	brew() {
		case "$1" in
		cleanup)
			brew-cleanup
			;;
		bump)
			brew-bump
			;;
		*)
			command brew "$@"
			;;
		esac
	}
fi
