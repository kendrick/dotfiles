# Terminal chrome shared by the apply-phase scripts, pulled in with a Go template include
# the same way the Brewfile is. Don't write that include inside this file: chezmoi parses
# this as a template too, so it would recurse.
#
# Animation goes to /dev/tty, which is the screen and only the screen. Settled summary
# lines go to stdout, which is what a captured or piped apply keeps. Detection is an open
# of /dev/tty rather than a test of stdout, because a human watching
# `chezmoi apply >log 2>&1` still has a terminal while a stdout probe goes blind on them.
#
# Targets bash 3.2, which is what /bin/bash is on a factory Mac. The before phase runs
# ahead of Homebrew, so nothing newer exists yet for anything that includes this.

# How often the live line redraws itself while the caller is blocked. The frame
# cannot ride on step_tick alone: every adopted script ticks once per item and
# then sits inside an install for seconds, so a tick-driven frame freezes for
# exactly as long as the work takes, which is the silence this kit exists to
# break.
#
# It has to run well clear of the terminal's cursor blink, around 1 Hz. The
# blink is the reference motion already on screen, so a spinner at or below it
# reads as stalled no matter how faithfully it is advancing. 0.1 is the rate
# the kit's own spin_until has always used.
_UI_TICK_INTERVAL=0.1

SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

say() { printf '  %s\n' "$1"; }
ok() { printf '  ✓  %s\n' "$1"; }
warn() { printf '  !  %s\n' "$1"; }

# Callers set their own EXIT trap (they have their own temp files to clear), so the
# cursor restore lives here rather than in a trap of its own.
show_cursor() {
  ui_watching || return 0
  _ui_write "$_UI_SHOW"
  return 0
}

elapsed() {
  local s=$((SECONDS - $1))
  printf '%d:%02d' $((s / 60)) $((s % 60))
}

progress_bar() {
  local pct="${1:-0}" width=24 filled i out=''
  # A percentage that isn't a number is a display fault, and a display fault
  # must never take the script down. Under `set -u` the arithmetic below reads
  # a non-numeric argument as a variable name and aborts the whole script with
  # `unbound variable`, which is how a cosmetic bar stops a package install.
  case "$pct" in
  '' | *[!0-9]*) pct=0 ;;
  esac
  [ "$pct" -le 100 ] || pct=100
  filled=$((pct * width / 100))
  # Braces are load-bearing: bash 3.2 reads the block glyph's lead byte as part of the
  # variable name in a UTF-8 locale, so bare "$out█" silently truncates every append.
  for ((i = 0; i < width; i++)); do
    if [ "$i" -lt "$filled" ]; then out="${out}█"; else out="${out}░"; fi
  done
  printf '%s' "$out"
}

# Spin until a command succeeds. Frames tick every 0.1s but the predicate only runs
# every couple of seconds. Polling it at frame rate would fork the predicate ten times a
# second for the length of an Xcode download.
spin_until() {
  local label=$1 timeout=$2
  shift 2
  local start=$SECONDS n
  if ! ui_watching; then
    say "$label..."
    while ! "$@"; do
      [ $((SECONDS - start)) -lt "$timeout" ] || return 1
      sleep 5
    done
    return 0
  fi
  while ! "$@"; do
    if [ $((SECONDS - start)) -ge "$timeout" ]; then
      _ui_erase
      return 1
    fi
    n=0
    while [ "$n" -lt 20 ]; do
      _UI_FRAME=$((${_UI_FRAME:-0} + 1))
      _ui_measure
      _ui_write "${_UI_ERASE}${_UI_HIDE}$(_ui_fit "  $(_ui_glyph)  $label  ($(elapsed $start))" "$_UI_COLS")${_UI_SHOW}"
      n=$((n + 1))
      sleep 0.1
    done
  done
  _ui_erase
  return 0
}

