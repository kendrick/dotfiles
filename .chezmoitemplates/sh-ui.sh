# Terminal chrome shared by the before-phase scripts, pulled in with a Go template include
# the same way the Brewfile is. Don't write that include inside this file: chezmoi parses
# this as a template too, so it would recurse.
#
# Everything here degrades to plain lines without a TTY. chezmoi captures this output and
# the auto-sync log has to stay greppable, so no escape codes unless someone's watching.
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
  [ -t 1 ] && printf '\033[?25h'
  return 0
}

elapsed() {
  local s=$((SECONDS - $1))
  printf '%d:%02d' $((s / 60)) $((s % 60))
}

progress_bar() {
  local pct=$1 width=24 filled i out=''
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
  local start=$SECONDS i=0 n
  if [ ! -t 1 ]; then
    say "$label..."
    while ! "$@"; do
      [ $((SECONDS - start)) -lt "$timeout" ] || return 1
      sleep 5
    done
    return 0
  fi
  printf '\033[?25l'
  while ! "$@"; do
    if [ $((SECONDS - start)) -ge "$timeout" ]; then
      printf '\r\033[K\033[?25h'
      return 1
    fi
    n=0
    while [ "$n" -lt 20 ]; do
      printf '\r  %s  %s  (%s)\033[K' "${SPINNER_FRAMES[i % 10]}" "$label" "$(elapsed $start)"
      i=$((i + 1))
      n=$((n + 1))
      sleep 0.1
    done
  done
  printf '\r\033[K\033[?25h'
  return 0
}

# Spin while a background job runs, redrawing softwareupdate's percentage if it emits
# one. Its output format has been reworded across releases, so treat any NN% in the
# log as the truth and fall back to a bare spinner when nothing parses.
spin_on_log() {
  local pid=$1 label=$2 log=$3
  local start=$SECONDS i=0 pct phase
  if [ ! -t 1 ]; then
    say "$label..."
    wait "$pid"
    return $?
  fi
  printf '\033[?25l'
  while kill -0 "$pid" 2>/dev/null; do
    pct=$(tr '\r' '\n' <"$log" 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?%' | tail -1 | tr -d '%')
    pct=${pct%%.*}
    phase=$(tr '\r' '\n' <"$log" 2>/dev/null | grep -oE '^(Downloading|Downloaded|Installing|Preparing|Waiting)' | tail -1)
    [ -n "$phase" ] || phase=$label
    if [ -n "$pct" ]; then
      printf '\r  %s  %-12s %s  %3d%%   (%s)\033[K' \
        "${SPINNER_FRAMES[i % 10]}" "$phase" "$(progress_bar "$pct")" "$pct" "$(elapsed $start)"
    else
      printf '\r  %s  %s  (%s)\033[K' "${SPINNER_FRAMES[i % 10]}" "$phase" "$(elapsed $start)"
    fi
    i=$((i + 1))
    sleep 0.1
  done
  printf '\r\033[K\033[?25h'
  wait "$pid"
}
