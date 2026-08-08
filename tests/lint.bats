#!/usr/bin/env bats
#
# bash 3.2 — /bin/bash, what bats itself runs these test bodies under — has a
# genuine errexit bug: a failing `[[ ]]` or `(( ))` does not abort the
# function unless it is the last statement executed, so a bare compound
# reintroduced anywhere in command position — as a line's first word, or
# after `;`, `&&`, `||`, `then`, `do`, `else`, or inside a `{ ...; }` group —
# silently stops gating anything that follows it (see tests/helpers.bash for
# the hand-confirmed repro). Every bare compound statement on the guarded
# surface was converted away for exactly that reason. This case is what
# stops one coming back.
#
# `[[`/`((` right after `if`, `elif`, `while`, or `until` is the idiomatic,
# safe form: the condition's exit status controls the branch regardless of
# the bug, so those positions are deliberately not scanned. Only a compound
# in command position — where a failure would otherwise have to propagate
# on its own — is a violation.
#
# The guarded surface also legitimately contains those two characters inside
# `grep -oE` patterns, inside `[[:space:]]` character classes in
# single-bracket tests, inside `$(( ))` arithmetic expansions, inside
# `if [[ ... ]]; then` conditions, and inside comments — including this
# file's own, and the ones in tests/helpers.bash and tests/mutation-check.sh
# that describe this very bug. Comment-only lines are dropped outright,
# which is what lets this file name — and work an example of — the pattern
# it forbids without matching itself.

load 'helpers'

@test "no bare [[ or (( on the guarded surface" {
	# The guarded surface, fixed by constitution clause B-1: every *.bats
	# file, the shared helpers, and the mutation script itself — all three
	# run under the same bash 3.2 and are equally able to reintroduce the bug.
	# Resolved from BATS_TEST_DIRNAME, never $PWD: a checker that copies this
	# suite into a scratch worktree and plants a canary there must have that
	# canary scanned, not the real working tree this process happens to be
	# running from.
	local -a files=("$BATS_TEST_DIRNAME"/*.bats "$BATS_TEST_DIRNAME/helpers.bash" "$BATS_TEST_DIRNAME/mutation-check.sh")

	# `[[`/`((` at the start of a line, or immediately after `;`, `{`, `&&`,
	# `||`, `then`, `do`, or `else`. `if`/`elif`/`while`/`until` are left out
	# on purpose — a compound there is already a safe condition, not a bare
	# statement. Every one of those separators requires an actual space
	# before the bracket: real shell code always writes one (`; [[`, `&& [[`,
	# `{ [[`), and requiring it is what keeps this line's own pattern text —
	# which necessarily spells `;[[:space:]]`, `&&[[:space:]]`, `\{[[:space:]]`
	# and so on with no space at all between the separator and the literal
	# `[[` — from matching itself, the same trap an escaped `\{` right
	# before a `[[:space:]]` class sets in tests/mutation-check.sh.
	local pattern='(^[[:space:]]*|;[[:space:]]+|&&[[:space:]]+|\|\|[[:space:]]+|\{[[:space:]]+|\bthen\b[[:space:]]+|\bdo\b[[:space:]]+|\belse\b[[:space:]]+)(\[\[|\(\()'

	local all_hits=""
	local f raw rstatus filtered fstatus

	for f in "${files[@]}"; do
		# bats runs @test bodies under `set -e`. A bare `raw="$(grep ...)"`
		# would abort the whole case the moment grep's clean-pass exit 1
		# hits errexit, before `rstatus` is ever read — the same class of
		# bug this guard exists to keep out, just via a command
		# substitution instead of a bare `[[`. The `&&`/`||` keeps the exit
		# status in a conditional context, which set -e leaves alone.
		raw="$(/usr/bin/grep -nE "$pattern" "$f" 2>&1)" && rstatus=0 || rstatus=$?

		# Exit 2 means grep couldn't open the file or the pattern failed to
		# compile — a broken check, not a clean one.
		if [ "$rstatus" -eq 2 ]; then
			echo "lint check itself failed to run on $f:"
			echo "$raw"
			return 1
		fi

		if [ "$rstatus" -eq 1 ]; then
			continue
		fi

		# The pattern above has no way to say "not inside a comment", so a
		# candidate line is only a real violation once a line that is
		# entirely `#`-prose has been ruled out. grep -n bakes the line
		# number into the text before this second pass runs, so filtering
		# here does not renumber anything that survives it.
		filtered="$(printf '%s\n' "$raw" | /usr/bin/grep -vE '^[0-9]+:[[:space:]]*#')" && fstatus=0 || fstatus=$?

		if [ "$fstatus" -eq 2 ]; then
			echo "lint check itself failed to run on $f:"
			echo "$filtered"
			return 1
		fi

		if [ "$fstatus" -eq 1 ]; then
			continue
		fi

		all_hits+="$(printf '%s\n' "$filtered" | sed "s|^|$f:|")"$'\n'
	done

	if [ -n "$all_hits" ]; then
		echo "bare [[ or (( found in command position — convert to a helper call or single-bracket test:"
		printf '%s' "$all_hits"
		return 1
	fi

	return 0
}
