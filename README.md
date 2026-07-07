# claude-semantic-scholar

Claude Code and Codex plugin for academic literature search using the [Semantic Scholar API](https://www.semanticscholar.org/product/api).

## Features

- **Keyword search** with boolean operators, year/citation/venue filters
- **Title matching** for exact paper lookup
- **Citation network exploration** (forward and backward, with influential-only filter)
- **Seed-based discovery** via recommendations API
- **Author search** with h-index, papers, affiliations
- **Batch retrieval** for papers (up to 500) and authors (up to 1000)
- **BibTeX export** from paper details or batch results
- **Zotero integration** via Search-to-Zotero pipeline (see Optional Dependencies)
- **Systematic review workflow** with PICO framework support
- **Built-in rate limiting** across all scripts

## Installation

### Codex

```
codex plugin marketplace add ekunish/claude-semantic-scholar
codex plugin add semantic-scholar@claude-semantic-scholar
```

Start a new thread after installing so Codex can load the plugin skills and scripts.

### Claude Code

```
/plugin marketplace add ekunish/claude-semantic-scholar
/plugin install semantic-scholar@claude-semantic-scholar
```

## Usage

The skill triggers automatically when you ask about literature search, paper discovery, or citation networks. Examples:

- "phonocardiogram quality assessment の論文を検索して"
- "Find papers about heart sound classification since 2020"
- "この論文を引用している論文を探して: DOI:10.1109/TBME.2023.1234"
- "Recommend papers similar to these seed papers"

## Optional Dependencies

- **[claude-zotero](https://github.com/ekunish/claude-zotero)** — Required for the Search-to-Zotero pipeline (Workflow 6). Enables `ss-batch.sh --bibtex | zotero_import.sh` to import search results directly into Zotero. The `--bibtex` flag itself works standalone and outputs standard BibTeX to stdout.

## Repository Layout

- `plugins/semantic-scholar/.codex-plugin/plugin.json` — Codex plugin manifest
- `plugins/semantic-scholar/.claude-plugin/plugin.json` — Claude Code plugin manifest
- `plugins/semantic-scholar/skills/semantic-scholar/SKILL.md` — Literature search skill
- `plugins/semantic-scholar/bin/` — Semantic Scholar and arXiv helper scripts
- `.agents/plugins/marketplace.json` — Codex marketplace
- `.claude-plugin/marketplace.json` — Claude Code marketplace

## Rate Limiting

Without an API key, the shared rate pool is aggressively throttled (60s default interval between calls). For better performance:

1. Get a free API key at https://www.semanticscholar.org/product/api#api-key-form
2. Set `S2_API_KEY` environment variable

## License

MIT
