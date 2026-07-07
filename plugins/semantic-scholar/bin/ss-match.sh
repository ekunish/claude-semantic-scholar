#!/usr/bin/env bash
# ss-match.sh — Find a paper by exact title match
# Usage: ss-match.sh "<exact title>" [options]
#   --fields <f>  Comma-separated fields (default: same as ss-paper.sh)
#
# Uses the /paper/search/match endpoint which returns the single best match.
# Useful when copying a title from a PDF, citation list, or reference manager.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

DEFAULT_FIELDS="title,abstract,year,citationCount,referenceCount,authors,venue,tldr,fieldsOfStudy,publicationDate,externalIds"

title=""
fields="$DEFAULT_FIELDS"

while [[ $# -gt 0 ]]; do
  case $1 in
    --fields) fields=$(require_arg "$1" "${2:-}"); shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) title="$title${title:+ }$1"; shift ;;
  esac
done

if [[ -z "$title" ]]; then
  echo "Usage: ss-match.sh \"<exact title>\" [--fields <fields>]" >&2
  exit 1
fi

encoded_title=$(urlencode "$title")

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

if s2_get "/paper/search/match?query=${encoded_title}&fields=${fields}" "$tmpfile"; then
  # Extract first match from data array
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
matches = data.get('data', [data])
if matches:
    print(json.dumps(matches[0]))
else:
    print('No match found', file=sys.stderr)
    sys.exit(1)
" "$tmpfile"
else
  # Check if it was a 404 (no match)
  exit 1
fi
