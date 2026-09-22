#!/usr/bin/env python3
"""Claude Code Status Line — Dreambase Flat

Single-line adaptation of @kyleledbetter's Dreambase Panel, rendered on one
line instead of a boxed three-row panel.

Layout:
    ◆ Model  ·  branch │ bar pct of SIZE │ ↓in ↑out │ ⏱dur │ 5h · n% ↻ r │ 7d · n% ↻ r

Colors come from the terminal's 16-color palette (SGR 30-37 plus bold and dim)
wherever that palette has the hue, so they follow whatever theme the terminal
is running. Three hues it lacks, Claude's rust plus the lime and orange rungs of
the usage ladder, are fixed 256-color indexes. A fixed index is the same color
under every theme, so each of the three is a mid-tone that keeps contrast
against both Catppuccin Latte and Mocha. Index 255 fails that test, since it is
white on a light background too, and a percentage printed in it vanishes. The
script also skips the bright variants (90-97). Solarized and its descendants repurpose
them as greys, so bright yellow there is a mid-grey and bright black is the
background itself. Grey is dim (SGR 2), since bright black is out.

The panel's cost, lines-changed, git dirty-state, clock, and vim segments are
deliberately absent, so the code behind them is gone rather than computed and
dropped. The git call is down to one `branch --show-current` for the same
reason: the +/~/? counts cost three more subprocesses per render and nothing
displays them.
"""

import hashlib
import json
import os
import subprocess
import sys
import time

data = json.load(sys.stdin)

# ── Extract data ──────────────────────────────────────────
model = data.get("model", {}).get("display_name", "—")
model_id = data.get("model", {}).get("id", "")
project_dir = data.get("workspace", {}).get("project_dir", ".")
pct = int(float(data.get("context_window", {}).get("used_percentage") or 0))
ctx_size = int(data.get("context_window", {}).get("context_window_size") or 200000)
input_tokens = int(data.get("context_window", {}).get("total_input_tokens") or 0)
output_tokens = int(data.get("context_window", {}).get("total_output_tokens") or 0)
duration_ms = int(data.get("cost", {}).get("total_duration_ms") or 0)
exceeds_200k = data.get("exceeds_200k_tokens", False)

# Present only for claude.ai Pro and Max, and only after the session's first API
# response. Each window disappears on its own once its reset time passes, so
# every read below tolerates a missing window rather than a missing object.
rate_limits = data.get("rate_limits") or {}

# ── ANSI Colors ───────────────────────────────────────────
R = "\033[0m"
B = "\033[1m"
D = "\033[2m"

# Claude rust / terracotta. 173 is the nearest xterm index to the brand
# #D97757. 131 is its darker sibling, for separators and labels.
RUST = "\033[38;5;173m"
RUST_D = "\033[38;5;131m"

# Theme palette
GRN = "\033[32m"
YEL = "\033[33m"
RED = "\033[31m"
BLU = "\033[34m"
PUR = "\033[35m"
FG = "\033[39m"   # default foreground: the one color every theme keeps readable
GRY = "\033[2m"

# Ladder rungs the theme palette lacks. 70 is a yellow-green dark enough to
# read on Latte, where 118, the obvious lime, washes out. 208 is a plain orange
# that sits apart from both theme yellow and theme red.
LIME = "\033[38;5;70m"
ORG = "\033[38;5;208m"


