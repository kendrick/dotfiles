#!/bin/bash
# Fuller bootstrap for a remote Claude Code container (#43), run by hand: env-setup.sh's rules, then each named skill from the lockfile, for containers where account skill sync is missing.
#
#   remote-bootstrap.sh <skill-name>...
#
# A person watches this one run, so it attempts every step, names each failure on stderr, and exits 1 if anything failed.

base="${DOTFILES_RAW_BASE:-https://raw.githubusercontent.com/kendrick/dotfiles/main}"
export DOTFILES_RAW_BASE="$base"
skills="$HOME/.claude/skills"
failed=0

fail() {
	echo "remote-bootstrap: $*" >&2
	failed=1
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/remote-bootstrap.XXXXXX")" || exit 1
trap 'rm -rf "$tmp"' EXIT

# Fetched and run, so env-setup.sh stays the only copy of that logic. It always exits 0, so its stderr is the only sign that part of it failed.
if curl -fsSL "$base/scripts/env-setup.sh" -o "$tmp/env-setup.sh"; then
	bash "$tmp/env-setup.sh" 2>"$tmp/env-setup.err"
	if [ -s "$tmp/env-setup.err" ]; then
		cat "$tmp/env-setup.err" >&2
		failed=1
	fi
else
	fail "could not fetch scripts/env-setup.sh"
fi

if [ "$#" -eq 0 ]; then
	echo "usage: remote-bootstrap.sh <skill-name>..."
	exit "$failed"
fi

lock="$tmp/skill-lock.json"
if ! command -v jq >/dev/null 2>&1; then
	fail "jq is required to read the skill lockfile"
	exit 1
fi
if ! curl -fsSL "$base/dot_local/private_state/skills/dot_skill-lock.json" -o "$lock"; then
	fail "could not fetch the skill lockfile"
	exit 1
fi

# One clone per source repo, however many skills share it. Lines are "<url> <dir>"; bash 3.2 has no associative arrays.
clones="$tmp/clones"
: >"$clones"
n=0

for name in "$@"; do
	entry="$(jq -r --arg n "$name" '.skills[$n] // empty | "\(.sourceUrl) \(.skillPath)"' "$lock")"
	if [ -z "$entry" ]; then
		fail "unknown skill: $name"
		continue
	fi
	url="${entry% *}"
	path="${entry##* }"

	# Account sync can make the bucket dir a symlink, and the glob follows it.
	synced=0
	for f in "$skills"/synced/*/"$name"/SKILL.md; do
		[ -f "$f" ] && synced=1
	done
	if [ "$synced" = 1 ]; then
		echo "$name: synced, skipping"
		continue
	fi

	repo="$(awk -v u="$url" '$1 == u { print $2; exit }' "$clones")"
	if [ -z "$repo" ]; then
		n=$((n + 1))
		repo="$tmp/repo$n"
		git clone -q --depth 1 "$url" "$repo" || repo="-"
		echo "$url $repo" >>"$clones"
	fi
	if [ "$repo" = "-" ] || [ ! -f "$repo/$path" ]; then
		fail "could not get $name from $url"
		continue
	fi

	# Copy the whole folder so scripts/ and references/ arrive with SKILL.md. A skill at its repo's root would otherwise drag .git along.
	stage="$tmp/stage-$name"
	mkdir -p "$skills" &&
		cp -R "$(dirname "$repo/$path")" "$stage" &&
		rm -rf "$stage/.git" "$skills/$name" &&
		mv "$stage" "$skills/$name" &&
		echo "$name: installed" ||
		fail "could not install $name into $skills/$name"
done

exit "$failed"
