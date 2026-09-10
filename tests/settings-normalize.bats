#!/usr/bin/env bats
#
# claude-settings-normalize runs right after `dotfiles-sync`'s blanket `chezmoi re-add`,
# and it exists because age ciphertext doesn't delta: any rewrite of the encrypted
# settings blob commits all 9.9KB again, permanently, to a public repo's history.
#
# Two ways that happens. The first is the one the script was written for: `/model` writes
# a machine-local pin into the live file and re-add carries it into source. The second is
# subtler and went unnoticed for weeks. `chezmoi re-add` compares live against the
# *source's* plaintext, never against HEAD, so an app that writes some key and later takes
# it back leaves source holding HEAD's exact content under fresh ciphertext, with nothing
# machine-local to strip. Four of the eight commits before this suite existed were that,
# each one a full-blob diff with an empty plaintext change.
#
# The fake encryption below is what makes any of this testable: a nonce line followed by
# the plaintext. It is not encryption and isn't pretending to be. The only property under
# test is age's real one, that encrypting identical content twice gives different bytes.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
SCRIPT="$SRC/dot_local/bin/executable_claude-settings-normalize"

# Captured before setup() narrows PATH, so the stub dir can shadow chezmoi while the real
# python3 and git stay reachable. Guarded per tests/helpers.bash:46-47: `load` runs under
# errexit, so an unguarded miss would kill the whole file at load instead of one case.
REAL_PYTHON="$(command -v python3 || true)"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export REPO="$BATS_TEST_TMPDIR/repo"
	SRCFILE="$REPO/dot_claude/encrypted_private_settings.json.age"
	export SRCFILE
	mkdir -p "$HOME/.claude" "$STUBS" "$REPO/dot_claude"

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
	# With an argument the script is asking where one target lives; bare, it's asking
	# for the repo root.
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
	git -C "$REPO" commit --quiet -m "settings"
}

run_normalize() {
	"$REAL_PYTHON" "$SCRIPT"
}

settings_without_model() {
	cat <<'JSON'
{
  "cleanupPeriodDays": 30,
  "permissions": {
    "allow": []
  }
}
JSON
}

# The same document Claude Code would write back after touching the file: identical
# content, keys in a different order. json.dumps preserves insertion order, so this
# re-serializes to different bytes while meaning exactly the same thing.
settings_reordered() {
	cat <<'JSON'
{
  "permissions": {
    "allow": []
  },
  "cleanupPeriodDays": 30
}
JSON
}

settings_with_model() {
	cat <<'JSON'
{
  "cleanupPeriodDays": 30,
  "model": "opus",
  "permissions": {
    "allow": []
  }
}
JSON
}

# The regression this suite was added for. Nothing machine-local is present, so the old
# code returned at its "nothing to strip" exit and left the rewritten blob sitting dirty
# until a sync committed it.
@test "normalize: unchanged plaintext under fresh ciphertext is restored from HEAD" {
	settings_without_model | encrypt_to_source
	commit_source
	local committed
	committed="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"

	# Same content, new nonce — exactly what a re-add produces when live drifted and came
	# back.
	settings_without_model | encrypt_to_source
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

# The other half of the same branch. A real settings change has to survive, or the fix
# above would trade pointless commits for lost ones.
@test "normalize: a genuine content change with nothing to strip is left alone" {
	settings_without_model | encrypt_to_source
	commit_source

	printf '{\n  "cleanupPeriodDays": 45\n}\n' | encrypt_to_source
	local before
	before="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"

	run run_normalize
	[ "$status" -eq 0 ]

	local after
	after="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"
	[ "$after" = "$before" ]
	run "$STUBS/chezmoi" decrypt "$SRCFILE"
	assert_contains "45"
}

@test "normalize: a model pin that strips back to HEAD is restored, not re-encrypted" {
	settings_without_model | encrypt_to_source
	commit_source
	local committed
	committed="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"

	settings_with_model | encrypt_to_source

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "model"
	assert_contains "no net change"

	local after
	after="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"
	[ "$after" = "$committed" ]
	run git -C "$REPO" status --porcelain
	[ -z "$output" ]
}

# A pin arriving alongside a real edit. The pin comes out, the edit stays, and the file
# has to be rewritten because there is no committed blob matching that result.
@test "normalize: a model pin beside a real edit is stripped and the edit kept" {
	settings_without_model | encrypt_to_source
	commit_source

	printf '{\n  "cleanupPeriodDays": 45,\n  "model": "opus"\n}\n' | encrypt_to_source

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "dropped model from source"

	run "$STUBS/chezmoi" decrypt "$SRCFILE"
	assert_not_contains "model"
	assert_contains "45"
}

# LOCAL_KEYS widened past `model` alone to cover the corporate-gateway `env` block. This
# pins the denylist to stay flat — strip the whole `env` key, leave every sibling key
# alone — rather than, say, recursing into nested objects and taking `permissions`/
# `hooks` down with it.
@test "normalize: an env block is stripped and permissions/hooks survive" {
	printf '{\n  "env": {"ANTHROPIC_BASE_URL": "https://corp.example/bifrost"},\n  "permissions": {"allow": []},\n  "hooks": {"PreToolUse": []}\n}\n' | encrypt_to_source
	commit_source

	printf '{\n  "env": {"ANTHROPIC_BASE_URL": "https://corp.example/bifrost"},\n  "cleanupPeriodDays": 45,\n  "permissions": {"allow": []},\n  "hooks": {"PreToolUse": []}\n}\n' | encrypt_to_source

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "dropped env from source"

	run "$STUBS/chezmoi" decrypt "$SRCFILE"
	assert_not_contains "ANTHROPIC_BASE_URL"
	assert_contains "permissions"
	assert_contains "hooks"
	assert_contains "45"
}

# The bootstrap case: no age key, so nothing decrypts. The encrypted config isn't deployed
# on such a machine either, so the script has nothing to normalize and must not treat that
# as an error the sync should report.
@test "normalize: an undecryptable source is skipped, not failed" {
	settings_without_model | encrypt_to_source
	commit_source
	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path)
	if [ -n "\$2" ]; then echo "$SRCFILE"; else echo "$REPO"; fi
	;;
# Points at a path that does not exist, which is what makes this the bootstrap case
# rather than a machine whose key is present and simply cannot open the blob.
execute-template) echo "$BATS_TEST_TMPDIR/absent-key.txt" ;;
decrypt) exit 1 ;;
esac
STUB
	chmod +x "$STUBS/chezmoi"

	run run_normalize
	[ "$status" -eq 2 ]
	assert_contains "couldn't decrypt"
}

