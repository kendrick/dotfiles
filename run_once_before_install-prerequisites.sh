#!/bin/bash
# Install Xcode Command Line Tools and Homebrew (runs once per machine).
#
# This script only gets to run on a bare Mac because the README bootstrap passes
# --use-builtin-git=on. Without it, chezmoi shells out to /usr/bin/git to clone the
# repo, that stub fires the CLT install prompt and exits 1, and init dies before the
# before-phase exists. Don't drop the flag from the README command.
#
# Targets bash 3.2, which is what /bin/bash is on a factory Mac. Nothing newer is
# installed yet at this point in the run.

set -e

CLT_SENTINEL=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

cleanup() {
  rm -f "$CLT_SENTINEL"
  [ -t 1 ] && printf '\033[?25h' # cursor back, however we exited
  return 0
}
trap cleanup EXIT

# --- terminal chrome -------------------------------------------------------------
# Everything here degrades to plain lines without a TTY. chezmoi captures this output
# and the auto-sync log has to stay greppable, so no escape codes unless someone's
# actually watching.

say() { printf '  %s\n' "$1"; }
ok() { printf '  ✓  %s\n' "$1"; }
warn() { printf '  !  %s\n' "$1"; }

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
# every couple of seconds. Polling it at frame rate would fork pkgutil ten times a
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

# --- Xcode Command Line Tools ----------------------------------------------------

# `xcode-select -p` is not a presence check: it prints a path for a directory holding
# nothing but the shims, which is exactly the state a factory Mac is in. Probe for real
# binaries instead. The pkgutil receipt is the second opinion, for a layout change that
# moves them somewhere we don't expect.
have_clt() {
  local dev
  dev=$(xcode-select -p 2>/dev/null) || return 1
  [ -x "$dev/usr/bin/clang" ] && [ -x "$dev/usr/bin/git" ] && return 0
  pkgutil --pkg-info=com.apple.pkg.CLTools_Executables >/dev/null 2>&1 &&
    [ -x /Library/Developer/CommandLineTools/usr/bin/clang ]
}

# Install without the GUI installer, so progress lands in the terminal the user is
# already looking at. The sentinel file is what makes softwareupdate list CLT at all.
install_clt_headless() {
  local label log status
  touch "$CLT_SENTINEL"

  # Cataloguing is the slow half of this, a minute or so on a cold machine.
  log=$(mktemp)
  (softwareupdate -l >"$log" 2>&1) &
  spin_on_log $! "Finding the installer" "$log" || true
  # BSD sed and grep have no \s, hence the POSIX classes.
  label=$(grep -E '^[[:space:]]*\*[[:space:]]*Label:.*Command Line Tools' "$log" |
    sed -E 's/^[[:space:]]*\*[[:space:]]*Label:[[:space:]]*//' | sort -V | tail -1)
  rm -f "$log"

  if [ -z "$label" ]; then
    warn "Couldn't find Command Line Tools in the software update catalog."
    return 1
  fi
  ok "$label"

  # Prime sudo in the foreground. Backgrounding the install is what lets us draw the
  # progress bar, and a background job can't own the terminal to ask for a password.
  say "macOS needs your password to install them."
  sudo -v || return 1

  log=$(mktemp)
  # shellcheck disable=SC2024  # the log is our own mktemp file; the shell should own
  # this redirect, not root, or we'd leave a root-owned file behind in /tmp.
  (sudo softwareupdate -i "$label" --verbose >"$log" 2>&1) &
  # Assign through || so errexit can't kill us before we've read the status.
  status=0
  spin_on_log $! "Installing" "$log" || status=$?
  [ "$status" -eq 0 ] || sed 's/^/     /' "$log"
  rm -f "$log"

  # softwareupdate has been known to exit 0 without installing anything, so the exit
  # status alone doesn't settle it.
  [ "$status" -eq 0 ] && have_clt
}

# Fall back to Apple's installer. Slower to watch, but it works on every macOS release
# regardless of how the update catalog is worded this year.
install_clt_gui() {
  xcode-select --install >/dev/null 2>&1 || true

  # `open -a` on a running app just activates it, so no Accessibility grant and no
  # permission modal of our own. Otherwise the dialog opens behind the terminal and
  # looks like a hang, which is how we got here in the first place.
  open -a "/System/Library/CoreServices/Install Command Line Developer Tools.app" >/dev/null 2>&1 || true

  printf '\n'
  say "→ Apple's installer is open. Click Install to continue."
  say "  (check behind this window if you don't see it)"
  printf '\n'
  spin_until "Waiting for the install to finish" 3600 have_clt
}

if have_clt; then
  ok "Xcode Command Line Tools already installed."
else
  say "Xcode Command Line Tools are missing. Homebrew and git need them."

  # Only ask when someone's there to answer. The auto-sync LaunchAgent must never
  # block on a read, and a run_once script re-runs whenever its contents change.
  if [ -t 0 ]; then
    printf '  Install them now? [Y/n] '
    read -r reply || reply=""
    case "$reply" in
      [nN] | [nN][oO])
        warn "Skipped. Install them with 'xcode-select --install', then re-run 'chezmoi apply'."
        exit 1
        ;;
    esac
  fi

  start=$SECONDS
  if install_clt_headless; then
    ok "Xcode Command Line Tools installed  ($(elapsed $start))"
  elif install_clt_gui; then
    ok "Xcode Command Line Tools installed  ($(elapsed $start))"
  else
    warn "Xcode Command Line Tools didn't install."
    warn "Run 'xcode-select --install' by hand, then re-run 'chezmoi apply'."
    exit 1
  fi
fi

# --- Homebrew ---------------------------------------------------------------------

if command -v brew &>/dev/null; then
  ok "Homebrew already installed."
else
  say "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  ok "Homebrew installed."
fi

say "Prerequisites ready."
