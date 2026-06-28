# Revo OS v0.3.0

**The 12-Megabyte Operating System — Docker + On-Demand Packages**

Built: June 2026 | Kernel: 6.12.94 (Alpine virt) | Arch: x86_64

## What you get

- **Linux kernel 6.12.94** — stripped virt kernel with EFI stub support
- **Busybox userspace** — 306 applets (shell, networking, filesystem tools)
- **Essential kernel modules** — ext4, overlayfs, vfat, loop, virtio, e1000
- **Docker built-in** — static containerd + runc + revocker CLI shim
- **revo-fs package streaming** — fetch any package on first use via BitTorrent DHT
- **12 MB compressed** — kernel + initramfs + modules + setup scripts
- **UEFI bootable** — the kernel IS the bootloader (CONFIG_EFI_STUB=y)

## How to use

### Option 1: Test in QEMU (fastest)

```bash
tar xzf revo-os-v0.3.0.tar.gz
cd revo-package
qemu-system-x86_64 \
  -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" \
  -nographic
```

### Option 2: Create bootable USB

```bash
# Extract
tar xzf revo-os-v0.3.0.tar.gz
cd revo-package

# Build partition image + flash to USB
python3 build-image.py          # Creates 128 MB GPT image
sudo ./setup-usb.sh             # Formats partitions + copies files

# Write to USB (replace sdX with your USB device)
sudo dd if=revo-os-v0.3.0.img of=/dev/sdX bs=4M status=progress conv=fsync
```

The USB will boot on any UEFI x86_64 machine. Just enable UEFI boot in BIOS.

### Option 3: Manual USB setup

```bash
# Partition USB (assume /dev/sdX)
sudo parted /dev/sdX mklabel gpt
sudo parted /dev/sdX mkpart ESP fat32 1MiB 65MiB
sudo parted /dev/sdX mkpart data ext4 65MiB 100%
sudo parted /dev/sdX set 1 esp on

# Format
sudo mkfs.vfat -F32 /dev/sdX1
sudo mkfs.ext4 /dev/sdX2

# Copy files
sudo mount /dev/sdX1 /mnt
sudo mkdir -p /mnt/EFI/BOOT /mnt/modules
sudo cp vmlinuz-virt /mnt/EFI/BOOT/BOOTX64.EFI
sudo cp initramfs.cpio.gz /mnt/EFI/BOOT/initrd.img
sudo cp modules/*.ko.gz /mnt/modules/
sudo umount /mnt
```

## What boots

- Revo greets you with a banner showing kernel version, CPU cores, RAM
- Loads essential modules from the EFI partition
- Tries DHCP on eth0
- **Starts containerd** — Docker runtime available immediately
- **Starts revo-fs** — connects to BitTorrent DHT mesh for package streaming
- Mounts /dev/sda2 (or nvme0n1p2) as the Revo data volume
- Drops you to an ash shell with `docker` commands and package streaming ready

## Docker in Revo

```bash
# Check Docker status
docker ps

# Pull and run a container
docker run -it alpine:latest sh
```

The `docker` command is provided by **revocker**, a lightweight 100 KB CLI shim that translates Docker commands to containerd instructions.

## Package Streaming (revo-fs)

Revo v0.3.0 introduces **revo-fs** — an on-demand package streaming daemon. Instead of pre-installing packages, revo-fs fetches them from the **Revo Package Mesh** (a BitTorrent DHT network) the first time you run them:

```bash
# First run — revo-fs downloads python3 from the mesh (~15 MB)
$ python3 --version
  [revo-fs] Fetching python3-3.12.7 from mesh...
  [revo-fs] Verified SHA-256 ✓ | Cached to /revo/pkgs/
  Python 3.12.7

# Second run — instant (cached)
$ python3 --version
  Python 3.12.7

# Fetch Node.js
$ node --version
  [revo-fs] Fetching node-22.4.0 from mesh...
  v22.4.0
```

### How revo-fs works

1. You type a command (e.g. `python3`)
2. The shell can't find `python3` in `/bin` — triggers revo-fs
3. revo-fs checks local cache at `/revo/pkgs/`
4. If not cached: queries DHT, downloads `.revo-pkg` (squashfs delta)
5. Verifies SHA-256, mounts via overlay, creates symlink
6. Shell retries — command runs

### Cold start latencies (100 Mbps connection)

| Package | Size | First Use | Cached |
|---------|------|-----------|--------|
| Python 3.12 | ~15 MB | ~1.2s | <50ms |
| Node.js 22 | ~28 MB | ~2.2s | <50ms |
| nginx | ~4 MB | ~0.3s | <50ms |
| git | ~8 MB | ~0.6s | <50ms |
| gcc | ~120 MB | ~10s | <50ms |

### Package sources

| Source | For |
|--------|-----|
| Revo Package Mesh | Revo-native `.revo-pkg` packages |
| Ubuntu archive | `.deb` → converted to squashfs |
| GitHub Releases | Standalone CLI binaries |
| Docker Hub / ghcr.io | Container images via containerd |

## Next steps

This v0.3.0 adds on-demand package streaming to the Docker-equipped base. The next phases:

1. **v0.4.0** — Custom-compiled kernel (`tinyconfig` base, 8 MB target)
2. **v1.0.0** — Full Ubuntu feature parity via overlay mesh (10 MB target)

See the full blueprint: revo-os-kernel-blueprint.md

## License

Kernel: GPL-2.0 | Busybox: GPL-2.0 | Setup scripts: MIT
