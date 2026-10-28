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

# Copy the front Finder window's directory to the clipboard, and echo it.
# Exists because `cdf && pwd | pbcopy && cd -` clobbers $OLDPWD, so a `cd -`
# toggle between two work dirs starts landing in the Finder dir. This one
# never cds, so $PWD and $OLDPWD come out untouched. Yes, `cfd` is one
# transposed keystroke from `cdf`; mnemonic is "copy Finder dir" vs "cd Finder".
function cfd() {
	local dir
	dir="$(osascript -e 'tell app "Finder" to POSIX path of (insertion location as alias)')" || return $?
	printf '%s' "$dir" | pbcopy && printf '%s\n' "$dir"
}

# Copy the full path of each item selected in the front Finder window, one per
# line in Finder's order, and echo them. An empty selection falls back to cfd,
# and like cfd this never changes directory.
function cff() { # "copy Finder file(s)"
	local sel
	sel="$(osascript \
		-e 'set out to ""' \
		-e 'tell application "Finder"' \
		-e 'repeat with f in (get selection)' \
		-e 'set out to out & POSIX path of (f as alias) & linefeed' \
		-e 'end repeat' \
		-e 'end tell' \
		-e 'out')" || return $?
	if [ -z "$sel" ]; then
		cfd
		return $?
	fi
	printf '%s' "$sel" | pbcopy && printf '%s\n' "$sel"
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
# ~/.claude/plugins/{installed_plugins,known_marketplaces}.json. Capture the intent
# behind that change rather than the file itself: the CLI bakes this box's absolute
# installPaths, resolved versions, and git SHAs into those manifests, so the verbatim
# `chezmoi re-add` this used to run gave two machines two different files and every
# concurrent auto-sync collided on them. claude-plugins-capture strips them to the
# repos and specs the reinstall script actually reads, which is identical everywhere.
# The in-app /plugin menu bypasses this shell wrapper, so the daily dotfiles-sync
# capture stays the real safety net.
function claude() {
	command claude "$@"
	local rc=$?
	case "$1" in
		plugin)
			claude-plugins-capture >/dev/null 2>&1
			;;
	esac
	return $rc
}

# `code --install-extension` / `--uninstall-extension` changes the installed
# extension set. vscode-extensions-capture records the intent and merges the
# tracked list; a failed command records nothing, so a refused uninstall can't
# blacklist an extension that is still installed.
# Stderr passes through and failures print one line naming the helper, so a broken
# capture is visible; the wrapper still returns code's own status.
# The wrapper forwards `--profile <name>`, so an uninstall from one profile tombstones
# the id in that profile's removed file (#45).
function _code_record_extension() {
	local flag="$1" id="$2" profile="${3:-}"
	local -a profile_args=()
	case "$id" in
		*.vsix) return 0 ;;  # a package path carries no id to record
	esac
	id="${id%@*}"  # foo.bar@1.2.3 pins a version; the list and removed file hold bare ids
	if ! command -v vscode-extensions-capture >/dev/null 2>&1; then
		echo "code: vscode-extensions-capture not found, extension list not updated" >&2
		return 0
	fi
	if [ -n "$profile" ] && [ "$profile" != "Default" ]; then
		# This repeats the helper's shape test. Names become paths, and VS Code profile
		# names are case-sensitive, so `Web` must not match web.txt on case-insensitive APFS.
		case "$profile" in
			*-removed | *[!a-z0-9-]*) profile_args=() ;;
			*) [ -f "$(chezmoi source-path)/dot_config/vscode-profiles/$profile.txt" ] &&
				profile_args=(--profile "$profile") ;;
		esac
		if [ ${#profile_args[@]} -eq 0 ]; then
			echo "code: profile $profile is not tracked in dotfiles, list not updated" >&2
			return 0
		fi
	fi
	vscode-extensions-capture "$flag" "$id" "${profile_args[@]}" >/dev/null ||
		echo "code: vscode-extensions-capture failed, extension list not updated" >&2
	return 0
}

function code() {
	command code "$@"
	local rc=$?
	if [ $rc -eq 0 ]; then
		local prev="" arg profile=""
		for arg in "$@"; do
			case "$arg" in
				--profile=*) profile="${arg#--profile=}" ;;
			esac
			[ "$prev" = "--profile" ] && profile="$arg"
			prev="$arg"
		done
		prev=""
		for arg in "$@"; do
			case "$prev" in
				--uninstall-extension) _code_record_extension --removed "$arg" "$profile" ;;
				--install-extension) _code_record_extension --restored "$arg" "$profile" ;;
			esac
			prev="$arg"
		done
	fi
	return $rc
}

