# T-003 verification report

Final pass for #22 (drop-and-retry the unresolvable Brewfile entry). Runs
the two whole-job checks (C-4, C-7) that no single building task can run
for itself. Repairs nothing; a failure here would name the offending
path or case, not fix it.

## Check 1 — C-4: the whole suite stays green

**Command:**

```
bats tests/
```

**Exit code:** `0`

**Result:** `1..129`, all 129 cases `ok`, 0 `not ok`. `129 = 125` (the clean
baseline this job started from) `+ 4` (T-001's new `install-packages`
cases). Confirmed by direct count:

```
$ grep -c '^ok ' <output>
129
$ grep -c '^not ok ' <output>
0
```

The five pre-existing `install-packages` cases named in C-4 are all
present and green:

- `ok 74 install-packages: absent tool skips clean`
- `ok 75 install-packages: present tool failing names the item`
- `ok 76 install-packages: a fetch-phase failure names only the entry that doesn't exist`
- `ok 77 install-packages: a fetch failure where every entry exists names the whole batch`
- `ok 78 install-packages: all items succeed prints no failure summary`

T-001's four new cases are present and green:

- `ok 79 install-packages: drop-and-retry, mixed batch installs the survivors`
- `ok 80 install-packages: drop-and-retry, all unresolvable reports without retrying`
- `ok 81 install-packages: no extra brew calls on a clean run`
- `ok 82 install-packages: reports and stops after a second failure`

The bash 3.2 bare-compound guard is present and green:

- `ok 111 no bare [[ or (( on the guarded surface`

No environment hazard hit: no `.chezmoi*` scratch file was introduced,
and nothing in the run suggested the renderer misbehaved, so
`chezmoi execute-template '{{ template "bundles" . }}'` was not needed as
a sanity check.

**Verdict: PASS.**

## Check 2 — C-7: the registry is reported on, never edited

**Command:**

```
.agent-guild/scripts/check-diff-scope.py run_onchange_install-packages.sh.tmpl dot_local/bin/executable_dotfiles-doctor tests/install-failures.bats tests/doctor.bats _working-memory/ --ignore dot_claude/encrypted_private_settings.json.age
```

**Exit code:** `0`

**Output:** `OK: 4 path(s) in scope`

**Every path the working tree's diff touched**, per `git status
--porcelain` run from the repo root before this task added anything
under `_working-memory/`:

| Path | In scope via |
|---|---|
| `dot_local/bin/executable_dotfiles-doctor` | allowlist (exact match, T-002) |
| `run_onchange_install-packages.sh.tmpl` | allowlist (exact match, T-001) |
| `tests/install-failures.bats` | allowlist (exact match, T-001) |
| `dot_claude/encrypted_private_settings.json.age` | `--ignore` (pre-existing, not this job's) |

4 changed paths, 0 offenders. `tests/doctor.bats` and `_working-memory/`
are allowlisted but were not part of the diff at the time this check ran
(this task's own `_working-memory/` write happens after this check, and
`check-diff-scope.py` treats everything under `.agent-guild/state/` as
always permitted, so this report's own path is not and cannot be an
offender). `.chezmoidata.toml` does not appear among the changed paths,
confirmed unmodified: no package entry was silently dropped.

**Verdict: PASS.**

## Summary

Both C-4 and C-7 pass. Nothing here implicates T-003 itself, since T-003
only executes the two check scripts above; a FAIL on either would have
named the responsible dependency (T-001 for C-4/the installer/its bats
cases, T-002 for the doctor rewording, either for an out-of-scope path)
rather than a defect in this task.
