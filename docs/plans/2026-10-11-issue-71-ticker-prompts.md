# Ticker Over Prompts and Status Lines (#71) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Stop the `step_begin` ticker from erasing prompts and painting over status lines, in the prerequisites script that #71 names and everywhere else the same pattern occurs.

**Architecture:** Fix the class in the display kit, `.chezmoitemplates/sh-ui.sh`, so call sites can't reintroduce it. `say`/`ok`/`warn` pause a live ticker around their line. `spin_until`, `spin_on_log`, and `spin_until_log_gate` stop the ticker before drawing their own frames. Then fix the call sites the kit can't reach: the prerequisites prompt moves ahead of `step_begin`, every TTY-owning command runs through `step_run`, and the few bare `echo`/`printf` lines inside a live step become `say`. The tests run through the existing pty driver, which gains a mode that puts stdin on the pty.

**Tech Stack:** bash 3.2 (`/bin/bash` on a factory Mac), chezmoi templates, bats, `tests/support/pty-run.py` (Python 3 stdlib).

---

## Audit Findings This Plan Acts On

An audit on 2026-10-11 read every script that includes the kit, looking for commands that run while a ticker is live. The results:

- **HANG** (prompt erased, run blocks on input). All three are in `run_once_before_install-prerequisites.sh.tmpl` and all three are already in #71: the `Install them now? [Y/n]` read at :115-116, `sudo -v` at :72, and Homebrew's `install.sh` at :145, whose sudo `Password:` prompt gets painted over.
- **GARBLE** (status text painted over, no hang). This is what the user reported seeing on top of #71:
  - prerequisites: the `say` lines at :67, :71, :110, the `sed` replay of the failure log at :81, and the lines at :99-103 ahead of `spin_until`
  - `run_before_provision-age-key.sh.tmpl`: `say` at :46 and :51, and `printf '\n'` plus `say` at :72-76
  - `run_onchange_after_fetch-licensed-fonts.sh.tmpl`: the `echo` lines at :92 and :101
  - `run_onchange_configure-raycast.sh.tmpl`: `open` at :55 (its stderr reaches the TTY), and the `echo` at :69
- **Two writers on the live line**: `spin_on_log`/`spin_until` called inside a `step_begin` window, at prerequisites :57, :80, :103 and age-key :77.
- **Double settle**: when the catalog has no CLT, prerequisites :64 runs `step_warn "xcode clt"`, and then `install_clt_gui` can settle a `✓` for the same step.
- **Cleared**: the `step_run`-wrapped tools in tode, claude-plugins, agent-skills, vscode, and node; `op` in fonts (stdin is `/dev/null`, auth happens in a GUI); the age-key `brew install --cask` lines (no pkg installer, so no sudo); and `brew bundle` in install-packages (`step_begin_quiet` plus `spin_until_log_gate`).

## Decisions

These are settled. Implement them as written.

1. **`say` resumes the ticker after its line; `step_run` doesn't.** `say` is called mid-step before long silent work, such as the 1Password cask install. If the animation never came back, the step would look frozen for that whole time. `step_run` hands the terminal to a tool, so restarting the ticker there would put a frame back in front of the tool's output or the caller's failure echo. The kit's comment above `step_run` already gives that reason. So a prompt must never follow a `say` directly: it goes ahead of `step_begin`, or through `step_run`.
2. **The spinners stop the step ticker and don't restart it.** Each spinner owns the live line until it returns, and every caller settles the step soon after. Restarting would add a third writer to reason about.
3. **The CLT question is asked before `step_begin "xcode clt"`.** This follows `_working-memory/conventions.md` ("Put anything interactive ahead of `step_begin`") and the `gh auth login` precedent in `run_onchange_after_restore-agent-skills.sh.tmpl:64-82`.
4. **The prerequisites `step_warn` at :64 becomes `say`.** One step settles exactly once.
5. **A bare blank line inside a live step becomes `say ""`.** It prints two trailing spaces, which nobody sees, and gets the yield for free.

## Out of Scope

- The Homebrew false-success in #59. It edits the same block at prerequisites :138-148, so whichever change lands second rebases on the first.
- `op`'s own "add an account? [Y/n]" prompt, which `2>/dev/null` hides in age-key :65 and :81 whether or not a ticker is running. That's a separate bug.
- The race the audit inferred in `spin_until_log_gate`, between the gate read (sh-ui :157) and the next draw (:161). No run has shown it.

---

### Task 1: `say`, `ok`, and `warn` Pause a Live Ticker

