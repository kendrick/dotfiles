#!/usr/bin/env bats
#
# scripts/env-setup.sh and scripts/remote-bootstrap.sh (#43): give a remote Claude container the global ~/.claude/CLAUDE.md (and the files it cites) without chezmoi.
#
# Expected values come from the issue's acceptance criteria and the plan's Decisions, never from reading the scripts. Both scripts fetch "$DOTFILES_RAW_BASE/<source path>" (Decision 1), so every case points that at a file:// fixture laid out like the repo.

load 'helpers'

# `run --separate-stderr` needs 1.5+. A plain `run cmd 2>file` merges stderr into $output and leaves the file empty, so a stderr assertion against the file could never pass.
bats_require_minimum_version 1.5.0

SRC="${BATS_TEST_DIRNAME}/.."

# Resolved before anything can shadow chezmoi, for the one case that renders the real source tree.
REAL_CHEZMOI="$(command -v chezmoi || true)"

setup() {
	unset XDG_CONFIG_HOME XDG_CACHE_HOME
	D="$BATS_TEST_TMPDIR/bs"
	FX="$D/fixture"
	HOME="$D/home"
	export HOME
	KEY="$HOME/.config/chezmoi/key.txt"
	DOTFILES_RAW_BASE="file://$FX"
	export DOTFILES_RAW_BASE
	mkdir -p "$FX/dot_claude" "$FX/scripts" "$FX/dot_local/private_state/skills" "$HOME"

	# One extra @RTK.md mention that is not the whole line: only a line that is exactly @RTK.md goes, so this one has to survive.
	cat >"$FX/dot_claude/CLAUDE.md" <<'MD'
# Fixture rules

Read ~/.claude/PROSE.md before writing prose.
See @RTK.md for notes on the token proxy.
@RTK.md
Last line of the rules.
MD
	EXPECTED="$D/expected-CLAUDE.md"
	cat >"$EXPECTED" <<'MD'
# Fixture rules

Read ~/.claude/PROSE.md before writing prose.
See @RTK.md for notes on the token proxy.
Last line of the rules.
MD
	printf 'delegation fixture body\n' >"$FX/dot_claude/private_DELEGATION.md"

	# Copied only when present so a missing script fails the case that runs it, not setup().
	for s in env-setup.sh remote-bootstrap.sh; do
		if [ -f "$SRC/scripts/$s" ]; then
			cp "$SRC/scripts/$s" "$FX/scripts/$s"
		fi
	done

	PROSE_PLAIN="$D/prose-plain.md"
	VOICE_PLAIN="$D/voice-plain.md"
	printf 'prose fixture line one\nprose fixture line two\n' >"$PROSE_PLAIN"
	printf 'voice fixture line one\nvoice fixture line two\n' >"$VOICE_PLAIN"
	if [ -n "$REAL_AGE" ] && [ -n "$REAL_AGE_KEYGEN" ]; then
		FX_KEY="$D/fixture-key.txt"
		"$REAL_AGE_KEYGEN" -o "$FX_KEY" 2>/dev/null
		recipient="$("$REAL_AGE_KEYGEN" -y "$FX_KEY")"
		"$REAL_AGE" -r "$recipient" -o "$FX/dot_claude/encrypted_private_PROSE.md.age" "$PROSE_PLAIN"
		"$REAL_AGE" -r "$recipient" -o "$FX/dot_claude/encrypted_private_VOICE.md.age" "$VOICE_PLAIN"
	fi
}

# Shadows age with a stub that logs its arguments and fails. Decision 3 says a 0-byte key is no key at all, but a script that checks existence and then falls back on the failed decrypt would still end up with the amendment, so the output files alone can't catch it. The log can.
stub_age() {
	AGE_LOG="$D/age-calls.log"
	mkdir -p "$D/stubs"
	cat >"$D/stubs/age" <<SH
#!/bin/sh
printf '%s\n' "\$*" >>"$AGE_LOG"
exit 1
SH
	chmod +x "$D/stubs/age"
	PATH="$D/stubs:$PATH"
	export PATH
}

