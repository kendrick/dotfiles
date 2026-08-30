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
      _ui_write "${_UI_ERASE}${_UI_HIDE}  $(_ui_glyph)  $label  ($(elapsed $start))${_UI_SHOW}"
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
  while kill -0 "$pid" 2>/dev/null; do
    pct=$(tr '\r' '\n' <"$log" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?%' | tail -1 | tr -d '%')
    pct=${pct%%.*}
    phase=$(tr '\r' '\n' <"$log" 2>/dev/null | grep -oE '^(Downloading|Downloaded|Installing|Preparing|Waiting)' | tail -1)
    [ -n "$phase" ] || phase=$label
    _UI_FRAME=$((${_UI_FRAME:-0} + 1))
    if [ -n "$pct" ]; then
      _ui_write "${_UI_ERASE}${_UI_HIDE}$(printf '  %s  %-12s %s  %3s%%   (%s)' \
        "$(_ui_glyph)" "$phase" "$(progress_bar "$pct")" "$pct" "$(elapsed $start)")${_UI_SHOW}"
    else
      _ui_write "${_UI_ERASE}${_UI_HIDE}$(printf '  %s  %s  (%s)' \
        "$(_ui_glyph)" "$phase" "$(elapsed $start)")${_UI_SHOW}"
    fi
    sleep 0.1
  done
  _ui_erase
  wait "$pid"
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
  printf '  %s  %-16s %-24s (%s)\n' "$1" "$2" "$3" "$4"
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
step_begin() {
  _UI_STEP_LABEL="$1"
  _UI_STEP_START=$SECONDS
  ui_watching || return 0
  _ui_write "${_UI_ERASE}${_UI_HIDE}  $(_ui_glyph)  $1${_UI_SHOW}"
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
  _ui_write "${_UI_ERASE}${_UI_HIDE}  $(_ui_glyph)  ${_UI_STEP_LABEL:-}  ${count}${detail}${_UI_SHOW}"
  return 0
}

_ui_close() {
  local glyph="$1" label="$2" detail="${3:-}"
  local start="${_UI_STEP_START:-$SECONDS}"
  _ui_erase
  _ui_settled "$glyph" "$label" "$detail" "$(elapsed "$start")"
  _UI_STEP_LABEL=""
  return 0
}

step_ok() { _ui_close '✓' "$1" "${2:-}"; }
step_warn() { _ui_close '!' "$1" "${2:-}"; }
step_fail() { _ui_close '✗' "$1" "${2:-}"; }

# Chained from each caller's EXIT trap, which must capture $? into a local as
# its very first statement and pass it here. Without that the finalizer reads
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
  if [ -n "${_UI_STEP_LABEL:-}" ] && [ "$st" -ne 0 ]; then
    step_fail "$_UI_STEP_LABEL" "failed (exit $st)" || true
  fi
  show_cursor || true
  return 0
}