# Spin while a background job runs, redrawing softwareupdate's percentage if it emits
# one. Its output format has been reworded across releases, so treat any NN% in the
# log as the truth and fall back to a bare spinner when nothing parses.
spin_on_log() {
  local pid=$1 label=$2 log=$3
  local start=$SECONDS pct phase
  if ! ui_watching; then
    say "$label..."
    wait "$pid"
    return $?
  fi
  _ui_measure
  while kill -0 "$pid" 2>/dev/null; do
    pct=$(tr '\r' '\n' <"$log" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?%' | tail -1 | tr -d '%')
    pct=${pct%%.*}
    phase=$(tr '\r' '\n' <"$log" 2>/dev/null | grep -oE '^(Downloading|Downloaded|Installing|Preparing|Waiting)' | tail -1)
    [ -n "$phase" ] || phase=$label
    _UI_FRAME=$((${_UI_FRAME:-0} + 1))
    if [ -n "$pct" ]; then
      _ui_write "${_UI_ERASE}${_UI_HIDE}$(_ui_fit "$(printf '  %s  %-12s %s  %3s%%   (%s)' \
        "$(_ui_glyph)" "$phase" "$(progress_bar "$pct")" "$pct" "$(elapsed $start)")" "$_UI_COLS")${_UI_SHOW}"
    else
      _ui_write "${_UI_ERASE}${_UI_HIDE}$(_ui_fit "$(printf '  %s  %s  (%s)' \
        "$(_ui_glyph)" "$phase" "$(elapsed $start)")" "$_UI_COLS")${_UI_SHOW}"
    fi
    sleep 0.1
  done
  _ui_erase
  wait "$pid"
}

# Spin while a background job runs, and stop for good the moment $log grows a
# line matching $gate_re. Whichever comes first, the gate or the job's death,
# ends the animation; nothing here ever starts it again.
#
# That one-way shape is the whole point, and it is why this is not spin_on_log
# with a predicate bolted on. It exists for a caller whose tool goes from silent
# to owning the terminal partway through its run: brew, which downloads in
# silence and then hands /dev/tty to a cask's sudo prompt. A frame drawn after
# that handover can erase "Password:" a hundred milliseconds after it appears,
# and the apply then blocks forever on a question nobody was shown.
#
# Two differences from spin_on_log follow from that, both deliberate:
#
# It does not wait on the pid. The caller still has a live job, an open log, and
# a status to collect after the gate opens, so waiting here would strand all
# three. Every caller owes its own wait.
#
# The gate is read before each draw rather than after, so no frame can follow a
# line this loop has already seen. Reading it after would leave exactly one
# frame on the far side of the gate, which is the frame that erases the prompt.
#
# Polling the log costs a `tr | grep` per frame, the same order as spin_on_log's
# own per-frame read, and for the same reason: the log is the only thing that
# knows what phase the tool is in.
spin_until_log_gate() {
  local pid=$1 label=$2 log=$3 gate_re=$4
  local start=$SECONDS
  ui_watching || return 0
  _ui_measure
  while kill -0 "$pid" 2>/dev/null; do
    if tr '\r' '\n' <"$log" 2>/dev/null | grep -Eq "$gate_re"; then
      break
    fi
    _UI_FRAME=$((${_UI_FRAME:-0} + 1))
    _ui_write "${_UI_ERASE}${_UI_HIDE}$(_ui_fit "  $(_ui_glyph)  ${label}  ($(elapsed "$start"))" "$_UI_COLS")${_UI_SHOW}"
    sleep "$_UI_TICK_INTERVAL"
  done
  _ui_erase
  return 0
}

# --- step vocabulary -------------------------------------------------------
#
# fd 9 is the screen. It is opened once, lazily, by ui_watching.

# Is anyone watching? Answered by opening /dev/tty, not by testing stdout.
#
# /dev/tty fails with "Device not configured" wherever the process has no
# controlling terminal—under setsid, over ssh without a tty, in a cron job—
# which is exactly the set of venues that want plain lines. A captured apply is
# deliberately not in that set. Its /dev/tty stays open, so the animation keeps
# running on the screen while the log stays greppable.
#
# The open is guarded because a `set -e` caller must survive a venue with no
# terminal, and the answer is cached tri-state so the open happens once.
ui_watching() {
  [ -n "${NO_COLOR:-}" ] && return 1
  [ -n "${DOTFILES_NO_PROGRESS:-}" ] && return 1
  case "${_UI_TTY:-}" in
  1) return 0 ;;
  0) return 1 ;;
  esac
  # The redirection order matters: `exec 9>/dev/tty 2>/dev/null` applies
  # 9>/dev/tty first and prints "Device not configured" to the still-live
  # stderr before the silencer exists, so every plain-venue run would carry a
  # diagnostic about the terminal it correctly decided it does not have. A
  # brace group silences the whole thing and still leaves fd 9 open here,
  # which a subshell would not.
  if { exec 9>/dev/tty; } 2>/dev/null; then
    _UI_TTY=1
    return 0
  fi
  _UI_TTY=0
  return 1
}

