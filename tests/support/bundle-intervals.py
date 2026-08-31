#!/usr/bin/env python3
"""Report frame glyphs landing inside a brew bundle's own interval.

The property is interval-scoped, not whole-run silence, and the difference
decides real cases. Read as whole-run silence the rule rejects a script that
animates around the tap-trust loop; read as interval silence it permits that
and still catches the frame that matters. The interval is the reading.

The stub standing in for `brew bundle` brackets itself by writing BUNDLE-ENTER
and BUNDLE-EXIT markers to /dev/tty, so entry and exit are anchored by the
thing being measured rather than guessed from timing. A frame glyph between an
ENTER and its matching EXIT is a violation, because that is the window in which
a cask's sudo prompt owns the stream.

Usage: bundle-intervals.py CAPTURE GLYPHS
Prints: intervals=N violations=M
"""

import re
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: bundle-intervals.py CAPTURE GLYPHS\n")
        return 2
    data = open(sys.argv[1], "rb").read()
    glyphs = [g.encode("utf-8") for g in sys.argv[2]]

    intervals = 0
    violations = 0
    for m in re.finditer(rb"BUNDLE-ENTER-(\d+)", data):
        n = m.group(1)
        exit_m = re.search(rb"BUNDLE-EXIT-" + n, data[m.end():])
        if exit_m is None:
            # An interval opened and never closed still counts as entered, and
            # everything after it is inside it.
            segment = data[m.end():]
        else:
            segment = data[m.end():m.end() + exit_m.start()]
        intervals += 1
        violations += sum(segment.count(g) for g in glyphs)

    print("intervals=%d violations=%d" % (intervals, violations))
    return 0


if __name__ == "__main__":
    sys.exit(main())
