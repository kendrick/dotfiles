#!/usr/bin/env python3
"""Shared fixture helpers for the archived #117 corpus.

Two suites replay the same seven-task job from
`.agent-guild/state/archive/2026-08-10-issue-117/`: test_check_job_spec.py
runs the linter over it, and test_ready_set.py replays its dependency graph
through the wave computation. Both need the corpus to carry an `owns:` field
it predates, and deriving that twice is how a fixture starts lying—two
derivations drift, and the drift shows up as a test that agrees with itself
about the wrong thing.

Import-safe on purpose: constants and functions, no side effects. The suites
that use it are flat scripts ending in sys.exit(), so neither can import from
the other.
"""
import os
import re

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPTS_DIR))
ARCHIVE_117 = os.path.join(
    REPO_ROOT, ".agent-guild", "state", "archive", "2026-08-10-issue-117"
)

ARTIFACTS_LIST_ITEM_RE = re.compile(r"^\s*-\s+.*$")


def add_owns(state_dir):
    """Give every task in `state_dir/tasks/` an `owns:` frontmatter field
    cloned from its own `artifacts:`—the #117 corpus predates #133, so
    `owns` doesn't exist in it yet. Mirrors `artifacts:`'s own two shapes
    (flat `[a, b]` or a block `- path` sequence) rather than normalizing
    to one, so the cloned `owns:` reads exactly like the field it copied.
    Mutates the task files on disk.

    A clone, not a repair: most entries are exact file paths and T-003's
    three are directory prefixes already ending in `/`, but T-004 declares
    `~/repos/skills/...`, which `owns_entry_problem` refuses as a shell
    expansion. Normalizing that away here would hide it from the wave
    replay, where it is the difference between six waves and five."""
    tasks_dir = os.path.join(state_dir, "tasks")
    for name in sorted(os.listdir(tasks_dir)):
        path = os.path.join(tasks_dir, name)
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        out = []
        i = 0
        inserted = False
        while i < len(lines):
            line = lines[i]
            out.append(line)
            if not inserted and re.match(r"^artifacts:\s*(.*)$", line):
                block = [line]
                i += 1
                while i < len(lines) and ARTIFACTS_LIST_ITEM_RE.match(lines[i]):
                    block.append(lines[i])
                    out.append(lines[i])
                    i += 1
                owns_block = ["owns:" + block[0][len("artifacts:"):]] + block[1:]
                out.extend(owns_block)
                inserted = True
                continue
            i += 1
        assert inserted, f"{name}: no artifacts: field found to derive owns from"
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
