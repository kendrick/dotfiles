# dotfiles-sync preflight guard

Design doc. 2026-08-07.

## Problem

`dotfiles-sync` runs `chezmoi re-add` unattended twice a day. It never asks whether this machine's live tree is the newer side of the comparison. When source has commits the machine never applied, the re-add captures the stale live copies back over them and commits the reversion.

This happened on 2026-08-07. The 16:00 run on That-Air produced `2787c16`, which reverted four things:

- the "Normalizing Claude settings" phase in `dot_local/bin/executable_dotfiles-sync`, from `19f9edc`
- `model: opus[1m]` back into `dot_claude/encrypted_private_settings.json.age`, undoing `daf7ae3`
- the Voice section of `dot_claude/CLAUDE.md`, from `7a98445`
- `slalom-agent-kit` and its two plugins from both plugin manifests, from `a692c9d`

Restored in `60637c4`.

The machine was behind because the guild job that produced those commits forbade `chezmoi apply` during the run, so source moved forward while live stayed put. Any machine that lags source has the same exposure, and the work machine acquires it the moment `60637c4` is pushed.

## Why `chezmoi status` is not enough on its own

For a file whose live copy differs from source, `chezmoi status` prints `M` in both columns. Column 0 says a re-add would update source; column 1 says an apply would update the target. That is the same output whether live drifted forward (the case re-add exists to handle) or source moved ahead (the regression). Direction is not recoverable from status.

The guard therefore needs a second signal.

## Approach

For each file where an apply would modify the target, compare the source file's last commit time against the live file's mtime. A source commit newer than the live file means source moved after this machine last wrote that file, which is the regression.

```bash
committed=$(git -C "$SRC" log -1 --format=%ct -- "$src")
live=$(stat -f %m "$HOME/$tgt")
[ "$committed" -gt "$live" ] && behind+=("$tgt")
```

Checked against real state after the restore: `dot_claude/CLAUDE.md` last committed at 1786140723 and the live file was written at 1786140792 by the recovery apply. Live is newer, no trip. Before that apply the comparison ran the other way.

Two approaches were rejected:

- **Recording the source HEAD sha after each sync**, and tripping when HEAD moved and any file is apply-behind. Simpler, but coarse: once tripped it blocks capture of files that are only apply-behind because the user drifted them, and it needs a bootstrap branch for the first run on an existing machine.
- **Applying before the re-add.** Silently overwrites legitimate live drift with source before anything captures it. Data loss.

## Placement

A new phase between the plugin-manifest capture (`:52-62`) and the re-add (`:64-69`). It has to precede the re-add: afterwards source equals live for every capturable file and the evidence is gone.

The existing template-drift phase at `:82-100` stays where it is. It reads the same `chezmoi status` output but asks a different question, what re-add structurally could not capture, and it needs post-re-add state to ask it. The two loops cannot be merged; a comment should say so.

The guard lives inline in `dotfiles-sync` rather than in its own `dot_local/bin` executable, unlike `claude-plugins-capture` and `claude-settings-normalize`. It needs `$SRC`, `notify_fail`, and the log redirect that already exist in the script, it is about twenty lines, and a separate file is one more artifact that can be deployed out of step with its caller.

## Scope: column-1 `M` only

`A` (apply would create) and `D` (apply would delete) carry no capture risk, because `chezmoi re-add` does not remove source entries for absent targets.

Demonstrated by the incident itself: `7a98445` added `dot_claude/encrypted_private_VOICE.md.age` to source at 13:28, its target was still missing when the 16:00 sync ran, and the file survives in `2787c16`.

`R` rows are run_onchange scripts and have no target file to compare.

## Output on trip

Nothing is captured. The log carries the full remediation; the notification stays short because macOS truncates it.

```text
==> Checking whether source moved ahead of this machine
    ! these files have source commits this machine never applied:
        .claude/CLAUDE.md
        .local/bin/dotfiles-sync
    Capturing now would revert them. Nothing was captured.

    See what would change:       chezmoi diff ~/.claude/CLAUDE.md
    Take source's version:       chezmoi apply ~/.claude/CLAUDE.md
    Keep this machine's version: chezmoi re-add ~/.claude/CLAUDE.md
    Then re-run:                 dotfiles-sync
```

The offenders are listed one per line; the four remediation commands print once, using the first offender as the worked example rather than repeating a block per file.

Then `notify_fail` and `exit 1`, matching the script's existing failure convention at `:66-69`.

The "keep this machine's version" line is not optional. A clobbered mtime would otherwise make the guard unescapable, leaving the user no move but to edit the script.

## Failure modes

Every degradation falls back to current behavior rather than to a blocked sync, which is the correct direction for an unattended job:

- source file with no commits: `git log` returns empty, skip the file
- live file missing: `stat` fails, skip the file
- `git log` errors, or the source dir is not a git repo: skip the file
- mtime rewritten by a restore or a file-sync tool: reads as "live is newer", guard stays quiet

Accumulate offenders into an array and test `${#behind[@]}` before expanding it. bash 3.2 renders an empty array as one empty word under `set -u`; `run_onchange_after_install-claude-plugins.sh.tmpl` documents the same hazard.

## Known limitation

The guard ships inside the file it protects. A machine running a stale `dotfiles-sync` has no guard, so its first backwards capture after this lands is still unguarded. That is inherent to a sync that deploys its own fixes and is the same shape as the original incident. Mitigation is operational: apply on each machine once after this lands.

## Tests

New `tests/sync-guard.bats`, following the `tests/install-failures.bats` conventions (synthetic `$HOME`, stubs on `PATH`, the script driven as a real subprocess). The `chezmoi` stub dispatches on subcommand: `source-path`, `status`, `re-add`, `execute-template`.

The central assertion in the tripping cases is that the re-add was never reached, proved by a recording stub rather than by exit status alone.

Cases:

1. source commit newer than live mtime: exits 1, names the file, re-add never called
2. live mtime newer than source commit: proceeds, re-add called
3. one file behind and one drifted forward: exits 1, names only the behind file
4. `A`, `D`, and `R` status rows: ignored, proceeds
5. template source: ignored here, left to the existing drift phase
6. source path with no commits: ignored, proceeds
7. clean status: proceeds, prints the none case

## Related

Third distinct `dotfiles-sync` defect alongside #19 (commits onto a detached HEAD) and #20 (labels commits with `hostname -s`). Independent of both.
