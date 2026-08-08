# bash 3.2 — /bin/bash, what bats itself runs these test bodies under — has a
# genuine errexit bug: a failing `[[ ]]` does not abort the function unless it
# is the function's literal last statement, so any assertion before the last
# one in a multi-assertion @test silently stops gating anything. Confirmed by
# hand: `set -e; f() { [[ 1 -eq 2 ]]; echo reached; }; f` prints "reached" on
# this machine's /bin/bash. `(( ))` behaves identically, and a semicolon is no
# escape — `true; [[ 1 -eq 2 ]]; echo reached` prints it too, so the rule is
# about using either as a statement, not about where the line starts. Worst of
# all is a loop: `for i in 1 2 3; do [[ $i -ge 3 ]]; done` exits 0, so one
# passing iteration erases every failure before it, and no statement has to
# follow the assertion for that to happen. grep and case, used below,
# propagate from all of those positions.
assert_contains() {
	local needle="$1" haystack="${2-$output}"
	grep -qF -- "$needle" <<<"$haystack"
}

assert_not_contains() {
	local needle="$1" haystack="${2-$output}"
	case "$haystack" in
	*"$needle"*) return 1 ;;
	esac
}
