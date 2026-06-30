# 🌀 Revo OS v1.2.0 — Container Runtime Built-In

**Developed and coded by [Mudassir](https://github.com/skmudassir-it)**  
*Conceived June 2026 · Built from scratch · Kernel 6.12.94 · x86_64 UEFI*

[![OS Size](https://img.shields.io/badge/size-13_MB-00cc66)](https://github.com/skmudassir-it/revo-os)
[![Kernel](https://img.shields.io/badge/kernel-6.12.94-blue)](https://www.kernel.org)
[![Status](https://img.shields.io/badge/status-v1.2.0-brightgreen)](https://github.com/skmudassir-it/revo-os)
[![Containerd](https://img.shields.io/badge/containerd-built--in-2496ED)](https://github.com/skmudassir-it/revo-os)
[![dm-verity](https://img.shields.io/badge/integrity-dm--verity-orange)](https://github.com/skmudassir-it/revo-os)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## Project Overview

**Revo OS** answers a single provocative question: *how small can a fully functional Linux OS be while remaining genuinely useful?* The answer, as of v1.2.0, is **13 megabytes** — a bootable UEFI-native operating system with cryptographic integrity verification, a TLS-ready CA bundle, and a **built-in container runtime** powered by containerd + runc + the revocker Docker CLI shim.

Revo boots from a single immutable image smaller than a high-resolution photograph. It is not a toy — it is a real operating system built on Linux 6.12.94 with a Busybox userspace of 306 Unix utilities, dm-verity data integrity, and now a fully functional OCI container runtime.

### What Revo IS (v1.2.0)

- A bootable UEFI x86_64 operating system
- A Busybox-powered Linux environment with an interactive shell
- dm-verity cryptographic integrity verification at boot
- 30 essential root CA certificates for TLS support
- **Built-in container runtime** — containerd + runc + revocker Docker CLI shim
- 11 kernel modules (ext4, overlay, virtio, dm-verity stack)
- A source-compile kernel pipeline targeting 3–4 MB vmlinuz
- A foundation for embedded, container, and edge computing

### What Revo IS NOT (yet)

- A desktop OS with a GUI
- A production server OS
- A drop-in Ubuntu replacement (planned — see future updates)

---

## Quick Start

```bash
# QEMU (fastest)
tar xzf revo-os-v1.2.0.tar.gz && cd revo-package
qemu-system-x86_64 -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" -nographic

# Flash to USB
python3 build-image.py           # → revo-os-v1.2.0.img (128 MB)
sudo ./setup-usb.sh              # Format + copy kernel/initramfs/modules/certs/containerd
sudo dd if=revo-os-v1.2.0.img of=/dev/sdX bs=4M status=progress conv=fsync

# Download container runtime
./scripts/download-containerd.sh  # → build/containerd/ (containerd + runc)

# Build custom kernel (10 MB target)
sudo apt install flex bison libelf-dev libssl-dev bc
./scripts/build-kernel.sh 6.12.21
```

### Run Containers with revocker

```bash
# Pull and run an Alpine container
revocker run alpine:latest sh

# List containers
revocker ps

# List images
revocker images

# Pull an image
revocker pull ubuntu:latest
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    USER APPLICATIONS                     │
│  ┌───────────────────┐  ┌────────────────────────────┐   │
│  │    revocker CLI   │  │   Docker / OCI Containers   │   │
│  │  (Docker-compat)  │  │   (Alpine, Ubuntu, etc.)   │   │
│  └────────┬──────────┘  └──────────────┬─────────────┘   │
├───────────┼─────────────────────────────┼────────────────┤
│           │       REVO CORE (initramfs, ~660 KB)        │
│  ┌────────┴────────┐  ┌───────────┴──────────────┐     │
│  │    containerd   │  │   dm-verity + CA bundle   │     │
│  │    + runc       │  │   integrity + TLS         │     │
│  └────────┬────────┘  └───────────┬──────────────┘     │
│           └───────────┬───────────┘                     │
│                   revod (PID 1)                         │
├───────────────────────┼──────────────────────────────────┤
│           REVO KERNEL (vmlinuz, 12 MB pre-built)       │
│  cgroups v2 │ namespaces │ overlayfs │ ext4            │
│  DM_VERITY  │ NVMe       │ virtio    │ net             │
└──────────────────────────────────────────────────────────┘
```

---

## Repository Structure

| Directory | Purpose |
|---|---|
| `initramfs/` | Init script, revocker CLI, system config, CA certificates |
| `scripts/` | Kernel build, dm-verity hash generator, containerd downloader |
| `src/kernel/` | `revo-tiny.config` — minimal kernel config (~550 options) |
| `revo-package/` | Distribution artifacts (build-image, setup-usb, README) |

---

## Size Budget

| Component | Size |
|---|---|
| Kernel (vmlinuz-virt, Alpine pre-built) | 12.0 MB |
| Initramfs (cpio.gz — busybox + init + revocker + CA certs) | 660 KB |
| Kernel modules (11 × .ko.gz) | 1,050 KB |
| containerd + runc (on ESP, not in initramfs) | 73 MB |
| **Total core (tarball)** | **~13 MB** |
| **Total with container runtime** | **~86 MB** |

---

## Future Updates

| # | Feature | Description |
|---|---|---|
| 1 | **Ornet kernel AI inference** | `ornet.ko` kernel module (~500 KB) — model memory manager, tensor dispatch. Ornith-1 9B GGUF on dedicated RevoAI volume |
| 2 | **revo-fs package streaming** | FUSE-like overlay mesh filesystem — BitTorrent-backed on-demand package streaming. Any Ubuntu package available, never pre-installed |
| 3 | **Secure remote access** | Dropbear SSH server (~200 KB), WireGuard kernel module, IPv6 dual-stack |
| 4 | **GPU acceleration** | CUDA/Vulkan passthrough for Ornet inference. Multi-model hot-swap. CPU/GPU tensor offload |
| 5 | **Immutable updates** | Cryptographic signing of core image. A/B partition updates with automatic rollback. Binary delta updates |
| 6 | **Observability dashboard** | Web-based management console. Structured JSON logging. Prometheus metrics endpoint |
| 7 | **Multi-architecture** | ARM64 (aarch64) port — Raspberry Pi 5, AWS Graviton. RISC-V preview |
| 8 | **Multi-node orchestration** | Revo Mesh peer discovery. Distributed Ornet — split inference across nodes. Lightweight Kubernetes shim |
| 9 | **AI-First boot** | Kernel awakens Ornet before filesystem mount — model ready before PID 1 |
| 10 | **Full Ubuntu parity** | Overlay mesh delivers any Ubuntu package on-demand. Complete desktop/server feature parity |

---

## License

Revo OS source files are licensed under **MIT**. See [`LICENSE`](LICENSE).

Linux kernel: GPL-2.0. Busybox: GPL-2.0. containerd/runc: Apache-2.0.

---

## Credits

**Author & Developer:** Mudassir ([@skmudassir-it](https://github.com/skmudassir-it))  
**Kernel:** Linux LTS 6.12.94 (Alpine virt) · **Userspace:** Busybox 306 applets  
**Containers:** containerd 2.0.0 + runc 1.2.2 (Alpine community)  
**Inspiration:** Alpine Linux, TinyCore Linux, Buildroot, Linux From Scratch  

---

*"Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away." — Antoine de Saint-Exupéry*