# `npm` / `pnpm` global installs change ~/.npm-globals or the pnpm global store.
# When -g/--global appears alongside a mutating subcommand, merge this machine's
# globals into the tracked list. The list is shared across Macs, so it's
# (list ∪ installed here) − removed, never a rewrite from one machine's view: a
# package only another Mac has must survive (#91, same defect as #75 for VS Code).
# `<manager>-globals-removed.txt` is the tombstone file: a global uninstall records
# the package there so a Mac that still has it can't put it back.
function _dotfiles_regen_node_globals() {
	local manager="$1" action="$2"  # npm|pnpm; added|removed|update
	shift 2
	local src="$(chezmoi source-path)/dot_config"
	local verb=install
	[ "$manager" = pnpm ] && verb=add
	local json
	json=$(command "$manager" list -g --depth=0 --json 2>/dev/null) || return
	# Version specs and tags aren't part of the name a tombstone matches on.
	local -a names
	local n
	for n in "$@"; do
		case "$n" in
			-*) ;;
			@*) n="${n#@}"; names+=("@${n%%@*}") ;;
			*) names+=("${n%%@*}") ;;
		esac
	done
	_NG_JSON="$json" python3 -c '
import json, os, sys
manager, action, list_path, removed_path, list_hdr, removed_hdr, *names = sys.argv[1:]
data = json.loads(os.environ["_NG_JSON"])
# pnpm wraps in a list; npm doesn'"'"'t
deps = data[0].get("dependencies", {}) if isinstance(data, list) else data.get("dependencies", {})
# npm and corepack ship bundled with Node, so "npm list -g" always reports them.
# Tracking them means a fresh machine runs "npm install -g npm", which self-updates
# in place, exits non-zero, and aborts chezmoi apply. Drop the plumbing; keep intent.
bundled = {"npm", "corepack", "pnpm", "yarn"}

def ids(path):
    try:
        with open(path) as f:
            return {l.strip() for l in f if l.strip() and not l.lstrip().startswith("#")}
    except FileNotFoundError:
        return set()

def write(path, header, body):
    text = header + "\n" + "".join(x + "\n" for x in body)
    try:
        if open(path).read() == text:
            return
    except FileNotFoundError:
        pass
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)

removed = ids(removed_path)
if action == "removed":
    removed |= set(names)
elif action == "added":
    removed -= set(names)
merged = sorted((ids(list_path) | set(deps)) - bundled - removed)
write(list_path, list_hdr, merged)
if action == "removed" or (action == "added" and os.path.exists(removed_path)):
    write(removed_path, removed_hdr, sorted(removed))
' "$manager" "$action" "$src/${manager}-globals.txt" "$src/${manager}-globals-removed.txt" \
		"# Global ${manager} packages to install
# Edit this list (or use \`${manager} ${verb} -g <pkg>\`) and run \`chezmoi apply\` to sync." \
		"# Global ${manager} packages removed on purpose. Capture never adds these back.
# Remove a line (or run \`${manager} ${verb} -g <pkg>\`) to allow it again." \
		"${names[@]}" 2>/dev/null
}

# A failed command changed nothing worth recording. `update -g` with no names is
# left alone: it moves versions, not membership.
function _dotfiles_node_globals_hook() {
	local manager="$1" rc="$2" sub="$3"
	shift 3
	[ "$rc" -eq 0 ] || return 0
	case " $* " in
		*" -g "*|*" --global "*) ;;
		*) return 0 ;;
	esac
	local action
	case "$sub" in
		install|i|add) action=added ;;
		uninstall|un|remove|rm) action=removed ;;
		update|up|upgrade)
			action=update
			[ -n "${*:#-*}" ] || return 0
			;;
		*) return 0 ;;
	esac
	_dotfiles_regen_node_globals "$manager" "$action" "$@"
}

