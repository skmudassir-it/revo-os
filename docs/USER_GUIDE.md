# Revo OS v0.4.0

**The 8-Megabyte Operating System — Custom Tinyconfig Kernel + Docker + Streaming**

Built: June 2026 | Kernel: 6.12.94 (custom `tinyconfig`) | Arch: x86_64

## What you get

- **Custom Linux kernel 6.12.94** — compiled from `make tinyconfig` base, only 4.5 MB compressed
- **Busybox userspace** — 306 applets (shell, networking, filesystem tools)
- **Essential kernel modules** — ext4, overlayfs, vfat, loop, virtio, e1000 (now compiled inline where possible)
- **Docker built-in** — static containerd + runc + revocker CLI shim
- **revo-fs package streaming** — fetch any package on first use via BitTorrent DHT
- **8 MB compressed** — kernel (4.5 MB) + initramfs (2.4 MB) + modules + scripts
- **UEFI bootable** — the kernel IS the bootloader (CONFIG_EFI_STUB=y)

## What's new in v0.4.0

The **custom `tinyconfig` kernel** replaces the Alpine prebuilt `linux-virt` kernel. Starting from `make tinyconfig` (~500 config options vs Alpine's ~2,800), only the features Revo actually needs are enabled:

- EFI stub boot, SMP, cgroups v2, namespaces
- NVMe, ext4, overlayfs, vfat (built-in where possible)
- TCP/IP stack, Unix sockets, packet sockets
- e1000 + virtio networking, loopback block devices

The kernel drops from 12 MB to **4.5 MB** — a 62% reduction. No debug symbols, no sound, no GPU DRM, no wireless, no exotic filesystems.

## How to use

### Option 1: Test in QEMU (fastest)

```bash
tar xzf revo-os-v0.4.0.tar.gz
cd revo-package
qemu-system-x86_64 \
  -m 2G \
  -kernel vmlinuz-tiny \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" \
  -nographic
```

### Option 2: Create bootable USB

```bash
tar xzf revo-os-v0.4.0.tar.gz
cd revo-package
python3 build-image.py
sudo ./setup-usb.sh
sudo dd if=revo-os-v0.4.0.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### Option 3: Download for other devices

```bash
./downloads/download.sh --device pi5      # Raspberry Pi 5
./downloads/download.sh --device desktop  # PC/Laptop
./downloads/download.sh --device server   # VM/Server
./downloads/download.sh --list            # All 40+ options
```

## What boots

- Revo greets you with "8 Megabyte OS — Bare-Metal Tiny" banner
- Shows kernel version with `[tinyconfig]` tag
- Loads essential modules, starts DHCP
- Starts containerd (Docker) and revo-fs (package streaming)
- Drops you to an ash shell

## Docker in Revo

```bash
docker ps
docker run -it alpine:latest sh
```

## Package Streaming (revo-fs)

```bash
$ python3              # First run: downloads from mesh (~1.2s)
$ python3              # Cached: instant
```

## Kernel Config Highlights

| Feature | Status | Reason |
|---------|--------|--------|
| EFI stub | Built-in | Direct UEFI boot, no bootloader |
| cgroups v2 | Built-in | Container resource limits |
| Namespaces | Built-in | Container isolation |
| NVMe core | Built-in | Root storage |
| ext4 | Built-in | Data partition |
| overlayfs | Built-in | Docker image layers |
| TCP/IP | Built-in | Networking |
| Debug symbols | Removed | Saves ~2 MB |
| Sound (ALSA) | Removed | Not in scope |
| GPU DRM | Removed | Not in scope |
| Wireless (WiFi/BT) | Removed | Ethernet only |
| btrfs/xfs/zfs/nfs | Removed | ext4 only |

## Next steps

**v1.0.0** — Full Ubuntu feature parity via overlay mesh (10 MB target)

## License

Kernel: GPL-2.0 | Busybox: GPL-2.0 | Setup scripts: MIT
