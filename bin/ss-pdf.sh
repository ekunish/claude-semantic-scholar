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

doi=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) doi="$1"; shift ;;
  esac
done

if [[ -z "$doi" ]]; then
  echo "Usage: ss-pdf.sh <DOI>" >&2
  echo "  Requires UNPAYWALL_EMAIL env var for non-arXiv DOIs" >&2
  exit 1
fi

# Normalize DOI
doi=$(echo "$doi" | sed -E 's#^doi:##i; s#^https?://(dx\.)?doi\.org/##')

# 1. arXiv pattern match
doi_lower=$(echo "$doi" | tr '[:upper:]' '[:lower:]')
if [[ "$doi_lower" == 10.48550/arxiv.* ]]; then
  arxiv_id="${doi#*/arXiv.}"
  arxiv_id="${arxiv_id#*/arxiv.}"
  arxiv_id="${arxiv_id#*/ARXIV.}"
  pdf_url="https://arxiv.org/pdf/${arxiv_id}.pdf"
  python3 -c "
import json
print(json.dumps({'doi': '$doi', 'pdfUrl': '$pdf_url', 'source': 'arxiv'}))
"
  exit 0
fi

# 2. Unpaywall
if [[ -z "${UNPAYWALL_EMAIL:-}" ]]; then
  echo "Warning: UNPAYWALL_EMAIL not set, cannot query Unpaywall" >&2
  python3 -c "
import json
print(json.dumps({'doi': '$doi', 'pdfUrl': None, 'source': None}))
"
  exit 0
fi

encoded_doi=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$doi', safe=''))")

pdf_url=$(curl -s "https://api.unpaywall.org/v2/${encoded_doi}?email=${UNPAYWALL_EMAIL}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
if not d.get('is_oa'):
    print('')
    sys.exit(0)
best = d.get('best_oa_location') or {}
url = best.get('url_for_pdf') or ''
if not url:
    for loc in d.get('oa_locations', []):
        if loc.get('url_for_pdf'):
            url = loc['url_for_pdf']
            break
print(url)
" 2>/dev/null)

if [[ -n "$pdf_url" ]]; then
  python3 -c "
import json
print(json.dumps({'doi': '$doi', 'pdfUrl': '$pdf_url', 'source': 'unpaywall'}))
"
else
  python3 -c "
import json
print(json.dumps({'doi': '$doi', 'pdfUrl': None, 'source': None}))
"
fi
