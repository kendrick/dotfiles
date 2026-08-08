---
task: T-008
checker: checker-judgment
vendor: openai
model: gpt-5.6
verdict: PASS
checked_at: 2026-08-08T00:00:00Z
duration_ms: None
cost_usd: None
---

<!-- GENERATED FILE—do not hand-edit. Rendered by render-verdict.py
from the verdict JSON, the record of record. Edit the JSON and
re-render instead. -->

## Per-clause results

| clause | severity | description | evidence |
| ------ | -------- | ------------ | -------- |
| durability | minor | General rule: 'Under `set -e`, a failing `[[ ]]` or `(( ))` doesn't abort.' It establishes the relevant construct and execution context. | conventions.md (provided excerpt), sentence 1 |
| durability | minor | General rule: 'The failure is discarded unless the construct is the enclosing function's literal last statement, so `f() { [[ 1 -eq 2 ]]; echo reached; }` prints `reached` and exits 0.' It explains that statement position within a function—not line start—controls the hazard. | conventions.md (provided excerpt), sentence 2 |
| durability | minor | General rule, explicitly rejecting the narrow reading: 'A semicolon is no escape either (`true; [[ 1 -eq 2 ]]; echo reached` prints it too), which is why the rule is "never use either as a statement" rather than "never start a line with one".' | conventions.md (provided excerpt), sentence 3 |
| durability | minor | General rule: 'Loops are where it hides longest: `for i in 1 2 3; do [[ $i -ge 3 ]]; done` exits 0, so only the last iteration's result survives.' This extends the warning beyond line-leading forms. | conventions.md (provided excerpt), sentence 4 |
| durability | minor | General rule: '`[ ]`, `grep`, and a function returning non-zero all propagate from every one of those positions.' It distinguishes the unsafe compound statements from alternatives across positions. | conventions.md (provided excerpt), sentence 5 |
| durability | minor | General rule: 'Assert with `assert_contains` and `assert_not_contains` from `tests/helpers.bash`, never with a bare `[[ ]]` or `(( ))`; the bash 3.2 bullet above is the why.' | conventions.md (provided excerpt), first bullet, sentence 1 |
| durability | minor | General rule: '`tests/lint.bats` fails the whole suite if a bare `[[` or `((` comes back in command position anywhere on `tests/*.bats`, `tests/helpers.bash`, or `tests/mutation-check.sh`.' 'Command position anywhere' directly prevents a first-token or line-start interpretation. | conventions.md (provided excerpt), second bullet, sentence 1 |
| durability | minor | General rule with explicit boundary: 'A compound used as an `if` or `while` condition is left alone on purpose: the branch consumes its exit status, so the bug can't reach it there.' This preserves the role-based exception without suggesting a line-position exception. | conventions.md (provided excerpt), second bullet, sentence 2 |
| durability | minor | General rule: 'The rule is about role, not position.' | decisionLog.md (provided 2026-08-08 entry), heading sentence |
| durability | minor | General rule, explicitly rejecting the narrow reading: '`true; [[ 1 -eq 2 ]]; echo reached` prints `reached` — a semicolon is not a fresh start as far as errexit is concerned, so "don't start a line with `[[`" was never the rule and "never use either as a statement" is.' | decisionLog.md (provided 2026-08-08 entry), sentence 1 |
| durability | minor | General rule: 'The guard's first draft was a first-token grep and passed a planted `true; [[ 1 -eq 2 ]]` clean, which is how that got noticed; it now looks for a compound in command position generally.' This records the exact failed narrow implementation and its correction. | decisionLog.md (provided 2026-08-08 entry), sentence 2 |
| durability | minor | General rule with explicit boundary: '`if` and `while` conditions are deliberately left unscanned, because a compound there is a condition whose status the branch consumes rather than a statement that has to propagate on its own.' | decisionLog.md (provided 2026-08-08 entry), sentence 3 |
| durability | minor | Conclusion: No. A reader of only these files should not reasonably conclude 'do not start a line with them'; both files explicitly contrast and reject that wording, supply the semicolon counterexample, and state the durable role-based formulation. | conventions.md and decisionLog.md (provided excerpts) |
