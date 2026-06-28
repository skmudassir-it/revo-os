# Revo OS — Technical Specifications

**Version:** 0.3.0 · **Author:** Mudassir  

---

## 1. System Specifications

| Parameter | Value |
|-----------|-------|
| **OS Name** | Revo OS |
| **Version** | 0.3.0 |
| **Architecture** | x86_64 (AMD64) |
| **Boot Method** | UEFI (GPT partition table) |
| **EFI Support** | Native (CONFIG_EFI_STUB=y) |
| **Compressed Size** | 12 MB (tar.gz) |
| **Installed Size** | ~128 MB (disk image with partitions) |
| **Kernel RAM** | ~11 MB (code + data + BSS) |
| **Userspace RAM** | ~8 MB (initramfs + shell + containerd + runc + revo-fs) |
| **Minimum RAM** | 256 MB |
| **Recommended RAM** | 1 GB |
| **Disk Requirement** | 128 MB (one USB drive or disk) |

---

## 2. Kernel Specifications

| Parameter | Value |
|-----------|-------|
| **Kernel Version** | Linux 6.12.94 |
| **Kernel Variant** | virt (Alpine Linux build) |
| **Kernel Build** | `#1-Alpine SMP PREEMPT_DYNAMIC` |
| **Build Date** | 2026-06-23 |
| **Compression** | gzip (bzImage format) |
| **Kernel Size** | 12 MB (compressed), ~28 MB (uncompressed) |
| **Config Options** | ~2,800 (Alpine virt config) |
| **Target Config** | ~500 (future tinyconfig-based build) |

### Key Kernel Features (Built-In)

| Feature | Config | Purpose |
|---------|--------|---------|
| EFI Stub | `CONFIG_EFI_STUB=y` | Boot without separate bootloader |
| EFI Handover | `CONFIG_EFI_HANDOVER_PROTOCOL=y` | UEFI boot protocol |
| SMP | `CONFIG_SMP=y` | Multi-core CPU support |
| Control Groups v2 | `CONFIG_CGROUPS=y` | Resource limits for containers |
| Namespaces | `CONFIG_NAMESPACES=y` | Process isolation |
| devtmpfs | `CONFIG_DEVTMPFS=y` | Auto-create /dev nodes |
| NVMe Core | `CONFIG_NVME_CORE=y` | NVMe storage |
| AHCI SATA | `CONFIG_SATA_AHCI=y` | SATA storage |
| TCP/IP Stack | `CONFIG_INET=y` | IPv4 networking |
| Unix Sockets | `CONFIG_UNIX=y` | Local IPC |
| Packet Socket | `CONFIG_PACKET=y` | Raw network access (DHCP) |

### Kernel Modules (Loadable)

| Module | File | Size (compressed) | Purpose |
|--------|------|-------------------|---------|
| ext4 | `ext4.ko.gz` | 536 KB | Filesystem for data partition |
| overlay | `overlay.ko.gz` | 115 KB | OverlayFS for containers |
| vfat | `vfat.ko.gz` | 16 KB | FAT32 for ESP and USB |
| loop | `loop.ko.gz` | 24 KB | Loopback block devices |
| virtio_blk | `virtio_blk.ko.gz` | 18 KB | VM block driver |
| virtio_net | `virtio_net.ko.gz` | 68 KB | VM network driver |
| e1000 | `e1000.ko.gz` | 96 KB | Intel PRO/1000 NIC driver |
| **Total** | | **~880 KB** | |

---

## 3. Userspace Specifications

| Parameter | Value |
|-----------|-------|
| **Shell** | Busybox ash (POSIX-compatible) |
| **Busybox Version** | 1.37.0 |
| **Linkage** | Static (no dynamic libc dependency) |
| **libc** | musl (embedded in busybox static binary) |
| **Busybox Size** | 1.0 MB (stripped static binary) |
| **Available Applets** | 306 |
| **Init System** | Shell script (/init, ~2 KB) |
| **Initramfs Format** | cpio (newc) + gzip |
| **Initramfs Size** | 631 KB (compressed), ~1.1 MB (uncompressed) |

### Busybox Applet Categories

| Category | Count | Key Applets |
|----------|-------|-------------|
| Shell | 1 | ash (POSIX shell) |
| Filesystem | 40 | mount, umount, df, du, ls, cp, mv, rm, mkdir, ln, chmod, chown |
| Text Processing | 30 | cat, grep, awk, sed, vi, head, tail, wc, sort, cut, tr |
| Compression | 8 | gzip, gunzip, tar, bzip2, xz |
| Networking | 25 | ip, ifconfig, ping, wget, udhcpc, route, netstat |
| Process | 10 | ps, kill, top, nice, nohup |
| System | 20 | init, reboot, halt, dmesg, insmod, lsmod, modprobe |
| Disk | 8 | fdisk, mkfs, dd, sync, losetup |
| Misc | 164 | date, echo, sleep, true, false, test, expr, bc |

### Container Runtime

| Component | Binary | Size | Purpose |
|-----------|--------|------|---------|
| containerd | `/bin/containerd` | ~1.5 MB | Container lifecycle manager (gRPC, image pull, task execution) |
| runc | `/bin/runc` | ~0.5 MB | OCI runtime (namespace creation, cgroups, rootfs pivot) |
| revocker | `/bin/docker` | ~0.1 MB | Docker CLI compatibility shim (translates to containerd commands) |

### Package Streaming (revo-fs)

