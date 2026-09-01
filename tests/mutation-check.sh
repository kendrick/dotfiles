#!/usr/bin/env bash
#
# tests/mutation-check.sh — proves each converted assertion still turns its
# own @test case red when its condition is false (constitution clause V-2,
# kendrick/dotfiles#21). Syntax checks and a green suite both stay silent
# about a helper call whose condition can never fail; this is what catches
# that.
#
# For each recognised site it: backs the containing file up, inverts that
# one assertion, runs bats scoped to that file, confirms the mutated case
# — by name — reports "not ok" in TAP output, then restores from the
# backup and moves on. Judgment is by TAP, never by exit status: a mutation
# that breaks bash parsing collapses the whole file to a single synthetic
# "not ok 1 setup_file failed" with the case under test never having run at
# all, and a script reading exit codes would call that a pass.
#
# No `set -e`: every command whose failure matters here is already guarded
# by an explicit `if`/`while`, so errexit buys nothing — and bash 3.2's
# errexit bug (a bare `[[ ]]`/`(( ))` statement can silently fail to abort;
# see tests/helpers.bash) is sidestepped entirely by never using either as a
# bare statement in this file. `[[ ]]` appears below only inside `if`/
# `while` conditions, where `if`/`while` — not `[[` — is the first token of
# the line and captures the exit status directly.
set -u

# Restore must never be `git checkout`: this is a committed, reusable tool a
# developer runs against a dirty working tree, and `git checkout` there
# discards their uncommitted work. Every restore below is a copy from a
# backup taken immediately before that one mutation.
CURRENT_BACKUP=""
CURRENT_TARGET=""
WORKDIR=""

cleanup() {
	if [ -n "$CURRENT_BACKUP" ]; then
		if [ -f "$CURRENT_BACKUP" ]; then
			cp "$CURRENT_BACKUP" "$CURRENT_TARGET"
		fi
		rm -f "$CURRENT_BACKUP"
		CURRENT_BACKUP=""
	fi
	if [ -n "$WORKDIR" ]; then
		if [ -d "$WORKDIR" ]; then
			rm -rf "$WORKDIR"
		fi
	fi
}
trap cleanup EXIT INT TERM

if command -v git >/dev/null 2>&1; then
	if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
		cd "$root" || exit 1
	fi
fi

# The guarded surface's six converted files (T-002..T-005), and no others.
#
# tests/install-failures.bats is excluded by name: its 30 assert_contains/
# assert_not_contains call sites predate this job (#17) and, since T-001
# moved the helper definitions into tests/helpers.bash, resolve to the exact
# same functions these do. They are formally indistinguishable from this
# job's conversions, so scanning that file would overcount.
#
# tests/lint.bats is excluded by name too: it is the reintroduction guard
# added by this job (V-1), not a conversion target, and counting any helper
# call it happens to make would inflate the per-file totals below.
ALL_FILES="tests/apps.bats tests/doctor.bats tests/font.bats tests/font-add.bats tests/jsonc.bats tests/licensed-fonts.bats tests/packages.bats"

usage() {
	echo "usage: tests/mutation-check.sh [FILE]" >&2
	echo "  FILE, if given, must be one of:" >&2
	for f in $ALL_FILES; do
		echo "    $f" >&2
	done
}

TARGET_FILES="$ALL_FILES"
if [ "$#" -gt 1 ]; then
	usage
	exit 2
fi
if [ "$#" -eq 1 ]; then
	match=0
	for f in $ALL_FILES; do
		if [ "$f" = "$1" ]; then
			match=1
		fi
	done
	if [ "$match" -ne 1 ]; then
		echo "tests/mutation-check.sh: '$1' is not one of the six converted files" >&2
		usage
		exit 2
	fi
	TARGET_FILES="$1"
fi

echo "mutation-check: scanning $TARGET_FILES"
echo "mutation-check: excluded by name — tests/install-failures.bats (30 pre-existing call sites, predate this job), tests/lint.bats (the reintroduction guard, not a conversion target)"
echo "mutation-check: excluded by shape — tests/packages.bats's [ -n \"\$cask\" ] || continue is loop control, not an assertion; inverting it would change which iterations run rather than make a case fail"

WORKDIR="$(mktemp -d)"
SITES_FILE="$WORKDIR/sites"
UNRECOGNISED_FILE="$WORKDIR/unrecognised"
: >"$SITES_FILE"
: >"$UNRECOGNISED_FILE"

