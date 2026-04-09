# Semantic Scholar API Reference

## Base URLs

| API | Base URL |
|-----|----------|
| Academic Graph | `https://api.semanticscholar.org/graph/v1` |
| Recommendations | `https://api.semanticscholar.org/recommendations/v1` |
| Datasets | `https://api.semanticscholar.org/datasets/v1` |

## Authentication

- Optional: set `S2_API_KEY` environment variable
- Header: `x-api-key: <key>`
- Unauthenticated: shared rate pool (slower under load)
- Authenticated: 1 request/second baseline

## Paper ID Formats

| Format | Example | Prefix |
|--------|---------|--------|
| S2 Paper ID | `649def34f8be52c8b66281af98ae884c09aef38b` | (none) |
| DOI | `DOI:10.18653/v1/N18-3011` | `DOI:` |
| ArXiv | `ARXIV:2106.15928` | `ARXIV:` |
| PubMed | `PMID:19872477` | `PMID:` |
| PubMed Central | `PMCID:2323736` | `PMCID:` |
| Corpus ID | `CorpusId:215416146` | `CorpusId:` |
| MAG | `MAG:112218234` | `MAG:` |
| ACL | `ACL:W12-3903` | `ACL:` |
| URL | `https://arxiv.org/abs/2106.15928` | (full URL) |

Supported URL domains: semanticscholar.org, arxiv.org, aclweb.org, acm.org, biorxiv.org

## Paper Fields

Always returned: `paperId`, `title`

| Field | Type | Notes |
|-------|------|-------|
| `paperId` | string | Always returned |
| `corpusId` | integer | S2 corpus identifier |
| `externalIds` | object | DOI, ArXiv, PMID, etc. |
| `url` | string | S2 URL |
| `title` | string | Always returned |
| `abstract` | string | May be null |
| `venue` | string | Publication venue |
| `publicationVenue` | object | Detailed venue info (id, name, type, url) |
| `year` | integer | Publication year |
| `publicationDate` | string | YYYY-MM-DD format |
| `publicationTypes` | list | JournalArticle, Conference, Review, etc. |
| `referenceCount` | integer | Number of references |
| `citationCount` | integer | Number of citations |
| `influentialCitationCount` | integer | High-impact citations |
| `isOpenAccess` | boolean | Open access status |
| `fieldsOfStudy` | list | e.g., Computer Science, Medicine |
| `s2FieldsOfStudy` | list | S2-specific field classification |
| `authors` | list | `[{authorId, name}]` |
| `citations` | list | Papers citing this paper |
| `references` | list | Papers cited by this paper |
| `embedding` | object | Use `embedding.specter_v2` |
| `tldr` | object | `{model, text}` auto-summary |
| `journal` | object | `{name, volume, pages}` |
| `citationStyles` | object | Formatted citation strings |

### Nested Author Fields (dot notation)

Use with `authors.` prefix: `authorId`, `name`, `url`, `affiliations`, `paperCount`, `citationCount`, `hIndex`

Example: `fields=title,authors.name,authors.hIndex`

### Nested Citation/Reference Fields

Use with `citations.` or `references.` prefix to access paper fields of citing/cited papers.

Example: `fields=citations.title,citations.year,citations.citationCount`

## Endpoints

### Paper Search (Bulk) — Primary search endpoint

