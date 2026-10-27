# Sync Default Branch Ref (#69) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `dotfiles-sync` derives the default branch from `origin/HEAD`'s full target ref, so a local branch or tag named `origin/main` no longer turns every run on `main` into a skip.

**Architecture:** Rewrite `default_branch()` in `dot_local/bin/executable_dotfiles-sync` to read the unabbreviated ref and strip the exact `refs/remotes/origin/` prefix. Cover it with new `tests/sync.bats` cases.

**Tech Stack:** bash 3.2, git, bats.

---

## Context

Issue #69. `default_branch()` (`executable_dotfiles-sync:129-133` at 499398c) runs `git symbolic-ref --short refs/remotes/origin/HEAD` and strips `origin/`. When a local branch or tag is named `origin/main`, git abbreviates the ref to `remotes/origin/main` to stay unambiguous, the strip leaves that unchanged, and every scheduled run skips. Two days later the sync posts a "paused" notification naming a branch that doesn't exist. The issue body has the repro, the expected behavior and the acceptance criteria. Implement against them.

## Decisions

These are settled. Implement them as written.

1. **New body:** `d="$(git -C "$SRC" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"`, then print `${d#refs/remotes/origin/}`. An unset `origin/HEAD` still yields an empty string, so the existing skip that names `git remote set-head origin --auto` is unchanged.
2. **Guard a target outside `refs/remotes/origin/`.** If `d` is non-empty but doesn't start with `refs/remotes/origin/`, print an empty string, so the run takes the existing unset-`origin/HEAD` skip rather than comparing against a full ref. Git doesn't create that state, but a hand-edited `origin/HEAD` can, and the empty-string path is the one that already tells the user how to repair it.
3. **Comment the WHY** above the function: `--short` abbreviates relative to whatever local refs exist, so a branch or tag named `origin/main` changed its output (#69). The full ref doesn't depend on local names.

## Task 1: Failing tests

**Files:**
tests/sync.bats

Put the new cases next to the existing origin/HEAD cases (about `:705-810`), using the file's `fresh_repo`. A dirty tree is whatever the neighboring commit cases use to make one. Copy that idiom; don't invent a new one.

1. **Local branch `origin/main`:** after `fresh_repo`, run `git -C "$REPO" branch origin/main`, dirty the tree on `main`, and run the script. It exits 0, the commit count on `main` goes up by 1, and the output doesn't contain `Skipping`.
2. **Local tag `origin/main`:** the same, with `git -C "$REPO" tag origin/main` instead of the branch.
3. **Rule check (falsifier):** the derived branch keys on `origin/HEAD`'s target alone. With the local branch `origin/main` from case 1 still present, push a `trunk` branch and `git remote set-head origin trunk`. A run on `main` skips and names `trunk`. A fix that hardcodes `main` or strips `remotes/origin/` as text fails one of these cases.

Run `bats --filter 'origin/main' tests/sync.bats`. Expected: cases 1 and 2 fail at the plan's base commit, and case 3 passes. Record the two `not ok` lines in the run's report, since the issue asks for them in the PR.

## Task 2: Fix

**Files:**
dot_local/bin/executable_dotfiles-sync
tests/sync.bats

**Step 1:** Apply Decisions 1–3.

**Step 2:** Run `bats tests/sync.bats tests/sync-guard.bats`. Expected: all pass, including the existing `origin/HEAD unset` cases (`:798` and its neighbors) and the `trunk` cases at `:705` and `:719`.

**Step 3:** Run `TMPDIR=$(mktemp -d /tmp/v69.XXXX) bats tests/` in the foreground or under a runner that passes SIGINT through, because `tests/mutation-check.bats` sends Ctrl-C. Expected: 0 not ok.

**Step 4:** Commit both files: `fix(sync): resolve the default branch from origin/HEAD's full ref (#69)`. The body says why: `--short` abbreviation depends on local ref names, so a local `origin/main` branch or tag paused sync on every machine that had one.

## Verification

- Cases 1 and 2 fail at the base commit and pass after the fix.
- Case 3 and every existing case in `tests/sync.bats` and `tests/sync-guard.bats` pass.
- `bats tests/` exits 0.

## Out of Scope

- Detecting a stale `origin/HEAD` that names a branch which still exists. That needs the network, which launchd runs don't have.
- Any other change to the skip or notification behavior.
