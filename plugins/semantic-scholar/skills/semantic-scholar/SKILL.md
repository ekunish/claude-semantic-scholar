---
name: semantic-scholar
description: "Literature search and citation exploration using the Semantic Scholar API. Use this skill when the user asks to \"find papers\", \"search literature\", \"literature review\", \"citation network\", \"related work\", \"survey papers\", \"systematic review\", \"論文検索\", \"文献調査\", \"引用ネットワーク\", \"関連研究\", \"先行研究\", \"who cited this paper\", \"find similar papers\", \"author papers\", or provides a DOI/ArXiv ID/PMID to explore. Also trigger when the user wants to find papers on a topic, compare citation counts, explore what influenced a paper, or discover new relevant research."
---

# Semantic Scholar Literature Research

Search academic papers, explore citation networks, and discover related work using the Semantic Scholar API. All scripts are available on PATH via the plugin's `bin/` directory. For detailed API field/endpoint reference, consult `references/api-reference.md`.

## Quick Reference

| Task | Script | Example |
|------|--------|---------|
| Keyword search | `ss-search.sh` | `ss-search.sh "heart sound classification" --year 2020-` |
| Title match | `ss-match.sh` | `ss-match.sh "Attention Is All You Need"` |
| Paper details | `ss-paper.sh` | `ss-paper.sh "DOI:10.1109/TBME.2023.1234"` |
| Paper BibTeX | `ss-paper.sh` | `ss-paper.sh "DOI:10.1109/TBME.2023.1234" --bibtex` |
| Batch retrieval | `ss-batch.sh` | `echo '["id1","id2"]' \| ss-batch.sh` |
| Batch BibTeX | `ss-batch.sh` | `ss-batch.sh id1 id2 --bibtex` |
| Citations (forward) | `ss-citations.sh` | `ss-citations.sh <paper_id> --direction forward` |
| Influential only | `ss-citations.sh` | `ss-citations.sh <paper_id> --influential-only` |
| References (backward) | `ss-citations.sh` | `ss-citations.sh <paper_id> --direction backward` |
| Recommendations | `ss-recommend.sh` | `ss-recommend.sh --positive id1,id2` |
| Author search | `ss-author.sh` | `ss-author.sh "Springer"` |
| Author papers | `ss-author.sh` | `ss-author.sh --id 12345 --papers` |
| Author batch | `ss-author-batch.sh` | `ss-author-batch.sh id1 id2 id3` |
| arXiv paper | `ss-arxiv.sh` | `ss-arxiv.sh 2106.15928` |
| arXiv BibTeX | `ss-arxiv.sh` | `ss-arxiv.sh 2106.15928 --bibtex` |
| arXiv search | `ss-arxiv-search.sh` | `ss-arxiv-search.sh "transformer" --category cs.CL` |
| PDF URL resolve | `ss-pdf.sh` | `ss-pdf.sh "10.48550/arXiv.1706.03762"` |

Scripts are on PATH — call them directly: `ss-search.sh ...`

## arXiv API vs S2 API

The plugin includes arXiv API scripts (`ss-arxiv*.sh`) that bypass S2's rate limit. Use them when working with arXiv papers:

| Use case | Script | Why |
|----------|--------|-----|
| arXiv paper metadata | `ss-arxiv.sh` | 3s wait vs 60s (no S2 API key) |
| arXiv category search | `ss-arxiv-search.sh` | S2 has no category filter |
| arXiv paper BibTeX | `ss-arxiv.sh --bibtex` | No S2 rate limit consumed |
| Citation network | `ss-citations.sh` | arXiv API has no citation data |
| Recommendations | `ss-recommend.sh` | arXiv API has no recommendation engine |
| Cross-database search | `ss-search.sh` | Covers journals, conferences, not just arXiv |
| Sort by citations | `ss-search.sh` | arXiv API has no citation counts |

**Rule of thumb**: If the paper is on arXiv and the task doesn't need citation data, use `ss-arxiv*.sh` first.

## Workflow 1: Keyword Search

This is the most common workflow — finding papers on a topic.

### Step 1: Clarify the research scope

