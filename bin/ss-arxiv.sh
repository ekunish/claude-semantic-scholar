#!/usr/bin/env bash
# ss-arxiv.sh — Fetch paper metadata from arXiv API (no rate limit hassle)
# Usage: ss-arxiv.sh <arxiv_id> [options]
#   --bibtex    Output BibTeX citation instead of JSON
#
# Much faster than S2 for arXiv papers (3s courtesy pause vs 60s rate limit).
# Accepts: 2106.15928, ARXIV:2106.15928, https://arxiv.org/abs/2106.15928
#
# Output JSON uses S2-compatible field names where possible.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

ARXIV_API="https://export.arxiv.org/api/query"

arxiv_id=""
bibtex=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --bibtex) bibtex=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) [[ -z "$arxiv_id" ]] || die "unexpected argument: $1"; arxiv_id="$1"; shift ;;
  esac
done

if [[ -z "$arxiv_id" ]]; then
  echo "Usage: ss-arxiv.sh <arxiv_id> [--bibtex]" >&2
  exit 1
fi

# Normalize arXiv ID: strip prefix and URL parts
arxiv_id=$(normalize_arxiv_id "$arxiv_id")

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

sleep 3  # arXiv courtesy pause
http_code=$(curl -sL -o "$tmpfile" -w "%{http_code}" --max-time 30 \
  "${ARXIV_API}?id_list=${arxiv_id}") || true
[[ -z "$http_code" || "$http_code" == "000" ]] && { printf 'Error: network request failed\n' >&2; exit 1; }

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

with open(sys.argv[1]) as f:
    tree = ET.parse(f)
root = tree.getroot()

entry = root.find(f'{ATOM}entry')
if entry is None:
    print('No paper found for this arXiv ID', file=sys.stderr)
    sys.exit(1)

# Check for error
if entry.find(f'{ATOM}title') is not None and 'Error' in (entry.find(f'{ATOM}title').text or ''):
    print(f'arXiv error: {entry.find(ATOM + \"summary\").text.strip()}', file=sys.stderr)
    sys.exit(1)

def text(el, tag, ns=ATOM):
    e = el.find(f'{ns}{tag}')
    return e.text.strip() if e is not None and e.text else ''

def clean(s):
    return re.sub(r'\s+', ' ', s).strip()

title = clean(text(entry, 'title'))
abstract = clean(text(entry, 'summary'))
published = text(entry, 'published')
updated = text(entry, 'updated')
comment = text(entry, 'comment', ARXIV)
journal_ref = text(entry, 'journal_ref', ARXIV)
doi_text = text(entry, 'doi', ARXIV)

# Extract arXiv ID from the entry URL
entry_id = text(entry, 'id')
aid = re.sub(r'^https?://arxiv\.org/abs/', '', entry_id)
aid_no_version = re.sub(r'v\d+$', '', aid)

year = int(published[:4]) if published else None
pub_date = published[:10] if published else None

authors = []
for a in entry.findall(f'{ATOM}author'):
    name = text(a, 'name')
    affil = text(a, 'affiliation', ARXIV)
    author = {'name': name}
    if affil:
        author['affiliation'] = affil
    authors.append(author)

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

bibtex_mode = '--bibtex' in sys.argv[2:]

if bibtex_mode:
    # Generate BibTeX
    first_author_last = authors[0]['name'].split()[-1].lower() if authors else 'unknown'
    first_word = re.sub(r'[^a-z]', '', title.split()[0].lower()) if title else 'untitled'
    cite_key = f'{first_author_last}{year or \"\"}{first_word}'
    author_str = ' and '.join(a['name'] for a in authors)
    bib = f'@article{{{cite_key},\n'
    bib += f'  title={{{title}}},\n'
    bib += f'  author={{{author_str}}},\n'
    if journal_ref:
        bib += f'  journal={{{journal_ref}}},\n'
    else:
        bib += f'  journal={{arXiv preprint arXiv:{aid_no_version}}},\n'
    if year:
        bib += f'  year={{{year}}},\n'
    bib += f'  eprint={{{aid_no_version}}},\n'
    bib += f'  archivePrefix={{arXiv}},\n'
    if primary_cat:
        bib += f'  primaryClass={{{primary_cat}}},\n'
    if doi_text:
        bib += f'  doi={{{doi_text}}},\n'
    bib = bib.rstrip(',\n') + '\n}'
    print(bib)
else:
    paper = {
        'arxivId': aid,
        'externalIds': external_ids,
        'title': title,
        'abstract': abstract,
        'year': year,
        'publicationDate': pub_date,
        'updatedDate': updated[:10] if updated else None,
        'authors': authors,
        'venue': journal_ref or 'arXiv',
        'primaryCategory': primary_cat,
        'categories': categories,
        'pdfUrl': pdf_url,
        'comment': comment or None,
        'journalRef': journal_ref or None,
    }
    print(json.dumps(paper, ensure_ascii=False))
" "$tmpfile" $(if $bibtex; then echo "--bibtex"; fi)
