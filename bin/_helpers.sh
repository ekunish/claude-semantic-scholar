#!/usr/bin/env bash
# _helpers.sh — Shared utilities for Semantic Scholar plugin scripts
# Source this file: source "$(dirname "$0")/_helpers.sh"

# Also source rate limiter
source "$(dirname "${BASH_SOURCE[0]}")/_rate_limit.sh"

S2_BASE_URL="https://api.semanticscholar.org/graph/v1"

# --- CLI helpers ---

die() { echo "Error: $*" >&2; exit 1; }

require_arg() {
  local flag="$1" value="${2:-}"
  [[ -n "$value" && "$value" != --* ]] || die "$flag requires an argument"
  echo "$value"
}

# Join remaining positional args into a single space-separated string
# Usage: in the case *) block: query="$query${query:+ }$1"
# (handled inline, not as a function)

# --- S2 API request helpers ---

# Make a GET request to S2 API with retry/backoff
# Usage: s2_get "/paper/search/bulk?query=..." output_file
# Returns: 0 on success (200), 1 on failure
s2_get() {
  local url="$1" tmpfile="$2"
  local max_retries=5 backoff=60

  local curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 30)
  [[ -n "${S2_API_KEY:-}" ]] && curl_args+=(-H "x-api-key: ${S2_API_KEY}")

  for attempt in $(seq 1 $max_retries); do
    ss_rate_wait
    local http_code
    http_code=$(curl "${curl_args[@]}" "${S2_BASE_URL}${url}")

    if [[ "$http_code" == "200" ]]; then
      return 0
    elif [[ "$http_code" == "429" && $attempt -lt $max_retries ]]; then
      echo "Rate limited, retrying in ${backoff}s (attempt $attempt/$max_retries)..." >&2
      sleep "$backoff"
      ss_rate_backoff "$backoff"
      backoff=$(( backoff * 2 ))
    else
      echo "Error: HTTP $http_code" >&2
      cat "$tmpfile" >&2
      return 1
    fi
  done
  return 1
}

# Make a POST request to S2 API with retry/backoff
# Usage: s2_post "/endpoint?fields=..." '{"json":"body"}' output_file
s2_post() {
  local url="$1" body="$2" tmpfile="$3"
  local max_retries=5 backoff=60

  local curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 30
    -X POST -H "Content-Type: application/json" -d "$body")
  [[ -n "${S2_API_KEY:-}" ]] && curl_args+=(-H "x-api-key: ${S2_API_KEY}")

  for attempt in $(seq 1 $max_retries); do
    ss_rate_wait
    local http_code
    http_code=$(curl "${curl_args[@]}" "${S2_BASE_URL}${url}")

    if [[ "$http_code" == "200" ]]; then
      return 0
    elif [[ "$http_code" == "429" && $attempt -lt $max_retries ]]; then
      echo "Rate limited, retrying in ${backoff}s (attempt $attempt/$max_retries)..." >&2
      sleep "$backoff"
      ss_rate_backoff "$backoff"
      backoff=$(( backoff * 2 ))
    else
      echo "Error: HTTP $http_code" >&2
      cat "$tmpfile" >&2
      return 1
    fi
  done
  return 1
}

# URL-encode a string
urlencode() {
  python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1"
}

# Normalize arXiv ID from various formats
normalize_arxiv_id() {
  echo "$1" | sed -E 's#^ARXIV:##i; s#^https?://arxiv\.org/(abs|pdf)/##; s#\?.*##; s##.*##; s#\.pdf$##; s#v[0-9]+$##'
}
