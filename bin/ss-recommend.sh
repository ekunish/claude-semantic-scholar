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
source "$(dirname "$0")/_helpers.sh"

REC_URL="https://api.semanticscholar.org/recommendations/v1"
DEFAULT_FIELDS="title,year,citationCount,authors,venue"

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
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$positive" ]]; then
  echo "Usage: ss-recommend.sh --positive <id1,id2,...> [--negative <id3,...>] [--fields <f>] [--limit <n>]" >&2
  exit 1
fi

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

IFS=',' read -ra pos_ids <<< "$positive"

# Single seed: simple GET
if [[ ${#pos_ids[@]} -eq 1 && -z "$negative" ]]; then
  encoded_id=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${pos_ids[0]}")

  curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 30)
  [[ -n "${S2_API_KEY:-}" ]] && curl_args+=(-H "x-api-key: ${S2_API_KEY}")

  max_retries=5
  backoff=60
  for attempt in $(seq 1 $max_retries); do
    ss_rate_wait
    http_code=$(curl "${curl_args[@]}" "${REC_URL}/papers/forpaper/${encoded_id}?fields=${fields}&limit=${limit}")

    if [[ "$http_code" == "200" ]]; then
      cat "$tmpfile"
      exit 0
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
else
  # Multi-seed: POST
  body_json=$(python3 -c "
import json, sys
pos = sys.argv[1].split(',')
neg = sys.argv[2].split(',') if sys.argv[2] else []
print(json.dumps({'positivePaperIds': pos, 'negativePaperIds': neg}))
" "$positive" "${negative:-}")

  curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 30
    -H "Content-Type: application/json")
  [[ -n "${S2_API_KEY:-}" ]] && curl_args+=(-H "x-api-key: ${S2_API_KEY}")

  max_retries=5
  backoff=60
  for attempt in $(seq 1 $max_retries); do
    ss_rate_wait
    http_code=$(curl "${curl_args[@]}" -X POST -d "$body_json" "${REC_URL}/papers?fields=${fields}&limit=${limit}")

    if [[ "$http_code" == "200" ]]; then
      cat "$tmpfile"
      exit 0
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
fi
