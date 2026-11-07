#!/usr/bin/env bats
#
# Capture used to rewrite the shared plugin manifests from one machine's live state, so a
# personal Mac, which installs only the public allowlist, dropped every work-only plugin
# from the record and then never installed anything it hadn't already got. These cases
# pin the merge rule: (source ∪ installed here) − removed, where an uninstall through the
# `claude` wrapper is what records a removal.
#
# Every case runs the real helper (and, for the wrapper, the real functions.zsh) against a
# throwaway source dir under a synthetic $HOME. `chezmoi` is stubbed with identity
# encrypt/decrypt, so the source files hold the plaintext the install template decrypts,
# and assertions read the keys that template ranges over: `.plugins` for specs and the
# top level for marketplaces.

load 'helpers'

SRC="${BATS_TEST_DIRNAME}/.."
HELPER="$SRC/dot_local/bin/executable_claude-plugins-capture"

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	export STUBS="$BATS_TEST_TMPDIR/stubs"
	export CHEZMOI_SRC="$BATS_TEST_TMPDIR/source"
	LIVE="$HOME/.claude/plugins"
	DIR="$CHEZMOI_SRC/dot_claude/private_plugins"
	mkdir -p "$STUBS" "$LIVE" "$DIR"
	cat >"$STUBS/chezmoi" <<STUB
#!/bin/sh
case "\$1" in
source-path) echo "$CHEZMOI_SRC" ;;
decrypt) cat "\$2" ;;
encrypt) cat ;;
*) exit 1 ;;
esac
STUB
	# Mimics the CLI: install/uninstall edits the live manifests, then exits 0.
	cat >"$STUBS/claude" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
live = os.path.expanduser("~/.claude/plugins/installed_plugins.json")
d = json.load(open(live))
args = [a for a in sys.argv[1:] if not a.startswith("-")]
if args[:2] == ["plugin", "uninstall"]:
    d["plugins"].pop(args[2], None)
elif args[:2] == ["plugin", "install"]:
    d["plugins"][args[2]] = [{"scope": "user", "installPath": "/x", "version": "1"}]