# Escape sequences, decoded once here rather than spelled as backslashes at
# each call site. _ui_write hands its argument to `printf '%s'`, which does not
# interpret escapes—and it must not, because labels and details are caller
# text that a `%b` would happily reinterpret.
_UI_HIDE=$'\033[?25l'
_UI_SHOW=$'\033[?25h'
_UI_ERASE=$'\r\033[K'

# One frame, one write, always ending with the cursor restore.
#
# Both redirections on the subshell are load-bearing, and the second one is the
# surprise. When /dev/tty is open but its writes fail—a closed pty master,
# which is how that state gets built—bash 3.2 keeps the bytes of the failed
# `printf >&9` in its stdout buffer and flushes them when the redirection is
# undone. A subshell alone does not save you. The flush lands on the subshell's
# own fd 1, which is still the caller's stdout, and the whole animation spills
# onto the one stream this design exists to keep clean. A capture measured here
# carried twelve frames of braille and CSI that way. Pointing the subshell's
# stdout at /dev/null gives those bytes somewhere harmless to go.
_ui_write() {
  ( printf '%s' "$1" >&9 ) >/dev/null 2>&1 || true
  return 0
}

# Erase the live line. Nothing but the cursor restore may follow a final frame,
# and no residual frame text may sit behind the erase.
_ui_erase() {
  ui_watching || return 0
  _ui_write "${_UI_ERASE}${_UI_SHOW}"
  return 0
}

# A settled line. Two spaces, one glyph, two spaces, then the shared columns—
# label, detail, elapsed—so ten scripts' worth of these read as one run
# rather than as a changelog of unrelated tools.
_ui_settled() {
  # Both fields are trimmed as well as padded. %-24s only pads, so one long
  # detail pushes the elapsed column out of line and ten scripts stop reading
  # as one run, which is the whole property these columns exist for.
  printf '  %s  %-16s %-24s (%s)\n' "$1" "$(_ui_fit "$2" 16)" "$(_ui_fit "$3" 24)" "$4"
  return 0
}

# Terminal width, from the terminal itself.
#
# `stty size </dev/tty` is the only thing that answers here. No script run by
# `chezmoi apply` has COLUMNS set or TERM exported, so a kit reading
# ${COLUMNS:-80} truncates nothing in production while passing any check that
# sets the variable.
#
# Cached into a global rather than returned, because a caller reading it
# through $( ) runs this in a subshell whose assignment dies with it, and the
# fork would then happen ten times a second for the length of a download. A
# terminal resized mid-apply keeps the width it started with, which costs one
# wrapped line at the moment of the resize.
_ui_measure() {
  [ -n "${_UI_COLS:-}" ] && return 0
  local size cols
  size=$(stty size </dev/tty 2>/dev/null) || size=''
  cols=${size##* }
  # A terminal reporting nothing, or zero columns, is a display fault. It must
  # not take the script down and must not produce a nonsense width.
  case "$cols" in
  '' | *[!0-9]*) cols=80 ;;
  esac
  [ "$cols" -ge 20 ] || cols=80
  _UI_COLS=$cols
  return 0
}