```
GET /paper/search/bulk
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `query` | Yes | Search query with boolean syntax |
| `fields` | No | Comma-separated field names |
| `year` | No | Year range: `2020-`, `2018-2023`, `2020` |
| `publicationTypes` | No | `JournalArticle`, `Conference`, `Review`, `CaseReport`, etc. |
| `minCitationCount` | No | Minimum citation threshold |
| `publicationDateOrYear` | No | Date range: `2020-01-01:2023-12-31` |
| `venue` | No | Venue filter |
| `fieldsOfStudy` | No | Field of study filter |
| `token` | No | Continuation token from previous response |
| `sort` | No | `citationCount`, `publicationDate`, `paperId` |

Response: `{total, token, data: [paper, ...]}`
- No hard result limit (paginate with `token`)
- 1000 papers per response

### Paper Search (Relevance) — Ranked by relevance

```
GET /paper/search
```

Same filters as bulk, plus `offset` and `limit` (max 100 per page, 1000 total results).

### Paper Title Match

```
GET /paper/search/match?query=<exact title>
```

Returns the best-matching paper for an exact title string.

### Single Paper

```
GET /paper/{paper_id}?fields=<fields>
```

### Batch Papers

```
POST /paper/batch?fields=<fields>
Body: {"ids": ["id1", "id2", ...]}
```

Max 500 IDs per request.

### Paper Citations (Forward)

```
GET /paper/{paper_id}/citations?fields=<fields>&limit=<n>&offset=<n>
```

Returns papers that cite this paper. Max 1000 per request, 9999 total.
Response: `{offset, next, data: [{citingPaper: {...}, isInfluential, contexts, intents}, ...]}`

### Paper References (Backward)

```
GET /paper/{paper_id}/references?fields=<fields>&limit=<n>&offset=<n>
```

Returns papers cited by this paper. Same limits as citations.
Response: `{offset, next, data: [{citedPaper: {...}, isInfluential, contexts, intents}, ...]}`

### Paper Authors

```
GET /paper/{paper_id}/authors?fields=<fields>&limit=<n>&offset=<n>
```

### Author Search

```
GET /author/search?query=<name>&fields=<fields>&limit=<n>&offset=<n>
```

### Author Details

```
GET /author/{author_id}?fields=<fields>
```

### Author Papers

```
GET /author/{author_id}/papers?fields=<fields>&limit=<n>&offset=<n>
```

### Batch Authors

```
POST /author/batch?fields=<fields>
Body: {"ids": ["id1", "id2", ...]}
```

Max 1000 IDs per request.

### Recommendations (Single Seed)

```
GET /recommendations/v1/papers/forpaper/{paper_id}?fields=<fields>&limit=<n>
```

### Recommendations (Multi-Seed)

```
POST /recommendations/v1/papers?fields=<fields>&limit=<n>
Body: {"positivePaperIds": ["id1", ...], "negativePaperIds": ["id3", ...]}
```

Max 500 recommendations.

## Author Fields

Always returned: `authorId`, `name`

| Field | Type |
|-------|------|
| `authorId` | string |
| `name` | string |
| `url` | string |
| `affiliations` | list |
| `homepage` | string |
| `paperCount` | integer |
| `citationCount` | integer |
| `hIndex` | integer |
| `externalIds` | object (ORCID, DBLP) |
| `papers` | list |

## Boolean Query Syntax

| Operator | Example | Meaning |
|----------|---------|---------|
| `+` | `+machine +learning` | Both terms required |
| `-` | `AI -ethics` | Exclude term |
| `\|` | `(CNN \| ResNet)` | Either term |
| `"..."` | `"heart sound"` | Exact phrase |
| `*` | `phonocard*` | Prefix match |
| `~N` | `murmur~2` | Fuzzy match (edit distance N) |
| `"..." ~N` | `"cardiac auscultation" ~3` | Phrase proximity (terms within N positions) |

Combine: `("heart sound" | phonocardiogram) +classification -fetal`

## HTTP Status Codes

| Code | Meaning | Action |
|------|---------|--------|
| 200 | Success | — |
| 400 | Bad request | Check parameters |
| 404 | Not found | Check paper/author ID |
| 429 | Rate limited | Wait 60s, retry with exponential backoff |
| 500 | Server error | Retry after delay |

## Limits Summary

| Resource | Limit |
|----------|-------|
| Bulk search per call | 1000 papers |
| Relevance search total | 1000 papers |
| Batch papers | 500 IDs |
| Batch authors | 1000 IDs |
| Citations/References | 1000 per call, 9999 total |
| Recommendations | 500 max |
| Response size | 10 MB |
| Rate (authenticated) | 1 req/sec |
