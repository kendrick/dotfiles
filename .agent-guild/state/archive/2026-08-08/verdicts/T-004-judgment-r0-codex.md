# Verdict: T-004 — Courier Second Opinion

**Task:** T-004 — Convert apps.bats: 11 sites with computed haystacks  
**Checker:** checker-courier (second opinion, lane: codex)  
**Vendor:** openai | **Model:** gpt-5.6-terra  
**Verdict:** PASS  
**Timestamp:** 2026-08-08

---

## Findings

### Conversion 1 (Line 135→137)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `bundles = ["media"]`, passes the unchanged `$(registry_line 'owner/repo/x')` haystack as argument two, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$(registry_line 'owner/repo/x')" == *'bundles = ["media"]'* ]]` → Current: `assert_contains 'bundles = ["media"]' "$(registry_line 'owner/repo/x')"`

### Conversion 2 (Line 142→144)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `["cloud"]`, passes the unchanged `$(registry_line spotify)` haystack as argument two, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$(registry_line spotify)" == *'["cloud"]'* ]]` → Current: `assert_contains '["cloud"]' "$(registry_line spotify)"`

### Conversion 3 (Line 143→145)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `["cloud"]`, passes the unchanged `$(registry_line 1password)` haystack as argument two, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$(registry_line 1password)" == *'["cloud"]'* ]]` → Current: `assert_contains '["cloud"]' "$(registry_line 1password)"`

### Conversion 4 (Line 150→152)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `bundles = ["core", "media"]`, passes the unchanged `$(registry_line spotify)` haystack as argument two, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$(registry_line spotify)" == *'bundles = ["core", "media"]'* ]]` → Current: `assert_contains 'bundles = ["core", "media"]' "$(registry_line spotify)"`

### Conversion 5 (Line 190→192, with trailing comma)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `{ name = "yq", type = "brew", bundles = ["core"] },`, including its load-bearing trailing comma, passes the unchanged `$(registry_line yq)` haystack as argument two, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$(registry_line yq)" == *'{ name = "yq", type = "brew", bundles = ["core"] },'* ]]` → Current: `assert_contains '{ name = "yq", type = "brew", bundles = ["core"] },' "$(registry_line yq)"`

### Conversion 6 (Line 179→181)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `found 0`, retains `$output` through the helper default haystack, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$output" == *"found 0"* ]]` → Current: `assert_contains "found 0"` (default haystack is `$output`)

### Conversion 7 (Line 202→204)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `nothing untracked`, retains `$output` through the helper default haystack, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$output" == *"nothing untracked"* ]]` → Current: `assert_contains "nothing untracked"`

### Conversion 8 (Line 274→276)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `fzf`, retains `$output` through the helper default haystack, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$output" == *"fzf"* ]]` → Current: `assert_contains "fzf"`

### Conversion 9 (Line 280→282)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `unknown option`, retains `$output` through the helper default haystack, uses literal-equivalent fixed-string containment, and calls `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$output" == *"unknown option"* ]]` → Current: `assert_contains "unknown option"`

### Conversion 10 (Line 286→288)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `--adopt`, retains `$output` through the helper default haystack, uses literal-equivalent fixed-string containment, and the helper's `--` guard preserves this leading-dash needle while calling `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$output" == *"--adopt"* ]]` → Current: `assert_contains "--adopt"` (helper uses `grep -qF -- "$needle"`)

### Conversion 11 (Line 287→289)
- **Clause:** B-2
- **Severity:** blocker
- **Description:** Preserves the byte-identical needle `--machine`, retains `$output` through the helper default haystack, uses literal-equivalent fixed-string containment, and the helper's `--` guard preserves this leading-dash needle while calling `assert_contains` directly.
- **Evidence:** Baseline: `[[ "$output" == *"--machine"* ]]` → Current: `assert_contains "--machine"`

### Summary Finding
- **Clause:** B-2
- **Severity:** blocker
- **Description:** All 11 conversions pass: each retains its needle and haystack, preserves positive containment semantics because every quoted baseline needle is literal and `grep -qF` performs literal matching, retains the yq comma, and routes the assertion through the shared helper.
- **Evidence:** Verified baseline-to-current for all conversions and confirmed `assert_contains` implementation with `grep -qF -- "$needle"` produces the required literal-string matching semantics.

---

## Verdict Summary

The second opinion agrees with the checker of record: all 11 conversions preserve their semantic meaning. Each conversion maintains byte-identical needles, unchanged haystacks (either as explicit arguments or via the helper's default `$output`), and positive containment polarity. The switch from `[[ ]]` glob-pattern matching to `grep -qF` literal-string matching is semantically safe because all baseline needles are quoted literals containing no glob metacharacters. The trailing comma on the yq needle is correctly preserved. All conversions call `assert_contains` by name without inlining comparison logic.
