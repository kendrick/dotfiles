---
source: github-issue
ref: kendrick/dotfiles#22
issue: 22
title: One unresolvable Brewfile entry aborts the fetch, so no package in the bundle installs
fetched_at: 2026-08-14T21:39:04Z
---

# One unresolvable Brewfile entry aborts the fetch, so no package in the bundle installs

## Problem

One Brewfile entry that brew can't resolve stops every other package in the bundle from installing, and nothing retries afterward.

Homebrew batch-fetches everything that needs downloading before it installs anything. `bundle/installer.rb:81-88`:

```ruby
if (fetchable_names = fetchable_formulae_and_casks(installable_entries, no_upgrade:).presence)
  fetchable_names_joined = fetchable_names.join(", ")
  puts Formatter.success("Fetching #{fetchable_names_joined}") unless quiet
  unless Bundle.brew("fetch", *fetchable_names, verbose:)
    $stderr.puts Formatter.error "`brew bundle` failed! Failed to fetch #{fetchable_names_joined}"
    return false
  end
end
```

That `return false` sits above the install phase at `:90`, so a single unresolvable name means zero packages install. Not "the bad one is skipped": zero.

This isn't hypothetical. `deskflow` was removed from homebrew-cask at some point and `brew info` now finds it under neither type. It sat in `.chezmoidata.toml` and aborted every package install on a personal machine for an unknown stretch, leaving `sbcinnovation/tap/squoosh`, `databricks/tap/databricks`, `font-fantasque-sans-mono-nerd-font`, `zappy`, and three App Store apps all stuck behind it. Removed in `984e4e9`.

`1bc1fb5` made the failure loud: the installer now re-derives which batched name is actually unresolvable and prints it. Loud is a real improvement over the silence in #17, but the run still installs nothing.

This also falsifies the reasoning behind the B-3 clause in #17's job constitution, which exempted `brew bundle` from the keeps-going requirement:

> One `brew bundle` call over the whole rendered Brewfile, so it has no keeps-going case of its own — B-3 exempts it, since `brew bundle` already continues past a failing entry internally.

True of the install phase. False of the fetch phase.

### Secondary

`dotfiles-doctor` lists unresolvable and uninstalled entries under `-- in a bundle you've enabled but not installed (next apply installs these):`. The next apply usually won't. `run_onchange` records the script's hash once the script completes, and the installer exits 0 by design (#17), so chezmoi treats it as done and skips it until the rendered Brewfile changes again. The parenthetical promises a retry the tool's model doesn't provide.

## Steps to Reproduce

```bash
# 1. add a name brew cannot resolve to any bundle this machine enables
#    in .chezmoidata.toml, under `# ---- core ----`:
#      { name = "definitely-not-a-real-formula-xyz", type = "brew", bundles = ["core"] },

# 2. render the installer and run it against real brew
chezmoi execute-template < run_onchange_install-packages.sh.tmpl > /tmp/install-packages.sh
bash /tmp/install-packages.sh

# 3. see what did and didn't install
dotfiles-doctor | grep -A8 "not installed"

# 4. revert
git checkout -- .chezmoidata.toml
```

Any machine with at least one tracked-but-uninstalled package shows the effect most clearly, since those are what the fetch phase was going to download.

## Observed vs. Expected

**Observed:** brew names the whole batch it was fetching, aborts, and installs nothing. The installer correctly names the unresolvable entry, and every other tracked package remains uninstalled.

**Expected:** the unresolvable entry is reported and set aside; every entry that does resolve installs in the same run.

## Error Output

```text
Fetching definitely-not-a-real-formula-xyz, sbcinnovation/tap/squoosh, databricks/tap/databricks, font-fantasque-sans-mono-nerd-font, deskflow, zappy
`brew bundle` failed! Failed to fetch definitely-not-a-real-formula-xyz, sbcinnovation/tap/squoosh, databricks/tap/databricks, font-fantasque-sans-mono-nerd-font, deskflow, zappy
Error: No available formula with the name "definitely-not-a-real-formula-xyz".
Homebrew ran, but these Brewfile entries don't exist (its errors are above):
  definitely-not-a-real-formula-xyz
  deskflow
```

Both dead names are correctly identified. Six entries were in the batch; four of them were fine and none of those four installed.

## Proposed Behavior

Build on what `1bc1fb5` already does rather than validating up front. Pre-checking all 88 entries would mean 88 `brew info` calls on every apply to guard against a case that almost never fires.

Instead, on a fetch failure the installer already knows which batched names fail to resolve. Drop those lines from the rendered Brewfile and run `brew bundle` once more with what's left, then report the dropped entries by name. The cost lands only on the failure path, and the happy path is untouched.

A second run that fails again for a different reason should report and stop rather than looping.

The doctor's wording should either say what actually happens or the installer should make the promise true.

## Acceptance Criteria

- [ ] With one unresolvable entry in an enabled bundle, every other entry in the rendered Brewfile installs during the same run
- [ ] The unresolvable entry is named in the output and the script still exits 0
- [ ] A run in which every entry resolves makes no additional `brew` calls beyond what the current script makes, measurable by stub invocation count
- [ ] A retry that fails for a reason other than an unresolvable name reports and stops instead of retrying again
- [ ] `dotfiles-doctor`'s "next apply installs these" either becomes accurate or is reworded to match what `run_onchange` does
- [ ] `bats tests/` passes, with new coverage driving the drop-and-retry path from stubs rather than from a real failed install

## Non-Goals

- **Removing dead entries from the registry automatically.** Whether a package that vanished upstream was renamed, moved to a tap, or genuinely dropped is a human call. Report it; don't edit `.chezmoidata.toml`.
- **Making `run_onchange` retry until it succeeds.** Settled as a non-goal in #17 and unchanged here.
- **Aborting the apply on failure.** Also settled in #17.
- **Progress display.** #16 owns that, and the two shouldn't be tangled.

## For a Coding Agent

- **Verify with:** `bats tests/`
- **Setup:** macOS, `/bin/bash` is 3.2, `bats-core` is in the registry. Guard every array expansion with `[ "${#arr[@]}" -gt 0 ]`; bash 3.2 renders an empty array as one empty word under `set -u`.
- **Start here:** `run_onchange_install-packages.sh.tmpl:62-105` is the fetch-phase handling added by `1bc1fb5`, including the `brew info` re-derivation this builds on. `tests/install-failures.bats` holds the two fetch-phase cases and the stub conventions.
- **Read first:** Homebrew's `bundle/installer.rb:81-114` for the two failure phases and the five distinct failure strings they emit. Assuming one shape is what caused this bug's predecessor.
- **Done when:** every acceptance criterion passes, and a run with a deliberately unresolvable entry installs everything else.
- **Out of scope:** everything in Non-Goals.
