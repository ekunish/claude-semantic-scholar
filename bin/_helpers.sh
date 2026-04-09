#!/usr/bin/env bash
# _helpers.sh — Shared utilities for Semantic Scholar plugin scripts
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

# Also source rate limiter
source "$(dirname "${BASH_SOURCE[0]}")/_rate_limit.sh"

S2_BASE_URL="https://api.semanticscholar.org/graph/v1"

# --- CLI helpers ---

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

require_arg() {
  local flag="$1" value="${2:-}"
  [[ -n "$value" && "$value" != --* ]] || die "$flag requires an argument"
  printf '%s' "$value"
}

# --- S2 API request helpers ---

# Make a GET request to S2 API with retry/backoff
# Usage: s2_get "/paper/search/bulk?query=..." output_file [base_url]
# Returns: 0 on success (200), 1 on failure
s2_get() {
  local url="$1" tmpfile="$2" base="${3:-$S2_BASE_URL}"
  local max_retries=5 backoff=60

  local curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 30)
  [[ -n "${S2_API_KEY:-}" ]] && curl_args+=(-H "x-api-key: ${S2_API_KEY}")

  for ((attempt=1; attempt<=max_retries; attempt++)); do
    ss_rate_wait
    local http_code
    http_code=$(curl "${curl_args[@]}" "${base}${url}") || true
    [[ -z "$http_code" || "$http_code" == "000" ]] && http_code="000"

    if [[ "$http_code" == "200" ]]; then
      return 0
    elif [[ "$http_code" == "429" && $attempt -lt $max_retries ]]; then
      printf 'Rate limited, retrying in %ds (attempt %d/%d)...\n' "$backoff" "$attempt" "$max_retries" >&2
      sleep "$backoff"
      backoff=$(( backoff * 2 ))
    else
      printf 'Error: HTTP %s\n' "$http_code" >&2
      cat "$tmpfile" >&2
      return 1
    fi
  done
  die "All $max_retries retries exhausted"
}

# Make a POST request to S2 API with retry/backoff
# Usage: s2_post "/endpoint?fields=..." '{"json":"body"}' output_file [base_url]
s2_post() {
  local url="$1" body="$2" tmpfile="$3" base="${4:-$S2_BASE_URL}"
  local max_retries=5 backoff=60

  local curl_args=(-s -o "$tmpfile" -w "%{http_code}" --max-time 30
    -X POST -H "Content-Type: application/json" -d "$body")
  [[ -n "${S2_API_KEY:-}" ]] && curl_args+=(-H "x-api-key: ${S2_API_KEY}")

  for ((attempt=1; attempt<=max_retries; attempt++)); do
    ss_rate_wait
    local http_code
    http_code=$(curl "${curl_args[@]}" "${base}${url}") || true
    [[ -z "$http_code" || "$http_code" == "000" ]] && http_code="000"

    if [[ "$http_code" == "200" ]]; then
      return 0
    elif [[ "$http_code" == "429" && $attempt -lt $max_retries ]]; then
      printf 'Rate limited, retrying in %ds (attempt %d/%d)...\n' "$backoff" "$attempt" "$max_retries" >&2
      sleep "$backoff"
      backoff=$(( backoff * 2 ))
    else
      printf 'Error: HTTP %s\n' "$http_code" >&2
      cat "$tmpfile" >&2
      return 1
    fi
  done
  die "All $max_retries retries exhausted"
}

# URL-encode a string. Optional second arg sets safe chars (default: /)
urlencode() {
  local safe="${2:-/}"
  python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=sys.argv[2]))" "$1" "$safe"
}

# Normalize arXiv ID from various formats (URLs, prefixes, version suffixes)
normalize_arxiv_id() {
  echo "$1" | sed -E \
    -e 's%^ARXIV:%%i' \
    -e 's%^https?://arxiv\.org/(abs|pdf)/%%' \
    -e 's%\?.*%%' \
    -e 's%#.*%%' \
    -e 's%\.pdf$%%' \
    -e 's%v[0-9]+$%%'
}
