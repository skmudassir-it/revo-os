# Revo OS v1.0.0

**The 13-Megabyte AI-Native Operating System — Bootable USB Image**

Codename: Révo | Built: June 2026 | Kernel: 6.12.94 (Alpine virt) | Arch: x86_64

> *"The 10-Megabyte AI-Native Operating System" — a unikernel that integrates local AI inference at the kernel level, provides built-in Docker support, and matches Ubuntu feature parity via an overlay mesh architecture. Smaller than a single high-resolution photograph.*

---

## v1.0.0 — Bootable Core with Integrity

### What's Included

| Component | Details |
|---|---|
| **Linux kernel 6.12.94** | Stripped virt kernel, EFI stub — the kernel IS the bootloader |
| **Busybox userspace** | 306 applets — shell, networking, filesystem tools |
| **dm-verity integrity** | Cryptographic verification of the data volume at boot — Merkle hash tree, root hash in config |
| **CA certificate bundle** | 30 essential root CAs (39 KB) — ISRG, DigiCert, GlobalSign, Amazon, Google, GoDaddy, Sectigo, Microsoft |
| **Kernel slim config** | `revo-tiny.config` — ~550 options targeting 3–4 MB vmlinuz (source compile path) |
| **11 kernel modules** | ext4, overlay, vfat, loop, virtio-blk, virtio-net, e1000, dm-mod, dm-verity, dm-bufio |
| **Image size** | 13 MB compressed (kernel + initramfs + modules) — 10 MB target with source-compiled kernel |

### Boot Sequence
Revo banner → 11 kernel modules loaded → dm-verity integrity check → CA bundle installed → DHCP on eth0 → Revo data volume mounted → ash shell

---

## Quick Start

```bash
# QEMU (fastest)
qemu-system-x86_64 -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" -nographic

# Bootable USB
python3 build-image.py           # → revo-os-v1.0.0.img (128 MB)
sudo ./setup-usb.sh              # Format + copy kernel/initramfs/modules/certs
sudo dd if=revo-os-v1.0.0.img of=/dev/sdX bs=4M status=progress conv=fsync

# Build custom kernel (10 MB target)
sudo apt install flex bison libelf-dev libssl-dev bc  # prerequisites
./scripts/build-kernel.sh 6.12.21                      # → build/vmlinuz-revo
```

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  USER APPLICATIONS                   │
│  ┌─────────────────┐  ┌──────────────────────────┐   │
│  │  Native Revo    │  │  Docker / OCI Containers  │   │
│  │  (revo-fs)      │  │  (Ubuntu, Alpine, etc.)   │   │
│  └────────┬────────┘  └────────────┬──────────────┘   │
├───────────┼────────────────────────┼──────────────────┤
│           │     REVO CORE (initramfs, ~660 KB)       │
│  ┌────────┴──────┐  ┌──────────────┴─────────────┐   │
│  │   dm-verity   │  │     SSL CA bundle (30)     │   │
│  └────────┬──────┘  └──────────────┬─────────────┘   │
│           └────────────┬───────────┘                  │
│                   revod (PID 1)                       │
├────────────────────────┼──────────────────────────────┤
│           REVO KERNEL (vmlinuz, 12 MB)               │
│  cgroups v2 │ namespaces │ overlayfs │ ext4          │
│  DM_VERITY  │ NVMe       │ virtio    │ net           │
└──────────────────────────────────────────────────────┘
```

---

## Future Updates

| # | Feature | Description |
|---|---|---|
| 1 | **Container runtime built-in** | Static containerd + runc compiled into initramfs (~2 MB). Docker-compatible CLI shim with zero daemon overhead |
| 2 | **Ornet kernel AI inference** | `ornet.ko` kernel module (~500 KB) — model memory manager, tensor dispatch, ring buffer. Ornith-1 9B GGUF on dedicated RevoAI volume |
| 3 | **revo-fs package streaming** | FUSE-like overlay mesh filesystem — BitTorrent-backed on-demand package streaming. Any Ubuntu package available, never pre-installed |
| 4 | **Secure remote access** | Dropbear SSH server (~200 KB), WireGuard kernel module, IPv6 dual-stack |
| 5 | **GPU acceleration** | CUDA/Vulkan passthrough for Ornet inference. Multi-model hot-swap on RevoAI volume. Transparent CPU/GPU tensor offload |
| 6 | **Immutable updates** | Cryptographic signing of core image. A/B partition updates with automatic rollback. Binary delta updates — no full re-download |
| 7 | **Observability dashboard** | Web-based management console. Structured JSON logging from kernel + revod + containerd. Prometheus metrics endpoint |
| 8 | **Multi-architecture** | ARM64 (aarch64) port — Raspberry Pi 5, AWS Graviton, Apple Silicon VMs. RISC-V preview |
| 9 | **Multi-node orchestration** | Revo Mesh peer discovery protocol. Distributed Ornet — split inference across nodes. Lightweight Kubernetes shim without kubelet overhead |
| 10 | **AI-First boot** | Kernel awakens Ornet before filesystem mount — model ready before PID 1. Explicit model/system separation with dedicated integrity verification |

---

## Design Philosophy

| Principle | Meaning |
|---|---|
| **AI-First Boot** | Ornet inference engine awakens before any filesystem mounts — the model is ready before userspace init |
| **Immutable Core, Fluid Everything Else** | 10 MB core is cryptographically signed and read-only; all writable state lives on the Revo volume |
| **Overlay Mesh, Not Package Manager** | No `apt`, no `dnf` — BitTorrent-backed overlay mesh streams packages on first use |
| **Container-Native Userspace** | Primary process model is containers; even native tools run in thin container shims |
| **Explicit Model/System Separation** | The AI model is firmware, not software — dedicated partition with its own integrity verification |

---

## Size Budget

| Component | Size |
|---|---|
| Kernel (vmlinuz-virt, pre-built) | 12 MB |
| Initramfs (cpio.gz — busybox + init + CA certs) | 660 KB |
| Kernel modules (11 × .ko.gz) | 1,050 KB |
| **Total (tarball)** | **~13 MB** |
| Target (source-compiled kernel) | ~4 MB vmlinuz → **~5 MB total** |

---

## Project Structure

```
revo-build/
├── revo-package/
│   ├── vmlinuz-virt              # Pre-built kernel (download from Alpine)
│   ├── initramfs.cpio.gz         # Built initramfs
│   ├── modules/                  # 11 kernel modules (.ko.gz)
│   ├── build-image.py            # GPT disk image builder
│   ├── setup-usb.sh              # USB flash script
│   └── README.md
├── initramfs/
│   ├── init                      # PID 1 init script
│   ├── bin/                      # Busybox symlinks (306 applets)
│   ├── etc/ssl/certs/            # 30 root CAs
│   └── etc/revo/config.json      # v1.0.0 config + verity params
├── scripts/
│   ├── build-kernel.sh           # Kernel source compile pipeline
│   └── generate-verity.py        # dm-verity hash tree generator
├── src/kernel/
│   └── revo-tiny.config          # Minimal kernel config (~550 options)
├── build-image.py                # Root-level builder
├── setup-usb.sh                  # Root-level USB flasher
├── revo-os-blueprint.md          # Full conceptual blueprint
└── revo-os-kernel-blueprint.md   # Kernel-specific blueprint
```

---

## License

| Component | License |
|---|---|
| Linux Kernel | GPL-2.0 |
| Busybox | GPL-2.0 |
| Setup Scripts | MIT |
| Revo Brand & Blueprints | Proprietary — © AMS Ventures |