# The sibling of npmrc-normalize's inode case, and the same reasoning: `open(src, "w")`
# truncates first, so an interrupted rewrite leaves a partial blob that the sync commits
# because it continues past a normalize failure. A rename swaps in a finished file, which
# shows up here as a changed inode.
@test "normalize: rewriting source replaces the file instead of truncating it in place" {
	settings_without_model | encrypt_to_source
	commit_source

	printf '{\n  "cleanupPeriodDays": 45,\n  "model": "opus"\n}\n' | encrypt_to_source
	local before_inode
	before_inode="$(stat -f %i "$SRCFILE")"

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "dropped model from source"

	local after_inode
	after_inode="$(stat -f %i "$SRCFILE")"
	[ "$after_inode" != "$before_inode" ]

	# The temp file lands in src's own directory so the rename stays atomic, which puts it
	# inside the repo where `git add -A` would sweep it into the commit.
	run git -C "$REPO" status --porcelain
	assert_not_contains "??"
}

# `chezmoi re-add` captures live settings.json, so a capture that lands while Claude Code
# is rewriting the file yields half a JSON document. The parse arm used to swallow that
# and return 0, which was harmless only while the sync ignored exit codes. Now that the
# sync aborts on nonzero and on nothing else, reporting success here is what would commit
# the gateway token this script exists to strip.
@test "normalize: a source blob that isn't valid JSON fails instead of reporting success" {
	settings_without_model | encrypt_to_source
	commit_source

	printf '{\n  "env": {"ANTHROPIC_AUTH_TOKEN": "sk-corp-secret"},\n  "permissions"\n' | encrypt_to_source

	run run_normalize
	[ "$status" -ne 0 ]
	assert_contains "isn't valid JSON"
}

# The sibling of npmrc-normalize's sweep case. A SIGKILL between the temp's creation and
# os.replace skips the except arm, stranding the file inside the worktree.
@test "normalize: a stranded replacement temp is swept before the rewrite" {
	settings_without_model | encrypt_to_source
	commit_source

	local orphan="$REPO/dot_claude/.normalize-tmp-deadbeef.tmp"
	printf 'partial ciphertext\n' >"$orphan"

	printf '{\n  "cleanupPeriodDays": 45,\n  "model": "opus"\n}\n' | encrypt_to_source

	run run_normalize
	[ "$status" -eq 0 ]

	[ ! -e "$orphan" ]
	run git -C "$REPO" status --porcelain
	assert_not_contains "??"
}

