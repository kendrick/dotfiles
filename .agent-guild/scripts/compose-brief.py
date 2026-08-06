#!/usr/bin/env python3
"""Assemble a self-contained vendor brief for one task.

External couriers dispatch work to models that can't read this repo, this
session, or the state bus — no `.agent-guild/state/` paths, no CLAUDE.md, no
"as discussed." This script builds the one file such a vendor needs: the task
id and title, the full verbatim text of every constitution clause the task
cites (never clause ids alone — the far side has no constitution to look
them up in), the task's spec excerpt, and any prior rework diagnosis.

    .agent-guild/scripts/compose-brief.py T-NNN [--out PATH]

Inputs are read relative to the working directory's `.agent-guild/state/`:
`tasks/T-NNN.md` and `constitution.md`. Output defaults to
`.agent-guild/state/briefs/T-NNN.md` (directory created on demand); `--out`
writes to PATH instead. The written file is the artifact — stdout carries at
most a one-line confirmation, never the brief body.

Exit codes: 0 success; 1 the task can't be turned into a brief (missing task
file, a cited clause id absent from the constitution, or zero cited clauses).
No bare tracebacks as the interface — every failure prints one diagnostic
line to stderr naming the problem, mirroring check-provenance.py's
`provenance: <problem>` convention.

Stdlib only, so the kit stays copy-in portable. Deliberately standalone:
does not import from .agent-guild/hooks/, matching check-provenance.py.
"""
import argparse
import os
import re
import sys

FM_LINE_RE = re.compile(r"^([A-Za-z0-9_]+):\s*(.*)$")
HEADING_RE_TMPL = r"(?m)^{}\s*$"
NEXT_H2_RE = re.compile(r"(?m)^## ")
NEXT_H2_OR_H3_RE = re.compile(r"(?m)^#{2,3} ")
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)


def parse_frontmatter(text):
    """Split `text` into (frontmatter dict, body). Frontmatter is the flat
    `--- ... ---` block the kit's task files use (see new-task.py /
    check-provenance.py for the same shape). Returns (None, None) if there
    is no closed frontmatter block at all."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, None
    fm = {}
    body_start = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            body_start = i + 1
            break
        m = FM_LINE_RE.match(line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        fm[key] = val
    if body_start is None:
        return None, None
    return fm, "\n".join(lines[body_start:])


def parse_clause_list(raw):
    """`clauses: [C-1, C-4]` (or `[]`) -> ["C-1", "C-4"] (or [])."""
    raw = (raw or "").strip()
    if not (raw.startswith("[") and raw.endswith("]")):
        return []
    inner = raw[1:-1].strip()
    if not inner:
        return []
    return [c.strip() for c in inner.split(",") if c.strip()]


def extract_section(body, heading):
    """Return the verbatim slice of `body` starting at the `heading` line
    (inclusive) up to the next `## `-level heading or end of string. None if
    `heading` doesn't appear. Trailing blank lines before the next heading
    are trimmed; everything else is untouched."""
    m = re.search(HEADING_RE_TMPL.format(re.escape(heading)), body)
    if not m:
        return None
    rest = body[m.end():]
    next_m = NEXT_H2_RE.search(rest)
    end = m.end() + (next_m.start() if next_m else len(rest))
    return body[m.start():end].rstrip("\n")


def section_is_empty(section_body):
    """A Rework diagnosis section counts as empty if, once HTML template
    comments are stripped, nothing but whitespace remains."""
    return HTML_COMMENT_RE.sub("", section_body).strip() == ""


def extract_clause(constitution_text, clause_id):
    """Return the verbatim `### C-N: name` block (heading plus every bullet
    line) for `clause_id`, ending at the next `##`/`###` heading. None if the
    clause id doesn't appear. The trailing `:` in the pattern keeps C-1 from
    matching C-10, C-2, etc."""
    m = re.search(r"(?m)^### {}:.*$".format(re.escape(clause_id)), constitution_text)
    if not m:
        return None
    rest = constitution_text[m.end():]
    next_m = NEXT_H2_OR_H3_RE.search(rest)
    end = m.end() + (next_m.start() if next_m else len(rest))
    return constitution_text[m.start():end].rstrip("\n")


def compose(task_id, state_dir):
    """Build the brief text for `task_id`, reading from `state_dir`. Returns
    (brief_text, None) on success or (None, error_message) on failure — the
    caller decides exit code and stderr, this stays pure for testability."""
    task_path = os.path.join(state_dir, "tasks", f"{task_id}.md")
    try:
        with open(task_path, encoding="utf-8") as f:
            task_text = f.read()
    except OSError:
        return None, f"compose-brief: task file not found: {task_id}"

    fm, body = parse_frontmatter(task_text)
    if fm is None:
        return None, f"compose-brief: task file has no frontmatter: {task_id}"

    title = fm.get("title", "").strip()
    clause_ids = parse_clause_list(fm.get("clauses"))
    if not clause_ids:
        return None, f"compose-brief: task cites zero clauses: {task_id}"

    constitution_path = os.path.join(state_dir, "constitution.md")
    try:
        with open(constitution_path, encoding="utf-8") as f:
            constitution_text = f.read()
    except OSError:
        return None, "compose-brief: constitution.md not found"

    clause_blocks = []
    for cid in clause_ids:
        block = extract_clause(constitution_text, cid)
        if block is None:
            return None, f"compose-brief: clause not found in constitution: {cid}"
        clause_blocks.append(block)

    spec_excerpt = extract_section(body, "## Spec excerpt")
    if spec_excerpt is None:
        return None, f"compose-brief: task file has no ## Spec excerpt section: {task_id}"

    diagnosis_content = None
    diagnosis_section = extract_section(body, "## Rework diagnosis")
    if diagnosis_section is not None:
        # Strip the heading line itself; only the content beneath it moves
        # under the brief's own "## Prior attempt diagnosis" heading.
        content = diagnosis_section.split("\n", 1)
        content = content[1] if len(content) > 1 else ""
        if not section_is_empty(content):
            diagnosis_content = content.strip("\n")

    parts = [
        f"# Brief: {task_id}",
        "",
        f"**Task:** {task_id} — {title}",
        "",
        "## Constitution clauses",
        "",
        "\n\n".join(clause_blocks),
        "",
        spec_excerpt,
    ]
    if diagnosis_content is not None:
        parts += ["", "## Prior attempt diagnosis", "", diagnosis_content]

    return "\n".join(parts).rstrip("\n") + "\n", None


def main():
    ap = argparse.ArgumentParser(
        description="Assemble a self-contained vendor brief for one task."
    )
    ap.add_argument("task_id", help="task id, e.g. T-001")
    ap.add_argument("--out", default=None, help="output path (default: .agent-guild/state/briefs/T-NNN.md)")
    args = ap.parse_args()

    state_dir = os.path.join(os.getcwd(), ".agent-guild", "state")
    brief_text, err = compose(args.task_id, state_dir)
    if err is not None:
        sys.stderr.write(err + "\n")
        return 1

    out_path = args.out or os.path.join(state_dir, "briefs", f"{args.task_id}.md")
    out_dir = os.path.dirname(out_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(brief_text)

    print(f"OK: brief written ({out_path})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
