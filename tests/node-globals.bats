#!/usr/bin/env bats
#
# The npm and pnpm wrappers used to rewrite the tracked globals list from one machine's
# `list -g`, so a package only another Mac had dropped off it (#91, the same defect #75
# was for VS Code extensions). These cases pin the merge rule: (list ∪ installed here) −
# removed, where a global uninstall is what records a removal.
#
# Every case runs the real functions.zsh under zsh against a throwaway source dir, with
# `chezmoi` and the manager stubbed on PATH, so nothing can reach the live lists.
# Assertions read the files as written, which is what the installer reads.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
REAL_CHEZMOI="$(command -v chezmoi || true)"

setup() {
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export CHEZMOI_SRC="$BATS_TEST_TMPDIR/source"
	export LISTING="$BATS_TEST_TMPDIR/listing.json"
	DIR="$CHEZMOI_SRC/dot_config"
	mkdir -p "$STUBS" "$DIR"
	cat >"$STUBS/chezmoi" <<STUB
#!/bin/sh
[ "\$1" = source-path ] && { echo "$CHEZMOI_SRC"; exit 0; }
exit 1
STUB
	# Answers `list` with $LISTING, shaped like the manager's own JSON, and accepts anything else.
	for m in npm pnpm; do
		cat >"$STUBS/$m" <<STUB
#!/bin/sh
[ "\$1" = list ] && cat "$LISTING"
exit 0
STUB
	done
	chmod +x "$STUBS"/*
}

# seed <manager> <ids...>: the tracked list under its real header.
seed() {
	local m="$1" verb=install
	shift
	[ "$m" = pnpm ] && verb=add
	{
		echo "# Global $m packages to install"
		echo "# Edit this list (or use \`$m $verb -g <pkg>\`) and run \`chezmoi apply\` to sync."
		[ $# -eq 0 ] || printf '%s\n' "$@"
	} >"$DIR/$m-globals.txt"
}

# seed_removed <manager> <ids...>: the tombstone file under its header.
seed_removed() {
	local m="$1"
	shift
	{
		echo "# Global $m packages removed on purpose. Capture never adds these back."
		echo "# Remove a line to allow it again."
		[ $# -eq 0 ] || printf '%s\n' "$@"
	} >"$DIR/$m-globals-removed.txt"
}

# machine <manager> <names...>: what `list -g` reports on this Mac. pnpm wraps in a list, npm doesn't.
machine() {
	local m="$1" deps="" n
	shift
	for n in "$@"; do
		deps="${deps:+$deps,}\"$n\":{}"
	done
	if [ "$m" = pnpm ]; then
		echo "[{\"dependencies\":{$deps}}]" >"$LISTING"
	else
		echo "{\"dependencies\":{$deps}}" >"$LISTING"
	fi
}

wrapper() {
	PATH="$STUBS:/usr/bin:/bin" run zsh -c "source '$SRC/dot_config/zsh/functions.zsh'; $*"
}

# Package names only, comma-joined, so an assertion is not hostage to header wording.
ids() {
	{ grep -vE '^[[:space:]]*(#|$)' "$1" || true; } | paste -sd, -
}

snapshot() {
	cat "$DIR/$1-globals.txt" "$DIR/$1-globals-removed.txt" 2>/dev/null | cksum
}

# ---- the merge rule ----

@test "pnpm: a package only another Mac has stays on the list" {
	seed pnpm pkg-a pkg-b
	seed_removed pnpm
	machine pnpm pkg-a pkg-c
	wrapper pnpm add -g pkg-c
	assert_contains "status=0" "status=$status"
	assert_contains "ids=pkg-a,pkg-b,pkg-c" "ids=$(ids "$DIR/pnpm-globals.txt")"
}

@test "npm: a package only another Mac has stays on the list" {
	seed npm pkg-a pkg-b
	seed_removed npm
	machine npm pkg-a pkg-c
	wrapper npm install -g pkg-c
	assert_contains "status=0" "status=$status"
	assert_contains "ids=pkg-a,pkg-b,pkg-c" "ids=$(ids "$DIR/npm-globals.txt")"
}

# ---- removal ----

@test "pnpm: remove -g takes the package off the list and records it as removed" {
	seed pnpm pkg-a pkg-b
	seed_removed pnpm
	machine pnpm pkg-a pkg-c
	wrapper pnpm remove -g pkg-b
	assert_contains "list=pkg-a,pkg-c" "list=$(ids "$DIR/pnpm-globals.txt")"
	assert_contains "removed=pkg-b" "removed=$(ids "$DIR/pnpm-globals-removed.txt")"
}

@test "npm: uninstall -g takes the package off the list and records it as removed" {
	seed npm pkg-a pkg-b
	seed_removed npm
	machine npm pkg-a pkg-c
	wrapper npm uninstall -g pkg-b
	assert_contains "list=pkg-a,pkg-c" "list=$(ids "$DIR/npm-globals.txt")"
	assert_contains "removed=pkg-b" "removed=$(ids "$DIR/npm-globals-removed.txt")"
}

@test "pnpm: a Mac that still has the removed package does not put it back" {
	seed pnpm pkg-a
	seed_removed pnpm pkg-b
	machine pnpm pkg-a pkg-b pkg-c
	wrapper pnpm add -g pkg-c
	assert_contains "list=pkg-a,pkg-c" "list=$(ids "$DIR/pnpm-globals.txt")"
	assert_not_contains "pkg-b" "$(cat "$DIR/pnpm-globals.txt")"
}

@test "npm: a Mac that still has the removed package does not put it back" {
	seed npm pkg-a
	seed_removed npm pkg-b
	machine npm pkg-a pkg-b pkg-c
	wrapper npm install -g pkg-c
	assert_contains "list=pkg-a,pkg-c" "list=$(ids "$DIR/npm-globals.txt")"
	assert_not_contains "pkg-b" "$(cat "$DIR/npm-globals.txt")"
}

@test "pnpm: removing a scoped package records its bare name" {
	seed pnpm pkg-a @s/pkg-b
	seed_removed pnpm
	machine pnpm pkg-a
	wrapper pnpm remove -g @s/pkg-b
	assert_contains "removed=@s/pkg-b" "removed=$(ids "$DIR/pnpm-globals-removed.txt")"
	assert_not_contains "@s/pkg-b" "$(cat "$DIR/pnpm-globals.txt")"
}

# ---- reinstall ----

@test "pnpm: add -g on a removed package puts it back and clears the tombstone" {
	seed pnpm pkg-a
	seed_removed pnpm pkg-b
	machine pnpm pkg-a pkg-b
	wrapper pnpm add -g pkg-b@1.2.3
	assert_contains "list=pkg-a,pkg-b" "list=$(ids "$DIR/pnpm-globals.txt")"
	assert_not_contains "pkg-b" "$(cat "$DIR/pnpm-globals-removed.txt")"
}

@test "npm: install -g on a removed package puts it back and clears the tombstone" {
	seed npm pkg-a
	seed_removed npm pkg-b
	machine npm pkg-a pkg-b
	wrapper npm install -g pkg-b@1.2.3
	assert_contains "list=pkg-a,pkg-b" "list=$(ids "$DIR/npm-globals.txt")"
	assert_not_contains "pkg-b" "$(cat "$DIR/npm-globals-removed.txt")"
}

# ---- leave-alone cases ----

@test "pnpm: update -g with no package names changes neither file" {
	seed pnpm pkg-a pkg-b
	seed_removed pnpm pkg-x
	machine pnpm pkg-a pkg-c
	local before
	before="$(snapshot pnpm)"
	wrapper pnpm update -g
	assert_contains "status=0" "status=$status"
	assert_contains "snap=$before" "snap=$(snapshot pnpm)"
}

@test "npm: update -g with no package names changes neither file" {
	seed npm pkg-a pkg-b
	seed_removed npm pkg-x
	machine npm pkg-a pkg-c
	local before
	before="$(snapshot npm)"
	wrapper npm update -g
	assert_contains "status=0" "status=$status"
	assert_contains "snap=$before" "snap=$(snapshot npm)"
}

@test "npm: a local (non-global) install touches nothing" {
	seed npm pkg-a pkg-b
	machine npm pkg-a pkg-c
	local before
	before="$(snapshot npm)"
	wrapper npm install pkg-c
	assert_contains "snap=$before" "snap=$(snapshot npm)"
}

# ---- bundled packages ----

@test "pnpm: packages that ship with Node never reach either file" {
	seed pnpm pkg-a
	machine pnpm pkg-a npm corepack pnpm yarn
	wrapper pnpm add -g pkg-a
	assert_contains "list=pkg-a" "list=$(ids "$DIR/pnpm-globals.txt")"
	assert_not_contains "corepack" "$(cat "$DIR"/pnpm-globals*.txt)"
}

@test "npm: packages that ship with Node never reach either file" {
	seed npm pkg-a
	machine npm pkg-a npm corepack pnpm yarn
	wrapper npm install -g pkg-a
	assert_contains "list=pkg-a" "list=$(ids "$DIR/npm-globals.txt")"
	assert_not_contains "corepack" "$(cat "$DIR"/npm-globals*.txt)"
}

# ---- headers ----

@test "pnpm: the header names pnpm add, not pnpm pnpm" {
	seed pnpm
	machine pnpm pkg-a
	wrapper pnpm add -g pkg-a
	assert_contains '(or use `pnpm add -g <pkg>`)' "$(sed -n 2p "$DIR/pnpm-globals.txt")"
	assert_not_contains "pnpm pnpm" "$(cat "$DIR/pnpm-globals.txt")"
}

@test "npm: the header names npm install" {
	seed npm
	machine npm pkg-a
	wrapper npm install -g pkg-a
	assert_contains '(or use `npm install -g <pkg>`)' "$(sed -n 2p "$DIR/npm-globals.txt")"
}

@test "a first removal creates the tombstone file under a header" {
	seed pnpm pkg-a pkg-b
	machine pnpm pkg-a
	wrapper pnpm remove -g pkg-b
	assert_contains "# Global pnpm packages removed on purpose" "$(sed -n 1p "$DIR/pnpm-globals-removed.txt")"
}

# ---- deployment ----

@test "chezmoi managed lists neither tombstone file" {
	if [ -z "$REAL_CHEZMOI" ]; then
		skip "chezmoi not installed on this machine"
	fi
	local cfg="$BATS_TEST_TMPDIR/role.toml"
	printf '[data]\n  machine_role = "work"\n' >"$cfg"
	run "$REAL_CHEZMOI" managed --source "$SRC" --destination "$BATS_TEST_TMPDIR/home" --config "$cfg"
	assert_contains "status=0" "status=$status"
	# Positive control: the listing really covers this repo's deployable files.
	assert_contains ".config/zsh"
	assert_not_contains "globals-removed"
}