# A key can only be installed by a test that has age to decrypt with.
require_age() {
	if [ -z "$REAL_AGE" ] || [ -z "$REAL_AGE_KEYGEN" ]; then
		skip "age/age-keygen not installed on this machine"
	fi
}

install_key() {
	mkdir -p "$(dirname "$KEY")"
	cp "$FX_KEY" "$KEY"
}

# Byte comparison reported as a word, so the assert_* helpers (and the mutation check that inverts them) can gate it.
same_bytes() {
	if cmp -s "$1" "$2"; then echo same; else echo differ; fi
}

present() {
	if [ -e "$1" ]; then echo present; else echo absent; fi
}

# The lockfile and the git repo it points at: alpha carries references/, beta carries scripts/.
build_skills() {
	SK="$D/skillrepo"
	mkdir -p "$SK/skills/alpha/references" "$SK/skills/beta/scripts"
	printf -- '---\nname: alpha\n---\nalpha body\n' >"$SK/skills/alpha/SKILL.md"
	printf 'alpha reference content\n' >"$SK/skills/alpha/references/x.md"
	printf -- '---\nname: beta\n---\nbeta body\n' >"$SK/skills/beta/SKILL.md"
	printf '#!/bin/sh\necho beta helper\n' >"$SK/skills/beta/scripts/y.sh"
	git -C "$SK" init -q
	git -C "$SK" add -A
	git -C "$SK" -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m fixture
	cat >"$FX/dot_local/private_state/skills/dot_skill-lock.json" <<JSON
{
  "version": 3,
  "skills": {
    "alpha": {"source": "fixture/skills", "sourceType": "github", "sourceUrl": "file://$SK", "skillPath": "skills/alpha/SKILL.md"},
    "beta": {"source": "fixture/skills", "sourceType": "github", "sourceUrl": "file://$SK", "skillPath": "skills/beta/SKILL.md"}
  }
}
JSON
}

run_env() {
	bash "$SRC/scripts/env-setup.sh"
}

run_bootstrap() {
	bash "$SRC/scripts/remote-bootstrap.sh" "$@"
}

AMENDMENT_HEAD='## Missing House Rules'
AMENDMENT_BODY='This container has no age key, so `~/.claude/PROSE.md` and `~/.claude/VOICE.md` were not installed. When a rule above says to read one of them, say that it'\''s unavailable here and continue without it.'

# ---- 1. what env-setup.sh installs (criterion 1, Decision 2) ----

@test "env-setup.sh writes CLAUDE.md from the fixture minus the @RTK.md line, and DELEGATION.md" {
	run run_env
	assert_contains "status=0" "status=$status"
	head -n 5 "$HOME/.claude/CLAUDE.md" >"$D/head.md"
	assert_contains "same" "$(same_bytes "$D/head.md" "$EXPECTED")"
	assert_contains "delegation fixture body" "$(cat "$HOME/.claude/DELEGATION.md")"
}

@test "env-setup.sh with a key writes exactly the fixture minus the @RTK.md line" {
	require_age
	install_key
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "same" "$(same_bytes "$HOME/.claude/CLAUDE.md" "$EXPECTED")"
}

@test "env-setup.sh drops an exact @RTK.md line but keeps one that only mentions it" {
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "count=0" "count=$(grep -cxF '@RTK.md' "$HOME/.claude/CLAUDE.md")"
	assert_contains "See @RTK.md for notes on the token proxy." "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "Last line of the rules." "$(cat "$HOME/.claude/CLAUDE.md")"
}

# ---- 2. a failed fetch never wedges startup (criterion 2, Decision 6) ----

