#!/usr/bin/env python3
"""Verify author-protected passages ship verbatim—curly quotes and all.

For each passage in the manifest, requires that its exact text appears as a
substring of its `source` file AND that sha256(text) matches the declared hash.
On drift, prints a character-level diff that calls out the usual silent
corruptions: straight-for-curly quotes, hyphen-for-dash, space-for-nbsp.

    .agent-guild/scripts/check-protected.py <manifest> [--file PATH] [--rehash]

    --file PATH   only check passages whose `source` equals PATH
    --rehash      recompute each sha256 from the fenced text and rewrite the
                  manifest in place (use after editing protected text); does
                  not verify sources, exits 0 on success

Exit codes: 0 all pass; 1 a passage drifted (content failure); 3 manifest
malformed or unreadable / hash out of sync without --rehash (infra error).
"""
import argparse
import hashlib
import os
import re
import sys
import unicodedata

COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)
HEADER_RE = re.compile(r"^##\s+(PP-\S+)\s*$")
BULLET_RE = re.compile(r"^-\s*(source|sha256)\s*:\s*(.+?)\s*$")
FENCE_OPEN_RE = re.compile(r"^```")

# Confusable pairs worth naming explicitly—the ones that fool a skim.
CONFUSABLES = {
    "‘": "LEFT SINGLE QUOTE (curly ‘)",
    "’": "RIGHT SINGLE QUOTE (curly ’)",
    "“": "LEFT DOUBLE QUOTE (curly “)",
    "”": "RIGHT DOUBLE QUOTE (curly ”)",
    "'": "APOSTROPHE (straight ')",
    '"': "QUOTATION MARK (straight \")",
    "–": "EN DASH (–)",
    "—": "EM DASH (—)",
    "-": "HYPHEN-MINUS (-)",
    " ": "NO-BREAK SPACE",
    " ": "SPACE",
}


def cp(ch):
    name = CONFUSABLES.get(ch)
    if name is None:
        try:
            name = unicodedata.name(ch)
        except ValueError:
            name = "control/unnamed"
    return f"U+{ord(ch):04X} {name}"


def parse_manifest(path):
    """Return (passages, errors). Each passage: id, source, sha256, text, line."""
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
    except OSError as e:
        return None, [f"cannot read manifest {path}: {e}"]

    # Blank out comment blocks but keep line numbers stable for error messages.
    def blank(m):
        return "".join("\n" if c == "\n" else " " for c in m.group(0))

    text = COMMENT_RE.sub(blank, raw)
    lines = text.splitlines()

    passages, errors = [], []
    i = 0
    while i < len(lines):
        hm = HEADER_RE.match(lines[i])
        if not hm:
            i += 1
            continue
        pid, header_line = hm.group(1), i + 1
        source = sha = None
        i += 1
        # Collect bullets until the fence opens or the next header/EOF.
        while i < len(lines) and not FENCE_OPEN_RE.match(lines[i]):
            if HEADER_RE.match(lines[i]):
                break
            bm = BULLET_RE.match(lines[i])
            if bm:
                if bm.group(1) == "source":
                    source = bm.group(2)
                else:
                    sha = bm.group(2).lower()
            i += 1
        if i >= len(lines) or not FENCE_OPEN_RE.match(lines[i]):
            errors.append(f"{pid} (line {header_line}): no fenced text block")
            continue
        i += 1  # step past opening fence
        start = i
        while i < len(lines) and not FENCE_OPEN_RE.match(lines[i]):
            i += 1
        if i >= len(lines):
            errors.append(f"{pid} (line {header_line}): unclosed fenced block")
            continue
        passage_text = "\n".join(lines[start:i])
        i += 1  # step past closing fence
        if source is None:
            errors.append(f"{pid} (line {header_line}): missing `- source:`")
            continue
        if sha is None:
            errors.append(f"{pid} (line {header_line}): missing `- sha256:`")
            continue
        passages.append(
            {"id": pid, "source": source, "sha256": sha,
             "text": passage_text, "line": header_line}
        )
    return passages, errors


def char_diff(expected, actual):
    """Human-readable char-level diff, naming confusable codepoints."""
    import difflib
    sm = difflib.SequenceMatcher(None, expected, actual, autojunk=False)
    out = []
    for tag, e0, e1, a0, a1 in sm.get_opcodes():
        if tag == "equal":
            continue
        exp, act = expected[e0:e1], actual[a0:a1]
        if tag == "replace":
            out.append(f"    changed: {exp!r} → {act!r}")
        elif tag == "delete":
            out.append(f"    removed: {exp!r}")
        elif tag == "insert":
            out.append(f"    added:   {act!r}")
        for ch in exp:
            if ch in CONFUSABLES or not ch.isascii():
                out.append(f"      expected {cp(ch)}")
        for ch in act:
            if ch in CONFUSABLES or not ch.isascii():
                out.append(f"      found    {cp(ch)}")
    return out


