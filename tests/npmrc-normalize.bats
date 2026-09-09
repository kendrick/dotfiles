#!/usr/bin/env bats
#
# npmrc-normalize runs right after `dotfiles-sync`'s blanket `chezmoi re-add`,
# and it guards two distinct failure modes against the encrypted ~/.npmrc
# blob in source.
#
# The first is the reason the script exists: this machine sits behind a
# corporate gateway, so live ~/.npmrc carries `proxy=`/`https-proxy=` lines
# that `chezmoi re-add` has no way to tell from `audit=false` or the shared
# registry auth token — it just captures whatever live holds, and commits
# this machine's gateway address into a file meant to sync to machines that
# don't sit behind it.
#
# The second is subtler: `chezmoi re-add` compares live against *source's*
# plaintext, never HEAD, so an app that writes a key and later withdraws it
# leaves source holding HEAD's exact plaintext under fresh ciphertext with
# nothing left to strip. Age ciphertext doesn't delta, so re-encrypting that
# is a full-blob commit representing no real change.
#
# The fake encryption below is what makes any of this testable: a nonce line
# followed by the plaintext. It is not encryption and isn't pretending to be.
# The only property under test is age's real one, that encrypting identical
# content twice gives different bytes.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/dot_local/bin/executable_npmrc-normalize"

# Captured before setup() narrows PATH, so the stub dir can shadow chezmoi while the real
# python3 and git stay reachable. Guarded per tests/helpers.bash:46-47: `load` runs under
# errexit, so an unguarded miss would kill the whole file at load instead of one case.
REAL_PYTHON="$(command -v python3 || true)"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export REPO="$BATS_TEST_TMPDIR/repo"
	SRCFILE="$REPO/encrypted_private_dot_npmrc.age"
	export SRCFILE
	mkdir -p "$HOME" "$STUBS" "$REPO"

	# A real git repo rather than a stubbed git. The behavior under test is which tree
	# `checkout HEAD --` restores from, and stubbing git would mean asserting against my
	# own idea of that instead of against git's.
	git -C "$REPO" init --quiet
	git -C "$REPO" config user.email "test@example.com"
	git -C "$REPO" config user.name "Test"

	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path)
	# With an argument the script is asking where one target (~/.npmrc) lives; bare,
	# it's asking for the repo root.
	if [ -n "\$2" ]; then echo "$SRCFILE"; else echo "$REPO"; fi
	;;
decrypt) tail -n +2 "\$2" ;;
encrypt)
	# The nonce is the whole point: same plaintext in, different bytes out, which is
	# what makes re-encrypting unchanged content a real cost rather than a no-op.
	echo "nonce \$RANDOM\$RANDOM\$\$"
	cat
	;;
esac
STUB
	chmod +x "$STUBS/chezmoi"
	export PATH="$STUBS:/usr/bin:/bin"
}

# Writes plaintext into source as freshly "encrypted" bytes, the way a re-add would.
encrypt_to_source() {
	"$STUBS/chezmoi" encrypt >"$SRCFILE"
}

commit_source() {
	git -C "$REPO" add -A
	git -C "$REPO" commit --quiet -m "npmrc"
}

run_normalize() {
	"$REAL_PYTHON" "$SCRIPT"
}

# Shared intent: audit setting plus the registry auth token every machine carries alike.
npmrc_with_token() {
	cat <<'NPMRC'
audit=false
//registry.npmjs.org/:_authToken=npm_FAKETOKEN1234567890
NPMRC
}

# Live on this machine: shared intent plus the corporate gateway lines that describe only
# this machine's network path.
npmrc_with_proxy() {
	cat <<'NPMRC'
audit=false
//registry.npmjs.org/:_authToken=npm_FAKETOKEN1234567890
proxy=http://corp-proxy.example.com:8080
https-proxy=http://corp-proxy.example.com:8080
NPMRC
}

# A genuine settings change that carries nothing machine-local, so the script must leave
# it alone rather than treat "differs from HEAD" as license to touch it.
npmrc_edited() {
	cat <<'NPMRC'
audit=false
//registry.npmjs.org/:_authToken=npm_FAKETOKEN1234567890
registry=https://custom.registry.example.com/
NPMRC
}

# The capture loop this script exists for: proxy lines land in source via a blanket
# re-add, and only they should come out — the shared audit setting and the registry
# token are shared intent, not machine-local noise.
@test "normalize: proxy lines are stripped while audit=false and the auth token survive" {
	npmrc_with_token | encrypt_to_source
	commit_source

	npmrc_with_proxy | encrypt_to_source

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "dropped proxy, https-proxy from source"

	run "$STUBS/chezmoi" decrypt "$SRCFILE"
	assert_contains "audit=false"
	assert_contains "npm_FAKETOKEN1234567890"
	assert_not_contains "proxy="
}

