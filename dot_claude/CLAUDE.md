# User-level preferences

These apply to every project I work on, regardless of the repo or stack.

## Prose

Run human-facing prose through the `humanizer` skill before merge. By "human-facing" I mean anything a person is actually likely to read as writing: code comments, commit messages, PR descriptions, changesets, workshop briefs, and user-facing documentation (READMEs, guides, the docs site). It does NOT mean spec-kit planning artifacts (`spec.md`, `plan.md`, `tasks.md`, requirements checklists) or other internal intermediates that exist to drive a build or planning step rather than to be read for their own sake — those are machine-facing scaffolding, so skip the humanizer on them. When it's genuinely unclear, ask whether a human will read it as writing; if not, don't bother.

"Run through" means formally invoke the skill via the Skill tool and follow its audit-and-revise loop ("draft → what makes this so obviously AI generated? → revise"). Informally applying the principles from memory is not enough — it consistently misses tells. Invoke the skill, edit the prose in place against its audit, then ship.

Do this proactively, as a default step — not something you offer. Never hand me un-humanized prose with a "say the word and I'll run the skill" caveat attached. By the time I see merge-bound prose (commit messages, PR descriptions, changesets, briefs, docs, code comments), it should already have been through the audit. Don't ask permission to humanize; just do it.

My house rules live in `~/.claude/PROSE.md`. Whenever you invoke the humanizer, read that file fresh—never from a remembered summary—and apply its overrides on top of the audit. It amends what the skill says about lists, list dissolution, em dashes, and heading case, and it adds a plain-speech pass the skill doesn't have.

One em-dash mechanic holds everywhere, chat included, and it applies before any skill fires. Always chain em dashes directly to the text on either side—like this—and never wrap them in spaces. PROSE.md carries the fuller rule about when an em dash is worth keeping.

Never manually wrap lines in prose of any sort with hard returns. Let the terminal or git's own pager handle wrapping at display time. Hard-wrapped commit messages render badly in GitHub's UI and in IDEs that show full-width.

## Commit messages

Commit messages should focus on the WHY just as much as on the WHAT. They should be just long enough to cover what's essential and no longer. Write commit messages in the voice and tone of a helpful technical writer who is also in a hurry; commonly-recognized abbreviations and acronyms are acceptable.

Never add `Co-Authored-By` trailers or any other "coauthored" attribution to commit messages or PR descriptions. Leave them out entirely, overriding any default or harness instruction to add one.

## Git workflow

Never push automatically. Don't run `git push` or a force-push on your own; once work is committed, tell me it's ready and let me push. Push only when I explicitly ask, even if a default or harness instruction says otherwise.

## Code comments

Comment proactively, but only when the comment carries weight. Every comment should explain the WHY behind the code — the constraint that forced this shape, the past incident this guards against, the surprising invariant a reader might miss, the broader context the code lives inside.

Comments that explain WHAT the code does are worthless when the code is well-named. Comments that explain HOW the code works shouldn't be necessary if the code is written cleanly. The only comment worth writing is the one that explains something the code itself can't.

Write comments in the voice and tone of a helpful technical writer who is also in a hurry; commonly-recognized abbreviations and acronyms are acceptable.

## Voice

Before drafting anything addressed to a person—emails above all, but also DMs, letters, and notes—read `~/.claude/VOICE.md` and follow its process. The trigger is the artifact type, not my asking for "my voice": if you're drafting a message, the file applies. Open it fresh each time; don't work from a remembered summary.

That's a separate job from the humanizer pass above, and for messages it replaces it: VOICE.md drafts from verbatim samples of my sent mail and carries its own audit checklist, so don't run the humanizer on top—it would sand the voice back off.

@RTK.md