# Trim to a display-column budget. A wrapped live line sends the next carriage
# return back to the wrong row, after which the animation eats the scrollback
# above it.
#
# ${#s} counts characters rather than bytes under a UTF-8 locale, which is what
# a braille or block glyph needs. Callers pass plain text with no escape
# sequences in it, so what is counted here is what the terminal renders.
_ui_fit() {
  local s="$1" max="$2"
  if [ "$max" -lt 2 ]; then
    printf ''
    return 0
  fi
  if [ "${#s}" -le "$max" ]; then
    printf '%s' "$s"
    return 0
  fi
  printf '%s…' "${s:0:$((max - 1))}"
  return 0
}

# The current frame glyph.
#
# SPINNER_FRAMES unset and SPINNER_FRAMES empty are separate states on bash
# 3.2—`${#a[@]}` raises `unbound variable` under `set -u` when unset and
# evaluates to 0 when empty—so both are guarded, in that order. A display
# with no frames to draw falls back to a character rather than taking the
# script down with it.
_UI_FRAME=0

_ui_glyph() {
  if [ -z "${SPINNER_FRAMES+x}" ]; then
    printf '*'
    return 0
  fi
  local n=${#SPINNER_FRAMES[@]}
  if [ "$n" -eq 0 ]; then
    printf '*'
    return 0
  fi
  printf '%s' "${SPINNER_FRAMES[${_UI_FRAME:-0} % n]}"
  return 0
}

# Open a step: remember its label and start time, and put a first frame on the
# screen. Writes nothing to stdout—a step that has only begun has no outcome
# to record yet, and a line written now would have to be unwritten later.
# The live line's own clock. Forked by step_begin and re-forked by step_tick,
# because the text between two ticks never changes — only the glyph does — so
# re-forking once per item is cheaper than a state file both processes read.
#
# Exactly one process writes the live line at a time. Two writers interleave
# mid-escape-sequence and leave the cursor wherever the loser stopped.
_ui_start_ticker() {
  ui_watching || return 0
  [ "${_UI_NO_LIVE:-0}" = 1 ] && return 0
  local text="$1"
  (
    local i="${_UI_FRAME:-0}"
    while :; do
      _UI_FRAME=$i
      _ui_write "${_UI_ERASE}${_UI_HIDE}$(_ui_fit "  $(_ui_glyph)  ${text}" "$_UI_COLS")${_UI_SHOW}"
      i=$((i + 1))
      sleep "$_UI_TICK_INTERVAL"
    done
  ) &
  _UI_TICK_PID=$!
  return 0
}

# Guarded end to end. A ticker that cannot be signalled is a cosmetic problem;
# a finalizer that aborts on one is a display fault changing the exit status.
_ui_stop_ticker() {
  [ -n "${_UI_TICK_PID:-}" ] || return 0
  kill "$_UI_TICK_PID" 2>/dev/null || true
  wait "$_UI_TICK_PID" 2>/dev/null || true
  _UI_TICK_PID=""
  return 0
}

step_begin() {
  _UI_STEP_LABEL="$1"
  _UI_STEP_START=$SECONDS
  ui_watching || return 0
  _ui_measure
  _ui_start_ticker "$1"
  return 0
}

# A step that owns a settled line and no live one. The installer needs this:
# a frame drawn while `brew bundle` holds /dev/tty can erase a cask's sudo
# prompt, and the apply then blocks forever on something shown for 100ms.
# Making it a separate entry point keeps that guarantee structural rather than
# a matter of where the frames happen to land.
step_begin_quiet() {
  _UI_STEP_LABEL="$1"
  _UI_STEP_START=$SECONDS
  return 0
}

# One frame of a running step. Callers drive this from inside their own loop:
# the scripts here are synchronous, so there is no background job to poll and
# no state to share between them.
#
# The frame index advances whether or not anyone is watching, so a kit that
# starts drawing partway through a run picks up where the count is rather than
# restarting on the first glyph every time.
step_tick() {
  local n="${1:-}" total="${2:-}" detail="${3:-}" count=''
  _UI_FRAME=$((${_UI_FRAME:-0} + 1))
  ui_watching || return 0
  if [ -n "$n" ] && [ -n "$total" ]; then
    count="$n/$total "
  fi
  _ui_measure
  _ui_stop_ticker
  _ui_start_ticker "${_UI_STEP_LABEL:-}  ${count}${detail}"
  return 0
}

# Run a tool with the live line out of the way, handing back its exit status
# untouched. Every tool that writes to the terminal while a step is live owes
# its call to this.
#
# A frame write parks the cursor at the end of the drawn text and never emits a
# newline, so a tool printing while the ticker is up continues the frame's row
# rather than starting one. On an attended apply that is every tool, because
# stdout and /dev/tty are the same device there (#38). It is also why the
# suite's split-stream venues cannot see the collision: they are the one venue
# where the two streams are not the same device.
#
# Buffering the tool and replaying it once the step settles would erase the
# collision too, and it is ruled out. A failing tool's stderr has to stay on
# screen beside the item that failed, and a slow tool's scrollback is the only
# liveness signal there is while it holds the run.
#
# No ticker restart on the way out. step_tick forks one at the top of the next
# iteration, and restarting here would put a live line back in front of the
# caller's own failure echo, which is the same collision one line further down.
# The cost is real: in a loop that ticks and then immediately shells out, the
# live line is drawn and erased inside a millisecond, so these steps are
# carried by their settled line and the tool's own output rather than by the
# animation.
#
# step_run closes the tool's window, not the race. _ui_stop_ticker waits on the
# ticker, so no frame lands once it returns, but anything printing outside a
# step_run call still arrives mid-frame.
step_run() {
  _ui_stop_ticker
  _ui_erase
  "$@"
}

_ui_close() {
  local glyph="$1" label="$2" detail="${3:-}"
  local start="${_UI_STEP_START:-$SECONDS}"
  _ui_stop_ticker
  _ui_erase
  _ui_settled "$glyph" "$label" "$detail" "$(elapsed "$start")"
  _UI_STEP_LABEL=""
  return 0
}

step_ok() { _ui_close '✓' "$1" "${2:-}"; }
step_warn() { _ui_close '!' "$1" "${2:-}"; }
step_fail() { _ui_close '✗' "$1" "${2:-}"; }

# Chained from each caller's EXIT trap, which must capture $? into a variable
# as the trap body's very first statement and pass it here. Without that the finalizer reads
# whatever the trap body's own first command returned—and
# run_once_before_install-prerequisites' trap opens with `rm -f`, which always
# returns 0, so a failing script would settle its line as a success.
#
# Every command is guarded, not just the last. Under `set -e` a trap aborts at
# its first failing command, and the write to a vanished tty is exactly the
# command that fails in the venues this exists for, so an unguarded finalizer
# never reaches its cursor restore. Returning non-zero is its own bug. A trap
# that fails turns a successful script into an exit 1, which is a display fault
# changing the exit status.
ui_finalize() {
  local st="${1:-0}"
  case "$st" in
  '' | *[!0-9]*) st=0 ;;
  esac
  _ui_stop_ticker || true
  if [ -n "${_UI_STEP_LABEL:-}" ] && [ "$st" -ne 0 ]; then
    step_fail "$_UI_STEP_LABEL" "failed (exit $st)" || true
  fi
  show_cursor || true
  return 0
}
