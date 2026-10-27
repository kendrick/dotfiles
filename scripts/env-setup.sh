#!/bin/bash
# Installs the global ~/.claude rules into a remote Claude Code container, where chezmoi never
# runs (#43). Paste it into an environment's setup-script field, or pipe it from curl.
#
# The setup field holds one script, so this file sources nothing beside it. It always exits 0,
# because a failed fetch must never wedge container startup.

base="${DOTFILES_RAW_BASE:-https://raw.githubusercontent.com/kendrick/dotfiles/main}"
dest="$HOME/.claude"
key="$HOME/.config/chezmoi/key.txt"

mkdir -p "$dest" || exit 0
# Staged inside ~/.claude so each install is a same-filesystem mv and can't leave a half-written file.
tmp="$(mktemp -d "$dest/.env-setup.XXXXXX")" || exit 0
trap 'rm -rf "$tmp"' EXIT

fetch() {
	curl -fsSL "$base/$1" -o "$2" 2>/dev/null && return 0
	echo "env-setup: could not fetch $1, leaving any existing copy in place" >&2
	return 1
}

if fetch dot_claude/private_DELEGATION.md "$tmp/DELEGATION.md"; then
	mv -f "$tmp/DELEGATION.md" "$dest/DELEGATION.md"
fi

# A failed `op read` leaves a 0-byte key.txt behind, so the check is on size.
have_rules=0
if [ -s "$key" ] && command -v age >/dev/null 2>&1; then
	have_rules=1
	for f in PROSE VOICE; do
		if ! fetch "dot_claude/encrypted_private_$f.md.age" "$tmp/$f.md.age"; then
			have_rules=0
		elif ! age -d -i "$key" -o "$tmp/$f.md" "$tmp/$f.md.age"; then
			echo "env-setup: could not decrypt $f.md" >&2
			have_rules=0
		fi
	done
	if [ "$have_rules" = 1 ]; then
		mv -f "$tmp/PROSE.md" "$dest/PROSE.md"
		mv -f "$tmp/VOICE.md" "$dest/VOICE.md"
	fi
fi

# Each run rebuilds CLAUDE.md from the fetched text, so a second run writes the same bytes as
# the first.
if fetch dot_claude/CLAUDE.md "$tmp/CLAUDE.src"; then
	awk '$0 != "@RTK.md"' "$tmp/CLAUDE.src" >"$tmp/CLAUDE.md"
	if [ "$have_rules" = 0 ]; then
		cat >>"$tmp/CLAUDE.md" <<'MD'

## Missing House Rules

This container has no age key, so `~/.claude/PROSE.md` and `~/.claude/VOICE.md` were not installed. When a rule above says to read one of them, say that it's unavailable here and continue without it.
MD
	fi
	mv -f "$tmp/CLAUDE.md" "$dest/CLAUDE.md"
fi

exit 0
