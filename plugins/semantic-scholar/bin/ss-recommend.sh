#!/usr/bin/env bash
# ss-recommend.sh — Get paper recommendations from seed papers
# Usage: ss-recommend.sh [options]
#   --positive <ids>   Comma-separated paper IDs to use as positive seeds (required)
#   --negative <ids>   Comma-separated paper IDs to use as negative seeds (optional)
#   --fields <f>       Comma-separated fields (default: title,year,citationCount,authors,venue)
#   --limit <n>        Max recommendations (default: 20, max: 500)
#
# Single seed mode: If only one positive ID and no negatives, uses the simpler GET endpoint.
# Multi-seed mode: Uses POST endpoint with positive/negative seeds.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

REC_BASE="https://api.semanticscholar.org/recommendations/v1"
DEFAULT_FIELDS="title,abstract,tldr,year,citationCount,authors,venue"

positive=""
negative=""
fields="$DEFAULT_FIELDS"
limit="20"

while [[ $# -gt 0 ]]; do
  case $1 in
    --positive) positive=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --negative) negative=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --fields) fields=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --limit) limit=$(require_arg "$1" "${2:-}"); shift 2 ;;
    -*) die "Unknown option: $1" ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$positive" ]] || die "Usage: ss-recommend.sh --positive <id1,id2,...> [--negative <id3,...>] [--fields <f>] [--limit <n>]"

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

IFS=',' read -ra pos_ids <<< "$positive"

# Single seed: simple GET
if [[ ${#pos_ids[@]} -eq 1 && -z "$negative" ]]; then
  encoded_id=$(urlencode "${pos_ids[0]}" "")
  s2_get "/papers/forpaper/${encoded_id}?fields=${fields}&limit=${limit}" "$tmpfile" "$REC_BASE"
  cat "$tmpfile"
else
  # Multi-seed: POST
  body_json=$(python3 -c "
import json, sys
pos = [p.strip() for p in sys.argv[1].split(',')]
neg = [n.strip() for n in sys.argv[2].split(',') if n.strip()] if sys.argv[2] else []
print(json.dumps({'positivePaperIds': pos, 'negativePaperIds': neg}))
" "$positive" "${negative:-}")
  s2_post "/papers?fields=${fields}&limit=${limit}" "$body_json" "$tmpfile" "$REC_BASE"
  cat "$tmpfile"
fi
