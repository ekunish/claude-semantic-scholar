#!/usr/bin/env bash
# ss-author.sh — Search authors or get author details/papers
# Usage:
#   ss-author.sh <query>                  Search authors by name
#   ss-author.sh --id <author_id>         Get author details
#   ss-author.sh --id <author_id> --papers  Get author's papers
#
# Options:
#   --fields <f>   Comma-separated fields
#   --limit <n>    Max results (default: 20)
#   --offset <n>   Offset for pagination (default: 0)
set -euo pipefail
source "$(dirname "$0")/_rate_limit.sh"

BASE_URL="https://api.semanticscholar.org/graph/v1"
DEFAULT_SEARCH_FIELDS="name,affiliations,paperCount,citationCount,hIndex"
DEFAULT_DETAIL_FIELDS="name,affiliations,paperCount,citationCount,hIndex,homepage,externalIds"
DEFAULT_PAPER_FIELDS="title,year,citationCount,venue"

query=""
author_id=""
get_papers=false
fields=""
limit="20"
offset="0"

while [[ $# -gt 0 ]]; do
  case $1 in
    --id) author_id="$2"; shift 2 ;;
    --papers) get_papers=true; shift ;;
    --fields) fields="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --offset) offset="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) query="$1"; shift ;;
  esac
done

if [[ -z "$author_id" && -z "$query" ]]; then
  echo "Usage: ss-author.sh <query> | ss-author.sh --id <author_id> [--papers]" >&2
  exit 1
fi

# Determine URL and default fields
if [[ -n "$author_id" ]]; then
  if $get_papers; then
    [[ -z "$fields" ]] && fields="$DEFAULT_PAPER_FIELDS"
    url="${BASE_URL}/author/${author_id}/papers?fields=${fields}&limit=${limit}&offset=${offset}"
  else
    [[ -z "$fields" ]] && fields="$DEFAULT_DETAIL_FIELDS"
    url="${BASE_URL}/author/${author_id}?fields=${fields}"
  fi
else
  [[ -z "$fields" ]] && fields="$DEFAULT_SEARCH_FIELDS"
  encoded_query=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
  url="${BASE_URL}/author/search?query=${encoded_query}&fields=${fields}&limit=${limit}&offset=${offset}"
fi

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
