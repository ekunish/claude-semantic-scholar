#!/usr/bin/env bash
# ss-search.sh — Semantic Scholar keyword search
# Usage: ss-search.sh <query> [options]
#   --fields <f>          Comma-separated fields (default: title,year,citationCount,authors,venue,openAccessPdf)
#   --year <range>        Year filter (e.g., "2020-", "2018-2023")
#   --min-citations <n>   Minimum citation count
#   --limit <n>           Max results (default: 20)
#   --venue <v>           Venue filter
#   --fields-of-study <f> Fields of study filter
#   --pub-types <t>       Publication types (e.g., "JournalArticle,Conference")
#   --sort <field>        Sort by: citationCount, publicationDate, paperId (bulk only)
#   --relevance           Use relevance-ranked search instead of bulk
#   --token <t>           Continuation token for bulk pagination
set -euo pipefail
source "$(dirname "$0")/_rate_limit.sh"

BASE_URL="https://api.semanticscholar.org/graph/v1"
DEFAULT_FIELDS="title,year,citationCount,influentialCitationCount,authors,venue,openAccessPdf"

query=""
fields="$DEFAULT_FIELDS"
year=""
min_citations=""
limit="20"
venue=""
fields_of_study=""
pub_types=""
sort=""
use_relevance=false
token=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --fields) fields="$2"; shift 2 ;;
    --year) year="$2"; shift 2 ;;
    --min-citations) min_citations="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --venue) venue="$2"; shift 2 ;;
    --fields-of-study) fields_of_study="$2"; shift 2 ;;
    --pub-types) pub_types="$2"; shift 2 ;;
    --sort) sort="$2"; shift 2 ;;
    --relevance) use_relevance=true; shift ;;
    --token) token="$2"; shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) query="$1"; shift ;;
  esac
done

if [[ -z "$query" ]]; then
  echo "Usage: ss-search.sh <query> [options]" >&2
  exit 1
fi

# Build URL
if $use_relevance; then
  url="${BASE_URL}/paper/search"
else
  url="${BASE_URL}/paper/search/bulk"
fi

encoded_query=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
params="query=${encoded_query}&fields=${fields}&limit=${limit}"
[[ -n "$year" ]] && params+="&year=${year}"
[[ -n "$min_citations" ]] && params+="&minCitationCount=${min_citations}"
[[ -n "$venue" ]] && params+="&venue=${venue}"
[[ -n "$fields_of_study" ]] && params+="&fieldsOfStudy=${fields_of_study}"
[[ -n "$pub_types" ]] && params+="&publicationTypes=${pub_types}"
[[ -n "$sort" && "$use_relevance" == "false" ]] && params+="&sort=${sort}"
[[ -n "$token" && "$use_relevance" == "false" ]] && params+="&token=${token}"

if $use_relevance && [[ -n "$token" ]]; then
  params+="&offset=${token}"
fi

# Build curl args
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 30)
if [[ -n "${S2_API_KEY:-}" ]]; then
  curl_args+=(-H "x-api-key: ${S2_API_KEY}")
fi

# Retry logic
max_retries=5
backoff=60
for attempt in $(seq 1 $max_retries); do
  ss_rate_wait
  http_code=$(curl "${curl_args[@]}" "${url}?${params}")

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
