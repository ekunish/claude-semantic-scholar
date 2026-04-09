#!/usr/bin/env bash
# ss-pdf.sh — Resolve open-access PDF URL for a DOI
# Usage: ss-pdf.sh <DOI>
#
# Resolution order:
#   1. arXiv pattern match (10.48550/arXiv.* → arxiv.org/pdf/{id}.pdf, no API call)
#   2. Unpaywall API (requires UNPAYWALL_EMAIL env var)
#
# Output: JSON with {doi, pdfUrl, source} or {doi, pdfUrl: null, source: null}
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

doi=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -*) die "Unknown option: $1" ;;
    *)
      [[ -z "$doi" ]] || die "unexpected argument: $1"
      doi="$1"; shift ;;
  esac
done

if [[ -z "$doi" ]]; then
  die "Usage: ss-pdf.sh <DOI>"
fi

# Normalize DOI
doi=$(echo "$doi" | sed -E 's#^doi:##i; s#^https?://(dx\.)?doi\.org/##')

# 1. arXiv pattern match
doi_lower=$(echo "$doi" | tr '[:upper:]' '[:lower:]')
if [[ "$doi_lower" == 10.48550/arxiv.* ]]; then
  arxiv_id="${doi_lower#*/arxiv.}"
  arxiv_id=$(normalize_arxiv_id "$arxiv_id")
  pdf_url="https://arxiv.org/pdf/${arxiv_id}.pdf"
  python3 -c "import json,sys; print(json.dumps({'doi': sys.argv[1], 'pdfUrl': sys.argv[2], 'source': 'arxiv'}))" "$doi" "$pdf_url"
  exit 0
fi

# 2. Unpaywall
if [[ -z "${UNPAYWALL_EMAIL:-}" ]]; then
  printf 'Warning: UNPAYWALL_EMAIL not set, cannot query Unpaywall\n' >&2
  python3 -c "import json,sys; print(json.dumps({'doi': sys.argv[1], 'pdfUrl': None, 'source': None}))" "$doi"
  exit 0
fi

encoded_doi=$(urlencode "$doi" "")

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

http_code=$(curl -s -o "$tmpfile" -w "%{http_code}" "https://api.unpaywall.org/v2/${encoded_doi}?email=${UNPAYWALL_EMAIL}")

if [[ "$http_code" != "200" ]]; then
  printf 'Unpaywall error: HTTP %s\n' "$http_code" >&2
  python3 -c "import json,sys; print(json.dumps({'doi': sys.argv[1], 'pdfUrl': None, 'source': None}))" "$doi"
  exit 0
fi

python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    d = json.load(f)
doi = sys.argv[2]

if not d.get('is_oa'):
    print(json.dumps({'doi': doi, 'pdfUrl': None, 'source': None}))
    sys.exit(0)

best = d.get('best_oa_location') or {}
url = best.get('url_for_pdf') or ''
if not url:
    for loc in d.get('oa_locations', []):
        if loc.get('url_for_pdf'):
            url = loc['url_for_pdf']
            break

if url:
    print(json.dumps({'doi': doi, 'pdfUrl': url, 'source': 'unpaywall'}))
else:
    print(json.dumps({'doi': doi, 'pdfUrl': None, 'source': None}))
" "$tmpfile" "$doi"