json.dump(d, open(live, "w"))
STUB
	chmod +x "$STUBS"/*
	# The source file is mode 644; chezmoi sets the bit on deploy from the executable_ prefix.
	printf '#!/bin/sh\nexec python3 "%s" "$@"\n' "$HELPER" >"$STUBS/claude-plugins-capture"
	chmod +x "$STUBS/claude-plugins-capture"
}

# live_plugins <specs...>: this Mac's installed_plugins.json, with the machine-local fields
# the CLI writes, which capture has to strip.
live_plugins() {
	python3 -c '
import json, sys
print(json.dumps({"version": 2, "plugins": {s: [{"scope": "user", "installPath": "/Users/me/.claude/plugins/cache/" + s, "version": "1.0.0", "gitCommitSha": "abc", "installedAt": "2026-11-07T00:00:00Z"}] for s in sys.argv[1:]}}))
' "$@" >"$LIVE/installed_plugins.json"
}

# live_markets <name=owner/repo...>
live_markets() {
	python3 -c '
import json, sys
print(json.dumps({n: {"source": {"source": "github", "repo": r}, "installLocation": "/Users/me/x", "lastUpdated": "now"} for n, r in (a.split("=") for a in sys.argv[1:])}))
' "$@" >"$LIVE/known_marketplaces.json"
}

# seed_source <specs...> -- <name=owner/repo...>: what source already records.
seed_source() {
	python3 -c '
import json, sys
d, a = sys.argv[1], sys.argv[2:]
i = a.index("--")
specs, markets = a[:i], a[i + 1:]
json.dump({"plugins": {s: [{"scope": "user"}] for s in specs}, "version": 2}, open(d + "/encrypted_installed_plugins.json.age", "w"), indent=2)
json.dump({n: {"source": {"repo": r, "source": "github"}} for n, r in (m.split("=") for m in markets)}, open(d + "/encrypted_known_marketplaces.json.age", "w"), indent=2)
' "$DIR" "$@"
}

specs() { python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1]))["plugins"])))' "$DIR/encrypted_installed_plugins.json.age"; }
markets() { python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1])))))' "$DIR/encrypted_known_marketplaces.json.age"; }
tombstones() { python3 -c 'import json,sys; print(",".join(sorted(json.load(open(sys.argv[1]))["plugins"])))' "$DIR/encrypted_removed.json.age"; }

capture() { PATH="$STUBS:/usr/bin:/bin" run python3 "$HELPER" "$@"; }
wrapper() { PATH="$STUBS:/usr/bin:/bin" run zsh -c "source '$SRC/dot_config/zsh/functions.zsh'; $*"; }

# ---- the merge rule ----

@test "a plugin and marketplace only another Mac has stay in source" {
	seed_source work@kit pony@pony -- kit=Corp/kit pony=D/pony
	live_plugins pony@pony
	live_markets pony=D/pony
	capture
	[ "$status" -eq 0 ]
	[ "$(specs)" = "pony@pony,work@kit" ]
	[ "$(markets)" = "kit,pony" ]
}

@test "a plugin installed here joins source with machine-local fields stripped" {
	seed_source work@kit -- kit=Corp/kit
	live_plugins work@kit new@pub
	live_markets kit=Corp/kit pub=P/pub
	capture
	[ "$(specs)" = "new@pub,work@kit" ]
	[ "$(markets)" = "kit,pub" ]
	assert_not_contains "installPath" "$(cat "$DIR"/*.age)"
	assert_not_contains "installLocation" "$(cat "$DIR"/*.age)"
}

@test "unchanged intent rewrites nothing" {
	seed_source a@m -- m=O/m
	live_plugins a@m
	live_markets m=O/m
	capture
	before="$(cat "$DIR"/*.age | cksum)"
	capture
	assert_not_contains "captured"
	assert_contains "$before" "$(cat "$DIR"/*.age | cksum)"
}

# ---- removal ----

@test "uninstall through the wrapper drops the plugin and records it as removed" {
	seed_source a@m b@m -- m=O/m
	live_plugins a@m b@m
	live_markets m=O/m
	wrapper claude plugin uninstall b@m
	[ "$status" -eq 0 ]
	[ "$(specs)" = "a@m" ]
	[ "$(tombstones)" = "b@m" ]
}

@test "a removed plugin another Mac still has doesn't come back on its capture" {
	seed_source a@m -- m=O/m
	echo '{"marketplaces": [], "plugins": ["b@m"]}' >"$DIR/encrypted_removed.json.age"
	live_plugins a@m b@m
	live_markets m=O/m
	capture
	[ "$(specs)" = "a@m" ]
	[ "$(tombstones)" = "b@m" ]
}

@test "installing a removed plugin through the wrapper clears its tombstone" {
	seed_source a@m -- m=O/m
	echo '{"marketplaces": [], "plugins": ["b@m"]}' >"$DIR/encrypted_removed.json.age"
	live_plugins a@m
	live_markets m=O/m
	wrapper claude plugin install b@m --scope user
	[ "$(specs)" = "a@m,b@m" ]
	[ "$(tombstones)" = "" ]
	assert_not_contains "b@m" "$(tombstones)"
}

@test "an unreadable manifest after the command tombstones nothing" {
	seed_source a@m b@m -- m=O/m
	live_plugins a@m b@m
	live_markets m=O/m
	PATH="$STUBS:/usr/bin:/bin" python3 "$HELPER" --snapshot "$BATS_TEST_TMPDIR/snap"
	echo '{"plugins": {' >"$LIVE/installed_plugins.json"
	capture --since "$BATS_TEST_TMPDIR/snap"
	[ "$status" -eq 0 ]
	[ "$(specs)" = "a@m,b@m" ]
	[ ! -e "$DIR/encrypted_removed.json.age" ]
}