@test "env-setup.sh exits 0 on a failed fetch, says so on stderr, and leaves CLAUDE.md untouched" {
	mkdir -p "$HOME/.claude"
	printf 'pre-existing local rules\n' >"$HOME/.claude/CLAUDE.md"
	cp "$HOME/.claude/CLAUDE.md" "$D/seeded.md"
	DOTFILES_RAW_BASE="file://$D/does-not-exist"
	export DOTFILES_RAW_BASE
	run --separate-stderr bash "$SRC/scripts/env-setup.sh"
	assert_contains "status=0" "status=$status"
	assert_contains "CLAUDE.md" "$stderr"
	assert_contains "same" "$(same_bytes "$HOME/.claude/CLAUDE.md" "$D/seeded.md")"
}

@test "ENV_SETUP_STRICT=1 makes env-setup.sh exit 1 on a failed fetch" {
	DOTFILES_RAW_BASE="file://$D/does-not-exist"
	export DOTFILES_RAW_BASE
	run --separate-stderr env ENV_SETUP_STRICT=1 bash "$SRC/scripts/env-setup.sh"
	assert_contains "status=1" "status=$status"
	assert_contains "CLAUDE.md" "$stderr"
}

@test "ENV_SETUP_STRICT=1 leaves a clean env-setup.sh run at exit 0" {
	run env ENV_SETUP_STRICT=1 bash "$SRC/scripts/env-setup.sh"
	assert_contains "status=0" "status=$status"
}

# A fetch that works but an install that doesn't is still a failure: mv can't replace a non-empty directory.
@test "remote-bootstrap.sh exits 1 when a fetched file can't be installed" {
	mkdir -p "$HOME/.claude/DELEGATION.md/DELEGATION.md/blocker"
	run run_bootstrap
	assert_contains "status=1" "status=$status"
}

# Falsifier for judging by stderr: age warns, then decrypts fine, so nothing failed.
@test "remote-bootstrap.sh exits 0 when age warns on stderr but decrypts" {
	require_age
	install_key
	build_skills
	mkdir -p "$D/stubs"
	cat >"$D/stubs/age" <<SH
#!/bin/sh
echo "age: harmless warning" >&2
exec "$REAL_AGE" "\$@"
SH
	chmod +x "$D/stubs/age"
	PATH="$D/stubs:$PATH"
	export PATH
	run run_bootstrap alpha
	assert_contains "status=0" "status=$status"
	assert_contains "same" "$(same_bytes "$HOME/.claude/PROSE.md" "$PROSE_PLAIN")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/VOICE.md" "$VOICE_PLAIN")"
}

# Falsifier for ignoring env-setup: a missing base fails every fetch, and the exit status has to say so.
@test "remote-bootstrap.sh exits 1 and names the failed fetch when the base is missing" {
	DOTFILES_RAW_BASE="file://$D/does-not-exist"
	export DOTFILES_RAW_BASE
	run --separate-stderr run_bootstrap
	assert_contains "status=1" "status=$status"
	assert_contains "could not fetch" "$stderr"
}

# ---- 3. idempotency (criterion 3, Decision 5) ----

@test "env-setup.sh twice with no key leaves CLAUDE.md byte-identical, amendment once" {
	run run_env
	assert_contains "status=0" "status=$status"
	cp "$HOME/.claude/CLAUDE.md" "$D/first.md"
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "same" "$(same_bytes "$HOME/.claude/CLAUDE.md" "$D/first.md")"
	assert_contains "count=1" "count=$(grep -cxF "$AMENDMENT_HEAD" "$HOME/.claude/CLAUDE.md")"
}

@test "remote-bootstrap.sh twice with no key leaves CLAUDE.md byte-identical, amendment once" {
	run run_bootstrap
	assert_contains "status=0" "status=$status"
	cp "$HOME/.claude/CLAUDE.md" "$D/first.md"
	run run_bootstrap
	assert_contains "status=0" "status=$status"
	assert_contains "same" "$(same_bytes "$HOME/.claude/CLAUDE.md" "$D/first.md")"
	assert_contains "count=1" "count=$(grep -cxF "$AMENDMENT_HEAD" "$HOME/.claude/CLAUDE.md")"
}

