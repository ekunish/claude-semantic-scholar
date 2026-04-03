# claude-semantic-scholar

Claude Code plugin for academic literature search using the [Semantic Scholar API](https://www.semanticscholar.org/product/api).

## Features

- **Keyword search** with boolean operators, year/citation/venue filters
- **Citation network exploration** (forward and backward)
- **Seed-based discovery** via recommendations API
- **Author search** with h-index, papers, affiliations
- **Batch paper retrieval** (up to 500 at once)
- **Systematic review workflow** with PICO framework support
- **Built-in rate limiting** across all scripts

## Installation

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

## Rate Limiting

Without an API key, the shared rate pool is aggressively throttled (60s default interval between calls). For better performance:

1. Get a free API key at https://www.semanticscholar.org/product/api#api-key-form
2. Set `S2_API_KEY` environment variable

## License

MIT
