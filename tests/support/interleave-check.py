#!/usr/bin/env python3
"""Report animation frames sharing a terminal row with tool output.

The kit repaints its spinner with `\\r` + erase-to-end-of-line + text, never a
newline, so the cursor sits parked at the end of that line between frames.
When a tool writes to stdout in that window, and on a real terminal stdout
and /dev/tty are the same device, so its bytes land after the frame's own
bytes, on the row the frame is still occupying. Splitting the capture into
terminal rows the way the terminal itself would (on `\\r` as well as `\\n`,
since the kit's own frame writes begin with `\\r`) turns "did they collide"
into "did they end up in the same row," which is checkable without a real
terminal.

`glyph_rows` and `marker_rows` are non-vacuity guards, not just diagnostics.
A capture with no glyphs, or no marker, reports violations=0 while proving
nothing, the same trap as a stub that returns before its window opens and
so certifies whatever it is given (see `ui_write_brew_bundle_stub` in
tests/helpers.bash). The calling test asserts both counts are non-zero
precisely to rule that out.

Usage: interleave-check.py CAPTURE GLYPHS MARKER
Prints: rows=N glyph_rows=N marker_rows=N violations=N
"""

import sys


def main():
    if len(sys.argv) != 4:
        sys.stderr.write("usage: interleave-check.py CAPTURE GLYPHS MARKER\n")
        return 2
    data = open(sys.argv[1], "rb").read()
    glyphs = [g.encode("utf-8") for g in sys.argv[2]]
    marker = sys.argv[3].encode("ascii")

    # A row ends at \r or \n; folding \r to \n first lets one split catch
    # both, matching how the kit's \r-led frame writes and any ordinary
    # newline both close out the row they terminate.
    rows = data.replace(b"\r", b"\n").split(b"\n")

    glyph_rows = 0
    marker_rows = 0
    violations = 0
    for row in rows:
        # Escape sequences (e.g. \033[K) live inside the row's bytes, but
        # neither a UTF-8 glyph nor an ASCII marker can appear as a substring
        # of one, so the plain containment check below never mistakes an
        # escape for either.
        has_glyph = any(g in row for g in glyphs)
        has_marker = marker in row
        if has_glyph:
            glyph_rows += 1
        if has_marker:
            marker_rows += 1
        if has_glyph and has_marker:
            violations += 1

    print(
        "rows=%d glyph_rows=%d marker_rows=%d violations=%d"
        % (len(rows), glyph_rows, marker_rows, violations)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
