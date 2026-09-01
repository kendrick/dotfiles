#!/usr/bin/env python3
"""Build a throwaway TrueType-flavoured sfnt with dialled-in ligature evidence.

`font --add` (issue #15) refuses a font with no ligature evidence, and that
refusal has to be provable without betting on which fonts happen to be
installed on whatever machine runs the suite. This CLI is the alternative:
every signal font-inspect reads — GSUB feature tags, LigatureSubst rule
count, post/CFF glyph names, cmap coverage, stylistic-set names, fvar axes —
is a flag here, so a test can plant exactly the evidence (or lack of it) its
assertion needs and nothing else. The repo also forbids committing font
binaries (tests/font.bats:522 greps `git ls-files` for .ttf/.otf/.zip), so
generating one at setup time is the only option anyway.

TrueType only: no CFF, no TTC. font-inspect's CFF and post-v3 paths already
get real coverage from actual fonts on this machine, which is better evidence
for those paths than anything synthesised here.

Checksums in the table directory and in `head` are bogus. font-inspect never
verifies them (its own comment says so, next to the same fixture-friendly
choice), and a real checksum buys nothing for a file whose only reader treats
it as bytes to parse, not bytes to trust. Do not "fix" this later.

Every offset in every table is computed from the bytes actually written, and
the self-check that exercises this script parses each table back out of the
finished file rather than trusting the numbers that built it — the failure
mode worth guarding against is a byte-math slip that only a real reader
would catch.

Runs on /usr/bin/python3 (3.9): no `match`, no `X | Y` unions, no walrus in a
comprehension. That is the same interpreter font-inspect itself targets, so a
fixture built here is never exercising a language feature the consumer would
choke on.
"""

import argparse
import struct
import sys

# --- packing helpers ---------------------------------------------------

def u8(n):
    return struct.pack(">B", n)


def u16(n):
    return struct.pack(">H", n)


def i16(n):
    return struct.pack(">h", n)


def u32(n):
    return struct.pack(">I", n)


def fixed(value):
    """A 16.16 fixed-point number, per the OpenType `Fixed` type."""
    return struct.pack(">i", int(round(value * 65536)))


def tag(text):
    raw = text.encode("ascii")
    if len(raw) > 4:
        raise ValueError("tag %r longer than 4 bytes" % text)
    return raw + b" " * (4 - len(raw))


def pad4(data):
    """Zero-pad to a 4-byte boundary, per sfnt's table alignment rule."""
    remainder = len(data) % 4
    if remainder:
        data += b"\x00" * (4 - remainder)
    return data


# --- name table ----------------------------------------------------------

# Real fonts almost all use this platform/encoding/language triple for their
# Windows-readable strings, and it is the one font-inspect's read_names()
# ranks highest (rank 0), so every record here uses it rather than also
# modelling the Macintosh platform nobody is testing against.
NAME_PLATFORM, NAME_ENCODING, NAME_LANGUAGE = 3, 1, 0x0409


class NameTable(object):
    """Collects (nameID, string) records and allocates ids >= 256 on request.

    Stylistic-set and axis names share this one pool and this one counter, per
    the spec's own text: "Stylistic-set and axis names get IDs from 256 up."
    Nothing downstream cares which of the two claimed a given id first.
    """

    def __init__(self):
        self.records = []
        self._next_custom_id = 256

    def add(self, name_id, text):
        self.records.append((name_id, text))

    def add_custom(self, text):
        name_id = self._next_custom_id
        self._next_custom_id += 1
        self.add(name_id, text)
        return name_id

    def build(self):
        header = u16(0) + u16(len(self.records))  # format 0, count
        # storageOffset is filled in once the header + records length is known.
        record_bytes = b""
        storage = b""
        for name_id, text in self.records:
            encoded = text.encode("utf-16-be")
            record_bytes += (
                u16(NAME_PLATFORM) + u16(NAME_ENCODING) + u16(NAME_LANGUAGE)
                + u16(name_id) + u16(len(encoded)) + u16(len(storage))
            )
            storage += encoded
        storage_offset = len(header) + 2 + len(record_bytes)
        return header + u16(storage_offset) + record_bytes + storage


# --- head / maxp ----------------------------------------------------------

