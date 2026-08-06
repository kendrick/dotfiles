#!/usr/bin/env bash
# Run a build/test command supplied by the constitution clause and propagate
# its exit code, teeing output to a timestamped log the verdict can cite.
#
# Host projects build differently, so the command is an argument, not baked in.
# A clause names its own: e.g. `check-build.sh "npm run build"`.
#
#   .agent-guild/scripts/check-build.sh "<command>"
#
# Exit codes: passthrough from the command (0 pass, non-zero = build failure,
# surfaced to the checker as clause FAIL); 3 if no command is given, so a
# misconfigured clause fails loudly instead of silently "passing".
set -uo pipefail

if [ "$#" -lt 1 ] || [ -z "${1// }" ]; then
  echo "usage: check-build.sh \"<build command>\"" >&2
  echo "  refusing to run with no command—a clause with no check must FAIL" >&2
  exit 3
fi

CMD="$*"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/state/log"
mkdir -p "$LOG_DIR"

# Portable timestamp—no GNU-only flags.
TS="$(date +%Y%m%dT%H%M%S)"
LOG="$LOG_DIR/build-$TS.log"

echo "check-build.sh: running: $CMD" | tee "$LOG"
set +e
# shellcheck disable=SC2086
bash -c "$CMD" 2>&1 | tee -a "$LOG"
code=${PIPESTATUS[0]}
set -e

echo "check-build.sh: exit $code (log: $LOG)" | tee -a "$LOG"
exit "$code"
