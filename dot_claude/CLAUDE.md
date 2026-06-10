# User-level preferences

These apply to every project I work on, regardless of the repo or stack.

## Prose

Run all prose through the `humanizer` skill before merge. "Prose" includes documentation, markdown content, code comments, commit messages, PR descriptions, and any other narrative text you produce on my behalf.

"Run through" means formally invoke the skill via the Skill tool and follow its audit-and-revise loop ("draft → what makes this so obviously AI generated? → revise"). Informally applying the principles from memory is not enough — it consistently misses tells. Invoke the skill, edit the prose in place against its audit, then ship.

Caveat on the humanizer's anti-list stance: I'm fine keeping bulleted and numbered lists. The rule I care about is the tripartite-list tic — try to avoid lists of exactly three items when a fourth fits naturally or one can be dropped without loss. When three is the genuinely correct count (three distinct things, no padding, no omission), keep it three. Don't pad or trim a list just to satisfy the heuristic.

Second caveat, on the same axis: don't dissolve genuinely list-shaped content into prose. If you have N items that share an identical structure — say, four files where every entry reads "filename, then a short description" — keep it as a bulleted list. Humanizer pattern 16 is right that bolded inline headers with colons (`- **Performance:** Speed matters`) are a tell. A plain bullet of the form `- code-thing — description` is not. Don't bury parallel items in a paragraph that scans worse than the list it's hiding.

Third caveat: ignore the humanizer's title-case rule (pattern #17). I prefer title-cased headings. Don't lowercase main words on the way through the audit; leave headings as I'd write them in a doc or blog post.

Never manually wrap lines in prose of any sort with hard returns. Let the terminal or git's own pager handle wrapping at display time. Hard-wrapped commit messages render badly in GitHub's UI and in IDEs that show full-width.

## Commit messages

Commit messages should focus on the WHY just as much as on the WHAT. They should be just long enough to cover what's essential and no longer. Write commit messages in the voice and tone of a helpful technical writer who is also in a hurry; commonly-recognized abbreviations and acronyms are acceptable.

## Code comments

Comment proactively, but only when the comment carries weight. Every comment should explain the WHY behind the code — the constraint that forced this shape, the past incident this guards against, the surprising invariant a reader might miss, the broader context the code lives inside.

Comments that explain WHAT the code does are worthless when the code is well-named. Comments that explain HOW the code works shouldn't be necessary if the code is written cleanly. The only comment worth writing is the one that explains something the code itself can't.

Write comments in the voice and tone of a helpful technical writer who is also in a hurry; commonly-recognized abbreviations and acronyms are acceptable.

@RTK.md
