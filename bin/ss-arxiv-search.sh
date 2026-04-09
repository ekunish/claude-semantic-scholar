#!/usr/bin/env bash
# ss-arxiv-search.sh — Search arXiv papers (no auth, 3s rate limit)
# Usage: ss-arxiv-search.sh <query> [options]
#   --category <cat>  arXiv category filter (e.g., cs.AI, stat.ML, math.CO)
#   --limit <n>       Max results (default: 20, max: 2000)
#   --start <n>       Offset for pagination (default: 0)
#   --sort <field>    relevance (default), lastUpdatedDate, submittedDate
#   --order <dir>     descending (default), ascending
#
# Query supports arXiv field prefixes: ti:, au:, abs:, cat:, all:
# Boolean operators: AND, OR, ANDNOT
# Examples:
#   ss-arxiv-search.sh "transformer" --category cs.CL --limit 10
#   ss-arxiv-search.sh "ti:attention AND au:vaswani"
#   ss-arxiv-search.sh "deep learning" --sort submittedDate --limit 20
set -euo pipefail
source "$(dirname "$0")/_helpers.sh"

ARXIV_API="https://export.arxiv.org/api/query"

query=""
category=""
limit="20"
start="0"
sort="relevance"
order="descending"

while [[ $# -gt 0 ]]; do
  case $1 in
    --category) category=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --limit) limit=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --start) start=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --sort) sort=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --order) order=$(require_arg "$1" "${2:-}"); shift 2 ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) query="$query${query:+ }$1"; shift ;;
  esac
done

if [[ -z "$query" ]]; then
  echo "Usage: ss-arxiv-search.sh <query> [--category <cat>] [--limit <n>] [--sort <field>]" >&2
  exit 1
fi

# If query doesn't contain field prefixes, default to all: search
if ! echo "$query" | grep -qE '(ti:|au:|abs:|cat:|all:|jr:|co:)'; then
  query="all:${query}"
fi

# Append category filter if specified
if [[ -n "$category" ]]; then
  query="${query}+AND+cat:${category}"
fi

# URL-encode the query
encoded_query=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe='+:'))" "$query")

# Build URL
url="${ARXIV_API}?search_query=${encoded_query}&start=${start}&max_results=${limit}"
if [[ "$sort" != "relevance" ]]; then
  url+="&sortBy=${sort}&sortOrder=${order}"
fi

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

sleep 3  # arXiv courtesy pause
http_code=$(curl -sL -o "$tmpfile" -w "%{http_code}" --max-time 30 "$url")

if [[ "$http_code" != "200" ]]; then
  echo "Error: HTTP $http_code" >&2
  cat "$tmpfile" >&2
  exit 1
fi

python3 -c "
import xml.etree.ElementTree as ET
import json, sys, re

ATOM = '{http://www.w3.org/2005/Atom}'
ARXIV = '{http://arxiv.org/schemas/atom}'
OPENSEARCH = '{http://a9.com/-/spec/opensearch/1.1/}'

with open(sys.argv[1]) as f:
    tree = ET.parse(f)
root = tree.getroot()

total_el = root.find(f'{OPENSEARCH}totalResults')
total = int(total_el.text) if total_el is not None and total_el.text else 0

def text(el, tag, ns=ATOM):
    e = el.find(f'{ns}{tag}')
    return e.text.strip() if e is not None and e.text else ''

def clean(s):
    return re.sub(r'\s+', ' ', s).strip()

papers = []
for entry in root.findall(f'{ATOM}entry'):
    title = clean(text(entry, 'title'))
    if 'Error' in title:
        continue

    abstract = clean(text(entry, 'summary'))
    published = text(entry, 'published')
    journal_ref = text(entry, 'journal_ref', ARXIV)
    doi_text = text(entry, 'doi', ARXIV)

    entry_id = text(entry, 'id')
    aid = re.sub(r'^https?://arxiv\.org/abs/', '', entry_id)
    aid_no_version = re.sub(r'v\d+$', '', aid)

    year = int(published[:4]) if published else None

    authors = [{'name': text(a, 'name')} for a in entry.findall(f'{ATOM}author')]

    primary_cat = ''
    pc = entry.find(f'{ARXIV}primary_category')
    if pc is not None:
        primary_cat = pc.get('term', '')

    categories = [c.get('term', '') for c in entry.findall(f'{ATOM}category')]

    pdf_url = ''
    for link in entry.findall(f'{ATOM}link'):
        if link.get('title') == 'pdf':
            pdf_url = link.get('href', '')

    external_ids = {'ArXiv': aid_no_version}
    if doi_text:
        external_ids['DOI'] = doi_text

    papers.append({
        'arxivId': aid,
        'externalIds': external_ids,
        'title': title,
        'abstract': abstract,
        'year': year,
        'publicationDate': published[:10] if published else None,
        'authors': authors,
        'venue': journal_ref or 'arXiv',
        'primaryCategory': primary_cat,
        'categories': categories,
        'pdfUrl': pdf_url,
    })

print(json.dumps({'totalResults': total, 'data': papers}, ensure_ascii=False))
" "$tmpfile"