function npm() {
	command npm "$@"
	local rc=$?
	_dotfiles_node_globals_hook npm $rc "$@"
	return $rc
}

function pnpm() {
	command pnpm "$@"
	local rc=$?
	_dotfiles_node_globals_hook pnpm $rc "$@"
	return $rc
}

# gh has no per-directory account. Export the personal token while the cwd sits
# under a personal checkout root, and put back whatever was there on the way
# out. GH_TOKEN lives in one shell's environment, so two open terminals never
# fight the way they do after `gh auth switch`. chpwd fires only on cd, so the
# bare call at the end covers a shell opened straight into one of these dirs.
#
# The _GH_TOKEN_HOOK_ variables exist because a token already in the environment
# may belong to someone else. gh reads GH_TOKEN ahead of its own stored
# credentials, so an inherited token would otherwise act as the wrong account
# inside a personal checkout. Unsetting it on the way out would throw away a
# token the caller set on purpose. _GH_TOKEN_HOOK_OWNS records that the hook has
# taken over GH_TOKEN and has a prior value to put back.
#
# _GH_TOKEN_HOOK_PINNED is a separate flag because `gh auth token` fails for
# reasons that have nothing to do with the account: a keyring still locked after
# a reboot, a logged-out account, no gh on PATH. Ownership survives that and
# pinning does not, so the next cd inside the root asks again rather than
# caching the failure for the life of the shell. A failed lookup also clears
# GH_TOKEN instead of leaving an inherited one in place, since falling back to
# gh's active account is easier to diagnose than acting as whoever the parent
# shell happened to be. _GH_TOKEN_HOOK_WARNED holds that warning to one line per
# failure rather than one per cd.
#
# _GH_TOKEN_HOOK_PRIOR_SET is separate from _GH_TOKEN_HOOK_PRIOR because an
# inherited empty GH_TOKEN is not the same as no GH_TOKEN, so the restore puts
# back an empty value only where a shell inherited one.
_gh_account_for_cwd() {
  local root token
  for root in "$HOME/repos/personal" "$HOME/code/personal"; do
    if [[ "$PWD/" == "$root/"* ]]; then
      if [[ -z "$_GH_TOKEN_HOOK_OWNS" ]]; then
        _GH_TOKEN_HOOK_PRIOR_SET=${GH_TOKEN+1}
        _GH_TOKEN_HOOK_PRIOR=${GH_TOKEN-}
        _GH_TOKEN_HOOK_OWNS=1
      fi
      if [[ -z "$_GH_TOKEN_HOOK_PINNED" ]]; then
        token="$(gh auth token --user kendrick 2>/dev/null)"
        if [[ -n "$token" ]]; then
          export GH_TOKEN="$token"
          _GH_TOKEN_HOOK_PINNED=1
          unset _GH_TOKEN_HOOK_WARNED
        else
          unset GH_TOKEN
          if [[ -z "$_GH_TOKEN_HOOK_WARNED" ]]; then
            print -u2 "gh: no stored token for kendrick, so commands here fall back to gh's active account"
            _GH_TOKEN_HOOK_WARNED=1
          fi
        fi
      fi
      return
    fi
  done
  [[ -n "$_GH_TOKEN_HOOK_OWNS" ]] || return
  if [[ -n "$_GH_TOKEN_HOOK_PRIOR_SET" ]]; then
    export GH_TOKEN="$_GH_TOKEN_HOOK_PRIOR"
  else
    unset GH_TOKEN
  fi
  unset _GH_TOKEN_HOOK_OWNS _GH_TOKEN_HOOK_PINNED _GH_TOKEN_HOOK_PRIOR \
    _GH_TOKEN_HOOK_PRIOR_SET _GH_TOKEN_HOOK_WARNED
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _gh_account_for_cwd
_gh_account_for_cwd
