# 🌀 Revo OS v1.1.0 — The 13-Megabyte AI-Native Operating System

**Developed and coded by [Mudassir](https://github.com/skmudassir-it)**  
*Conceived June 2026 · Built from scratch · Kernel 6.12.94 · x86_64 UEFI*

[![OS Size](https://img.shields.io/badge/size-13_MB-00cc66)](https://github.com/skmudassir-it/revo-os)
[![Kernel](https://img.shields.io/badge/kernel-6.12.94-blue)](https://www.kernel.org)
[![Status](https://img.shields.io/badge/status-v1.1.0-brightgreen)](https://github.com/skmudassir-it/revo-os)
[![dm-verity](https://img.shields.io/badge/integrity-dm--verity-orange)](https://github.com/skmudassir-it/revo-os)
[![SSL](https://img.shields.io/badge/TLS-CA_bundle-2496ED)](https://github.com/skmudassir-it/revo-os)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## Project Overview

**Revo OS** answers a single provocative question: *how small can a fully functional Linux OS be while remaining genuinely useful?* The answer, as of v1.1.0, is **13 megabytes** — a bootable UEFI-native operating system with cryptographic integrity verification, a TLS-ready CA bundle, and a self-contained kernel build pipeline targeting 10 MB.

Revo boots from a single immutable image smaller than a high-resolution photograph. It is not a toy — it is a real operating system built on Linux 6.12.94 with a Busybox userspace of 306 Unix utilities, dm-verity data integrity, and a minimal SSL certificate store.

### What Revo IS (v1.1.0)

- A bootable UEFI x86_64 operating system
- A Busybox-powered Linux environment with an interactive shell
- dm-verity cryptographic integrity verification at boot
- 30 essential root CA certificates for TLS support
- 11 kernel modules (ext4, overlay, virtio, dm-verity stack)
- A source-compile kernel pipeline targeting 3–4 MB vmlinuz (`revo-tiny.config`)
- A foundation for embedded, container, and edge computing

### What Revo IS NOT (yet)

- A desktop OS with a GUI
- A production server OS
- A Docker/container runtime (planned — see future updates)
- A drop-in Ubuntu replacement (planned — see future updates)

---

## Quick Start

### Test in QEMU (30 seconds)

```bash
tar xzf revo-os-v1.1.0.tar.gz
cd revo-package
qemu-system-x86_64 -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" -nographic
```

### Flash to USB

```bash
python3 build-image.py           # → revo-os-v1.1.0.img (128 MB GPT)
sudo ./setup-usb.sh              # Format ESP + copy kernel/initramfs/modules/certs
sudo dd if=revo-os-v1.1.0.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### Build Custom Kernel (10 MB target)

```bash
sudo apt install flex bison libelf-dev libssl-dev bc   # prerequisites
./scripts/build-kernel.sh 6.12.21                       # → build/vmlinuz-revo (~4 MB)
```

---

## Boot Experience

```
  ╔══════════════════════════════════════╗
  ║        🌀 REVO OS v1.1.0            ║
  ║  The 10-Megabyte Operating System    ║
  ╚══════════════════════════════════════╝

  Kernel : 6.12.94-0-virt
  Arch   : x86_64
  CPU    : 4 cores
  RAM    : 2048 MB

  [OK] dm-mod
  [OK] dm-verity
  [OK] ext4
  [OK] overlay
  [OK] virtio_blk
  [OK] virtio_net
  [--] dm-verity: Verifying data integrity...
  [OK] Revo volume: /dev/vda2 -> /revo
  [OK] SSL CA bundle: 30 certs
  [OK] eth0: DHCP

  ┌──────────────────────────────────────────────┐
  │  Revo v1.1 ready — integrity + TLS active.   │
  └──────────────────────────────────────────────┘
```

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  USER APPLICATIONS                   │
│  ┌─────────────────┐  ┌──────────────────────────┐   │
│  │  Native Revo    │  │  Docker / OCI Containers  │   │
│  │  (revo-fs)      │  │  (planned)                │   │
│  └────────┬────────┘  └────────────┬──────────────┘   │
├───────────┼────────────────────────┼──────────────────┤
│           │     REVO CORE (initramfs, 660 KB)        │
│  ┌────────┴──────┐  ┌──────────────┴─────────────┐   │
│  │   dm-verity   │  │     SSL CA bundle (30)     │   │
│  └────────┬──────┘  └──────────────┬─────────────┘   │
│           └────────────┬───────────┘                  │
│                   revod (PID 1)                       │
├────────────────────────┼──────────────────────────────┤
│           REVO KERNEL (vmlinuz, 12 MB pre-built)     │
│  cgroups v2 │ namespaces │ overlayfs │ ext4          │
│  DM_VERITY  │ NVMe       │ virtio    │ net           │
└──────────────────────────────────────────────────────┘
```

---

## Repository Structure

| Directory | Purpose |
|---|---|
| `initramfs/` | Init script, system config, CA certificates |
| `scripts/` | Kernel build pipeline, dm-verity hash generator |
| `src/kernel/` | `revo-tiny.config` — minimal kernel config (~550 options) |
| `revo-package/` | Distribution artifacts (build-image, setup-usb, README) |
| `revo-os-blueprint.md` | Full conceptual blueprint for the AI-native vision |
| `revo-os-kernel-blueprint.md` | Kernel-specific design document |

---

## Size Budget

| Component | Size |
|---|---|
| Kernel (vmlinuz-virt, Alpine pre-built) | 12.0 MB |
| Initramfs (cpio.gz — busybox + init + CA certs) | 660 KB |
| Kernel modules (11 × .ko.gz) | 1,050 KB |
| **Total (tarball)** | **~13 MB** |
| Target (source-compiled kernel) | ~4 MB vmlinuz → **~5 MB total** |

---

## Future Updates

| # | Feature | Description |
|---|---|---|
| 1 | **Container runtime built-in** | Static containerd + runc compiled into initramfs (~2 MB). Docker-compatible CLI shim with zero daemon overhead |
| 2 | **Ornet kernel AI inference** | `ornet.ko` kernel module (~500 KB) — model memory manager, tensor dispatch, ring buffer. Ornith-1 9B GGUF on dedicated RevoAI volume |
| 3 | **revo-fs package streaming** | FUSE-like overlay mesh filesystem — BitTorrent-backed on-demand package streaming. Any Ubuntu package available, never pre-installed |
| 4 | **Secure remote access** | Dropbear SSH server (~200 KB), WireGuard kernel module, IPv6 dual-stack |
| 5 | **GPU acceleration** | CUDA/Vulkan passthrough for Ornet inference. Multi-model hot-swap on RevoAI volume. Transparent CPU/GPU tensor offload |
| 6 | **Immutable updates** | Cryptographic signing of core image. A/B partition updates with automatic rollback. Binary delta updates |
| 7 | **Observability dashboard** | Web-based management console. Structured JSON logging from kernel + revod + containerd. Prometheus metrics endpoint |
| 8 | **Multi-architecture** | ARM64 (aarch64) port — Raspberry Pi 5, AWS Graviton, Apple Silicon VMs. RISC-V preview |
| 9 | **Multi-node orchestration** | Revo Mesh peer discovery protocol. Distributed Ornet — split inference across nodes. Lightweight Kubernetes shim |
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

## License

Revo OS source files (init script, build scripts, documentation) are licensed under the **MIT License**. See [`LICENSE`](LICENSE) for details.

The Linux kernel is GPL-2.0. Busybox is GPL-2.0. Alpine-provided kernel modules and binaries retain their original licenses.

---

## Credits

**Author & Developer:** Mudassir ([@skmudassir-it](https://github.com/skmudassir-it))  
**Kernel:** [Linux LTS](https://www.kernel.org) (6.12.94, Alpine virt build)  
**Userspace:** [Busybox](https://busybox.net) (306 applets, Alpine static build)  
**Inspiration:** Alpine Linux, TinyCore Linux, Buildroot, Linux From Scratch  

---

*"Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away." — Antoine de Saint-Exupéry*