@test "env-setup.sh twice with a key leaves CLAUDE.md, PROSE.md and VOICE.md byte-identical" {
	require_age
	install_key
	run run_env
	assert_contains "status=0" "status=$status"
	cp "$HOME/.claude/CLAUDE.md" "$D/first-claude.md"
	cp "$HOME/.claude/PROSE.md" "$D/first-prose.md"
	cp "$HOME/.claude/VOICE.md" "$D/first-voice.md"
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "same" "$(same_bytes "$HOME/.claude/CLAUDE.md" "$D/first-claude.md")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/PROSE.md" "$D/first-prose.md")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/VOICE.md" "$D/first-voice.md")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/CLAUDE.md" "$EXPECTED")"
}

@test "remote-bootstrap.sh twice with a key leaves CLAUDE.md, PROSE.md and VOICE.md byte-identical" {
	require_age
	install_key
	run run_bootstrap
	assert_contains "status=0" "status=$status"
	cp "$HOME/.claude/CLAUDE.md" "$D/first-claude.md"
	cp "$HOME/.claude/PROSE.md" "$D/first-prose.md"
	cp "$HOME/.claude/VOICE.md" "$D/first-voice.md"
	run run_bootstrap
	assert_contains "status=0" "status=$status"
	assert_contains "same" "$(same_bytes "$HOME/.claude/CLAUDE.md" "$D/first-claude.md")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/PROSE.md" "$D/first-prose.md")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/VOICE.md" "$D/first-voice.md")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/CLAUDE.md" "$EXPECTED")"
}

# ---- 4. a usable key (criterion 4, Decisions 2-3) ----

@test "a non-empty key makes env-setup.sh decrypt PROSE.md and VOICE.md and skip the amendment" {
	require_age
	install_key
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "same" "$(same_bytes "$HOME/.claude/PROSE.md" "$PROSE_PLAIN")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/VOICE.md" "$VOICE_PLAIN")"
	assert_not_contains "$AMENDMENT_HEAD" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_not_contains "no age key" "$(cat "$HOME/.claude/CLAUDE.md")"
}

@test "a non-empty key makes remote-bootstrap.sh decrypt PROSE.md and VOICE.md and skip the amendment" {
	require_age
	install_key
	run run_bootstrap
	assert_contains "status=0" "status=$status"
	assert_contains "same" "$(same_bytes "$HOME/.claude/PROSE.md" "$PROSE_PLAIN")"
	assert_contains "same" "$(same_bytes "$HOME/.claude/VOICE.md" "$VOICE_PLAIN")"
	assert_not_contains "$AMENDMENT_HEAD" "$(cat "$HOME/.claude/CLAUDE.md")"
}

# ---- 5. no usable key (criterion 5, Decisions 3-4) ----
# The 0-byte case is the falsifier: a failed `op read` leaves an empty key.txt behind, and a check by existence instead of size would try to decrypt with it.

@test "with no key file, env-setup.sh appends the amendment and installs neither PROSE.md nor VOICE.md" {
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "$AMENDMENT_HEAD" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "$AMENDMENT_BODY" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/PROSE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/VOICE.md")"
}

@test "with a 0-byte key file, env-setup.sh appends the amendment and installs neither PROSE.md nor VOICE.md" {
	stub_age
	mkdir -p "$(dirname "$KEY")"
	: >"$KEY"
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "$AMENDMENT_HEAD" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "$AMENDMENT_BODY" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/PROSE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/VOICE.md")"
	assert_not_contains "key.txt" "$(cat "$AGE_LOG" 2>/dev/null)"
}

@test "with no key file, remote-bootstrap.sh appends the amendment and installs neither PROSE.md nor VOICE.md" {
	run run_bootstrap
	assert_contains "status=0" "status=$status"
	assert_contains "$AMENDMENT_HEAD" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "$AMENDMENT_BODY" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/PROSE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/VOICE.md")"
}

