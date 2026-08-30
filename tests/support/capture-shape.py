#!/usr/bin/env python3
"""Report the cursor-hygiene shape of a /dev/tty capture.

Three numbers, because the interesting property is not "was the cursor visible
afterward". That question was measured unable to discriminate: the same kit won
the post-signal race 11 trials of 12 in one harness, lost 12 of 12 in another,
and won 5 of 6 standalone, so the ending describes the venue rather than the
kit. What survives every venue is the shape of the byte stream.

  glyphs          how many frame glyphs the capture carries. A capture with
                  fewer than two proves nothing: a purely negative reading
                  passes on a zero-byte capture from a run that never executed.

  unmatched_hide  1 when an ESC[?25l is never followed by its restore, so the
                  terminal is left with no cursor.

  max_span        the most frame glyphs lying between any ESC[?25l and its
                  matching restore, with an unmatched hide running to the end
                  of the capture. A kit that restores on every frame write is
                  bounded at 1 by construction. A kit that hides once and
                  restores once spans every frame it drew.

Usage: capture-shape.py CAPTURE GLYPHS
"""

import re
import sys


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("usage: capture-shape.py CAPTURE GLYPHS\n")
        return 2
    data = open(sys.argv[1], "rb").read()
    glyphs = [g.encode("utf-8") for g in sys.argv[2]]

    def count(buf):
        return sum(buf.count(g) for g in glyphs)

    unmatched = 0
    max_span = 0
    for m in re.finditer(rb"\x1b\[\?25l", data):
        end = data.find(b"\x1b[?25h", m.end())
        if end == -1:
            unmatched = 1
            segment = data[m.end():]
        else:
            segment = data[m.end():end]
        max_span = max(max_span, count(segment))

    print("glyphs=%d unmatched_hide=%d max_span=%d" % (count(data), unmatched, max_span))
    return 0


if __name__ == "__main__":
    sys.exit(main())