Before searching, clarify with the user (or infer from context):
- **Topic keywords**: What to search for
- **Year range**: How recent? (default: last 5 years)
- **Minimum citations**: Quality threshold (0 for bleeding-edge, 10+ for established work)
- **Publication type**: Journal articles, conference papers, reviews
- **Field of study**: Medicine, Computer Science, Engineering, etc.

### Step 2: Construct the query

Use boolean syntax for precision:
- `"exact phrase"` for specific terms
- `+required -excluded` for filtering
- `(term1 | term2)` for synonyms
- `prefix*` for word variants

Example for PCG quality prediction:
```
("phonocardiogram" | "heart sound") +quality +(prediction | assessment | classification)
```

### Step 3: Execute search

```bash
ss-search.sh \
  '("phonocardiogram" | "heart sound") +quality' \
  --year 2020- --min-citations 5 --limit 30 \
  --sort citationCount
```

### Step 4: Present results

Format results as a markdown table, sorted by citation count descending:

```markdown
| # | Title | Authors | Year | Citations | Influential | Venue |
|---|-------|---------|------|-----------|-------------|-------|
| 1 | ... | First Author et al. | 2023 | 45 | 12 | IEEE TBME |
```

Include:
- Sequential numbering for easy reference
- First author + "et al." (not all authors)
- Total result count and any filters applied

### Step 5: Synthesize

After presenting results, provide a brief synthesis:
- Key research themes/clusters in the results
- Most cited/influential papers
- Research gaps or trends
- Suggestions for narrowing or broadening the search

## Workflow 2: Citation Network Exploration

Explore the intellectual lineage of a paper — who it influenced and what influenced it.

### Forward citations (who cited this?)

```bash
ss-citations.sh <paper_id> \
  --direction forward --limit 100 \
  --fields title,year,citationCount,authors,venue
```

Sort results by citation count to find the most impactful follow-up work.

### Backward references (what did this cite?)

```bash
ss-citations.sh <paper_id> \
  --direction backward --limit 100 \
  --fields title,year,citationCount,authors,venue
```

### Snowball sampling (2-hop exploration)

For thorough literature discovery:
1. Start with a seed paper
2. Get its forward citations and backward references
3. Identify the most-cited papers from step 2
4. Repeat for those papers (2nd hop)
5. Deduplicate and rank by frequency of appearance + citation count

Papers that appear multiple times in the network are likely core to the field.

## Workflow 3: Seed-Based Discovery

When the user already knows some good papers and wants to find more like them.

### Single seed

```bash
ss-recommend.sh \
  --positive <paper_id> --limit 20
```

### Multiple seeds with negative examples

Positive seeds define "papers like these"; negative seeds define "but not like these."

```bash
ss-recommend.sh \
  --positive id1,id2,id3 --negative id4 --limit 30
```

This is powerful for finding papers in a specific niche — e.g., "like these PCG analysis papers, but not the fetal heart sound ones."

## Workflow 4: Author Exploration

### Find a researcher

```bash
ss-author.sh "Springer" \
  --fields name,affiliations,hIndex,paperCount,citationCount
```

### Get their publications

```bash
ss-author.sh --id <author_id> --papers \
  --fields title,year,citationCount,venue --limit 50
```

Present author summary: name, affiliation, h-index, total papers, total citations. Then list their most-cited papers.

## Workflow 5: Systematic Review

