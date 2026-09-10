#!/bin/bash
# Keep VS Code extensions current on machines the scheduled sync never reaches.
#
# A machine with sync_schedule = "off" gets no LaunchAgent (.chezmoiignore), so
# dotfiles-sync only ever runs there by hand, and the client role defaults to off.
# Applying is how such a machine takes changes at all, so that is where its update
# has to hang. vscode-extensions-update owns the weekly stamp, which is what keeps
# this and the dotfiles-sync phase from both doing the work in the same week.
#
# run_after_ rather than run_onchange_: the cadence is a clock, not a file, and a
# content hash would fire on edits to this script and stay silent for the rest of
# the year. Cheap on a warm stamp, which is the common case.
#
# teardown:none

set -eu

# bin/ is applied before scripts on a fresh machine, but not on a run scoped to a
# single target, so the helper being missing is ordinary rather than an error.
if ! command -v vscode-extensions-update &>/dev/null; then
	exit 0
fi

echo "==> Updating VS Code extensions (weekly)"

# Never fail an apply over this. A marketplace outage, a VS Code mid-update, or no
# network at all are all states where the rest of the apply is still worth finishing.
vscode-extensions-update || echo "    ! update failed, retrying on the next apply"
