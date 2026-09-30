#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURES="$ROOT/tests/fixtures"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

export PATH="$FIXTURES:$PATH"
export TMPDIR="$TEST_TMP"
export S2_API_KEY="test-api-key"
export S2_MIN_INTERVAL=0
export MOCK_CURL_ARGS="$TEST_TMP/curl.args"
export MOCK_CURL_STDIN="$TEST_TMP/curl.stdin"
export MOCK_CURL_STATE="$TEST_TMP/curl.state"
export MOCK_SLEEP_ARGS="$TEST_TMP/sleep.args"
export MOCK_CURL_BODY='{"data":[]}'

reset_mock() {
  : > "$MOCK_CURL_ARGS"
  : > "$MOCK_CURL_STDIN"
  : > "$MOCK_CURL_STATE"
  : > "$MOCK_SLEEP_ARGS"
  export MOCK_CURL_CODES=200
  unset MOCK_RETRY_AFTER
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

reset_mock
"$ROOT/plugins/semantic-scholar/bin/ss-search.sh" "PII detection" >/dev/null
grep -q '/paper/search?' "$MOCK_CURL_ARGS" || fail "default search did not use relevance endpoint"
! grep -q '/paper/search/bulk' "$MOCK_CURL_ARGS" || fail "default search unexpectedly used bulk"
grep -q 'fields=title,year,citationCount,authors,venue&limit=20' "$MOCK_CURL_ARGS" || fail "default fields or limit are incorrect"
! grep -q 'test-api-key' "$MOCK_CURL_ARGS" || fail "API key leaked into curl arguments"
grep -q 'x-api-key: test-api-key' "$MOCK_CURL_STDIN" || fail "API key was not sent through curl config"

reset_mock
"$ROOT/plugins/semantic-scholar/bin/ss-search.sh" "PII detection" --bulk --sort citationCount:desc >/dev/null
grep -q '/paper/search/bulk?' "$MOCK_CURL_ARGS" || fail "--bulk did not use bulk endpoint"
! grep -q '&limit=' "$MOCK_CURL_ARGS" || fail "bulk request included unsupported limit"
grep -q 'sort=citationCount:desc' "$MOCK_CURL_ARGS" || fail "bulk sort was not forwarded"

reset_mock
export MOCK_CURL_CODES=429,200
export MOCK_RETRY_AFTER=1
"$ROOT/plugins/semantic-scholar/bin/ss-search.sh" "PII detection" >/dev/null
[[ "$(<"$MOCK_CURL_STATE")" == 2 ]] || fail "429 response was not retried"
[[ "$(<"$MOCK_SLEEP_ARGS")" == 1 ]] || fail "Retry-After was not respected"

reset_mock
export MOCK_CURL_CODES=429,429,429,429,200
"$ROOT/plugins/semantic-scholar/bin/ss-search.sh" "PII detection" >/dev/null
[[ "$(<"$MOCK_CURL_STATE")" == 5 ]] || fail "keyed 429 without Retry-After was not retried until success"
[[ "$(paste -sd, "$MOCK_SLEEP_ARGS")" == 2,4,8,16 ]] || fail "keyed 429 backoff was incorrect"

reset_mock
export MOCK_CURL_CODES=429,200
(unset S2_API_KEY; "$ROOT/plugins/semantic-scholar/bin/ss-search.sh" "PII detection" >/dev/null </dev/null)
[[ "$(<"$MOCK_SLEEP_ARGS")" == 30 ]] || fail "unauthenticated 429 backoff was incorrect"

reset_mock
export MOCK_CURL_CODES=500,200
"$ROOT/plugins/semantic-scholar/bin/ss-search.sh" "PII detection" >/dev/null
[[ "$(<"$MOCK_CURL_STATE")" == 2 ]] || fail "500 response was not retried"
[[ "$(<"$MOCK_SLEEP_ARGS")" == 2 ]] || fail "server-error backoff was incorrect"

printf 'Semantic Scholar CLI tests passed.\n'
