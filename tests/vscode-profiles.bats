#!/usr/bin/env bats
#
# Pins the data split behind the VS Code profiles (#45): which ids sit in the
# default list, which in each profile list, and which carry a tombstone. The
# installer, capture, and update tests build against this layout, so a list
# edit that breaks a rule here should fail loudly before they do.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
DEFAULT="$SRC/dot_config/vscode-extensions.txt"
REMOVED="$SRC/dot_config/vscode-extensions-removed.txt"
PROFILES="$SRC/dot_config/vscode-profiles"
SETTINGS="$SRC/private_Library/private_Application Support/Code/User/settings.json"
JSONC="$SRC/dot_config/font/jsonc.jq"

# The ids #45 moves out of the default list, written out per destination: web
# work, PlatformIO and C/C++ work, and Markdown work. Jest and the JSDoc
# generator leave outright, and oxc replaces eslint and prettier in the default.
# They're spelled out here, not read from the list files, so a list edit can't
# move both the data and the expectation at once.
WEB_IDS="bradlc.vscode-tailwindcss stylelint.vscode-stylelint vunguyentuan.vscode-css-variables jaspernorth.vscode-pigments radhakantaroy.vs-color-preview csstools.postcss unifiedjs.vscode-mdx formulahendry.auto-rename-tag dbaeumer.vscode-eslint esbenp.prettier-vscode"
EMBEDDED_IDS="platformio.platformio-ide ms-vscode.cpptools"
DOCS_IDS="shd101wyy.markdown-preview-enhanced yzhang.markdown-all-in-one robole.markdown-snippets bierner.markdown-mermaid"
DROPPED_IDS="orta.vscode-jest crystal-spider.jsdoc-generator"

# Ids of a list file: comments and blanks out.
ids_of() {
	grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1"
}

