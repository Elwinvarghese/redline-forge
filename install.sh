#!/usr/bin/env bash
#
# ForgeTrack lab installer for Ubuntu Server 20.04 / 22.04 / 24.04 LTS.
#
# Usage:
#   sudo bash install.sh              # install / repair
#   sudo bash install.sh --reset      # rebuild the database and flags
#   sudo bash install.sh --no-privesc # skip the weak sudo rule
#   sudo bash install.sh --no-flags   # skip the user/root flag files
#
# Ubuntu 20.04 ships Python 3.8 and PostgreSQL 12. This installer selects a
# Python 3.8-compatible dependency set and avoids PostgreSQL 16-only commands,
# so the same script works on 20.04, 22.04, and 24.04.
#
# WARNING: this installs an intentionally vulnerable web app, a command
# injection endpoint, and a passwordless sudo rule for www-data. Run it only
# inside the disposable TryHackMe lab VM.

set -euo pipefail

APP_DIR=/opt/forgetrack
SERVICE=forgetrack
DB_NAME=forgetrack
DB_APP_USER=forge_app
DB_APP_PASS=forge_app_lab_password
DB_OWNER_USER=forge_owner
DB_OWNER_PASS=forge_owner_lab_password

USER_FLAG="${USER_FLAG:-THM{REPLACE_USER_FLAG}}"
ROOT_FLAG="${ROOT_FLAG:-THM{REPLACE_ROOT_FLAG}}"

RESET=0
PRIVESC=1
FLAGS=1
UFW_ENABLE=1

usage() {
  cat <<'EOF'
ForgeTrack lab installer for Ubuntu Server 20.04 / 22.04 / 24.04 LTS.

Usage:
  sudo bash install.sh              # install / repair
  sudo bash install.sh --reset      # rebuild the database and flags
  sudo bash install.sh --no-privesc # skip the weak sudo rule
  sudo bash install.sh --no-flags   # skip the user/root flag files
  sudo bash install.sh --no-ufw     # do not enable the firewall

WARNING: this installs an intentionally vulnerable web app, a command
injection endpoint, and a passwordless sudo rule for www-data. Run it only
inside the disposable TryHackMe lab VM.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --reset) RESET=1 ;;
    --no-privesc) PRIVESC=0 ;;
    --no-flags) FLAGS=0 ;;
    --no-ufw) UFW_ENABLE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

log() { printf '\n==> %s\n' "$*"; }

