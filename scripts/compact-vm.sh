#!/usr/bin/env bash
# compact-vm.sh - shrink a disposable lab VM before exporting an OVA.
# Run inside the VM as root: sudo bash scripts/compact-vm.sh
#
# WARNING: destructive. Intended only for the throwaway ForgeTrack lab VM.
# Do NOT run on bare metal or a machine you care about.

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

VIRT=$(systemd-detect-virt || true)
if [[ "$VIRT" == "none" ]]; then
  echo "ERROR: no virtualisation detected. Refusing to remove firmware/packages." >&2
  exit 1
fi
echo "Virtualisation: $VIRT"

# Path to the project. Override if it was extracted somewhere else:
#   sudo APP_DIR=/home/labadmin/redline-forge bash scripts/compact-vm.sh
APP_DIR="${APP_DIR:-/opt/forgetrack}"
echo "Project directory: $APP_DIR"

export DEBIAN_FRONTEND=noninteractive

echo "==> Removing swap file (saves 1-2 GB in the image)"
swapoff -a || true
sed -i -E '/[[:space:]]swap[[:space:]]/d' /etc/fstab
rm -f /swap.img /swapfile

echo "==> Purging heavy packages that a headless VM does not need"
for pkg in snapd linux-firmware man-db manpages groff-base \
           ubuntu-advantage-tools popularity-contest command-not-found; do
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    echo "  - $pkg"
    apt-get purge -y "$pkg" >/dev/null || true
  fi
done

echo "==> Removing orphaned dependencies"
apt-get autoremove --purge -y >/dev/null || true

echo "==> Disabling apt timers so package lists do not reappear"
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
systemctl mask apt-daily.service apt-daily-upgrade.service >/dev/null 2>&1 || true

echo "==> Clearing package caches and lists"
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/* /var/cache/debconf/*.dat-old
rm -rf /var/lib/snapd /var/cache/snapd /snap

echo "==> Cleaning logs and temporary files"
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-size=1M >/dev/null 2>&1 || true
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
rm -rf /tmp/* /var/tmp/* /root/.cache /home/*/.cache

echo "==> Removing docs, man pages and unused locales"
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/*
find /usr/share/locale -mindepth 1 -maxdepth 1 \
  ! -name 'en*' ! -name 'C*' ! -name 'locale.alias' \
  -exec rm -rf {} + 2>/dev/null || true

echo "==> Cleaning ForgeTrack build artefacts"
if [[ -d "$APP_DIR" ]]; then
  find "$APP_DIR" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
  find "$APP_DIR" -name '*.pyc' -delete 2>/dev/null || true
  rm -rf "$APP_DIR/.pytest_cache" "$APP_DIR/tests" "$APP_DIR/tmp"
  rm -rf /root/.cache/pip /home/*/.cache/pip
fi

# cloud-init is only needed while provisioning. Keep it with KEEP_CLOUD_INIT=1.
if [[ "${KEEP_CLOUD_INIT:-0}" != "1" ]] && dpkg -s cloud-init >/dev/null 2>&1; then
  echo "==> Removing cloud-init"
  cloud-init clean --logs --seed >/dev/null 2>&1 || true
  apt-get purge -y cloud-init >/dev/null 2>&1 || true
  apt-get autoremove --purge -y >/dev/null 2>&1 || true
fi

echo "==> Clearing shell history"
rm -f /root/.bash_history /home/*/.bash_history
history -c 2>/dev/null || true

echo "==> Zeroing free space so the sparse disk/OVA can shrink"
dd if=/dev/zero of=/zerofill bs=1M status=none || true
sync
rm -f /zerofill
sync
fstrim -av 2>/dev/null || true

echo
echo "==> Result"
df -h /
du -xsh --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run / 2>/dev/null || true
echo
echo "Next: compact the virtual disk, then export the OVA."
echo "  VirtualBox: VBoxManage modifymedium disk <disk>.vdi --compact"
echo "  VMware:     vmware-vdiskmanager -k <disk>.vmdk"
echo "  qcow2:      qemu-img convert -O qcow2 -c in.qcow2 out.qcow2"
