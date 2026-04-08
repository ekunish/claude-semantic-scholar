#!/usr/bin/env bash
# ss-author-batch.sh — Batch retrieve multiple authors
# Usage: echo '["id1","id2"]' | ss-author-batch.sh [options]
#    or: ss-author-batch.sh id1 id2 id3 [options]
#   --fields <f>  Comma-separated fields (default: name,affiliations,hIndex,paperCount,citationCount)
#
# Accepts author IDs as arguments or JSON array from stdin.
# Auto-chunks into batches of 1000 if more IDs are provided.
set -euo pipefail
source "$(dirname "$0")/_rate_limit.sh"

BASE_URL="https://api.semanticscholar.org/graph/v1"
DEFAULT_FIELDS="name,affiliations,hIndex,paperCount,citationCount"
BATCH_SIZE=1000

fields="$DEFAULT_FIELDS"
ids=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --fields) fields="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) ids+=("$1"); shift ;;
  esac
done

# If no IDs as args, read from stdin
if [[ ${#ids[@]} -eq 0 ]]; then
  stdin_data=$(cat)
  if echo "$stdin_data" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    mapfile -t ids < <(echo "$stdin_data" | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]")
  else
    mapfile -t ids < <(echo "$stdin_data" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$')
  fi
fi

if [[ ${#ids[@]} -eq 0 ]]; then
  echo "Usage: ss-author-batch.sh id1 id2 ... [--fields <fields>]" >&2
  echo "   or: echo '[\"id1\",\"id2\"]' | ss-author-batch.sh [--fields <fields>]" >&2
  exit 1
fi

url="${BASE_URL}/author/batch?fields=${fields}"

tmpfile=$(mktemp)
resultfile=$(mktemp)
echo "[]" > "$resultfile"
trap 'rm -f "$tmpfile" "$resultfile"' EXIT

curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 60 -H "Content-Type: application/json")
if [[ -n "${S2_API_KEY:-}" ]]; then
  curl_args+=(-H "x-api-key: ${S2_API_KEY}")
fi

# Process in chunks of BATCH_SIZE
total=${#ids[@]}
for ((start=0; start<total; start+=BATCH_SIZE)); do
  end=$((start + BATCH_SIZE))
  if [[ $end -gt $total ]]; then end=$total; fi

  # Build JSON body for this chunk
  chunk_json=$(python3 -c "
import json, sys
ids = sys.argv[1:]
print(json.dumps({'ids': ids}))
" "${ids[@]:$start:$((end-start))}")

  max_retries=5
  backoff=60
  for attempt in $(seq 1 $max_retries); do
    ss_rate_wait
    http_code=$(curl "${curl_args[@]}" -X POST -d "$chunk_json" "$url")

    if [[ "$http_code" == "200" ]]; then
      # Merge results using temp files to avoid argv size limits
      python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    existing = json.load(f)
with open(sys.argv[2]) as f:
    new = json.load(f)
existing.extend([x for x in new if x is not None])
with open(sys.argv[1], 'w') as f:
    json.dump(existing, f)
" "$resultfile" "$tmpfile"
      break
    elif [[ "$http_code" == "429" && $attempt -lt $max_retries ]]; then
      echo "Rate limited, retrying in ${backoff}s (attempt $attempt/$max_retries)..." >&2
      sleep "$backoff"
      ss_rate_backoff "$backoff"
      backoff=$(( backoff * 2 ))
    else
      echo "Error: HTTP $http_code (batch starting at index $start)" >&2
      cat "$tmpfile" >&2
      exit 1
    fi
  done
done

cat "$resultfile"
