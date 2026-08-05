#!/usr/bin/env bats
#
# The `font` switcher reads VS Code's settings, which are JSONC and will stay
# that way: Prettier runs on save and re-adds trailing commas faster than anyone
# can delete them. These tests pin the one distinction that matters. Commas are
# the formatter's, so they get tolerated silently. Comments are the user's, so a
# file carrying them must fail rather than get quietly rewritten without them.

FILTER="${BATS_TEST_DIRNAME}/../dot_config/font/jsonc.jq"
SETTINGS="${BATS_TEST_DIRNAME}/../private_Library/private_Application Support/Code/User/settings.json"

read_jsonc() {
	jq -Rs -f "$FILTER" "$1"
}

@test "strips a trailing comma before a closing brace" {
	echo '{"a": 1,}' >"$BATS_TEST_TMPDIR/in.json"
	run read_jsonc "$BATS_TEST_TMPDIR/in.json"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -c .)" = '{"a":1}' ]
}

@test "strips a trailing comma before a closing bracket" {
	echo '{"a": [1, 2,]}' >"$BATS_TEST_TMPDIR/in.json"
	run read_jsonc "$BATS_TEST_TMPDIR/in.json"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -c .)" = '{"a":[1,2]}' ]
}

# The reason the filter can't be a sed one-liner: editor.fontFamily is a
# comma-separated fallback chain, so a value ending in ", }" is the exact shape
# a naive regex would corrupt, in the exact key the switcher rewrites.
@test "leaves a comma-then-brace living inside a string alone" {
	printf '{"a": "x, }", "b": [1,],}\n' >"$BATS_TEST_TMPDIR/in.json"
	run read_jsonc "$BATS_TEST_TMPDIR/in.json"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -c .)" = '{"a":"x, }","b":[1]}' ]
}

@test "survives an escaped quote inside a string" {
	printf '{"a": "he said \\"go,\\" ok", "b": [1,],}\n' >"$BATS_TEST_TMPDIR/in.json"
	run read_jsonc "$BATS_TEST_TMPDIR/in.json"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.a')" = 'he said "go," ok' ]
}

@test "leaves strict JSON untouched" {
	printf '{"a": 1, "b": [1, 2]}\n' >"$BATS_TEST_TMPDIR/in.json"
	run read_jsonc "$BATS_TEST_TMPDIR/in.json"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -c .)" = '{"a":1,"b":[1,2]}' ]
}

# Both comment cases assert on the parse error specifically. A bare non-zero
# check would also pass with the filter file deleted, which is the one way these
# two could go green while the thing they guard is gone.
@test "refuses a file with line comments rather than stripping them" {
	printf '{\n\t// keep me\n\t"a": 1,\n}\n' >"$BATS_TEST_TMPDIR/in.json"
	run read_jsonc "$BATS_TEST_TMPDIR/in.json"
	[ "$status" -ne 0 ]
	[[ "$output" == *"while parsing"* ]]
}

@test "refuses a file with block comments rather than stripping them" {
	printf '{\n\t/* keep me */\n\t"a": 1,\n}\n' >"$BATS_TEST_TMPDIR/in.json"
	run read_jsonc "$BATS_TEST_TMPDIR/in.json"
	[ "$status" -ne 0 ]
	[[ "$output" == *"while parsing"* ]]
}

@test "reads this machine's real VS Code settings" {
	run read_jsonc "$SETTINGS"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.["editor.fontLigatures"]')" = "true" ]
}

# Byte-identical, not merely parseable: the fallback chain carries the double
# space and mixed quoting it was written with, and the switcher has to rewrite
# that value without disturbing anything it didn't mean to touch.
@test "returns editor.fontFamily byte-identical to its input" {
	expected=$(grep -o '"editor\.fontFamily": ".*"' "$SETTINGS" | sed 's/^"editor\.fontFamily": "//; s/"$//')
	run read_jsonc "$SETTINGS"
	[ "$status" -eq 0 ]
	[ "$(echo "$output" | jq -r '.["editor.fontFamily"]')" = "$expected" ]
}
