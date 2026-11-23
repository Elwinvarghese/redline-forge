# Compact ForgeTrack VM (under 3 GB)

The full Ubuntu Server install is ~3 GB before the app is even added. With a
minimal base and the trim script in `scripts/compact-vm.sh`, the guest uses
**~1.6-1.9 GB** and the exported **OVA lands around 0.9-1.2 GB** — comparable to
Metasploitable 2 and comfortably under 3 GB.

## What "3 GB" means

| Limit type | Target | How |
|---|---|---|
| OVA upload size | 0.9-1.2 GB | trim + zero free space + compressed stream-optimized VMDK |
| Sparse disk file on host | ~1.7 GB | 4 GB dynamically allocated disk, ~1.7 GB used |
| Virtual disk capacity | 4 GB recommended | 3 GB also fits, but leaves little headroom |

A 4 GB *virtual* disk does not consume 4 GB on the host while it is sparse. If
your platform bills virtual capacity, use 3 GB and keep guest usage under
~2 GB. Do not use a fixed/preallocated disk.

## Size budget (measured package sizes)

| Item | Size | Action |
|---|---|---|
| Ubuntu 24.04 minimal rootfs | ~1.2-1.5 GB | required |
| `linux-firmware` | **604 MB** | purge on a VM |
| `snapd` + snaps | **113 MB+** | purge, install via apt only |
| Default swap file | **1-2 GB** | disable + delete |
| APT lists/cache | 50-150 MB | clean, mask apt timers |
| Docs/man/locales | 100-200 MB | delete |
| PostgreSQL 16 + cluster | ~120 MB | required |
| Production Python venv | ~25-35 MB | install only Flask, psycopg2, gunicorn |
| Nginx | ~7 MB | required |
| App + 7 local car images | ~10 MB | required |
| Logs/journal | 20-200 MB | vacuum/truncate |

## Base OS choice

- **Ubuntu Server 24.04 LTS, minimal/cloud image (recommended).** Keeps the
  guide and `apt` commands identical. Comfortably under 3 GB after trimming.
- **Debian 12 genericcloud (smaller).** Cloud image is ~334 MB compressed and
  installs to ~1 GB; final OVA can be under 700 MB. Use if you want the
  absolute smallest image. PostgreSQL is version 15 instead of 16.
- Avoid Alpine for this lab: musl makes `psycopg2` and some Python wheels more
  work than the space is worth.

### Why not Ubuntu 8.04 (the Metasploitable 2 base)?

Ubuntu 8.04 cannot run this application and does not make the VM smaller:

| Blocker | Detail |
|---|---|
| Python | 8.04 ships Python 2.5; Flask 3.1 requires Python >= 3.9 |
| TLS | OpenSSL 0.9.8 cannot reach PyPI or modern mirrors (TLS 1.2 required) |
| Packaging | No systemd; the service unit and `systemctl` steps do not apply |
| PostgreSQL | 8.3 is far older than the app's driver/tooling expects |
| Kernel | 2.6 has many public local-root exploits that bypass the intended `sudo` privesc |
| Hypervisor | Guest Additions/VMware Tools may not build; TryHackMe boot/network support is unreliable |
| Size | Installed 8.04 is ~1.5-2 GB — the same as a trimmed 24.04 |

Metasploitable 2 is small because it is a minimal install on a sparse,
compressed disk, not because of its age. Keep the modern base and get the same
size with trimming.

## 1. Create the VM

- 2 vCPU, 2048 MB RAM
- **4 GB dynamically allocated disk** (3 GB only if capacity is the limit)
- NAT or bridged network, OpenSSH server
- No desktop, no snap packages, no LVM

If you use the Ubuntu **cloud image**, grow the root filesystem to fill the
disk before installing:

```bash
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
```

## 2. Install only what the app needs

```bash
sudo apt update
sudo apt install -y --no-install-recommends \
  nginx postgresql python3-venv iputils-ping ufw ca-certificates
```

Do **not** install `postgresql-contrib`, `python3-pip` system-wide, build
tools, or `linux-firmware`. The venv already contains pip.

## 3. Install the app with a production-only venv

```bash
sudo python3 -m venv /opt/forgetrack/venv
sudo /opt/forgetrack/venv/bin/pip install --no-cache-dir \
  Flask==3.1.0 psycopg2-binary==2.9.10 gunicorn==23.0.0
```

`app/requirements.txt` also pulls `pytest`; skip it in the VM. Do not copy the
repository's `tests/`, `.pytest_cache/`, or `__pycache__/` directories.

PostgreSQL tuning for a 2 GB lab VM (`/etc/postgresql/16/main/postgresql.conf`):

```conf
shared_buffers = 128MB
max_connections = 20
```

## 4. Trim the guest

Copy the script into the VM, then run:

```bash
sudo bash scripts/compact-vm.sh
```

It removes swap, `snapd`, `linux-firmware`, docs/man pages, unused locales,
APT caches, logs, pip caches, and cloud-init (set `KEEP_CLOUD_INIT=1` to keep
it). It then zeroes free space and runs `fstrim`.

Check the result:

```bash
df -h /
sudo du -xh / --max-depth=1 | sort -h | tail -15
```

Expected: **1.6-1.9 GB used** on `/`.

If you want a little more headroom, reduce ext4 reserved blocks:

```bash
sudo tune2fs -m 1 /dev/sda2    # confirm the root device with: findmnt /
```

## 5. Compact and export the disk

### VirtualBox

```bash
# Shut the VM down first.
VBoxManage modifymedium disk "ForgeTrack.vdi" --compact
VBoxManage export ForgeTrack --output ForgeTrack.ova
ls -lh ForgeTrack.ova
```

Exported OVAs use stream-optimized VMDK, which is compressed. If the result is
still too large, re-export with VMware `ovftool`:

```bash
ovftool --compress=9 ForgeTrack.vmx ForgeTrack.ova
```

### VMware

```bash
vmware-vdiskmanager -k ForgeTrack.vmdk
ovftool --compress=9 ForgeTrack.vmx ForgeTrack.ova
```

### QEMU/KVM

```bash
qemu-img convert -O qcow2 -c source.qcow2 compact.qcow2
qemu-img info compact.qcow2
```

For an OVA from QEMU, convert to a stream-optimized VMDK and package it, or use
`ovftool` if available:

```bash
qemu-img convert -O vmdk -o subformat=streamOptimized compact.qcow2 disk.vmdk
```

## 6. Verify before upload

```bash
# Guest usage
df -h /

# OVA size
ls -lh ForgeTrack.ova

# Boot test: import the OVA into a clean VM, start it, then:
curl -I http://127.0.0.1/
systemctl status nginx postgresql forgetrack --no-pager
```

The app and the Phase 2/3 attack chain are unchanged by this; only packaging
changes. Keep `linux-firmware` on any physical machine.
