#!/usr/bin/env python3
"""Report frame glyphs landing where a brew bundle interval forbids them.

The property is interval-scoped, not whole-run silence, and the difference
decides real cases. Read as whole-run silence the rule rejects a script that
animates around the tap-trust loop; read as interval silence it permits that
and still catches the frame that matters. The interval is the reading.

A BUNDLE-INSTALL marker splits interval 1 again, because the installer draws
during brew's silent fetch on purpose and then stops for good at brew's first
install-phase line. Glyphs before the marker are fetch_frames, expected and not
counted against anything. Glyphs at or after it are violations, because that is
the window in which a cask's sudo prompt owns the stream. Interval 1 with no
marker at all is the fetch-phase failure: the gate never opened, so the spinner
ran exactly as long as the phase it was drawing for, and every glyph in it is a
fetch_frame.

Interval 2 and beyond are retries, and they get no such split.
`handle_bundle_result` fires its retry through a plain pipeline with nothing
animating around it, so every glyph inside one is a violation whether or not an
INSTALL marker turns up.

The stub standing in for `brew bundle` brackets itself by writing BUNDLE-ENTER
and BUNDLE-EXIT markers to /dev/tty, so entry and exit are anchored by the
thing being measured rather than guessed from timing. BUNDLE-INSTALL marks the
moment its gate line lands, anchoring the fetch/install split the same way.

Usage: bundle-intervals.py CAPTURE GLYPHS
Prints: intervals=N violations=M fetch_frames=K
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
    fetch_frames = 0
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

        if n == b"1":
            install_m = re.search(rb"BUNDLE-INSTALL-1", segment)
            if install_m is None:
                # The fetch-phase-failure case: the gate never opened, so the
                # spinner correctly ran for the whole interval.
                fetch_frames += sum(segment.count(g) for g in glyphs)
            else:
                fetch = segment[:install_m.start()]
                install = segment[install_m.start():]
                fetch_frames += sum(fetch.count(g) for g in glyphs)
                violations += sum(install.count(g) for g in glyphs)
        else:
            # A retry gets no fetch carve-out: it never animates at all.
            violations += sum(segment.count(g) for g in glyphs)

    print("intervals=%d violations=%d fetch_frames=%d" % (intervals, violations, fetch_frames))
    return 0


if __name__ == "__main__":
    sys.exit(main())
