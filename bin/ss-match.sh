#!/usr/bin/env bash
# ss-match.sh — Find a paper by exact title match
# Usage: ss-match.sh "<exact title>" [options]
#   --fields <f>  Comma-separated fields (default: same as ss-paper.sh)
#
# Uses the /paper/search/match endpoint which returns the single best match.
# Useful when copying a title from a PDF, citation list, or reference manager.
set -euo pipefail
source "$(dirname "$0")/_rate_limit.sh"

BASE_URL="https://api.semanticscholar.org/graph/v1"
DEFAULT_FIELDS="title,abstract,year,citationCount,referenceCount,authors,venue,openAccessPdf,tldr,fieldsOfStudy,publicationDate,externalIds"

title=""
fields="$DEFAULT_FIELDS"

while [[ $# -gt 0 ]]; do
  case $1 in
    --fields) fields="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) title="$1"; shift ;;
  esac
done

if [[ -z "$title" ]]; then
  echo "Usage: ss-match.sh \"<exact title>\" [--fields <fields>]" >&2
  exit 1
fi

encoded_title=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$title")
url="${BASE_URL}/paper/search/match?query=${encoded_title}&fields=${fields}"

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 30)
if [[ -n "${S2_API_KEY:-}" ]]; then
  curl_args+=(-H "x-api-key: ${S2_API_KEY}")
fi

max_retries=5
backoff=60
for attempt in $(seq 1 $max_retries); do
  ss_rate_wait
  http_code=$(curl "${curl_args[@]}" "$url")

  if [[ "$http_code" == "200" ]]; then
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
    exit 0
  elif [[ "$http_code" == "404" ]]; then
    echo "No match found for: $title" >&2
    exit 1
  elif [[ "$http_code" == "429" && $attempt -lt $max_retries ]]; then
    echo "Rate limited, retrying in ${backoff}s (attempt $attempt/$max_retries)..." >&2
    sleep "$backoff"
    ss_rate_backoff "$backoff"
    backoff=$(( backoff * 2 ))
  else
    echo "Error: HTTP $http_code" >&2
    cat "$tmpfile" >&2
    exit 1
  fi
done