# ── Formatters ────────────────────────────────────────────
def fmt_tok(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def fmt_dur(ms):
    """Session length to the nearest minute: 2h 7m, 7m, or <1m. No seconds,
    for the reason fmt_eta gives."""
    total_min = round(ms / 60_000)
    if total_min < 1:
        return "<1m"
    h, m = divmod(total_min, 60)
    return f"{h}h {m}m" if h else f"{m}m"


def fmt_eta(seconds):
    """Compact countdown: 3d 4h, 2h 7m, 7m, or <1m. Past a day the minutes drop
    out as well. Only the 7d window runs that long, and nobody plans around
    the minute of a reset three days out. No seconds—the status line
    only re-renders on events (and on refreshInterval), so a ticking second
    would be wrong more often than right."""
    if seconds <= 0:
        return "now"
    d, rem = divmod(int(seconds), 86_400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    if d:
        return f"{d}d {h}h"
    if h:
        return f"{h}h {m}m"
    if m:
        return f"{m}m"
    return "<1m"


def truncate(s, maxlen=18):
    return s[: maxlen - 1] + "…" if len(s) > maxlen else s


def usage_color(p):
    """One threshold ladder shared by the context bar and both rate-limit
    windows, so 85% means the same shade wherever it appears."""
    if p >= 95:
        return RED
    if p >= 85:
        return ORG
    if p >= 70:
        return YEL
    if p >= 50:
        return LIME
    return GRN


# ── Progress bar ──────────────────────────────────────────
BAR_W = 22
BLOCKS = " ▏▎▍▌▋▊▉█"

bar_clr = usage_color(pct)

eighths = pct * BAR_W * 8 // 100
full = eighths // 8
partial = eighths % 8
empty = BAR_W - full - (1 if partial else 0)

bar = "█" * full
if partial:
    bar += BLOCKS[partial]
bar += "░" * empty

ctx_label = "1M" if ctx_size >= 1_000_000 else "200K"
# Red is the ladder's top rung and has to keep meaning "act now". This flag is
# informational: it reports the last API response crossing a fixed 200k total,
# and can flip back off on the next turn. Grey carries it without the alarm.
warn = f" {GRY}⚠{R}" if exceeds_200k else ""


# ── Git branch (cached for perf) ──────────────────────────
# Keyed by project_dir. A single shared cache file reports whichever repo
# rendered last, which is wrong for up to the TTL in every other session — and
# this setup runs worktrees side by side, so that is the common case, not the
# edge one.
# hashlib, not hash(): Python salts string hashing per process, so a built-in
# hash here names a different file on every render and the cache never hits.
CACHE = "/tmp/claude-sl-git-" + hashlib.md5(project_dir.encode()).hexdigest()[:12]


def git_branch():
    try:
        if time.time() - os.path.getmtime(CACHE) < 5:
            with open(CACHE) as f:
                cached = f.read().strip()
            # The previous script cached four pipe-joined fields here. Reading
            # one of those as a branch name prints `main|0|0|0` until the TTL
            # expires, so treat the old shape as a miss.
            if "|" not in cached:
                return cached
    except (OSError, ValueError):
        pass
    try:
        br = subprocess.run(
            ["git", "-C", project_dir, "branch", "--show-current"],
            capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        with open(CACHE, "w") as f:
            f.write(br)
        return br
    except Exception:
        return ""


branch = git_branch()

# ── Derived values ────────────────────────────────────────
in_t = fmt_tok(input_tokens)
out_t = fmt_tok(output_tokens)
dur_s = fmt_dur(duration_ms)

# Model diamond icon
if "opus" in model_id:
    m_icon = f"{RUST}◆{R}"
elif "sonnet" in model_id:
    m_icon = f"{BLU}◆{R}"
elif "haiku" in model_id:
    m_icon = f"{GRN}◆{R}"
else:
    m_icon = f"{GRY}◆{R}"


def limit_segment(label, key):
    """`5h · 26% ↻ 2h 7m`, colored on the same ladder as the context bar.
    Returns None when the window is absent so the caller can drop the separator
    with it, rather than printing an empty cell between two pipes."""
    window = rate_limits.get(key)
    if not window:
        return None
    used = window.get("used_percentage")
    if used is None:
        return None
    p = int(float(used))
    seg = f"{RUST_D}{label}{R} {D}·{R} {usage_color(p)}{B}{p}%{R}"
    resets_at = window.get("resets_at")
    if resets_at:
        seg += f" {GRY}↻ {fmt_eta(float(resets_at) - time.time())}{R}"
    return seg


# ── Build content strings ─────────────────────────────────
repo_content = f"{m_icon} {RUST}{B}{model}{R}"
if branch:
    repo_content += f"  {RUST_D}·{R}  {PUR}{truncate(branch)}{R}"

ctx_content = f"{bar_clr}{bar}{R}  {FG}{B}{pct}%{R}{warn} {D}of{R} {RUST}{ctx_label}{R}"

tok_content = f"{BLU}↓{R} {in_t}  {PUR}↑{R} {out_t}"

dur_content = f"{GRY}⏱ {dur_s}{R}"

# ── Render (single line) ──────────────────────────────────
sections = [repo_content, ctx_content, tok_content, dur_content]
sections += [s for s in (limit_segment("5h", "five_hour"),
                         limit_segment("7d", "seven_day")) if s]

sep = f"  {RUST_D}│{R}  "
print(sep.join(sections))
