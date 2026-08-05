# Read a JSONC file that jq would otherwise reject. Invoke as:
#
#   jq -Rs -f ~/.config/font/jsonc.jq settings.json
#
# -Rs slurps the file as one raw string so the filter can scan it as text; jq
# has no relaxed parsing mode and no plugin hook that could add one.
#
# Only trailing commas are tolerated, and only because Prettier owns them: it
# runs on save and puts them back faster than anyone can delete them, so a
# switcher that refused them would refuse on every invocation. Comments are the
# other case. Those someone wrote on purpose, so they still fail the parse below
# and the caller is expected to stop rather than rewrite the file without them.
#
# The alternation is what makes this safe. Its first branch consumes an entire
# string literal before the comma branch is ever tried, so a comma living inside
# a value can't be mistaken for a structural one. That is not hypothetical here:
# editor.fontFamily is a comma-separated fallback chain, and it's the exact value
# the switcher rewrites.
gsub("(?<s>\"(\\\\.|[^\"\\\\])*\")|(?<c>,\\s*(?=[}\\]]))"; .s // "")

# Parse here rather than in the caller, so one invocation either yields the
# object or fails loudly, with no half-normalized text in between.
| fromjson