profile_files() {
	local f
	for f in "$PROFILES"/*.txt; do
		case "$f" in
		*-removed.txt) ;;
		*) printf '%s\n' "$f" ;;
		esac
	done
}

@test "the profile directory holds web, embedded and docs lists" {
	for n in web embedded docs; do
		[ -f "$PROFILES/$n.txt" ]
	done
}

@test "every profile file name matches ^[a-z0-9-]+\\.txt\$" {
	local f base
	for f in "$PROFILES"/*; do
		base=$(basename "$f")
		printf '%s\n' "$base" | grep -Eq '^[a-z0-9-]+\.txt$'
	done
}

@test "each profile list opens with the two-line header" {
	local f n
	for f in $(profile_files); do
		n=$(basename "$f" .txt)
		[ "$(sed -n 1p "$f")" = "# VS Code extensions for the $n profile, on top of vscode-extensions.txt" ]
		[ "$(sed -n 2p "$f")" = '# Edit this list and run `chezmoi apply` to sync.' ]
	done
}

@test "each profile list is sorted with sort -f" {
	local f
	for f in $(profile_files); do
		ids_of "$f" >"$BATS_TEST_TMPDIR/got"
		LC_ALL=C sort -f "$BATS_TEST_TMPDIR/got" >"$BATS_TEST_TMPDIR/want"
		cmp "$BATS_TEST_TMPDIR/got" "$BATS_TEST_TMPDIR/want"
	done
}

@test "the default and removed lists stay sorted with sort -f" {
	local f
	for f in "$DEFAULT" "$REMOVED"; do
		ids_of "$f" >"$BATS_TEST_TMPDIR/got"
		LC_ALL=C sort -f "$BATS_TEST_TMPDIR/got" >"$BATS_TEST_TMPDIR/want"
		cmp "$BATS_TEST_TMPDIR/got" "$BATS_TEST_TMPDIR/want"
	done
}

@test "no profile id is also in the default list" {
	local f
	for f in $(profile_files); do
		run grep -ixFf <(ids_of "$DEFAULT") <(ids_of "$f")
		[ "$status" -eq 1 ]
	done
}

@test "no id appears in two profile lists" {
	local dups
	dups=$(for f in $(profile_files); do ids_of "$f"; done | LC_ALL=C sort -f | uniq -di)
	[ -z "$dups" ]
}

@test "the default list holds oxc and none of the ids oxc replaced or #45 dropped" {
	ids_of "$DEFAULT" | grep -qxF 'oxc.oxc-vscode'
	local id
	for id in dbaeumer.vscode-eslint esbenp.prettier-vscode orta.vscode-jest crystal-spider.jsdoc-generator; do
		run grep -qxF "$id" <(ids_of "$DEFAULT")
		[ "$status" -eq 1 ]
	done
}

@test "the default list holds none of the ids that moved to a profile" {
	local id
	for id in $WEB_IDS $EMBEDDED_IDS $DOCS_IDS; do
		run grep -qxF "$id" <(ids_of "$DEFAULT")
		[ "$status" -eq 1 ]
	done
}

@test "web.txt keeps eslint and prettier as the fallback" {
	ids_of "$PROFILES/web.txt" | grep -qxF 'dbaeumer.vscode-eslint'
	ids_of "$PROFILES/web.txt" | grep -qxF 'esbenp.prettier-vscode'
}

@test "each profile list holds exactly the ids #45 assigns it" {
	local n want
	for n in web embedded docs; do
		case "$n" in
		web) want="$WEB_IDS" ;;
		embedded) want="$EMBEDDED_IDS" ;;
		docs) want="$DOCS_IDS" ;;
		esac
		printf '%s\n' $want | LC_ALL=C sort -f >"$BATS_TEST_TMPDIR/want"
		ids_of "$PROFILES/$n.txt" >"$BATS_TEST_TMPDIR/got"
		cmp "$BATS_TEST_TMPDIR/got" "$BATS_TEST_TMPDIR/want"
	done
}

@test "every id #45 takes out of the default list is tombstoned" {
	local id
	for id in $WEB_IDS $EMBEDDED_IDS $DOCS_IDS $DROPPED_IDS; do
		ids_of "$REMOVED" | grep -qxF "$id"
	done
}

@test "the removed file keeps its two header lines" {
	[ "$(sed -n 1p "$REMOVED")" = '# VS Code extensions removed on purpose. Capture never adds these back.' ]
	[ "$(sed -n 2p "$REMOVED")" = '# Remove a line (or run `code --install-extension <id>`) to allow it again.' ]
}

@test "the default list holds 26 ids and the removed file 25" {
	[ "$(ids_of "$DEFAULT" | wc -l | tr -d ' ')" -eq 26 ]
	[ "$(ids_of "$REMOVED" | wc -l | tr -d ' ')" -eq 25 ]
}

@test "chezmoi managed lists no vscode-profiles path" {
	command -v chezmoi >/dev/null || skip "chezmoi not installed"
	run chezmoi managed --source "$SRC"
	[ "$status" -eq 0 ]
	assert_not_contains 'vscode-profiles'
}

# The acceptance bar is about what VS Code does at startup, so this reads each
# installed manifest rather than trusting the list. An id with no manifest on
# disk counts as not starting, and the failure message names those so a green
# run on a half-installed machine is visibly weaker.
@test "the default profile starts fewer than 8 extensions on * or onStartupFinished" {
	local ext_dir="$HOME/.vscode/extensions"
	[ -d "$ext_dir" ] || skip "$ext_dir is absent (CI or a fresh machine)"
	local id dir pkg starting=0 unread=""
	while IFS= read -r id; do
		pkg=""
		for dir in "$ext_dir"/*; do
			[ -f "$dir/package.json" ] || continue
			case "$(printf '%s' "$(basename "$dir")" | tr '[:upper:]' '[:lower:]')" in
			"$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')"-[0-9]*) pkg="$dir/package.json" ;;
			esac
		done
		if [ -z "$pkg" ]; then
			unread="$unread $id"
			continue
		fi
		if jq -e '(.activationEvents // []) | any(. == "*" or . == "onStartupFinished")' "$pkg" >/dev/null; then
			starting=$((starting + 1))
		fi
	done < <(ids_of "$DEFAULT")
	echo "starting=$starting unread:${unread:- none}" >&3
	[ "$starting" -lt 8 ]
}

@test "settings.json formats with oxc by default" {
	run jq -Rs -f "$JSONC" "$SETTINGS"
	[ "$status" -eq 0 ]
	[ "$(jq -r '.["editor.defaultFormatter"]' <<<"$output")" = "oxc.oxc-vscode" ]
	[ "$(jq -r '.["editor.codeActionsOnSave"]["source.fixAll.oxc"]' <<<"$output")" = "explicit" ]
}