# The gap the earlier fail-closed change opened. `.chezmoiignore` enables the encrypted
# targets whenever key.txt is merely nonempty, and age encrypts to a recipient hardcoded
# in .chezmoi.toml, so a machine holding a corrupt or foreign key still captures live
# settings.json into source through `chezmoi re-add`. It just cannot read it back. Reporting
# success there hands the sync an unstripped blob and calls the commit clean.
@test "normalize: a decrypt failure with an identity present fails instead of skipping" {
	settings_without_model | encrypt_to_source
	commit_source

	local keyfile="$BATS_TEST_TMPDIR/key.txt"
	printf 'AGE-SECRET-KEY-NOT-THE-RIGHT-ONE\n' >"$keyfile"

	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path)
	if [ -n "\$2" ]; then echo "$SRCFILE"; else echo "$REPO"; fi
	;;
execute-template) echo "$keyfile" ;;
decrypt) exit 1 ;;
esac
STUB
	chmod +x "$STUBS/chezmoi"

	run run_normalize
	[ "$status" -ne 0 ]
	assert_contains "refusing to report success"
}

# `.chezmoiignore` tests size rather than existence because a failed `op read` creates the
# file before op writes anything. The normalizer has to draw the line in the same place,
# or a zero-byte key would read as a usable identity and fail a bootstrap that should skip.
@test "normalize: a zero-byte identity counts as absent and still skips" {
	settings_without_model | encrypt_to_source
	commit_source

	local keyfile="$BATS_TEST_TMPDIR/key.txt"
	: >"$keyfile"

	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path)
	if [ -n "\$2" ]; then echo "$SRCFILE"; else echo "$REPO"; fi
	;;
execute-template) echo "$keyfile" ;;
decrypt) exit 1 ;;
esac
STUB
	chmod +x "$STUBS/chezmoi"

	run run_normalize
	[ "$status" -eq 2 ]
	assert_contains "couldn't decrypt"
}

# An absent identity is the normal bootstrap state only while nothing has been captured
# yet. `.chezmoiignore` skips this target whenever the key is missing or zero bytes, so a
# source that differs from HEAD was written by an earlier run that did have a key. Since
# dotfiles-sync now aborts between re-add and commit, a stranded capture is a designed
# outcome rather than only a crash, and this branch would hand it to `git add -A` unread.
@test "normalize: an absent identity with a captured source fails instead of skipping" {
	settings_without_model | encrypt_to_source
	commit_source

	# What an earlier keyed run left in source before the sync gave up.
	settings_with_model | encrypt_to_source

	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path)
	if [ -n "\$2" ]; then echo "$SRCFILE"; else echo "$REPO"; fi
	;;
execute-template) echo "$BATS_TEST_TMPDIR/absent-key.txt" ;;
decrypt) exit 1 ;;
esac
STUB
	chmod +x "$STUBS/chezmoi"

	run run_normalize
	[ "$status" -ne 0 ]
	assert_contains "differs from HEAD"
}

# Exit 2, not 0. This path never opened the file, and dotfiles-sync reads a plain 0 as
# "a normalizer vouched for this blob" and skips its own dirty-source check on the
# strength of it. Reporting success from here is what lets an unread capture through.
@test "normalize: an unresolvable target reports a skip rather than a verified pass" {
	settings_without_model | encrypt_to_source
	commit_source

	cat >"$STUBS/chezmoi" <<'STUB'
#!/usr/bin/env bash
case "$1" in
source-path) exit 1 ;;
esac
STUB
	chmod +x "$STUBS/chezmoi"

	run run_normalize
	[ "$status" -eq 2 ]
}

# The sibling resolution failure: the target resolves but the repo root does not, so the
# script still never reads the blob and still must not claim it did.
@test "normalize: chezmoi not answering for the repo root reports a skip, not a pass" {
	settings_without_model | encrypt_to_source
	commit_source

	cat >"$STUBS/chezmoi" <<STUB
#!/usr/bin/env bash
case "\$1" in
source-path)
	if [ -n "\$2" ]; then echo "$SRCFILE"; else exit 1; fi
	;;
esac
STUB
	chmod +x "$STUBS/chezmoi"

	run run_normalize
	[ "$status" -eq 2 ]
}

# Claude Code reorders top-level keys when it rewrites settings.json. A byte comparison
# against HEAD's plaintext calls that a change, so the blob stays dirty and the sync
# commits the whole re-encrypted file for nothing. 25a7412 was exactly this — three keys
# changing position — and it diverged main from origin for two days.
@test "normalize: a key reorder with no content change is restored from HEAD" {
	settings_without_model | encrypt_to_source
	commit_source
	local committed
	committed="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"

	settings_reordered | encrypt_to_source
	local churned
	churned="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"
	[ "$churned" != "$committed" ]

	run run_normalize
	[ "$status" -eq 0 ]
	assert_contains "restored the committed blob"

	local after
	after="$(shasum -a 256 "$SRCFILE" | cut -d' ' -f1)"
	[ "$after" = "$committed" ]
	run git -C "$REPO" status --porcelain
	[ -z "$output" ]
}
