# Revo OS v1.3.0

**The 13-Megabyte AI-Native Operating System — Bootable USB Image**

Codename: Révo | Built: July 2026 | Kernel: 6.12.94 (Alpine virt) | Arch: x86_64

> *"The model is firmware, not software." — Revo OS Ornet design philosophy*

---

## v1.3.0 — Ornet: Kernel-Native AI Inference ✅ *(current)*

### What's New

| Feature | Details |
|---|---|
| **ornetd dispatcher** | Userspace AI inference daemon — manages Ornith-1 9B model, chat sessions, priority scheduler (~12 KB) |
| **Ornith-1 9B GGUF** | DeepReinforce's 9B language model, Q4_K_M quantization (~5.5 GB) on dedicated RevoAI volume |
| **ornet.ko blueprint** | Full kernel module design — model memory manager, tensor dispatch, lock-free ring buffer (see `docs/ornet-blueprint.md`) |
| **Model download script** | `scripts/download-ornith.sh` — fetch Ornith-1 9B from HuggingFace |
| **RevoAI partition** | Dedicated GPT partition (`/dev/sda3`) for AI model — dm-verity protected, treated as firmware |

### Cumulative Features (v1.0–v1.2)

| Version | Feature | Size |
|---------|---------|------|
| v1.0.0 | Bootable core with dm-verity + CA bundle | 13 MB |
| v1.1.0 | dm-verity integrity + kernel slim config | 13 MB |
| v1.2.0 | Containerd + runc + revocker Docker CLI | 13 MB |
| **v1.3.0** | **Ornet: Kernel-native AI + Ornith-1 9B** | **13 MB** |

### Boot Sequence

Revo banner v1.3 → 11+ kernel modules loaded (including ornet.ko if available) → dm-verity integrity check → RevoAI volume mounted → CA bundle installed → containerd started → ornetd started (if model present) → DHCP on eth0 → ash shell with AI-ready prompt

---

## Quick Start

```bash
# QEMU (fastest)
qemu-system-x86_64 -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" -nographic

# Bootable USB
python3 build-image.py           # → revo-os-v1.3.0.img (128 MB)
sudo ./setup-usb.sh              # Format + copy kernel/initramfs/modules/certs/containerd
sudo dd if=revo-os-v1.3.0.img of=/dev/sdX bs=4M status=progress conv=fsync

# AI Inference
ornetd download                  # Fetch Ornith-1 9B (~5.5 GB)
ornetd infer "Hello!"            # Single inference
ornetd chat                      # Interactive chat session

# Containers
revocker run alpine:latest sh    # Pull + run Alpine container
revocker ps                      # List containers

# Build custom kernel (10 MB target)
sudo apt install flex bison libelf-dev libssl-dev bc
./scripts/build-kernel.sh 6.12.21
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

## Future Updates

| # | Feature | Description |
|---|---|---|
| 1 | **ornet.ko kernel module** | Compile kernel-level AI module — MMM, tensor dispatch, ring buffer. Blueprint in `docs/ornet-blueprint.md` |
| 2 | **revo-fs package streaming** | FUSE overlay mesh — BitTorrent-backed on-demand packages |
| 3 | **Secure remote access** | Dropbear SSH, WireGuard, IPv6 dual-stack |
| 4 | **GPU acceleration** | CUDA/Vulkan passthrough for Ornet inference |
| 5 | **Immutable updates** | Signed core image, A/B partitions, delta updates |
| 6 | **Observability dashboard** | Web console, JSON logging, Prometheus metrics |
| 7 | **Multi-architecture** | ARM64 (RPi 5, Graviton), RISC-V preview |
| 8 | **Multi-node orchestration** | Revo Mesh, distributed Ornet, k8s shim |

---

## Project Structure

```
revo-build/
├── revo-package/
│   ├── vmlinuz-virt              # Pre-built kernel (download from Alpine)
│   ├── initramfs.cpio.gz         # Built initramfs
│   ├── modules/                  # 11+ kernel modules (.ko.gz)
│   ├── build-image.py            # GPT disk image builder
│   ├── setup-usb.sh              # USB flash script
│   └── README.md
├── initramfs/
│   ├── init                      # PID 1 init script (v1.3: ornetd startup)
│   ├── bin/
│   │   ├── busybox               # Static busybox (306 applets)
│   │   ├── revocker              # Docker-compatible CLI shim
│   │   └── ornetd                # AI inference dispatcher
│   ├── etc/ssl/certs/            # 30 root CAs
│   └── etc/revo/config.json      # v1.3.0 config + verity + ornet params
├── scripts/
│   ├── build-kernel.sh           # Kernel source compile pipeline
│   ├── generate-verity.py        # dm-verity hash tree generator
│   ├── download-containerd.sh    # Fetch containerd + runc from Alpine
│   └── download-ornith.sh        # Fetch Ornith-1 9B from HuggingFace
├── docs/
│   └── ornet-blueprint.md        # Kernel module design (MMM, ring buffer, scheduler)
├── src/kernel/
│   └── revo-tiny.config          # Minimal kernel config (~550 options)
├── build-image.py                # Root-level builder
└── setup-usb.sh                  # Root-level USB flasher
```

---

## Size Budget

| Component | Size |
|---|---|
| Kernel (vmlinuz-virt, pre-built) | 12 MB |
| Initramfs (cpio.gz — busybox + init + revocker + ornetd + CA certs) | 680 KB |
| Kernel modules (11+ × .ko.gz) | 1,050 KB |
| **Total core (tarball)** | **~13 MB** |
| containerd + runc (on ESP) | 73 MB |
| Ornith-1 9B GGUF (on RevoAI volume) | 5.5 GB |

---

## License

| Component | License |
|---|---|
| Linux Kernel | GPL-2.0 |
| Busybox | GPL-2.0 |
| Containerd / runc | Apache-2.0 |
| Ornith-1 | Apache-2.0 |
| Setup Scripts | MIT |
| Revo Brand & Blueprints | Proprietary — © AMS Ventures |
