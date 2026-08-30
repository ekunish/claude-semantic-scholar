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
  python3 - "$S2_RATE_LOCK" "$S2_MIN_INTERVAL" <<'PY'
import fcntl
import math
import os
import sys
import time

state_path = sys.argv[1]

try:
    interval = float(sys.argv[2])
except ValueError:
    print("S2_MIN_INTERVAL must be a finite non-negative number", file=sys.stderr)
    raise SystemExit(2)

if not math.isfinite(interval) or interval < 0:
    print("S2_MIN_INTERVAL must be a finite non-negative number", file=sys.stderr)
    raise SystemExit(2)

lock_path = f"{state_path}.flock"
state_dir = os.path.dirname(state_path)

if state_dir:
    os.makedirs(state_dir, exist_ok=True)

with open(lock_path, "w") as lock_file:
    fcntl.flock(lock_file, fcntl.LOCK_EX)

    now = time.time()
    last_call = 0.0
    try:
        with open(state_path, "r") as state_file:
            raw_value = state_file.read().strip()
            if raw_value:
                parsed = float(raw_value)
                if math.isfinite(parsed) and parsed > 0:
                    # Releases before 2.1.0 stored Unix time in nanoseconds.
                    # Also accept the common millisecond and microsecond forms
                    # so an existing shared state file cannot cause a huge wait.
                    if parsed >= 1e17:
                        parsed /= 1e9
                    elif parsed >= 1e14:
                        parsed /= 1e6
                    elif parsed >= 1e11:
                        parsed /= 1e3
                    last_call = parsed
    except FileNotFoundError:
        pass
    except ValueError:
        last_call = 0.0

    wait_time = min(interval, max(0.0, interval - (now - last_call)))
    if last_call > 0 and wait_time > 0:
        print(
            f"Rate limit: waiting {math.ceil(wait_time)}s before API call...",
            file=sys.stderr,
        )
        time.sleep(wait_time)

    with open(state_path, "w") as state_file:
        state_file.write(f"{time.time():.6f}\n")
PY
}
