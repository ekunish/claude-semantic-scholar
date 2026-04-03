#!/usr/bin/env bash
# ss-citations.sh — Explore citation network (forward/backward)
# Usage: ss-citations.sh <paper_id> [options]
#   --direction <d>  "forward" (who cited this) or "backward" (what this cites) (default: forward)
#   --fields <f>     Comma-separated fields for cited/citing papers
#   --limit <n>      Max results (default: 100, max: 1000)
#   --offset <n>     Offset for pagination (default: 0)
set -euo pipefail
source "$(dirname "$0")/_rate_limit.sh"

BASE_URL="https://api.semanticscholar.org/graph/v1"
DEFAULT_FIELDS="title,year,citationCount,authors,venue"

paper_id=""
direction="forward"
fields="$DEFAULT_FIELDS"
limit="100"
offset="0"

while [[ $# -gt 0 ]]; do
  case $1 in
    --direction) direction="$2"; shift 2 ;;
    --fields) fields="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --offset) offset="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) paper_id="$1"; shift ;;
  esac
done

if [[ -z "$paper_id" ]]; then
  echo "Usage: ss-citations.sh <paper_id> [--direction forward|backward] [--fields <f>] [--limit <n>]" >&2
  exit 1
fi

encoded_id=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$paper_id")

if [[ "$direction" == "forward" ]]; then
  endpoint="citations"
elif [[ "$direction" == "backward" ]]; then
  endpoint="references"
else
  echo "Error: direction must be 'forward' or 'backward'" >&2
  exit 1
fi

url="${BASE_URL}/paper/${encoded_id}/${endpoint}?fields=${fields}&limit=${limit}&offset=${offset}"

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
