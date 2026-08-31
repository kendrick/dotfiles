# Checking the progress display on a real apply

The suite covers the display kit in every venue a harness can build. It cannot
build the one where you sit in front of a terminal and watch an apply run, so
that check is yours. It takes one command and about a minute.

## Run this

In a real terminal, not over ssh without a tty and not through a wrapper:

```bash
chezmoi apply >/tmp/apply-capture.log 2>&1
```

Redirect both streams. That puts you in the venue where a display deciding by
a test of stdout goes blind while you are still watching, so one run exercises
the detector and the plain-stdout guarantee together.

## Watch for two things while it runs

The terminal should show a single animated line at the bottom, redrawing in
place, with a settled line left behind for each script as it finishes:

```
  ✓  age key          already provisioned      (0:00)
  ✓  packages         Brewfile applied         (2:31)
  ⢼  vscode ext       12/43 errorlens          (0:19)
```

When the apply ends, your cursor should be back. If the prompt returns with no
cursor, the run left the terminal in a state the kit is supposed to prevent, and
`reset` will fix your shell.

## Then check the capture

```bash
LC_ALL=C grep -c $'\033' /tmp/apply-capture.log
```

That prints the number of lines carrying an ESC byte, `0x1b`. It must print
`0`. Anything else means escape codes reached the log. That is the defect this
work exists to remove, because a captured apply has to stay greppable and
animation belongs on `/dev/tty` and nowhere else.

To see the offending bytes if the count is not zero:

```bash
LC_ALL=C grep -n $'\033' /tmp/apply-capture.log | head
```

## One caveat about a steady-state apply

An apply with nothing to do returns in under a second and prints almost
nothing, which tells you very little. The display is worth watching on a run
where scripts actually execute: a new machine, a brew day, or after a change to
one of the ten `run_` scripts. Touching any of them re-runs it on the next
apply, which is the cheapest way to get a real run to watch.
