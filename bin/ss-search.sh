#!/usr/bin/env bash
# ss-search.sh — Semantic Scholar keyword search
# Usage: ss-search.sh <query> [options]
#   --fields <f>          Comma-separated fields (default: title,year,citationCount,authors,venue)
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
source "$(dirname "$0")/_helpers.sh"

DEFAULT_FIELDS="title,year,citationCount,influentialCitationCount,authors,venue"

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
    --fields) fields=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --year) year=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --min-citations) min_citations=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --limit) limit=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --venue) venue=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --fields-of-study) fields_of_study=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --pub-types) pub_types=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --sort) sort=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --relevance) use_relevance=true; shift ;;
    --token) token=$(require_arg "$1" "${2:-}"); shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) query="$query${query:+ }$1"; shift ;;
  esac
done

if [[ -z "$query" ]]; then
  echo "Usage: ss-search.sh <query> [options]" >&2
  exit 1
fi

# Build URL
if $use_relevance; then
  endpoint="/paper/search"
else
  endpoint="/paper/search/bulk"
fi

encoded_query=$(urlencode "$query")
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

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

if s2_get "${endpoint}?${params}" "$tmpfile"; then
  cat "$tmpfile"
else
  exit 1
fi