@test "with a 0-byte key file, remote-bootstrap.sh appends the amendment and installs neither PROSE.md nor VOICE.md" {
	stub_age
	mkdir -p "$(dirname "$KEY")"
	: >"$KEY"
	run run_bootstrap
	assert_contains "status=0" "status=$status"
	assert_contains "$AMENDMENT_HEAD" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "$AMENDMENT_BODY" "$(cat "$HOME/.claude/CLAUDE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/PROSE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/VOICE.md")"
	assert_not_contains "key.txt" "$(cat "$AGE_LOG" 2>/dev/null)"
}

# The amendment tells agents PROSE.md and VOICE.md weren't installed, so copies left by an earlier keyed run would make it false.
@test "a run without the key after a keyed run removes PROSE.md and VOICE.md and adds the amendment once" {
	require_age
	install_key
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "present" "$(present "$HOME/.claude/PROSE.md")"
	rm -f "$KEY"
	run run_env
	assert_contains "status=0" "status=$status"
	assert_contains "absent" "$(present "$HOME/.claude/PROSE.md")"
	assert_contains "absent" "$(present "$HOME/.claude/VOICE.md")"
	assert_contains "count=1" "count=$(grep -cxF "$AMENDMENT_HEAD" "$HOME/.claude/CLAUDE.md")"
	assert_contains "$AMENDMENT_BODY" "$(cat "$HOME/.claude/CLAUDE.md")"
}

# ---- 6. whole skill folders (criterion 6, Decision 7) ----

@test "remote-bootstrap.sh installs each named skill as a whole folder" {
	build_skills
	run run_bootstrap alpha beta
	assert_contains "status=0" "status=$status"
	assert_contains "alpha body" "$(cat "$HOME/.claude/skills/alpha/SKILL.md")"
	assert_contains "alpha reference content" "$(cat "$HOME/.claude/skills/alpha/references/x.md")"
	assert_contains "beta body" "$(cat "$HOME/.claude/skills/beta/SKILL.md")"
	assert_contains "beta helper" "$(cat "$HOME/.claude/skills/beta/scripts/y.sh")"
}

# ---- 7. already-synced skills (criterion 7, Decision 7) ----

@test "a skill under a symlinked synced bucket is skipped and not copied" {
	build_skills
	mkdir -p "$D/real-bucket/alpha" "$HOME/.claude/skills/synced"
	printf -- '---\nname: alpha\n---\nsynced alpha\n' >"$D/real-bucket/alpha/SKILL.md"
	ln -s "$D/real-bucket" "$HOME/.claude/skills/synced/bucket"
	run run_bootstrap alpha beta
	assert_contains "status=0" "status=$status"
	assert_contains "synced" "$output"
	assert_contains "absent" "$(present "$HOME/.claude/skills/alpha")"
	assert_contains "beta body" "$(cat "$HOME/.claude/skills/beta/SKILL.md")"
}

# ---- 8. unknown names (Decisions 6-7) ----

@test "an unknown skill name makes remote-bootstrap.sh exit 1 and name it, while the known one installs" {
	build_skills
	run --separate-stderr run_bootstrap nosuchskill alpha
	assert_contains "status=1" "status=$status"
	assert_contains "nosuchskill" "$stderr"
	assert_contains "alpha body" "$(cat "$HOME/.claude/skills/alpha/SKILL.md")"
	assert_contains "alpha reference content" "$(cat "$HOME/.claude/skills/alpha/references/x.md")"
}

# ---- 9. neither script deploys (criterion 8) ----

@test "chezmoi managed lists no path for either script" {
	if [ -z "$REAL_CHEZMOI" ]; then
		skip "chezmoi not installed on this machine"
	fi
	local cfg="$D/role.toml"
	printf '[data]\n  machine_role = "work"\n' >"$cfg"
	run "$REAL_CHEZMOI" managed --source "$SRC" --destination "$HOME" --config "$cfg"
	assert_contains "status=0" "status=$status"
	# Positive control: the listing really covers this repo's deployable files.
	assert_contains ".claude/CLAUDE.md"
	assert_not_contains "env-setup"
	assert_not_contains "remote-bootstrap"
}
