#!/usr/bin/env bash
# ss-citations.sh — Explore citation network (forward/backward)
# Usage: ss-citations.sh <paper_id> [options]
#   --direction <d>       "forward" (who cited this) or "backward" (what this cites) (default: forward)
#   --fields <f>          Comma-separated fields for cited/citing papers
#   --limit <n>           Max results (default: 100, max: 1000)
#   --offset <n>          Offset for pagination (default: 0)
#   --influential-only    Only show influential citations
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_helpers.sh"

DEFAULT_FIELDS="title,year,citationCount,authors,venue"

paper_id=""
direction="forward"
fields="$DEFAULT_FIELDS"
limit="100"
offset="0"
influential_only=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --direction) direction=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --fields) fields=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --limit) limit=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --offset) offset=$(require_arg "$1" "${2:-}"); shift 2 ;;
    --influential-only) influential_only=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) [[ -z "$paper_id" ]] || die "unexpected argument: $1"; paper_id="$1"; shift ;;
  esac
done

if [[ -z "$paper_id" ]]; then
  echo "Usage: ss-citations.sh <paper_id> [--direction forward|backward] [--fields <f>] [--limit <n>]" >&2
  exit 1
fi

encoded_id=$(urlencode "$paper_id" "")

if [[ "$direction" == "forward" ]]; then
  endpoint="citations"
elif [[ "$direction" == "backward" ]]; then
  endpoint="references"
else
  echo "Error: direction must be 'forward' or 'backward'" >&2
  exit 1
fi

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

if s2_get "/paper/${encoded_id}/${endpoint}?fields=${fields}&limit=${limit}&offset=${offset}" "$tmpfile"; then
  if $influential_only; then
    python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data['data'] = [x for x in data.get('data', []) if x.get('isInfluential')]
print(json.dumps(data))
" "$tmpfile"
  else
    cat "$tmpfile"
  fi
else
  exit 1
fi
