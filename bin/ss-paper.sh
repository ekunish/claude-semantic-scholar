#!/usr/bin/env bash
# ss-paper.sh — Get details for a single paper
# Usage: ss-paper.sh <paper_id> [options]
#   --fields <f>  Comma-separated fields (default: title,abstract,year,citationCount,authors,venue,openAccessPdf,tldr,fieldsOfStudy)
#   --bibtex      Output BibTeX citation instead of JSON
#
# Paper ID formats:
#   SHA hash:    649def34f8be52c8b66281af98ae884c09aef38b
#   DOI:         DOI:10.18653/v1/N18-3011
#   ArXiv:       ARXIV:2106.15928
#   PMID:        PMID:19872477
#   CorpusId:    CorpusId:215416146
#   URL:         https://arxiv.org/abs/2106.15928
set -euo pipefail
source "$(dirname "$0")/_rate_limit.sh"

BASE_URL="https://api.semanticscholar.org/graph/v1"
DEFAULT_FIELDS="title,abstract,year,citationCount,referenceCount,authors,venue,openAccessPdf,tldr,fieldsOfStudy,publicationDate,externalIds"

paper_id=""
fields="$DEFAULT_FIELDS"
bibtex=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --fields) fields="$2"; shift 2 ;;
    --bibtex) bibtex=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) paper_id="$1"; shift ;;
  esac
done

# Ensure citationStyles is in fields when --bibtex is requested
if $bibtex && [[ "$fields" != *"citationStyles"* ]]; then
  fields="${fields},citationStyles"
fi

if [[ -z "$paper_id" ]]; then
  echo "Usage: ss-paper.sh <paper_id> [--fields <fields>]" >&2
  exit 1
fi

encoded_id=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$paper_id")
url="${BASE_URL}/paper/${encoded_id}?fields=${fields}"

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
    if $bibtex; then
      python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
bib = data.get('citationStyles', {}).get('bibtex', '')
if bib:
    print(bib)
else:
    print('No BibTeX available for this paper', file=sys.stderr)
    sys.exit(1)
" "$tmpfile"
    else
      cat "$tmpfile"
    fi
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