| Component | Binary | Size | Purpose |
|-----------|--------|------|---------|
| revo-fs | `/bin/revo-fs` | ~0.3 MB | On-demand package streaming daemon (FUSE + BitTorrent DHT) |
| Package format | `.revo-pkg` | varies | Squashfs delta with full-path file tree |
| DHT protocol | Mainline DHT (Kademlia) | — | BitTorrent-based peer discovery |
| Transfer protocol | BitTorrent v2 | — | infohash = SHA-256 of file tree |

### Package Sources

| Source | Protocol | For |
|--------|----------|-----|
| Revo Package Mesh | BitTorrent DHT + HTTPS seeds | Revo-native `.revo-pkg` packages |
| Ubuntu archive | HTTPS → `.deb` → convert to squashfs | Debian/Ubuntu packages |
| GitHub Releases | HTTPS → extract → squashfs | CLI tools, standalone binaries |
| ghcr.io / Docker Hub | OCI pull → extract layer | Containerized tools |

---

## 4. Partition Schema

| Partition | Type | GUID | Size | Filesystem | Contents |
|-----------|------|------|------|------------|----------|
| 1 (ESP) | EFI System | `C12A7328-F81F-11D2-...` | 64 MB | FAT32 | Kernel, initramfs, modules |
| 2 (Data) | Linux Filesystem | `0FC63DAF-8483-4772-...` | 62 MB | ext4 | User data, persistent storage |

### ESP File Layout

```
EFI/
└── BOOT/
    ├── BOOTX64.EFI         ← Linux kernel as EFI executable (12 MB)
    └── initrd.img           ← Initramfs cpio archive (631 KB)
modules/
├── ext4.ko.gz               (536 KB)
├── overlay.ko.gz             (115 KB)
├── vfat.ko.gz                (16 KB)
├── loop.ko.gz                (24 KB)
├── virtio_blk.ko.gz          (18 KB)
├── virtio_net.ko.gz          (68 KB)
└── e1000.ko.gz               (96 KB)
loader/
└── entries/
    └── revo.conf            ← Boot entry for systemd-boot
```

---

## 5. Boot Time Performance

| Phase | Duration | Description |
|-------|----------|-------------|
| UEFI → Kernel entry | ~100 ms | Firmware loads BOOTX64.EFI |
| Kernel decompression | ~200 ms | gzip decompression of bzImage |
| Kernel initialization | ~300 ms | CPU, memory, PCI, storage |
| Initramfs extraction | ~100 ms | cpio decompression to tmpfs |
| Init script execution | ~250 ms | Mount filesystems, load modules |
| Network configuration | ~500 ms | DHCP discover + offer exchange |
| containerd startup | ~200 ms | Container runtime initialization |
| revo-fs startup | ~150 ms | FUSE mount + DHT bootstrap |
| **Total to shell** | **~1.9 seconds** | Interactive prompt + Docker + streaming ready |

*Measured on QEMU with 2 vCPUs, NVMe storage, 2 GB RAM*

---

## 6. Dependencies

### Build-Time Dependencies

| Tool | Version | Required For |
|------|---------|-------------|
| Python 3 | 3.8+ | GPT image builder |
| Bash | 4.0+ | Setup scripts |
| Busybox or cpio | any | Initramfs packaging |
| gzip | any | Initramfs compression |
| mkfs.vfat | any (dosfstools) | ESP formatting |
| mkfs.ext4 | any (e2fsprogs) | Data partition formatting |
| losetup | any (util-linux) | Loopback device management |
| wget | any | Downloading Alpine packages |

### Runtime Dependencies

Revo OS v0.3.0 has **zero runtime dependencies**. The kernel and initramfs are fully self-contained. containerd, runc, revocker, and revo-fs are statically compiled and included in the initramfs. Additional packages (Python, Node.js, etc.) are streamed on-demand via revo-fs.

---

## 7. Hardware Compatibility

### Supported Storage Controllers

- NVMe (any)
- AHCI SATA (any)
- VirtIO block (QEMU/VirtualBox/Hyper-V)

### Supported Network Controllers

- Intel PRO/1000 (e1000) — physical cards and QEMU default
- VirtIO network (QEMU/VirtualBox)

### Supported CPU Features

- x86_64 (long mode)
- SSE, SSE2, AVX (for kernel)
- SMP (multi-core)

### Minimum Requirements

- 64-bit x86 CPU (Intel Core 2 or newer, any AMD64)
- 128 MB RAM
- UEFI firmware (for direct boot; BIOS boot requires GRUB not yet packaged)
- 128 MB storage (USB 2.0 or faster)

---

## 8. Security Specifications

| Feature | Status |
|---------|--------|
| dm-verity integrity | Planned (v0.3.0) |
| Secure Boot signing | Planned (v0.3.0) |
| Kernel module signing | Not implemented |
| Userspace ASLR | Enabled (kernel default) |
| Stack canaries | Enabled (kernel default) |
| Read-only initramfs | Implemented (tmpfs, never written to) |

---

## 9. Known Limitations

| Limitation | Impact | Resolution |
|------------|--------|------------|
| No WiFi support | Ethernet-only networking | Load WiFi modules from data partition |
| No xHCI (USB 3.0) | USB 3.0 devices may not work | xHCI module planned for v0.3.0 |
| No sound | No audio output | Not in scope for minimal OS |
| No GPU acceleration | Framebuffer-only display | GPU passthrough to containers (future) |
| No IPv6 | IPv4 only | Load IPv6 module from data partition |
| No hibernation | Power-off only | Not in scope for minimal OS |

---

*Document version: 1.0 · Last updated: June 2026*
