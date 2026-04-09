#!/usr/bin/env bash
# ss-paper.sh — Get details for a single paper
# Usage: ss-paper.sh <paper_id> [options]
#   --fields <f>  Comma-separated fields (default: title,abstract,year,citationCount,authors,venue,tldr,fieldsOfStudy)
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
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

DEFAULT_FIELDS="title,abstract,year,citationCount,referenceCount,authors,venue,tldr,fieldsOfStudy,publicationDate,externalIds"

paper_id=""
fields="$DEFAULT_FIELDS"
bibtex=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --fields) fields=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --bibtex) bibtex=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) paper_id="$paper_id${paper_id:+ }$1"; shift ;;
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

encoded_id=$(urlencode "$paper_id" "")

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

if s2_get "/paper/${encoded_id}?fields=${fields}" "$tmpfile"; then
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
else
  exit 1
fi
