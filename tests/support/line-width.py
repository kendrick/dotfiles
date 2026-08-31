#!/usr/bin/env python3
"""Widest live line in a /dev/tty capture, in display columns.

Columns, not bytes. Every live line carries multibyte glyphs and CSI
sequences, so a raw byte count passes 40 long before the line has rendered
anything, and a check built on it fails a conforming kit.

A line that wraps is worse than a line that is merely long: the next carriage
return goes back to the wrong row and the animation starts eating the
scrollback above it.

Records are split on carriage returns, since every frame opens by returning to
column 0. CSI sequences count as zero. Braille and block glyphs count as the
one column each renders as, which is what Python's len() over decoded text
already gives.

Usage: line-width.py CAPTURE
"""

import re
import sys

CSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: line-width.py CAPTURE\n")
        return 2
    text = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
    widest = 0
    for record in re.split(r"[\r\n]", text):
        widest = max(widest, len(CSI.sub("", record)))
    print(widest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
