#!/usr/bin/env python3
"""Allocate the next task id atomically and stamp .agent-guild/templates/task.md into it.

Used by /decompose. Safe under parallel decomposition: the id is claimed with
open(..., 'x'), so two concurrent callers can never grab the same T-NNN—the
loser gets FileExistsError and retries the next number.

Usage:
    .agent-guild/scripts/new-task.py "Task title here"
Prints the path of the created task file on stdout.

Exit codes: 0 created; 3 usage/infra error (no title, template missing).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TASKS_DIR = os.path.join(ROOT, "state", "tasks")
TEMPLATE = os.path.join(ROOT, "templates", "task.md")

ID_RE = re.compile(r"^T-(\d+)\.md$")


def main():
    if len(sys.argv) < 2 or not sys.argv[1].strip():
        sys.stderr.write("usage: new-task.py <task title>\n")
        return 3
    title = sys.argv[1].strip()

    try:
        with open(TEMPLATE, encoding="utf-8") as f:
            body = f.read()
    except OSError as e:
        sys.stderr.write(f"cannot read template {TEMPLATE}: {e}\n")
        return 3

    os.makedirs(TASKS_DIR, exist_ok=True)

    # Highest existing id + 1 is the starting guess; collisions bump it.
    existing = [
        int(m.group(1))
        for name in os.listdir(TASKS_DIR)
        if (m := ID_RE.match(name))
    ]
    n = (max(existing) + 1) if existing else 1

    while True:
        tid = f"T-{n:03d}"
        path = os.path.join(TASKS_DIR, f"{tid}.md")
        stamped = body.replace("id: T-000", f"id: {tid}", 1)
        stamped = stamped.replace(
            "title: One-line task title", f"title: {title}", 1
        )
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        except FileExistsError:
            n += 1
            continue
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(stamped)
        print(path)
        return 0


if __name__ == "__main__":
    sys.exit(main())