# Never rsync a source tree that lives inside the destination (or vice versa).
if [[ "$SRC_DIR" == "$APP_DIR"/* || "$APP_DIR" == "$SRC_DIR"/* ]]; then
  echo "ERROR: the project is inside $APP_DIR." >&2
  echo "Extract it under /tmp and run the installer from there:" >&2
  echo "  sudo mv $SRC_DIR /tmp/redline-forge" >&2
  echo "  sudo bash /tmp/redline-forge/install.sh" >&2
  exit 1
fi

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "Installing on: ${PRETTY_NAME:-unknown}"
fi

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------
log "Installing packages"
export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -qq; then
  echo "ERROR: apt-get update failed." >&2
  echo "Ubuntu 20.04 is past its standard support window; if the classic" >&2
  echo "repositories are unavailable, enable Ubuntu Pro/ESM or point APT at" >&2
  echo "the old-releases archive, then re-run this installer." >&2
  exit 1
fi
apt-get install -y -qq --no-install-recommends \
  nginx postgresql python3 python3-venv python3-pip iputils-ping ufw \
  ca-certificates curl rsync unzip openssl sudo

# ---------------------------------------------------------------------------
# 2. Application files
# ---------------------------------------------------------------------------
if [[ ! -f "$SRC_DIR/app/lab_diagnostics.py" \
   || ! -f "$SRC_DIR/database/init.sql" \
   || ! -f "$SRC_DIR/database/seed.sql" ]]; then
  echo "ERROR: the project is incomplete." >&2
  echo "Expected app/lab_diagnostics.py and database/{init,seed}.sql." >&2
  echo "Re-download the current project folder." >&2
  exit 1
fi

if [[ "$SRC_DIR" != "$APP_DIR" ]]; then
  log "Copying application to $APP_DIR"
  mkdir -p "$APP_DIR"
  rsync -a --delete \
    --exclude venv \
    --exclude __pycache__ \
    --exclude .pytest_cache \
    --exclude .git \
    --exclude output \
    "$SRC_DIR"/ "$APP_DIR"/
else
  log "Application already lives in $APP_DIR"
fi

if [[ ! -f "$APP_DIR/database/init.sql" || ! -f "$APP_DIR/database/seed.sql" ]]; then
  echo "ERROR: database/init.sql or database/seed.sql is missing." >&2
  echo "Re-download the complete project folder." >&2
  exit 1
fi

if [[ ! -f "$APP_DIR/app/lab_diagnostics.py" ]]; then
  echo "ERROR: app/lab_diagnostics.py is missing." >&2
  echo "This is the intended foothold; re-download the current project folder." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 3. Python venv
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is not installed." >&2
  exit 1
fi

PY_VERSION=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
PY_MAJOR=$(python3 -c 'import sys; print(sys.version_info[0])')
PY_MINOR=$(python3 -c 'import sys; print(sys.version_info[1])')

if (( PY_MAJOR < 3 || (PY_MAJOR == 3 && PY_MINOR < 8) )); then
  echo "ERROR: Python ${PY_VERSION} detected; Python 3.8 or newer is required." >&2
  exit 1
fi

VENV_PY="$APP_DIR/venv/bin/python"
rebuild_venv=0
if [[ ! -x "$VENV_PY" ]]; then
  rebuild_venv=1
else
  venv_version=$("$VENV_PY" -c \
    'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo unknown)
  if [[ "$venv_version" != "$PY_VERSION" ]]; then
    log "Rebuilding virtualenv (found Python ${venv_version}, need ${PY_VERSION})"
    rebuild_venv=1
  fi
fi

if [[ "$rebuild_venv" == "1" ]]; then
  rm -rf "$APP_DIR/venv"
  log "Creating virtualenv with Python ${PY_VERSION}"
  python3 -m venv "$APP_DIR/venv"
fi

VENV_PY="$APP_DIR/venv/bin/python"
log "Installing Python dependencies"
if (( PY_MAJOR == 3 && PY_MINOR == 8 )); then
  # Ubuntu 20.04 ships Python 3.8. Flask 3.x requires Python >= 3.9, so use
  # the last Flask 2.3.x line. Werkzeug 2.3.x is required for the scrypt
  # password hashes in database/seed.sql.
  "$VENV_PY" -m pip install -q --upgrade 'pip<25'
  "$VENV_PY" -m pip install -q --no-cache-dir \
    'Flask==2.3.3' \
    'Werkzeug==2.3.7' \
    'Jinja2==3.1.4' \
    'MarkupSafe==2.1.5' \
    'itsdangerous==2.1.2' \
    'click==8.1.7' \
    'blinker==1.6.2' \
    'importlib-metadata==6.7.0' \
    'zipp==3.15.0' \
    'psycopg2-binary==2.9.10' \
    'gunicorn==23.0.0'
else
  "$VENV_PY" -m pip install -q --upgrade pip
  "$VENV_PY" -m pip install -q --no-cache-dir \
    'Flask==3.1.0' \
    'psycopg2-binary==2.9.10' \
    'gunicorn==23.0.0'
fi

# ---------------------------------------------------------------------------
# 4. Environment file
# ---------------------------------------------------------------------------
if [[ ! -f /etc/forgetrack.env ]]; then
  log "Writing /etc/forgetrack.env"
  SECRET_KEY=$(openssl rand -hex 32)
  cat > /etc/forgetrack.env <<EOF
DATABASE_URL=postgresql://${DB_APP_USER}:${DB_APP_PASS}@127.0.0.1:5432/${DB_NAME}
SECRET_KEY=${SECRET_KEY}
PYTHONUNBUFFERED=1
PYTHONDONTWRITEBYTECODE=1
EOF
fi
# Repair: add the bytecode setting to env files written by older installers.
if ! grep -q '^PYTHONDONTWRITEBYTECODE=' /etc/forgetrack.env; then
  echo 'PYTHONDONTWRITEBYTECODE=1' >> /etc/forgetrack.env
fi
chown root:root /etc/forgetrack.env
chmod 600 /etc/forgetrack.env

# ---------------------------------------------------------------------------
# 5. PostgreSQL
# ---------------------------------------------------------------------------
log "Configuring PostgreSQL"
systemctl enable --now postgresql || true

# Some minimal/cloud Ubuntu images install the postgresql package without
# creating the default cluster. Create one so the service has something to run.
if command -v pg_lsclusters >/dev/null 2>&1 \
   && [[ -z "$(pg_lsclusters -h 2>/dev/null)" ]]; then
  pg_major=$(ls -1 /usr/lib/postgresql 2>/dev/null | sort -V | tail -n1)
  if [[ -n "$pg_major" ]]; then
    log "Creating PostgreSQL ${pg_major}/main cluster"
    pg_createcluster "$pg_major" main --start
  fi
fi

# Wait for PostgreSQL to accept connections (slow disks / first start).
pg_ready=0
for _ in $(seq 1 30); do
  if sudo -u postgres psql -tAc 'SELECT 1' >/dev/null 2>&1; then
    pg_ready=1
    break
  fi
  sleep 1
done
if [[ "$pg_ready" != "1" ]]; then
  echo "ERROR: PostgreSQL did not become ready." >&2
  echo "Check 'pg_lsclusters'. If no cluster exists, create one with:" >&2
  echo "  pg_createcluster <version> main --start" >&2
  systemctl status postgresql --no-pager || true
  exit 1
fi

db_exists=$(sudo -u postgres psql -tAc \
  "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" || true)

schema_exists=""
if [[ "$db_exists" == "1" ]]; then
  schema_exists=$(sudo -u postgres psql -d "$DB_NAME" -tAc \
    "SELECT 1 FROM pg_namespace WHERE nspname='forge'" || true)
fi

if [[ "$RESET" == "1" || "$db_exists" != "1" || "$schema_exists" != "1" ]]; then
  log "Loading schema and seed data"
  systemctl stop "$SERVICE" >/dev/null 2>&1 || true

  # PostgreSQL 12 (Ubuntu 20.04) has no `dropdb --force`, so terminate
  # sessions first on older servers.
  pg_version_num=$(sudo -u postgres psql -tAc 'SHOW server_version_num' \
    | tr -d '[:space:]')
  if [[ "$pg_version_num" =~ ^[0-9]+$ ]] && (( pg_version_num >= 130000 )); then
    sudo -u postgres dropdb --if-exists --force "$DB_NAME"
  else
    sudo -u postgres psql -tAc \
      "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
       WHERE datname = '${DB_NAME}' AND pid <> pg_backend_pid()" \
      >/dev/null 2>&1 || true
    sudo -u postgres dropdb --if-exists "$DB_NAME"
  fi

  sudo -u postgres dropuser --if-exists "$DB_APP_USER"
  sudo -u postgres dropuser --if-exists "$DB_OWNER_USER"
  sudo -u postgres createdb "$DB_NAME"
  sudo -u postgres psql -q -d "$DB_NAME" -v ON_ERROR_STOP=1 \
    -f "$APP_DIR/database/init.sql"
  sudo -u postgres psql -q -d "$DB_NAME" -v ON_ERROR_STOP=1 \
    -f "$APP_DIR/database/seed.sql"
else
  log "Database already initialised; keeping data (use --reset to rebuild)"
fi

# ---------------------------------------------------------------------------
# 6. Permissions
# ---------------------------------------------------------------------------
log "Setting ownership and permissions"
chown -R root:www-data "$APP_DIR"
chmod -R u=rwX,g=rX,o= "$APP_DIR"

# ---------------------------------------------------------------------------
# 7. systemd service
# ---------------------------------------------------------------------------
log "Installing systemd service"
cat > "/etc/systemd/system/${SERVICE}.service" <<'EOF'
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

systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null
if ! systemctl restart "$SERVICE"; then
  echo "ERROR: ${SERVICE} failed to start. Recent logs:" >&2
  journalctl -u "$SERVICE" -n 50 --no-pager || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 8. Nginx
# ---------------------------------------------------------------------------
log "Configuring Nginx"
if systemctl is-active --quiet apache2 2>/dev/null; then
  systemctl disable --now apache2 >/dev/null 2>&1 || true
fi

cat > /etc/nginx/sites-available/forgetrack <<'EOF'
server {
    listen 80 default_server;
    #IPV6_LISTEN#
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

# Only listen on IPv6 when the kernel actually has IPv6 enabled; otherwise
# nginx fails to start on hosts booted with ipv6.disable=1.
if [[ -e /proc/net/if_inet6 ]]; then
  sed -i 's|^    #IPV6_LISTEN#$|    listen [::]:80 default_server;|' \
    /etc/nginx/sites-available/forgetrack
else
  sed -i '/^    #IPV6_LISTEN#$/d' /etc/nginx/sites-available/forgetrack
fi

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/forgetrack /etc/nginx/sites-enabled/forgetrack

if [[ ! -L /etc/nginx/sites-enabled/forgetrack \
   || -e /etc/nginx/sites-enabled/default ]]; then
  echo "ERROR: the ForgeTrack nginx site is not enabled correctly." >&2
  ls -l /etc/nginx/sites-enabled/ >&2 || true
  exit 1
fi

nginx -t
systemctl enable --now nginx >/dev/null
systemctl reload nginx

# ---------------------------------------------------------------------------
# 9. Intentionally weak sudo rule
# ---------------------------------------------------------------------------
if [[ "$PRIVESC" == "1" ]]; then
  log "Installing weak sudo rule for www-data"
  cat > /etc/sudoers.d/90-forgetrack-diag <<'EOF'
# INTENTIONALLY WEAK LAB RULE - www-data can run Python as root.
Defaults:www-data !authenticate
www-data ALL=(root) NOPASSWD: /usr/bin/python3
EOF
  chmod 0440 /etc/sudoers.d/90-forgetrack-diag
  visudo -cf /etc/sudoers.d/90-forgetrack-diag >/dev/null
fi

# ---------------------------------------------------------------------------
# 10. Flags
# ---------------------------------------------------------------------------
if [[ "$FLAGS" == "1" ]]; then
  log "Creating lab accounts and flags"
  if ! id forge >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" forge >/dev/null
  fi
  passwd -l forge >/dev/null 2>&1 || true

  if [[ ! -f /home/forge/user.txt || "$RESET" == "1" ]]; then
    printf '%s\n' "$USER_FLAG" > /home/forge/user.txt
  fi
  chown root:www-data /home/forge/user.txt
  chmod 640 /home/forge/user.txt
  chmod 755 /home/forge

  if [[ ! -f /root/root.txt || "$RESET" == "1" ]]; then
    printf '%s\n' "$ROOT_FLAG" > /root/root.txt
  fi
  chmod 400 /root/root.txt
fi

# ---------------------------------------------------------------------------
# 11. Login banner (show the lab IP without running ip/ifconfig)
# ---------------------------------------------------------------------------
log "Installing login banner"
cat > /etc/update-motd.d/20-lab-ip <<'EOF'
#!/bin/sh
# Managed by the ForgeTrack installer: show the lab URL on login.
ip4=$(ip -4 -o addr show scope global 2>/dev/null \
    | awk '$2 !~ /^(docker|veth|br-|virbr|tun|tap|wg)/ { sub(/\/.*/, "", $4); print $4; exit }')