# The no-net-change regression: nothing machine-local is present, so the "nothing to
# strip" path alone would leave the rewritten blob dirty until a sync committed pure
# nondeterminism to a public repo's history.
@test "normalize: unchanged plaintext under fresh ciphertext is restored from HEAD with clean git status" {
	npmrc_with_token | encrypt_to_source
	commit_source
	local committed
	committed="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"

	# Same content, new nonce — exactly what a re-add produces when live drifted and came
	# back.
	npmrc_with_token | encrypt_to_source
	local churned
	churned="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"
	[ "$churned" != "$committed" ]

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "restored the committed blob"

	local after
	after="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"
	[ "$after" = "$committed" ]
	# The point of restoring rather than re-encrypting: git has nothing to commit.
	run git -C "$REPO" status --porcelain
	[ -z "$output" ]
}

# The other half of the capture-loop branch: a real edit with no proxy keys present must
# survive untouched, or stripping proxy lines would double as license to rewrite anything
# that merely differs from HEAD.
@test "normalize: a genuine edit with nothing to strip is left byte-identical" {
	npmrc_with_token | encrypt_to_source
	commit_source

	npmrc_edited | encrypt_to_source
	local before
	before="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"

	run run_normalize
	[ "$status" -eq 0 ]

	local after
	after="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"
	[ "$after" = "$before" ]
	run "$STUBS/chezmoi" decrypt "$SRCFILE"
	assert_contains "registry=https://custom.registry.example.com/"
}

# The no-net-change branch reached via the capture loop rather than around it: proxy
# lines land back in source, but stripping them lands on exactly HEAD's plaintext, so the
# fix has to restore the committed blob rather than re-encrypt a payload equal to it.
@test "normalize: proxy lines that strip back to exactly HEAD are restored, not re-encrypted" {
	npmrc_with_token | encrypt_to_source
	commit_source
	local committed
	committed="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"

	npmrc_with_proxy | encrypt_to_source

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "dropped proxy, https-proxy from source (no net change)"

	local after
	after="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"
	[ "$after" = "$committed" ]
	run git -C "$REPO" status --porcelain
	[ -z "$output" ]
}

# The bootstrap case: no age key, so nothing decrypts. The encrypted config isn't deployed
# on such a machine either, so the script has nothing to normalize and must not treat that
# as an error the sync should report.
@test "normalize: an undecryptable source is skipped, not failed" {
	npmrc_with_token | encrypt_to_source
	commit_source
	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path)
	if [ -n "\$2" ]; then echo "$SRCFILE"; else echo "$REPO"; fi
	;;
decrypt) exit 1 ;;
esac
STUB
	chmod +x "$STUBS/chezmoi"

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "couldn't decrypt"
}

# A real edit that also carries this machine's proxy lines. Stripping leaves something
# that still differs from HEAD, which is the only path that re-encrypts and writes -
# every other branch either restores the committed blob or returns without touching src.
npmrc_edited_with_proxy() {
	cat <<'NPMRC'
audit=false
//registry.npmjs.org/:_authToken=npm_FAKETOKEN1234567890
registry=https://custom.registry.example.com/
proxy=http://corp-proxy.example.com:8080
NPMRC
}

# `open(src, "w")` empties the file before the new ciphertext lands, so a run interrupted
# mid-write leaves a truncated blob - and because the sync continues past a normalize
# failure, `git add -A` commits that undecryptable file. Renaming a finished file into
# place can't produce the partial state at all. The inode is what tells the two apart:
# writing through the existing file keeps it, replacing the directory entry changes it.
@test "normalize: rewriting source replaces the file instead of truncating it in place" {
	npmrc_with_token | encrypt_to_source
	commit_source

	npmrc_edited_with_proxy | encrypt_to_source
	local before_inode
	before_inode="$(stat -f %i "$SRCFILE")"

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "dropped proxy from source"

	local after_inode
	after_inode="$(stat -f %i "$SRCFILE")"
	[ "$after_inode" != "$before_inode" ]

	# The temp file has to sit in src's own directory for the rename to stay atomic, which
	# puts it inside the repo where `git add -A` would sweep it into the commit.
	run git -C "$REPO" status --porcelain
	assert_not_contains "??"
	run "$STUBS/chezmoi" decrypt "$SRCFILE"
	assert_contains "registry=https://custom.registry.example.com/"
	assert_not_contains "proxy="
}
