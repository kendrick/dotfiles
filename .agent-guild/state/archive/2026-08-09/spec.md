---
source: github-issue
ref: kendrick/dotfiles#19
issue: 19
title: dotfiles-sync commits onto a detached HEAD, so six weeks of syncs never left the machine
fetched_at: 2026-08-08T23:35:30Z
---

# dotfiles-sync commits onto a detached HEAD, so six weeks of syncs never left the machine

## Problem

`dotfiles-sync` commits without ever checking that `HEAD` points at a branch. When it doesn't, the script runs clean to the end and reports success, while the commits land where `git push` can't send them and `chezmoi update` can't advance past.

This ran undetected on a personal machine from 2026-06-26 to 2026-08-06. An interactive rebase of `main` onto `d16f978` was started by hand and abandoned mid-flight, which left `~/.local/share/chezmoi` detached. `dotfiles-sync` then committed onto that detached HEAD 26 times over six weeks. Every run reported success. Meanwhile `chezmoi update` couldn't pull, because a pull can't rebase onto a branch you aren't on, so the machine's source dir stayed frozen 117 commits behind `origin/main`.

The only symptom that ever reached a human was `chezmoi apply` appearing to do nothing.

The commit phase at `dot_local/bin/executable_dotfiles-sync:104-125` guards for a clean tree and for a failing commit, but nothing between `cd "$SRC"` at :105 and `git add -A` at :117 asks what `HEAD` is.

Reproduce on a scratch repo:

```bash
T=$(mktemp -d); R=$(mktemp -d); git init -q --bare "$R"; cd "$T"; git init -q .
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git remote add origin "$R"; git push -q origin HEAD:refs/heads/main
git checkout -q --detach HEAD; echo drift > file.txt
git add -A && git -c user.email=t@t -c user.name=t commit -q -m "[auto-sync] 1 file"
echo "commit exit: $?"
git push 2>&1 | head -2
```

**Observed:**

```
commit exit: 0
fatal: You are not currently on a branch.
```

**Expected:** the commit is refused before it happens, and the run says why.

`git symbolic-ref -q HEAD` is the whole test. It exits 1 on a detached HEAD and prints the ref otherwise, and it was available at every one of those 26 runs.

Two related states fail the same way and should be caught by the same guard, since both leave a repo where committing is legal and pushing isn't: a rebase in progress (`.git/rebase-merge` or `.git/rebase-apply`) and a merge in progress (`.git/MERGE_HEAD`). The incident above was a rebase, so `git add -A` was also staging into a suspended rebase's index for six weeks.

The push path isn't the defect here and shouldn't change. Push is opt-in and off by default for good reasons documented at :131-136, and with it off the script notifies `"Captured N files from HOST. Push by hand when ready."` So it did tell the user, every time. The notification was just unactionable, because the manual `git push` it suggests fails on a detached HEAD too. Fixing the guard fixes the notification's honesty as a side effect.

## Proposed Behavior

Before staging anything, `dotfiles-sync` checks that the source dir is in a state where a commit can eventually be pushed. If it isn't, the script refuses, names the state it found, and gives the command that gets out of it.

This matches the contract the script's own header sets: "Each phase is wrapped to catch known failure modes and fire a macOS notification with a concrete next step." A detached HEAD is a known failure mode that was missing from that set.

The refusal exits non-zero and is worded so it can't be mistaken for the existing "Nothing to commit. Already in sync." path, which also exits early and is the message a reader would otherwise assume they'd seen.

Recovery stays manual. Which branch the commits belong on, and whether a stalled rebase should be continued or aborted, are judgment calls the script has no basis to make.

## Acceptance Criteria

- [ ] With `HEAD` detached and the tree dirty, `dotfiles-sync` exits non-zero before `git add -A` runs, and no commit is created
- [ ] The refusal names the state found (detached HEAD, rebase in progress, merge in progress) rather than reporting a generic failure
- [ ] The refusal includes a command the user can run, and fires a notification consistent with the other `notify_fail` sites
- [ ] With `.git/rebase-merge`, `.git/rebase-apply`, or `.git/MERGE_HEAD` present, the same refusal fires even when `HEAD` is attached
- [ ] On a normal attached branch, output and exit code are byte-identical to today's
- [ ] The refusal is distinguishable in `~/.local/state/dotfiles/last-sync.log` from the "Nothing to commit" early exit
- [ ] `bats tests/` passes, with new cases driving both the detached and the attached path against a scratch repo

## Non-Goals

- **Auto-recovering.** Aborting a rebase, or picking which branch orphaned commits belong on, is a human decision. Refusing loudly is the fix.
- **Changing the opt-in push default.** That behavior is deliberate and documented at :131-136; an unattended push can't reach the 1Password SSH agent, and a push-protection block should be seen rather than buried.
- **Rewriting the 26 existing commits.** They're preserved on `origin/rescue-autosync` and are this machine's own recapturable state.
- **Making `chezmoi update` report a blocked pull.** Real, and worth its own issue, but the guard here is what would have caught this six weeks earlier.

## For a Coding Agent

- **Verify with:** `bats tests/`
- **Start here:** `dot_local/bin/executable_dotfiles-sync:104-125` is the commit phase with the missing guard. `:131-141` is the push path, which is correct as written and should be left alone.
- **Read first:** `_working-memory/conventions.md` under "Error Handling" and under "bash 3.2" (no associative arrays; guard every array expansion under `set -u`). Also `_working-memory/antipatterns.md`, 2026-08-05, on why a bare PATH stub does not isolate this repo's scripts, before building the test harness.
- **Environment:** macOS, `/bin/bash` is 3.2, `bats-core` is in the registry. The script runs `set -euo pipefail`. `tests/doctor.bats` has the stub-on-`PATH` harness these tests should follow, and it stubs `chezmoi source-path`, which is how you point the script at a scratch repo without touching the real one.
- **Done when:** every acceptance criterion passes and the new tests fail when the guard is removed.
- **Out of scope:** everything in Non-Goals.
