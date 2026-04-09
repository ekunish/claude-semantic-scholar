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
source "$(dirname "$0")/_helpers.sh"

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
    --id) author_id=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --papers) get_papers=true; shift ;;
    --fields) fields=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --limit) limit=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --offset) offset=$(require_arg "$1" "${2:-}"); shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) query="$query${query:+ }$1"; shift ;;
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
    endpoint="/author/${author_id}/papers?fields=${fields}&limit=${limit}&offset=${offset}"
  else
    [[ -z "$fields" ]] && fields="$DEFAULT_DETAIL_FIELDS"
    endpoint="/author/${author_id}?fields=${fields}"
  fi
else
  [[ -z "$fields" ]] && fields="$DEFAULT_SEARCH_FIELDS"
  encoded_query=$(urlencode "$query")
  endpoint="/author/search?query=${encoded_query}&fields=${fields}&limit=${limit}&offset=${offset}"
fi

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

if s2_get "$endpoint" "$tmpfile"; then
  cat "$tmpfile"
else
  exit 1
fi