# Prints "LINENO:CONTENT" for every line of FILE that is not inside a
# heredoc body — a JSON fixture's own bare `true`, or a stub script's own
# `esac`, must never be mistaken for a converted assertion or for the end of
# a @test body. Recognises `<<DELIM`, `<<-DELIM`, `<<'DELIM'`, `<<"DELIM"`,
# and does not mistake a here-string (`<<<`) for a heredoc start.
strip_heredocs() {
	awk -v sq="'" -v dq='"' '
		BEGIN { in_heredoc = 0; delim = ""; strip_tabs = 0 }
		{
			if (in_heredoc) {
				candidate = $0
				if (strip_tabs) { sub(/^\t+/, "", candidate) }
				if (candidate == delim) { in_heredoc = 0 }
				next
			}
			line = $0
			idx = index(line, "<<")
			if (idx > 0 && substr(line, idx, 3) != "<<<") {
				rest = substr(line, idx + 2)
				# `<<-DELIM` lets the terminator line be tab-indented; a
				# plain `<<DELIM` requires it at column 0. font.bats uses
				# the dash form for its stub scripts.
				if (substr(rest, 1, 1) == "-") {
					strip_tabs = 1
					rest = substr(rest, 2)
				} else {
					strip_tabs = 0
				}
				gsub(/^[ \t]+/, "", rest)
				first = substr(rest, 1, 1)
				if (first == sq || first == dq) {
					rest = substr(rest, 2)
					e = index(rest, first)
					if (e > 0) { d = substr(rest, 1, e - 1) } else { d = rest }
				} else {
					sp = index(rest, " ")
					if (sp > 0) { d = substr(rest, 1, sp - 1) } else { d = rest }
				}
				delim = d
				in_heredoc = 1
			}
			print NR ":" line
		}
	' "$1"
}

