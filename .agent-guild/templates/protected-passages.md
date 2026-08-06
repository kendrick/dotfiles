# Protected passages manifest

<!--
The author's exact words that must ship VERBATIM—taglines, quotes, legal
copy, brand lines. check-protected.py reads this file and, for each passage,
requires that the exact text appears as a substring of `source` AND that its
sha256 matches. Curly quotes, em dashes, and non-breaking spaces are all
significant—a straight-quote-for-curly swap is a FAIL.

PARSE FORMAT (strict—check-protected.py depends on it):
  - Each passage is a level-2 heading `## PP-N` (the id).
  - Two bullet lines follow, in any order: `- source: <path>` and
    `- sha256: <64 hex chars>`.
  - Then one fenced block ```text … ``` holding the exact passage.
  - The passage text = the lines between the fences joined with "\n", with NO
    trailing newline. That exact UTF-8 string is what gets hashed and searched.

Recompute a hash after editing a passage (paste the text on stdin, end with
Ctrl-D):
  python3 -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.read().rstrip("\n").encode()).hexdigest())'
Or let the checker regenerate the manifest from live source with:
  .agent-guild/scripts/check-protected.py <manifest> --rehash
-->

## PP-1
- source: path/to/page.html
- sha256: 0000000000000000000000000000000000000000000000000000000000000000

```text
You didn't know you needed this.
```
