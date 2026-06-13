#!/usr/bin/env zsh

# Lifted from the zsh plugin here:
# https://github.com/pndurette/zsh-lux
function os_is_dark() {
    local dark_mode=$(osascript -l JavaScript -e \
        "Application('System Events').appearancePreferences.darkMode.get()")

    if   [[ "$dark_mode" == "true" ]];  then return 0
    elif [[ "$dark_mode" == "false" ]]; then return 1
    else
        return 2
    fi
}

# Create a new directory and enter it
function mkd() {
	mkdir -p "$@" && cd "$_";
}

# Change working directory to the top-most Finder window location
function cdf() { # short for `cdfinder`
	cd "$(osascript -e 'tell app "Finder" to POSIX path of (insertion location as alias)')";
}

# Create a data URL from a file
function dataurl() {
	local mimeType=$(file -b --mime-type "$1");
	if [[ $mimeType == text/* ]]; then
		mimeType="${mimeType};charset=utf-8";
	fi
	echo "data:${mimeType};base64,$(openssl base64 -in "$1" | tr -d '\n')";
}

# Determine size of a file or total size of a directory
function fs() {
	if du -b /dev/null > /dev/null 2>&1; then
		local arg=-sbh;
	else
		local arg=-sh;
	fi
	if [[ -n "$@" ]]; then
		du $arg -- "$@";
	else
		du $arg .[^.]* ./*;
	fi;
}

# `o` with no arguments opens the current directory, otherwise opens the given
# location
function o() {
	if [ $# -eq 0 ]; then
		open .;
	else
		open "$@";
	fi;
}

# --- chezmoi auto-capture wrappers ---
# These wrap tools that change tracked dotfiles so source stays in sync without
# remembering `chezmoi re-add`. Each wrapper preserves the tool's exit code.

# `npx skills` mutates ~/.local/state/skills/.skill-lock.json on add/remove/sync.
# After any mutating subcommand, capture the lockfile back into source.
function skills() {
	command npx skills "$@"
	local rc=$?
	case "$1" in
		add|remove|install|uninstall|sync|update)
			chezmoi re-add ~/.local/state/skills/.skill-lock.json >/dev/null 2>&1
			;;
	esac
	return $rc
}

# `claude plugin ...` (install/uninstall, marketplace add/remove) rewrites
# ~/.claude/plugins/{installed_plugins,known_marketplaces}.json. Re-add after any
# plugin subcommand; those manifests are age-encrypted in source, so re-add
# re-encrypts rather than leaking. The in-app /plugin menu bypasses this shell
# wrapper, so the daily dotfiles-sync re-add stays the real safety net.
function claude() {
	command claude "$@"
	local rc=$?
	case "$1" in
		plugin)
			chezmoi re-add ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/known_marketplaces.json >/dev/null 2>&1
			;;
	esac
	return $rc
}

# `code --install-extension` / `--uninstall-extension` changes the installed
# extension set. Regenerate the tracked list when either flag is used.
function code() {
	command code "$@"
	local rc=$?
	case "$*" in
		*"--install-extension"*|*"--uninstall-extension"*)
			local list="$(chezmoi source-path)/dot_config/vscode-extensions.txt"
			{
				echo "# VS Code extensions to install"
				echo "# Edit this list and run \`chezmoi apply\` to sync."
				command code --list-extensions | sort -f
			} >"$list"
			;;
	esac
	return $rc
}

# `npm` / `pnpm` global installs change ~/.npm-globals or the pnpm global store.
# When -g/--global appears alongside a mutating subcommand, regenerate the
# tracked list of globals for whichever manager was invoked.
function _dotfiles_regen_node_globals() {
	local manager="$1"  # npm or pnpm
	local list="$(chezmoi source-path)/dot_config/${manager}-globals.txt"
	local packages
	packages=$(command "$manager" list -g --depth=0 --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
# pnpm wraps in a list; npm doesn't
deps = data[0].get('dependencies', {}) if isinstance(data, list) else data.get('dependencies', {})
print('\n'.join(sorted(deps.keys())))
" 2>/dev/null) || return
	{
		echo "# Global ${manager} packages to install"
		echo "# Edit this list (or use \`${manager} ${manager:-install} -g <pkg>\`) and run \`chezmoi apply\` to sync."
		echo "$packages"
	} >"$list"
}

function npm() {
	command npm "$@"
	local rc=$?
	case "$1" in
		install|i|uninstall|un|remove|rm|update|up|upgrade)
			case "$*" in
				*" -g "*|*" --global"*|*" -g")
					_dotfiles_regen_node_globals npm
					;;
			esac
			;;
	esac
	return $rc
}

function pnpm() {
	command pnpm "$@"
	local rc=$?
	case "$1" in
		add|install|i|remove|rm|uninstall|un|update|up|upgrade)
			case "$*" in
				*" -g "*|*" --global"*|*" -g")
					_dotfiles_regen_node_globals pnpm
					;;
			esac
			;;
	esac
	return $rc
}
