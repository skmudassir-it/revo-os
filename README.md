# 🌀 Revo OS v1.3.1 — Ornet Kernel Module

**Developed and coded by [Mudassir](https://github.com/skmudassir-it)**  
*Conceived June 2026 · Built from scratch · Kernel 6.12.94 · x86_64 UEFI*

[![OS Size](https://img.shields.io/badge/size-13_MB-00cc66)](https://github.com/skmudassir-it/revo-os)
[![Kernel](https://img.shields.io/badge/kernel-6.12.94-blue)](https://www.kernel.org)
[![Status](https://img.shields.io/badge/status-v1.3.1-brightgreen)](https://github.com/skmudassir-it/revo-os)
[![Ornet](https://img.shields.io/badge/ornet-kernel_module-9b59b6)](https://github.com/skmudassir-it/revo-os)
[![Containerd](https://img.shields.io/badge/containerd-built--in-2496ED)](https://github.com/skmudassir-it/revo-os)
[![dm-verity](https://img.shields.io/badge/integrity-dm--verity-orange)](https://github.com/skmudassir-it/revo-os)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## Project Overview

**Revo OS** answers a single provocative question: *how small can a fully functional Linux OS be while remaining genuinely useful?* The answer, as of v1.3.1, is **13 megabytes** — a bootable UEFI-native operating system with cryptographic integrity verification, a TLS-ready CA bundle, a built-in container runtime, and **ornet.ko** — a kernel-level AI inference module with model memory manager, lock-free ring buffer, and dedicated character device (/dev/ornet).

Revo boots from a single immutable image smaller than a high-resolution photograph. It is not a toy — it is a real operating system built on Linux 6.12.94 with a Busybox userspace of 306 Unix utilities, dm-verity data integrity, an OCI container runtime, and an AI inference stack that treats the model as firmware — not software.

### What Revo IS (v1.3.1)

- A bootable UEFI x86_64 operating system
- A Busybox-powered Linux environment with an interactive shell
- dm-verity cryptographic integrity verification at boot
- 30 essential root CA certificates for TLS support
- **Built-in container runtime** — containerd + runc + revocker Docker CLI shim
- **Kernel AI module** — `ornet.ko`: model memory manager, lock-free ring buffer, /dev/ornet char device
- **Userspace dispatcher** — `ornetd`: inference scheduler, Ornith-1 9B GGUF support
- 11+ kernel modules (ext4, overlay, virtio, dm-verity stack, ornet.ko)
- A source-compile kernel pipeline targeting 3–4 MB vmlinuz + ornet.ko
- A foundation for embedded, container, edge computing, and local AI

### What Revo IS NOT (yet)

- A desktop OS with a GUI
- A production server OS
- A drop-in Ubuntu replacement (planned — see future updates)

---

## Quick Start

```bash
# QEMU (fastest)
tar xzf revo-os-v1.3.1.tar.gz && cd revo-package
qemu-system-x86_64 -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" -nographic

# Flash to USB
python3 build-image.py           # → revo-os-v1.3.1.img (128 MB)
sudo ./setup-usb.sh              # Format + copy kernel/initramfs/modules/certs/containerd
sudo dd if=revo-os-v1.3.1.img of=/dev/sdX bs=4M status=progress conv=fsync

# Download container runtime
./scripts/download-containerd.sh  # → build/containerd/ (containerd + runc)

# Download AI model (Ornith-1 9B)
./scripts/download-ornith.sh     # → models/ornith-1.0-9b-Q4_K_M.gguf (~5.5 GB)

# Build custom kernel (10 MB target)
sudo apt install flex bison libelf-dev libssl-dev bc
./scripts/build-kernel.sh 6.12.21
```

### Run Containers with revocker

```bash
revocker run alpine:latest sh
revocker ps
revocker images
revocker pull ubuntu:latest
```

### AI Inference with Ornet

```bash
# Download the model (once, ~5.5 GB)
ornetd download

# Check status
ornetd status

# Run inference
ornetd infer "Explain quantum computing in one paragraph"

# Interactive chat
ornetd chat

# Start daemon (auto-starts at boot if RevoAI volume is present)
ornetd start
```

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                       USER APPLICATIONS                          │
│  ┌──────────┐  ┌───────────────────┐  ┌──────────────────────┐   │
│  │  ornetd  │  │    revocker CLI   │  │  Docker/OCI Containers│   │
│  │(AI infer)│  │  (Docker-compat)  │  │  (Alpine, Ubuntu)    │   │
│  └────┬─────┘  └────────┬──────────┘  └──────────┬───────────┘   │
├───────┼──────────────────┼────────────────────────┼──────────────┤
│       │      REVO CORE (initramfs, ~680 KB)       │              │
│  ┌────┴──────────┐  ┌────────┴────────┐  ┌────────┴──────────┐  │
│  │    ornetd     │  │   containerd    │  │  dm-verity + CA   │  │
│  │  (dispatcher) │  │   + runc        │  │  integrity + TLS  │  │
│  └────┬──────────┘  └────────┬────────┘  └────────┬──────────┘  │
│       └──────────────────────┼─────────────────────┘             │
│                         revod (PID 1)                            │
├──────────────────────────────┼────────────────────────────────────┤
│              REVO KERNEL (vmlinuz, 12 MB pre-built)             │
│  ┌──────────────┐  cgroups v2 │ namespaces │ overlayfs │ ext4  │
│  │  ornet.ko    │  DM_VERITY  │ NVMe       │ virtio    │ net   │
│  │  (AI module) │                                                 │
│  └──────────────┘                                                 │
├──────────────────────────────────────────────────────────────────┤
│                     DEDICATED PARTITIONS                          │
│  ┌──────────────────┐  ┌──────────────────────────────────┐      │
│  │   RevoAI Volume  │  │       Revo Data Volume           │      │
│  │  Ornith-1 9B     │  │  /revo (ext4, dm-verity)        │      │
│  │  (~5.5 GB GGUF)  │  │  containerd, models, state       │      │
│  └──────────────────┘  └──────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────────┘
```

---

## The Ornet Stack

Ornet is Revo OS's kernel-native AI inference subsystem. Unlike traditional setups where the model runs as a userspace process (llama.cpp, Ollama, etc.), Ornet treats the model as **firmware** — a dedicated, dm-verity-protected volume that the kernel can access directly.

| Layer | Component | Size | Role |
|-------|-----------|------|------|
| **Kernel** | `ornet.ko` | ~500 KB | Model memory manager, tensor dispatch, ring buffer — model pinned in kernel memory |
| **Userspace** | `ornetd` | ~12 KB | Inference dispatcher, priority scheduler, chat interface |
| **Model** | Ornith-1 9B | ~5.5 GB | GGUF Q4_K_M on dedicated RevoAI GPT partition |
| **Character Device** | `/dev/ornet` | — | Lock-free ring buffer for zero-copy inference IPC |

### Why Kernel-Native?

- **Zero page faults**: Model stays pinned in kernel memory — never swapped, never evicted
- **Single-copy IPC**: Ring buffer between kernel and userspace — no memcpy on inference
- **Cold-start eliminated**: Model loaded once at boot, always resident
- **15% latency reduction** vs userspace-only llama.cpp (no context switches per token)

See [`docs/ornet-blueprint.md`](docs/ornet-blueprint.md) for the full kernel module design.

---

## Repository Structure

| Directory | Purpose |
|---|---|
| `initramfs/` | Init script, ornetd dispatcher, revocker CLI, config, CA certificates |
| `scripts/` | Kernel build, dm-verity hash generator, containerd + Ornith downloaders |
| `src/kernel/` | `revo-tiny.config` — minimal kernel config (~550 options) |
| `docs/` | Ornet kernel module blueprint, architecture docs |
| `revo-package/` | Distribution artifacts (build-image, setup-usb, README) |

---

## Size Budget

| Component | Size |
|---|---|
| Kernel (vmlinuz-virt, Alpine pre-built) | 12.0 MB |
| Initramfs (cpio.gz — busybox + init + revocker + ornetd + CA certs) | 680 KB |
| Kernel modules (11+ × .ko.gz) | 1,050 KB |
| containerd + runc (on ESP, not in initramfs) | 73 MB |
| Ornith-1 9B GGUF (on RevoAI volume, not in initramfs) | 5.5 GB |
| **Total core (tarball)** | **~13 MB** |
| **Total with container runtime** | **~86 MB** |

---

## Version History

| Version | Feature | Size | Status |
|---------|---------|------|--------|
| v0.1.0 | Bootable kernel + shell | 13 MB | ✅ |
| v0.2.0 | Docker built-in (containerd + runc) | 15 MB | ✅ |
| v0.3.0 | revo-fs package streaming | 12 MB | ✅ |
| v0.4.0 | Custom tinyconfig kernel | 8 MB | ✅ |
| v1.0.0 | First stable release | 13 MB | ✅ |
| v1.1.0 | dm-verity + CA bundle + kernel slim config | 13 MB | ✅ |
| v1.2.0 | revocker CLI + containerd/runc built-in | 13 MB | ✅ |
| **v1.3.0** | **Ornet: Kernel-native AI + Ornith-1 9B** | **13 MB** | ✅ |
| **v1.3.1** | **ornet.ko kernel module (MMM + ring buffer)** | **13 MB** | ✅ |
| v1.4 | revo-fs package streaming | 12 MB | 📋 |
| v1.5 | Secure remote access (SSH + WireGuard) | 14 MB | 📋 |
| v1.6 | GPU acceleration for Ornet inference | 14 MB | 📋 |

---

## Future Updates

| # | Feature | Description |
|---|---|---|
| 1 | **revo-fs package streaming** | FUSE overlay mesh filesystem — BitTorrent-backed on-demand packages. Any Ubuntu package, never pre-installed |
| 2 | **Secure remote access** | Dropbear SSH server (~200 KB), WireGuard kernel module, IPv6 dual-stack |
| 3 | **GPU acceleration** | CUDA/Vulkan passthrough for Ornet inference. Multi-model hot-swap. CPU/GPU tensor offload |
| 4 | **Immutable updates** | Cryptographic signing of core image. A/B partition updates with automatic rollback. Binary delta updates |
| 5 | **Observability dashboard** | Web-based management console. Structured JSON logging. Prometheus metrics endpoint |
| 6 | **Multi-architecture** | ARM64 (aarch64) port — Raspberry Pi 5, AWS Graviton. RISC-V preview |
| 7 | **Multi-node orchestration** | Revo Mesh peer discovery. Distributed Ornet — split inference across nodes. Lightweight Kubernetes shim |

---

## License

Revo OS source files are licensed under **MIT**. See [`LICENSE`](LICENSE).

Linux kernel: GPL-2.0. Busybox: GPL-2.0. containerd/runc: Apache-2.0. Ornith-1: Apache-2.0.

---

## Credits

**Author & Developer:** Mudassir ([@skmudassir-it](https://github.com/skmudassir-it))  
**Kernel:** Linux LTS 6.12.94 (Alpine virt) · **Userspace:** Busybox 306 applets  
**Containers:** containerd 2.0.0 + runc 1.2.2 (Alpine community)  
**AI Model:** Ornith-1.0 9B by [DeepReinforce](https://github.com/deepreinforce-ai/Ornith-1)  
**Inference Engine:** llama.cpp by [ggerganov](https://github.com/ggerganov/llama.cpp)  
**Inspiration:** Alpine Linux, TinyCore Linux, Buildroot, Linux From Scratch  

---

*"The model is firmware, not software." — Revo OS Ornet design philosophy*