def closest_region(passage, source):
    """Best-effort: locate the drifted copy in source for a readable diff."""
    import difflib
    p_lines = passage.splitlines() or [passage]
    s_lines = source.splitlines()
    # Anchor on the passage's first line to find where the copy lives.
    anchors = difflib.get_close_matches(p_lines[0], s_lines, n=1, cutoff=0.4)
    if not anchors:
        return None
    idx = s_lines.index(anchors[0])
    window = "\n".join(s_lines[idx: idx + len(p_lines)])
    return window


def rehash(path, passages):
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read()
    except OSError as e:
        sys.stderr.write(f"cannot read manifest {path}: {e}\n")
        return 3
    for p in passages:
        want = hashlib.sha256(p["text"].encode()).hexdigest()
        raw = re.sub(
            rf"(- sha256:\s*){re.escape(p['sha256'])}",
            rf"\g<1>{want}",
            raw,
            count=1,
        ) if p["sha256"] != want else raw
        # Fallback for placeholder zeros or already-differing hashes: match by
        # the passage's source line proximity is overkill; the escape above
        # handles the common path. Replace any 64-zero placeholder too.
    # Simpler, robust rewrite: recompute every sha bullet in document order.
    lines = raw.splitlines(keepends=True)
    order = iter(passages)
    cur = next(order, None)
    for n, line in enumerate(lines):
        if cur and re.match(r"^-\s*sha256\s*:", line):
            want = hashlib.sha256(cur["text"].encode()).hexdigest()
            lines[n] = re.sub(r"(:\s*).*", rf"\g<1>{want}", line, count=1)
            cur = next(order, None)
    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(lines))
    print(f"rehashed {len(passages)} passage(s) in {path}")
    return 0


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("manifest")
    ap.add_argument("--file")
    ap.add_argument("--rehash", action="store_true")
    args = ap.parse_args()

    passages, errors = parse_manifest(args.manifest)
    if passages is None:
        sys.stderr.write(errors[0] + "\n")
        return 3
    if errors:
        sys.stderr.write("MANIFEST MALFORMED:\n")
        for e in errors:
            sys.stderr.write(f"  - {e}\n")
        return 3
    if not passages:
        sys.stderr.write(f"no passages found in {args.manifest}\n")
        return 3

    if args.rehash:
        return rehash(args.manifest, passages)

    selected = [p for p in passages
                if args.file is None or p["source"] == args.file]
    if args.file and not selected:
        print(f"no protected passages reference {args.file}—nothing to check")
        return 0

    manifest_dir = os.path.dirname(os.path.abspath(args.manifest))
    failures, infra = [], []
    for p in selected:
        want = hashlib.sha256(p["text"].encode()).hexdigest()
        if p["sha256"] != want:
            infra.append(
                f"{p['id']}: sha256 in manifest ({p['sha256'][:12]}…) does not "
                f"match its own fenced text ({want[:12]}…). Edit without "
                f"rehashing? Run: check-protected.py {args.manifest} --rehash"
            )
            continue
        # Resolve source relative to the manifest, then to cwd.
        src_path = p["source"]
        if not os.path.isabs(src_path):
            cand = os.path.join(manifest_dir, src_path)
            src_path = cand if os.path.exists(cand) else p["source"]
        try:
            with open(src_path, encoding="utf-8") as f:
                source = f.read()
        except OSError as e:
            infra.append(f"{p['id']}: cannot read source {p['source']}: {e}")
            continue
        if p["text"] in source:
            continue
        # Drifted—build the most useful diff we can.
        region = closest_region(p["text"], source)
        lines = [f"{p['id']} DRIFTED in {p['source']}:"]
        if region is not None:
            lines += char_diff(p["text"], region)
        else:
            lines.append("    exact text not found; no close region located")
            lines.append(f"    expected: {p['text']!r}")
        failures.append("\n".join(lines))

    if infra:
        sys.stderr.write("PROTECTED-PASSAGE CHECK ERROR:\n")
        for m in infra:
            sys.stderr.write(f"  - {m}\n")
        return 3
    if failures:
        sys.stderr.write("PROTECTED PASSAGES ALTERED:\n")
        for m in failures:
            sys.stderr.write(m + "\n")
        return 1
    print(f"OK: {len(selected)} protected passage(s) verbatim")
    return 0


if __name__ == "__main__":
    sys.exit(main())