For comprehensive literature surveys (e.g., for a paper's Related Work section).

### Step 1: Define search strategy (PICO framework for medical topics)

- **P**opulation: What patient/condition?
- **I**ntervention: What method/approach?
- **C**omparison: Against what?
- **O**utcome: What metrics?

### Step 2: Execute multiple queries

Run 3-5 complementary queries covering different angles:
```bash
# Query 1: Direct topic
ss-search.sh "phonocardiogram quality assessment" --year 2018- --limit 50

# Query 2: Synonym/alternative framing
ss-search.sh "heart sound signal quality" --year 2018- --limit 50

# Query 3: Method-focused
ss-search.sh "deep learning cardiac auscultation" --year 2018- --limit 50
```

### Step 3: Deduplicate and screen

Merge results, remove duplicates by paperId, and screen by:
- Relevance to research question
- Citation count (impact)
- Recency (state of the art)
- Publication venue quality

### Step 4: Expand via citations

For the top 5-10 most relevant papers, check their references (backward) for missed foundational work, and their citations (forward) for recent extensions.

### Step 5: Report

Present a structured literature summary:
- Total papers found vs. included after screening
- Categorized by theme/method/contribution
- Key findings per category
- Research gaps identified

## Workflow 6: Search-to-Zotero Pipeline

Import papers found via Semantic Scholar directly into Zotero using BibTeX.

### Step 1: Search and select

```bash
ss-search.sh "topic of interest" --year 2020- --limit 20
```

Present results as a numbered table. The user selects papers by number.

### Step 2: Export BibTeX

For selected papers, batch-fetch BibTeX citations:

```bash
ss-batch.sh <id1> <id2> <id3> --bibtex > /tmp/selected.bib
```

For a single paper:

```bash
ss-paper.sh <paper_id> --bibtex > /tmp/paper.bib
```

For arXiv papers (faster — no S2 rate limit):

```bash
ss-arxiv.sh 2106.15928 --bibtex > /tmp/paper.bib
```

### Step 3: Import to Zotero

```bash
zotero_import.sh --bibtex /tmp/selected.bib --collection "Literature Review"
```

If BibTeX is unavailable for some papers, fall back to DOI-based import by extracting DOIs from the search results' `externalIds.DOI` field:

```bash
zotero_import.sh --doi "10.1234/example1" "10.1234/example2"
```

## Paper ID Resolution

When the user provides a reference in various formats, resolve it to a usable ID:

- **DOI**: Prefix with `DOI:` → `ss-paper.sh "DOI:10.1109/TBME.2023.1234"`
- **ArXiv**: Use arXiv API (faster) → `ss-arxiv.sh 2106.15928`, or S2 → `ss-paper.sh "ARXIV:2106.15928"`
- **PubMed**: Prefix with `PMID:` → `ss-paper.sh "PMID:19872477"`
- **Title**: Use exact match → `ss-match.sh "exact paper title here"`
- **S2 URL**: Extract paper ID from the URL path

## Integration with paper-summary

After finding papers with this skill, use the `/paper-summary` skill to create detailed summaries:

1. For arXiv papers, use `ss-arxiv.sh <arxiv_id>` which already provides a `pdfUrl` field in its JSON output
2. For non-arXiv papers, use `ss-pdf.sh <DOI>` to resolve a PDF URL via Unpaywall
3. Download the PDF: `curl -L -o paper.pdf "<pdf_url>"`
4. Invoke `/paper-summary` to create a structured Japanese summary

This creates a complete workflow: **discover → filter → read → summarize**.

## Output Formatting Guidelines

### Paper tables

Always include: #, Title, Authors (first + et al.), Year, Citations, Venue.

### Author tables

Include: Name, Affiliation, h-index, Paper count, Citation count.

### Citation network

When presenting citation exploration results, note:
- Direction (forward/backward)
- Depth (1-hop, 2-hop)
- Total found vs. shown
- Sort order used

## Rate Limiting

All scripts share a rate limiter (`_rate_limit.sh`) that automatically enforces a minimum interval between API calls. This is handled at the program level — no manual sleep or pacing is needed when calling scripts.

- Without API key: **60-second default interval** (shared IP-based rate pool, aggressively throttled by S2)
- With `S2_API_KEY` env var: **1-second default interval** (guaranteed rate)
- The interval is configurable via `S2_MIN_INTERVAL` env var
- Scripts auto-retry on HTTP 429 with **exponential backoff** (60s → 120s → 240s → 480s, up to 5 attempts)
- Get an API key at: https://www.semanticscholar.org/product/api#api-key-form

**IMPORTANT**: Without an API key, do NOT call scripts in parallel. Always call sequentially and let the rate limiter handle pacing. Parallel calls will exhaust the shared rate pool and cause prolonged 429 blocks.

To minimize latency, prefer batch endpoints and request only the fields you need.
