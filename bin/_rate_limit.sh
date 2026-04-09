#!/usr/bin/env bash
# _rate_limit.sh — Shared rate limiter for Semantic Scholar API scripts
# Source this file at the top of each script: source "$(dirname "$0")/_rate_limit.sh"
#
# Uses a lockfile to track the last API call timestamp across all scripts.
# Default interval: 60s without API key, 1s with API key.

S2_RATE_LOCK="${TMPDIR:-/tmp}/.s2_rate_limit"
if [[ -n "${S2_API_KEY:-}" ]]; then
  S2_MIN_INTERVAL="${S2_MIN_INTERVAL:-1}"
else
  S2_MIN_INTERVAL="${S2_MIN_INTERVAL:-60}"
fi

ss_rate_wait() {
  local now last_call elapsed wait_time

  # Create lock file if it doesn't exist
  touch "$S2_RATE_LOCK"

  # Use flock to prevent race conditions between concurrent scripts
  (
    flock -x 200

    now=$(date +%s%N)  # nanoseconds
    last_call=$(cat "$S2_RATE_LOCK" 2>/dev/null || echo "0")
    last_call=${last_call:-0}

    if [[ "$last_call" != "0" ]]; then
      elapsed=$(( (now - last_call) / 1000000000 ))  # convert ns to seconds
      if [[ $elapsed -lt $S2_MIN_INTERVAL ]]; then
        wait_time=$(( S2_MIN_INTERVAL - elapsed ))
        echo "Rate limit: waiting ${wait_time}s before API call..." >&2
        sleep "$wait_time"
      fi
    fi

    # Record this call's timestamp
    date +%s%N > "$S2_RATE_LOCK"

  ) 200>"${S2_RATE_LOCK}.flock"
}

# Call after a 429 to record that a backoff period is needed.
# Sets the lock timestamp far enough in the future that the next
# ss_rate_wait() will sleep for $1 seconds (default: S2_MIN_INTERVAL).
ss_rate_backoff() {
  local backoff_secs="${1:-$S2_MIN_INTERVAL}"
  (
    flock -x 200
    # Write a future timestamp so the next ss_rate_wait() will sleep
    local future_ns=$(( $(date +%s%N) + backoff_secs * 1000000000 - S2_MIN_INTERVAL * 1000000000 ))
    echo "$future_ns" > "$S2_RATE_LOCK"
  ) 200>"${S2_RATE_LOCK}.flock"
}