**Files:**
- Modify: `.chezmoitemplates/sh-ui.sh:27-29` (say/ok/warn), `.chezmoitemplates/sh-ui.sh:326-341` (`_ui_start_ticker`)
- Test: `tests/progress.bats` (new case beside "interleave: no row carries both a frame and a tool's stdout", around :701)

**Step 1: Write the failing test.** Copy the shape of the interleave case at `tests/progress.bats:701-751`. Write a probe that runs `step_begin 'probe'`, then a loop of three iterations: `step_tick "$i" 3 'working'; sleep 0.25; say 'XSAYX'`. Run it with `ui_pty --stdout-to-tty --tty-capture ... --glyphs "$g"`. Assert, in this order:

```bash
[ "$(ui_interleave "$p/say.tty" "$g" XSAYX glyph_rows)" -ge 1 ]
[ "$(ui_interleave "$p/say.tty" "$g" XSAYX marker_rows)" -ge 1 ]
[ "$(ui_interleave "$p/say.tty" "$g" XSAYX violations)" -eq 0 ]
```

The two `-ge 1` lines are the non-vacuity checks. A run that drew no frame, or whose `say` never printed, would otherwise pass. Name the case `interleave: a say inside a live step never shares the frame's row`.

**Step 2: Run it and confirm it fails.**

Run: `bats -f 'say inside a live step' tests/progress.bats`
Expected: `not ok`, failing on the `violations` line.

**Step 3: Implement.** In `_ui_start_ticker`, record the text before forking: add `_UI_TICK_TEXT="$text"` right after `local text="$1"`. Above `say`, add:

```bash
# A line printed while the ticker runs would continue the frame's row, because
# a frame never ends in a newline. So a status line takes the live line down,
# prints, and puts it back: mid-step `say` is usually followed by slow silent
# work that still needs a moving spinner.
_ui_yield() {
  [ -n "${_UI_TICK_PID:-}" ] || return 0
  _ui_stop_ticker
  _ui_erase
  _UI_YIELDED=1
  return 0
}

_ui_resume() {
  [ "${_UI_YIELDED:-0}" = 1 ] || return 0
  _UI_YIELDED=0
  _ui_start_ticker "${_UI_TICK_TEXT:-}"
  return 0
}

say() { _ui_yield; printf '  %s\n' "$1"; _ui_resume; }
ok() { _ui_yield; printf '  ✓  %s\n' "$1"; _ui_resume; }
warn() { _ui_yield; printf '  !  %s\n' "$1"; _ui_resume; }
```

The functions call `_ui_stop_ticker`, `_ui_erase`, and `_ui_start_ticker`, which are defined further down the file. Bash resolves function names when they're called, so the order is fine.

**Step 4: Run it and confirm it passes.**

Run: `bats -f 'say inside a live step' tests/progress.bats`, then `bats tests/progress.bats`
Expected: all ok. If an existing case asserted byte-exact stdout around a `say`, read it before changing it: stdout is unchanged, and the erase goes to fd 9 (`/dev/tty`).

**Step 5: Commit.** `fix(ui): pause the live line around say, ok, and warn`, with a body that explains why.

### Task 2: Spinners Stop the Step Ticker Before Drawing