UNITS_PER_EM = 1000


def build_head():
    # checkSumAdjustment is 0, not a real checksum — see the module docstring.
    # created/modified are 0 (1904 epoch, LONGDATETIME); nothing reads them.
    return (
        fixed(1.0)                 # version
        + fixed(1.0)               # fontRevision
        + u32(0)                   # checkSumAdjustment (bogus, deliberately)
        + u32(0x5F0F3CF5)          # magicNumber
        + u16(0)                   # flags
        + u16(UNITS_PER_EM)
        + struct.pack(">q", 0)     # created
        + struct.pack(">q", 0)     # modified
        + i16(0) + i16(0) + i16(UNITS_PER_EM) + i16(UNITS_PER_EM)  # bbox
        + u16(0)                   # macStyle
        + u16(UNITS_PER_EM // 64)  # lowestRecPPEM, an arbitrary plausible value
        + i16(2)                   # fontDirectionHint (deprecated, 2 = mixed)
        + i16(0)                   # indexToLocFormat: moot, there is no loca
        + i16(0)                   # glyphDataFormat
    )


def build_maxp(num_glyphs):
    # Version 1.0: required for a TrueType-flavoured sfnt. There is no glyf
    # table backing any of this, so every field past numGlyphs is a zero that
    # nothing will ever read against real outlines.
    return fixed(1.0) + u16(num_glyphs) + u16(0) * 13


# --- post ------------------------------------------------------------------

# The fields shared by every post version, after `version` and before
# `numGlyphs` (v2 only): italicAngle, underlinePosition, underlineThickness,
# isFixedPitch, minMemType42, maxMemType42, minMemType1, maxMemType1.
# font-inspect never reads any of these, so they are all zero.
POST_HEADER_TAIL = fixed(0) + i16(0) + i16(0) + u32(0) * 5


def build_post(version, glyph_names):
    """v2.0 carries the standard-Mac-glyph-order indirection; v3.0 carries no
    names at all — both are real, legal post tables, not a v2 with pieces cut
    out. glyph_names excludes .notdef; glyph 0 always gets standard index 0.
    """
    if version == 3:
        return fixed(3.0) + POST_HEADER_TAIL
    num_glyphs = 1 + len(glyph_names)
    # Every requested name is written to the custom pool rather than reused
    # from the 258-entry standard Macintosh set, even where a name (like "a")
    # happens to already be one of those. Simpler, and equally legal per spec:
    # a v2 post table is never required to prefer the standard indices.
    indices = [0] + [258 + i for i in range(len(glyph_names))]
    pool = b"".join(u8(len(n.encode("latin-1"))) + n.encode("latin-1") for n in glyph_names)
    return (
        fixed(2.0) + POST_HEADER_TAIL
        + u16(num_glyphs)
        + b"".join(u16(i) for i in indices)
        + pool
    )


# --- cmap --------------------------------------------------------------

def build_cmap(codepoints):
    """Format 12 under platform 3 / encoding 10, one group per codepoint.

    Three of the Nerd Font probe codepoints sit above the BMP, which format 4
    cannot express at all — the whole reason this fixture forces format 12
    rather than the more common format 4, so the consumer's format-12 path
    gets exercised even when a test plants zero codepoints.
    """
    codepoints = sorted(set(codepoints))
    groups = b""
    for cp in codepoints:
        # startGlyphID is an arbitrary in-bounds id; nothing here has to
        # resolve to a real outline (there is no glyf table in this fixture).
        groups += u32(cp) + u32(cp) + u32(1)
    subtable = (
        u16(12) + u16(0)           # format, reserved
        + u32(16 + 12 * len(codepoints))  # length
        + u32(0)                   # language
        + u32(len(codepoints))     # numGroups
        + groups
    )
    header = u16(0) + u16(1)       # version, numTables
    # One EncodingRecord, offset 4-byte aligned to right after the record.
    record = u16(3) + u16(10) + u32(4 + 8)
    return header + record + subtable


# --- GSUB -------------------------------------------------------------

# font-inspect's count_ligature_rules() walks every lookup in the LookupList
# directly; it never dereferences a Feature's LookupListIndex to get there
# (see its own docstring: "Reachability analysis buys nothing here"). So the
# ScriptList and the Feature->lookup wiring below are real, spec-shaped
# structures for a stricter reader, but not what actually turns the dial on
# the consumer's ligature signal — the LookupList contents do that alone.

def build_ligature_subst(rule_count, glyph_id):
    """A format-1 LigatureSubst with one coverage glyph and `rule_count` rules.

    All `rule_count` Ligature records live under that single glyph's
    LigatureSet — real Ligature structures, not just a bare count, so a
    stricter parser than font-inspect (which only ever sums the LigatureSet's
    own count field) still finds glyph ids that resolve inside this file's
    declared numGlyphs.
    """
    ligatures = b"".join(
        u16(glyph_id) + u16(2) + u16(glyph_id)  # ligGlyph, compCount=2, [comp]
        for _ in range(rule_count)
    )
    lig_set_header = u16(rule_count)
    lig_offsets = b""
    offset = len(lig_set_header) + 2 * rule_count
    for _ in range(rule_count):
        lig_offsets += u16(offset)
        offset += 6  # each Ligature record above is fixed-size: 3 x uint16
    ligature_set = lig_set_header + lig_offsets + ligatures

    coverage = u16(1) + u16(1) + u16(glyph_id)  # format 1, glyphCount 1, glyph
    # Layout: substFormat, coverageOffset, ligSetCount, ligSetOffsets[1], then
    # Coverage, then the LigatureSet — matching count_ligature_subst()'s own
    # reads at +0/+4/+6 exactly.
    header = u16(1) + u16(0) + u16(1) + u16(0)
    coverage_offset = len(header)
    lig_set_offset = coverage_offset + len(coverage)
    header = u16(1) + u16(coverage_offset) + u16(1) + u16(lig_set_offset)
    return header + coverage + ligature_set


def build_lookup(lookup_type, subtable, extension_wrap):
    """One Lookup record: type 4 directly, or type 7 wrapping it.

    Extension Substitution exists in the spec so a subtable can sit past the
    16-bit offset limit; Nerd Font patching routinely produces GSUB tables
    that large, and count_ligature_rules() has a whole branch for
    dereferencing through it, so --extension-lookup exists to exercise that
    branch without needing a 64k+ table to force it.
    """
    if extension_wrap:
        # ExtensionSubstFormat1: format(=1), extensionLookupType, offset(32-bit)
        # to the real subtable, counted from the Extension record itself.
        ext = u16(1) + u16(lookup_type) + u32(8) + subtable
        lookup_type, subtable = 7, ext
    return (
        u16(lookup_type) + u16(0)  # lookupType, lookupFlag (0: no options set)
        + u16(1) + u16(8)          # subTableCount=1, offset to the one subtable
        + subtable
    )


def build_gsub(gsub_tags, ss_entries, liga_rules, extension_lookup, glyph_id, name_table):
    """ss_entries: list of (tag, display_name) pairs, display_name may be ''."""
    tags = list(gsub_tags)
    all_feature_tags = tags + [t for t, _ in ss_entries]

    lookup = build_lookup(4, build_ligature_subst(liga_rules, glyph_id), extension_lookup)
    lookup_list = u16(1) + u16(4) + lookup  # lookupCount=1, offset to it

    # FeatureList: ordinary tags point at lookup 0; stylistic sets carry a
    # FeatureParams offset instead and no lookups of their own (nothing here
    # ever needs to walk from an ssXX feature to a substitution to prove
    # anything — see the module-level note on why Feature->lookup is inert).
    feature_records = b""
    feature_tables = b""
    feature_list_header_len = 2 + 6 * len(all_feature_tags)
    cursor = feature_list_header_len
    ss_names = dict(ss_entries)
    for feature_tag in all_feature_tags:
        if feature_tag in ss_names:
            name_id = name_table.add_custom(ss_names[feature_tag])
            params = u16(0) + u16(name_id)  # StylisticSet FeatureParams
            # featureParamsOffset=4: the params record sits right after this
            # table's own fixed 4-byte header (offset, lookupIndexCount).
            feature_table = u16(4) + u16(0) + params
        else:
            feature_table = u16(0) + u16(1) + u16(0)  # no params, 1 lookup: #0
        feature_records += tag(feature_tag) + u16(cursor)
        feature_tables += feature_table
        cursor += len(feature_table)
    feature_list = u16(len(all_feature_tags)) + feature_records + feature_tables

    # ScriptList: one DFLT script, one default LangSys naming every feature by
    # index. Never read by font-inspect (see module note); built anyway
    # because a real font always carries one and a stricter reader would want
    # to find something coherent here.
    feature_indices = b"".join(u16(i) for i in range(len(all_feature_tags)))
    lang_sys = u16(0) + u16(0xFFFF) + u16(len(all_feature_tags)) + feature_indices
    script_table = u16(4) + u16(0)  # defaultLangSysOffset, langSysCount=0
    script_list = u16(1) + tag("DFLT") + u16(4 + 4) + script_table + lang_sys
    # (defaultLangSysOffset above is relative to the Script table's own start,
    # i.e. right after the 1 ScriptRecord + count; script_table sits right
    # after script_list's own header+record.)

    header = u16(1) + u16(0)  # majorVersion, minorVersion (GSUB 1.0)
    script_list_offset = len(header) + 6
    feature_list_offset = script_list_offset + len(script_list)
    lookup_list_offset = feature_list_offset + len(feature_list)
    return (
        header + u16(script_list_offset) + u16(feature_list_offset) + u16(lookup_list_offset)
        + script_list + feature_list + lookup_list
    )


# --- fvar -----------------------------------------------------------------

FVAR_AXIS_SIZE = 20  # fixed by spec: tag, min, default, max, flags, nameID


def build_fvar(axes, name_table):
    """axes: list of (tag, min, default, max). One axisNameID per axis, >= 256."""
    records = b""
    for axis_tag, lo, default, hi in axes:
        name_id = name_table.add_custom(axis_tag)
        records += (
            tag(axis_tag) + fixed(lo) + fixed(default) + fixed(hi)
            + u16(0)  # flags
            + u16(name_id)
        )
    header_len = 16
    return (
        u16(1) + u16(0)             # majorVersion, minorVersion
        + u16(header_len)           # axesArrayOffset
        + u16(2)                   # reserved (must be 2, per spec)
        + u16(len(axes))            # axisCount
        + u16(FVAR_AXIS_SIZE)       # axisSize
        + u16(0)                   # instanceCount: no named instances here
        + u16(4 + 4 * len(axes))   # instanceSize, per the spec formula
        + records
    )


# --- sfnt assembly ---------------------------------------------------------

def build_sfnt(tables):
    """tables: {tag: bytes}. Assembles a table directory in tag-sorted order,
    per the spec's own requirement, with real offsets/lengths and 4-byte
    padding between table bodies (the padding bytes fall outside every
    table's own recorded length, so a reader that trusts the length field
    never sees them).
    """
    tags = sorted(tables)
    num_tables = len(tags)
    # searchRange/entrySelector/rangeShift: the largest power of 2 <=
    # numTables, and what falls out of it. No reader here uses them for
    # anything but their presence is part of what "a real table directory"
    # means, and this is the formula the spec itself gives.
    entry_selector = 0
    while (1 << (entry_selector + 1)) <= num_tables:
        entry_selector += 1
    search_range = (1 << entry_selector) * 16
    range_shift = num_tables * 16 - search_range

    directory_header = (
        u32(0x00010000) + u16(num_tables)
        + u16(search_range) + u16(entry_selector) + u16(range_shift)
    )
    directory_size = len(directory_header) + 16 * num_tables

    body = b""
    records = b""
    cursor = directory_size
    for t in tags:
        data = tables[t]
        records += tag(t) + u32(0) + u32(cursor) + u32(len(data))  # bogus checksum
        body += pad4(data)
        cursor += len(pad4(data))

    return directory_header + records + body


def parse_gsub_tags(text):
    return [t for t in text.split(",") if t] if text else []


def parse_glyph_names(text):
    names = [n for n in text.split(",") if n] if text else []
    return names or ["a", "b"]


def parse_cmap_extra(text):
    return [int(cp, 16) for cp in text.split(",") if cp] if text else []


def parse_ss(entries):
    """--ss ss01:Name, repeated. An empty Name is a deliberate empty string,
    not "no name" — see the module docstring on what that distinguishes."""
    parsed = []
    for entry in entries or []:
        gsub_tag, _, name = entry.partition(":")
        parsed.append((gsub_tag, name))
    return parsed


def parse_fvar(entries):
    axes = []
    for entry in entries or []:
        axis_tag, lo, default, hi = entry.split(":")
        axes.append((axis_tag, float(lo), float(default), float(hi)))
    return axes


ICON_PROBES = (
    0xE0A0, 0xE0B0, 0xE0B2, 0xE0B4, 0xE0C0, 0xE5FA, 0xE62B, 0xE700,
    0xE718, 0xE7C5, 0xF000, 0xF09B, 0xF121, 0xE200, 0xF408, 0xF49B,
    0xE300, 0xEA60, 0xF0001, 0xF05C6, 0xF1AF0, 0xF008, 0xE60A, 0xEB01,
)


def build_font(args):
    name_table = NameTable()
    name_table.add(1, args.family)
    name_table.add(16, args.family)

    glyph_names = parse_glyph_names(args.glyph_names)
    # Glyph 0 is always .notdef; every requested name is a real glyph after
    # it. A single non-notdef glyph id (1) is always valid to reference from
    # GSUB/cmap below, since glyph_names is never empty (parse_glyph_names
    # falls back to a default pair rather than allowing zero glyphs).
    num_glyphs = 1 + len(glyph_names)
    liga_glyph_id = 1

    codepoints = list(parse_cmap_extra(args.cmap_extra))
    if args.nerd == "full":
        codepoints += ICON_PROBES

    gsub_tags = parse_gsub_tags(args.gsub_tags)
    ss_entries = parse_ss(args.ss)
    build_gsub_table = bool(gsub_tags) or args.liga_rules > 0 or bool(ss_entries) or args.extension_lookup

    tables = {
        "head": build_head(),
        "maxp": build_maxp(num_glyphs),
        "post": build_post(args.post_version, glyph_names),
        "cmap": build_cmap(codepoints),
    }
    if build_gsub_table:
        tables["GSUB"] = build_gsub(
            gsub_tags, ss_entries, args.liga_rules, args.extension_lookup,
            liga_glyph_id, name_table,
        )
    fvar_axes = parse_fvar(args.fvar)
    if fvar_axes:
        tables["fvar"] = build_fvar(fvar_axes, name_table)

    # name must be built last: GSUB's ss names and fvar's axis names both
    # allocate ids >= 256 out of the same table while they're built above.
    tables["name"] = name_table.build()
    return build_sfnt(tables)


def main():
    parser = argparse.ArgumentParser(
        description="Build a throwaway TrueType sfnt with dialled-in ligature evidence, "
                     "for font.bats to exercise font-inspect against without committing a "
                     "real font binary.",
    )
    parser.add_argument("out", help="path to write the .ttf to")
    parser.add_argument("--family", required=True, help="name ID 1 and 16")
    parser.add_argument("--gsub-tags", default="",
                        help="comma-separated feature tags in the GSUB FeatureList")
    parser.add_argument("--liga-rules", type=int, default=0,
                        help="total type-4 LigatureSubst rules")
    parser.add_argument("--glyph-names", default="",
                        help="comma-separated post v2.0 glyph names (default: a couple of plain names)")
    parser.add_argument("--nerd", choices=("full", "none"), default="none",
                        help="full plants all 24 Nerd Font probe codepoints; none plants nothing")
    parser.add_argument("--cmap-extra", default="",
                        help="comma-separated hex codepoints to add to cmap, e.g. E0A0,F0001")
    parser.add_argument("--post-version", type=int, choices=(2, 3), default=2)
    parser.add_argument("--fvar", action="append", metavar="TAG:MIN:DEFAULT:MAX",
                        help="a variable axis; repeatable. Omit entirely for a static font")
    parser.add_argument("--ss", action="append", metavar="TAG:NAME",
                        help="a stylistic-set feature and its UI name (may be empty); repeatable")
    parser.add_argument("--extension-lookup", action="store_true",
                        help="wrap the ligature lookup in a type-7 Extension Substitution lookup")
    args = parser.parse_args()

    data = build_font(args)
    with open(args.out, "wb") as handle:
        handle.write(data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