# Walks backward from a candidate line to the nearest preceding
# `@test "..." {` header and prints its name. Stops at an unindented `}`
# first if one is hit — that means the candidate sits between two tests (or
# inside a plain helper function such as setup()) and has no enclosing case.
# Column-0 `}` is a safe boundary here: every @test/function body in these
# six files is closed by an unindented `}`, while any `{ ...; }` command
# group or `${...}` expansion nested inside a body is always indented —
# verified against all six files before this script was written, and it is
# what lets this locate the doctor.bats disjunction without a line pin.
find_enclosing_test() {
	file="$1"
	target_line="$2"
	n=$((target_line - 1))
	while [ "$n" -ge 1 ]; do
		text="$(strip_heredocs "$file" | awk -v n="$n" '{ pat = "^" n ":"; if (sub(pat, "")) { print; exit } }')"
		if [[ "$text" =~ ^@test\ \"(.*)\"\ \{[[:space:]]*$ ]]; then
			printf '%s' "${BASH_REMATCH[1]}"
			return 0
		fi
		if [[ "$text" =~ ^\}[[:space:]]*$ ]]; then
			return 1
		fi
		n=$((n - 1))
	done
	return 1
}

record_site() {
	kind="$1" file="$2" line="$3"
	testname="$(find_enclosing_test "$file" "$line")"
	if [ -z "$testname" ]; then
		printf '%s\t%s\t%s\t\n' "$kind" "$file" "$line" >>"$UNRECOGNISED_FILE"
	else
		printf '%s\t%s\t%s\t%s\n' "$kind" "$file" "$line" "$testname" >>"$SITES_FILE"
	fi
}

# The mutation rule's first shape: a call to assert_contains or
# assert_not_contains, inverted by swapping the name (V-2).
enumerate_helper_calls() {
	file="$1"
	strip_heredocs "$file" |
		grep -E '^[0-9]+:[[:space:]]*(assert_contains|assert_not_contains)[[:space:]]' |
		while IFS=: read -r ln rest; do
			if printf '%s' "$rest" | grep -qE '^[[:space:]]*assert_contains[[:space:]]'; then
				record_site "helper:assert_contains" "$file" "$ln"
			else
				record_site "helper:assert_not_contains" "$file" "$ln"
			fi
		done
}

# The mutation rule's second shape: doctor.bats's one restructured
# disjunction, `case "$output" in *undeclared* | *casks*) ;; ...`. Located
# by its needle strings, not by line number — a line pin here would go
# stale on the next edit to a file this script is meant to outlive.
enumerate_case_block() {
	file="$1"
	# Matches the case *arm* — `*undeclared*` / `*casks*` as glob needles —
	# not just any line mentioning both words. The @test header above it
	# ("...reported as undeclared" / "no casks key...") contains both words
	# too, in prose rather than as a pattern, and must not match here.
	ln="$(strip_heredocs "$file" | grep -E '^[0-9]+:.*\*undeclared\*.*\*casks\*' | awk -F: '{ print $1; exit }')"
	if [ -n "$ln" ]; then
		record_site "case" "$file" "$ln"
	fi
}

# Any line, inside a @test body, whose entire content is a bare `true`,
# `false`, or `:` — the shape a converted assertion collapses to if it is
# ever replaced with something this script's two known forms don't cover.
# Reported as unrecognised rather than silently absent from the count.
enumerate_unrecognised_placeholders() {
	file="$1"
	strip_heredocs "$file" |
		grep -E '^[0-9]+:[[:space:]]*(true|false|:)[;]?[[:space:]]*$' |
		while IFS=: read -r ln _rest; do
			testname="$(find_enclosing_test "$file" "$ln")"
			if [ -n "$testname" ]; then
				printf 'placeholder\t%s\t%s\t%s\n' "$file" "$ln" "$testname" >>"$UNRECOGNISED_FILE"
			fi
		done
}

for target in $TARGET_FILES; do
	enumerate_helper_calls "$target"
	if [ "$target" = "tests/doctor.bats" ]; then
		enumerate_case_block "$target"
	fi
	enumerate_unrecognised_placeholders "$target"
done

if [ -s "$UNRECOGNISED_FILE" ]; then
	echo "mutation-check: found a converted-assertion site in a form this script does not recognise:" >&2
	while IFS=$'\t' read -r kind file ln _testname; do
		echo "  $file:$ln" >&2
	done <"$UNRECOGNISED_FILE"
	echo "mutation-check: recognised forms are assert_contains/assert_not_contains calls, and doctor.bats's undeclared/casks disjunction. Fix the site above or exclude it by name." >&2
	exit 1
fi

# Mutates FILE at LINE in place. `from`/`to` have no regex metacharacters
# (they are always one of the two helper names, or the fixed sentinel), so
# awk's dynamic-regexp sub() is safe here.
mutate_word() {
	file="$1" line="$2" from="$3" to="$4"
	awk -v ln="$line" -v from="$from" -v to="$to" '
		NR == ln { sub(from, to) }
		{ print }
	' "$file" >"$file.mutated"
	mv "$file.mutated" "$file"
}

mutate_case_needles() {
	file="$1" line="$2"
	sentinel="ZZZ_MUTATION_SENTINEL_ZZZ"
	awk -v ln="$line" -v s="$sentinel" '
		NR == ln { gsub(/undeclared/, s); gsub(/casks/, s) }
		{ print }
	' "$file" >"$file.mutated"
	mv "$file.mutated" "$file"
}

# True only if TAP output contains a "not ok N <NAME>" line for the exact
# test name NAME — compared verbatim, not as a regex, so parens/brackets/
# quotes in a test's own description can't be misread as pattern
# metacharacters. A file-level non-zero bats exit is not this proof: a
# mutation that breaks bash parsing collapses the run to a single synthetic
# "not ok 1 setup_file failed" while the case under test never ran, and
# reading exit status alone would call that a pass.
tap_reports_not_ok() {
	tap="$1" name="$2"
	found=1
	while IFS= read -r tline; do
		if [[ "$tline" =~ ^not\ ok\ [0-9]+\ (.*)$ ]]; then
			if [ "${BASH_REMATCH[1]}" = "$name" ]; then
				found=0
			fi
		fi
	done <<TAPOUT
$tap
TAPOUT
	return "$found"
}

total_sites=$(wc -l <"$SITES_FILE" | tr -d ' ')
site_index=0
overall_status=0

while IFS=$'\t' read -r kind file line testname; do
	site_index=$((site_index + 1))

	CURRENT_TARGET="$file"
	CURRENT_BACKUP="$(mktemp)"
	if ! cp "$file" "$CURRENT_BACKUP"; then
		echo "mutation-check: could not back up $file before mutating — aborting without changes" >&2
		exit 1
	fi

	case "$kind" in
	helper:assert_contains)
		mutate_word "$file" "$line" "assert_contains" "assert_not_contains"
		;;
	helper:assert_not_contains)
		mutate_word "$file" "$line" "assert_not_contains" "assert_contains"
		;;
	case)
		mutate_case_needles "$file" "$line"
		;;
	esac

	tap_output="$(bats --formatter tap "$file" 2>&1)"

	if tap_reports_not_ok "$tap_output" "$testname"; then
		echo "site [$site_index/$total_sites] $file:$line test=\"$testname\" -> not ok (wired in)"
	else
		echo "site [$site_index/$total_sites] $file:$line test=\"$testname\" -> DID NOT REPORT not ok — dead assertion or broken mutation" >&2
		overall_status=1
	fi

	cp "$CURRENT_BACKUP" "$file"
	rm -f "$CURRENT_BACKUP"
	CURRENT_BACKUP=""
done <"$SITES_FILE"

echo "--- summary, by file ---"
awk -F'\t' '{ counts[$2]++ } END { for (f in counts) print f": "counts[f] }' "$SITES_FILE" | sort
echo "total: $total_sites"

if [ "$overall_status" -eq 0 ]; then
	echo "mutation-check: all $total_sites sites turned their case red when inverted"
else
	echo "mutation-check: one or more sites did not turn red — see FAILs above" >&2
fi

exit "$overall_status"