**Files:**
- Modify: `.chezmoitemplates/sh-ui.sh:66` (`spin_until`), `:99` (`spin_on_log`), `:151` (`spin_until_log_gate`)
- Test: `tests/progress.bats` (new case after Task 1's)

**Step 1: Write the failing test.** The probe runs `step_begin 'XSTEPX'`, then `sleep 0.3`, then `spin_until 'XSPINX' 1 false || true`, then `step_ok 'XSTEPX' done`. Capture the TTY with `ui_pty --stdout-to-tty`. Assert three things against the capture:
- `XSTEPX` appears in the capture before `XSPINX`, which proves the ticker drew.
- `XSPINX` appears.
- Between the first `XSPINX` and the settled `✓` line, no frame carries `XSTEPX`.

Do the slicing with `python3 -c` or `awk` over the raw bytes, never `grep -c`. A frame row has no newline, so line counts can't see it (see the `ui_esc_count` comment in `tests/helpers.bash`). Name the case `spinners: the step ticker never draws while a spinner owns the live line`.

**Step 2: Run it and confirm it fails.**

Run: `bats -f 'spinner owns the live line' tests/progress.bats`
Expected: `not ok`, because at HEAD the ticker keeps drawing `XSTEPX` frames alongside `spin_until`'s.

**Step 3: Implement.** Make the first statement of each of the three spinner functions:

```bash
  # One writer on the live line: a step ticker still running here would
  # interleave with these frames mid-escape-sequence.
  _ui_stop_ticker
```

Put the comment on `spin_until` only. The other two get the bare call.

**Step 4: Run it and confirm it passes.**

Run: `bats -f 'spinner owns the live line' tests/progress.bats && bats tests/progress.bats`
Expected: all ok.

**Step 5: Commit.** `fix(ui): stop the step ticker before a spinner draws`.

### Task 3: A pty-run Mode With Stdin on the pty

**Files:**
- Modify: `tests/support/pty-run.py` (the docstring's modes list, `main()` argparse, `child_exec`)
- Test: `tests/progress.bats` (Task 4's case exercises it). Also add a small case `pty-run: --stdin-from-tty gives the child a tty on fd 0` that runs `/bin/bash -c '[ -t 0 ] && echo YES || echo NO'` with `--stdout-to-tty --stdin-from-tty` and asserts `YES` is in the TTY capture, then runs the same command without the flag and asserts `NO`.

**Step 1: Write the failing test** above.

**Step 2: Run it and confirm it fails.** Run `bats -f 'stdin-from-tty' tests/progress.bats`. Expected: `not ok`, because argparse rejects the unknown flag with exit 2.

**Step 3: Implement.**
- Add `ap.add_argument("--stdin-from-tty", action="store_true", help="leave fd 0 on the pty slave so the child can read a reply; pair with a timeout, since nothing answers")`.
- Reject it together with `--setsid`, using the same message pattern as `--stdout-to-tty`.
- In `child_exec`, when the flag is set, use `os.dup2(CTTY_KEEPALIVE_FD, 0)` instead of the `/dev/null` dup.
- Add a mode paragraph to the module docstring saying why the default keeps `/dev/null`: the prompt at `run_once_before_install-prerequisites.sh.tmpl:111` would otherwise block forever.
- Leave every existing mode's behavior unchanged.

**Step 4: Run it and confirm it passes.** `bats -f 'stdin-from-tty' tests/progress.bats`, then `bats tests/progress.bats`.

**Step 5: Commit.** `test(ui): let pty-run hand the child a tty on stdin`.

### Task 4: Prerequisites Asks First and Hands the TTY Over

**Files:**
- Modify: `run_once_before_install-prerequisites.sh.tmpl:63-148`
- Test: `tests/progress.bats` (new case)

**Step 1: Write the failing test.** This is the case #71's acceptance criteria call for.
- Render the prerequisites script the way `tests/install-failures.bats:41` does with `render_script`.
- Put stubs on a `$STUBS` directory ahead of `/usr/bin:/bin`. `xcode-select -p` exits 2, so `have_clt` fails. `softwareupdate`, `sudo`, and `curl` exit 0 silently.
- Run the script under `ui_pty --stdout-to-tty --stdin-from-tty --timeout 5 --tty-capture "$cap"`. Nothing answers the `read`, so the run times out with exit 199. Accept that status.
- Assert that the capture contains the bytes `Install them now? [Y/n]` (`grep -aF`).
- Assert that no `\r\033[K` (`$'\r\033[K'`) follows those bytes anywhere in the capture. Slice with `python3 -c` on the raw bytes: `data[data.index(prompt):]` must not contain `b'\r\x1b[K'`.

Name the case `prerequisites: the CLT question stays on screen until answered`. Before implementing, prove the case is red: it must fail against the current script.

**Step 2: Run it and confirm it fails.** Run `bats -f 'CLT question stays on screen' tests/progress.bats`. Expected: `not ok` on the erase assertion.

**Step 3: Implement.** Restructure the CLT block (:106-131) so the question runs before `step_begin`:

```bash
if have_clt; then
  step_ok "xcode clt" "already installed"
else
  say "Xcode Command Line Tools are missing. Homebrew and git need them."

  # Only ask when someone's there to answer. The auto-sync LaunchAgent must never
  # block on a read, and a run_once script re-runs whenever its contents change.
  # Asked before step_begin: the ticker's next frame would erase a prompt that
  # has no newline, and the run then waits on a question nobody can see (#71).
  if [ -t 0 ]; then
    printf '  Install them now? [Y/n] '
    read -r reply || reply=""
    case "$reply" in
      [nN] | [nN][oO])
        step_warn "xcode clt" "skipped by request"
        say "Install them with 'xcode-select --install', then re-run 'chezmoi apply'."
        exit 1
        ;;
    esac
  fi

  step_begin "xcode clt"
  start=$SECONDS
  # (unchanged from here: install_clt_headless || install_clt_gui || step_fail ...)
```

In `install_clt_headless`:
- Change :64 `step_warn "xcode clt" "not in the update catalog"` to `say "Not in the update catalog; trying Apple's installer."`.
- Change :72 `sudo -v || return 1` to `step_run sudo -v || return 1`.
- Wrap the failure replay at :81 the same way: `[ "$status" -eq 0 ] || step_run sed 's/^/     /' "$log"`.

In `install_clt_gui`, change both bare `printf '\n'` lines (:98, :101) to `say ""`.

In the Homebrew block (:140-148), change the installer line to:

```bash
  # install.sh asks for a sudo password and waits for RETURN; both need the
  # terminal to itself.
  step_run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Step 4: Run it and confirm it passes.** Run `bats -f 'CLT question stays on screen' tests/progress.bats`. Then move the prompt block back below `step_begin` in a scratch copy and confirm the case goes red. Restore the copy afterwards.

**Step 5: Check the non-interactive path.** Run `bats tests/progress.bats tests/install-failures.bats`. Both `xcode clt` and `homebrew` must still settle with their usual `✓`/`!`/`✗` lines when stdin isn't a TTY.

**Step 6: Commit.** `fix(prereqs): ask about CLT before the ticker starts (#71)`.

### Task 5: The Remaining Call Sites

**Files:**
- Modify: `run_before_provision-age-key.sh.tmpl:72,76`, `run_onchange_after_fetch-licensed-fonts.sh.tmpl:92,101`, `run_onchange_configure-raycast.sh.tmpl:55,69`
- Test: none new. Tasks 1 and 2 cover `say` and the spinners. Existing cases already cover `step_run`'s behavior: "interleave: no row carries both a frame and a tool's stdout" and "interleave-scripts".

**Steps:**

1. In age-key, change both `printf '\n'` lines (:72, :76) to `say ""`. The `say` lines at :46, :51, and :73-75 need no edit, because Task 1 fixed them, and Task 2 covers the `spin_until` at :77.
2. In fonts, change `echo "  not in vault, skipped: $title"` to `say "not in vault, skipped: $title"`, and do the same for the `could not unzip` line. The output is byte-identical, because `say` adds the same two leading spaces.
3. In Raycast, change :55 to `if ! step_run open "raycast://extensions/install/$ext"; then`. Change :69 `echo "Could not set..."` to `say "Could not set Raycast's global hotkey; its preferences are unchanged."`. Leave the `echo` at :76 alone, because it runs after `step_warn` has settled the step.
4. Run `bats tests/` and expect all ok. Two cases are known to flake under heavy load and pass when rerun alone: "Ctrl-C mid-mutation" in `tests/mutation-check.bats` and "interleave-scripts" in `tests/progress.bats`. If only those fail, rerun them alone and report both runs.
5. Commit: `fix(ui): keep status lines off the live row in age-key, fonts, and raycast`.

### Task 6: Record the Rule

**Files:**
- Modify: `_working-memory/conventions.md:24` (the "Put anything interactive ahead of `step_begin`" line)

**Steps:**

1. Extend the rule:
   - A command that may prompt goes ahead of `step_begin` or through `step_run`. This covers `read`, `sudo`, and any installer that reads the TTY.
   - Inside a live step, status text goes through `say`/`ok`/`warn`, never bare `echo`/`printf`.
   - Cite #71.
2. Commit: `docs(memory): record the prompt and status-line rule for live steps`.

## Acceptance Criteria (from #71)

- [ ] The `[Y/n]` question is asked before any ticker starts for the CLT step. Task 4 covers this.
- [ ] Neither the CLT step nor the Homebrew step has a ticker running while `sudo -v`, `sudo softwareupdate`, or Homebrew's installer can prompt. Task 4 covers this with `step_run sudo -v` (which primes the `sudo softwareupdate` that follows) and `step_run` around `install.sh`.
- [ ] No step has the `step_begin` ticker and `spin_on_log` or `spin_until` drawing at the same time. Task 2 covers this.
- [ ] A new case in `tests/progress.bats` runs the rendered prerequisites script under `ui_pty`, with stdin on the pty, stdout collapsed onto it (`--stdout-to-tty`), and CLT missing. It asserts that the `Install them now? [Y/n]` bytes appear in the TTY capture and that no `\r\033[K` follows them. Tasks 3 and 4 cover this.
- [ ] Non-interactive runs still show the `xcode clt` and `homebrew` steps settling with their usual `✓`/`!`/`✗` lines, and `bats tests/` exits 0. Task 4 step 5 and Task 5 step 4 cover this.

Added by the audit:

- [ ] A `say` inside a live step never shares a row with a frame. Task 1 covers this.
- [ ] age-key, fonts, and Raycast print no bare status line while their ticker runs. Task 5 covers this.

## Verification

`bats tests/` from the repo root. The suite had 347 cases after #70; this plan adds 5.