if [ -z "$ip4" ]; then
  ip4=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
[ -n "$ip4" ] || exit 0
printf '\n  Lab IPv4:    %s\n  ForgeTrack:  http://%s/\n' "$ip4" "$ip4"
EOF
chmod 755 /etc/update-motd.d/20-lab-ip

# Refresh the cached MOTD so the address shows on the next login.
if command -v run-parts >/dev/null 2>&1; then
  run-parts /etc/update-motd.d > /run/motd.dynamic 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 12. Firewall
# ---------------------------------------------------------------------------
if [[ "$UFW_ENABLE" == "1" ]] && command -v ufw >/dev/null 2>&1; then
  log "Configuring UFW"
  ufw allow OpenSSH >/dev/null 2>&1 || true
  ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow 80/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 13. Smoke test
# ---------------------------------------------------------------------------
log "Running smoke tests"
body_file=$(mktemp)
served=0
last_code=""
for _ in $(seq 1 30); do
  last_code=$(curl -s -o "$body_file" -w '%{http_code}' --max-time 2 \
    http://127.0.0.1/ 2>/dev/null || true)
  if [[ "$last_code" == "200" ]] && grep -qi 'ForgeTrack' "$body_file"; then
    served=1
    break
  fi
  sleep 1
done

if [[ "$served" != "1" ]]; then
  echo "ERROR: nginx responded with HTTP ${last_code:-none}, but did not" >&2
  echo "serve ForgeTrack. The default nginx page also returns HTTP 200," >&2
  echo "so this can mean the lab vhost is missing, or the app did not start." >&2
  echo "Check:" >&2
  echo "  ls -l /etc/nginx/sites-enabled/" >&2
  echo "  nginx -t" >&2
  echo "  journalctl -u ${SERVICE} -n 50 --no-pager" >&2
  echo "  curl -sS http://127.0.0.1:8080/ | head" >&2
  rm -f "$body_file"
  journalctl -u "$SERVICE" -n 50 --no-pager || true
  exit 1
fi
rm -f "$body_file"

injection=$(curl -s --get --data-urlencode 'host=127.0.0.1; id' \
  http://127.0.0.1/diagnostics/ping || true)

echo
echo "ForgeTrack is installed."
echo "  URL:         http://<VM_IP>/"
echo "  Diagnostics: http://<VM_IP>/diagnostics"
echo "  Service:     systemctl status ${SERVICE}"
echo
echo "Seeded logins:"
echo "  pitwall.27    ForgePitwall27!"
echo "  nova.88       ForgeNova88!"
echo "  vortex.41     ForgeVortex41!"
echo "  slipstream.09 ForgeSlipstream09!"
echo "  sora.kade     ForgeSoraKade!"
echo

if printf '%s' "$injection" | grep -q 'uid='; then
  echo "Command injection check: $(printf '%s' "$injection" | grep -o 'uid=[^<]*' | head -1)"
else
  echo "WARNING: command injection check returned no uid; inspect /diagnostics/ping."
fi

if [[ "$FLAGS" == "1" ]]; then
  echo
  echo "Flags:"
  echo "  /home/forge/user.txt  $(cat /home/forge/user.txt)"
  echo "  /root/root.txt        $(cat /root/root.txt)"
  echo "  Replace the placeholders with your TryHackMe flag values."
fi

echo
echo "Before exporting the OVA, run:"
echo "  sudo bash ${APP_DIR}/scripts/compact-vm.sh"
echo
echo "Then remove the spoilers:"
echo "  sudo rm -rf ${APP_DIR}/docs ${APP_DIR}/database ${APP_DIR}/tests"
