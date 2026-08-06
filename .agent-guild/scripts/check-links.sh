#!/usr/bin/env bash
# Refetch every http(s) URL cited in the given files and fail on any that
# don't resolve to a 2xx/3xx. Catches link rot and hallucinated citations —
# a worker can claim a source exists; this proves it.
#
#   .agent-guild/scripts/check-links.sh <file> [file...]
#
# Exit codes: 0 all reachable; 1 one or more dead links; 3 usage/infra error.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: check-links.sh <file> [file...]" >&2
  exit 3
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "check-links.sh: curl not found on PATH" >&2
  exit 3
fi

UA="Mozilla/5.0 (compatible; agent-guild-linkcheck/1.0)"
URL_RE='https?://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+'

# Collect unique URLs across all inputs. Trailing punctuation from prose
# (periods, commas, closing brackets/quotes) is stripped so we fetch the URL,
# not the sentence it sat in.
urls=$(grep -oE "$URL_RE" "$@" 2>/dev/null \
  | sed -E 's/[.,;:)"'"'"'>]+$//' \
  | sort -u || true)

if [ -z "$urls" ]; then
  echo "no URLs found in: $*"
  exit 0
fi

fail=0
while IFS= read -r url; do
  [ -z "$url" ] && continue
  code=$(curl -sSL -A "$UA" --connect-timeout 10 --max-time 30 --retry 2 \
    -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")
  if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
    echo "  ok   $code  $url"
  else
    echo "  DEAD $code  $url" >&2
    fail=1
  fi
done <<< "$urls"

if [ "$fail" -ne 0 ]; then
  echo "check-links.sh: one or more URLs did not resolve to 2xx/3xx" >&2
  exit 1
fi
echo "OK: all cited links reachable"
