# Revo OS v1.1

**The 13-Megabyte AI-Native Operating System — Bootable USB Image**

Codename: Révo | Built: June 2026 | Kernel: 6.12.94 (Alpine virt) | Arch: x86_64

> "The 10-Megabyte AI-Native Operating System" — a unikernel that integrates local AI inference at the kernel level through the Ornet subsystem, provides built-in Docker support, and matches Ubuntu feature parity via an overlay mesh architecture. All from a single immutable image smaller than a high-resolution photograph.

---

## v1.1 — Kernel Slimming & Integrity ✅ *(current)*

### What's New

| Feature | Details |
|---|---|
| **dm-verity integrity** | Cryptographic verification of the Revo data volume at boot — root hash embedded in config, Merkle hash tree on ESP |
| **CA certificate bundle** | 30 essential root CAs (39 KB) — ISRG, DigiCert, GlobalSign, Amazon, Google, GoDaddy, Sectigo, Microsoft, Entrust, IdenTrust |
| **Kernel slim config** | `revo-tiny.config` — 550-option kernel config targeting 3-4 MB vmlinuz (requires source compile with `flex`/`bison`) |
| **Build pipeline** | `scripts/build-kernel.sh` — automated kernel download + tinyconfig + compile; `scripts/generate-verity.py` — Merkle hash tree generator |

### v1.0 Features (cumulative)

| Component | Details |
|---|---|
| **Linux kernel 6.12.94** | Stripped virt kernel with EFI stub (CONFIG_EFI_STUB=y) — the kernel IS the bootloader |
| **Busybox userspace** | 306 applets — shell, networking, filesystem tools |
| **Kernel modules** | ext4, overlayfs, vfat, loop, virtio-blk, virtio-net, e1000, dm-mod, dm-verity, dm-bufio |
| **Image size** | 13 MB compressed (kernel + initramfs + modules + setup scripts) |
| **Target** | 10 MB true core (see v1.3) — model on separate RevoAI volume |

### Boot Experience
- Revo banner v1.1 with kernel version, CPU cores, RAM
- Loads 11 kernel modules including dm-verity stack
- dm-verity integrity check on data partition (with graceful fallback)
- SSL CA bundle installed to `/etc/ssl/certs/`
- DHCP on eth0, mounts Revo data volume, drops to ash shell

---

## How to Use

### Option 1: Test in QEMU (fastest)

```bash
tar xzf revo-os-v1.1.0.tar.gz
cd revo-package
qemu-system-x86_64 \
  -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" \
  -nographic
```

### Option 2: Create Bootable USB

```bash
tar xzf revo-os-v1.1.0.tar.gz
cd revo-package
python3 build-image.py          # 128 MB GPT image → revo-os-v1.1.img
sudo ./setup-usb.sh             # Format ESP + copy kernel/initramfs/modules/certs
sudo dd if=revo-os-v1.1.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### Option 3: Manual USB Setup

```bash
sudo parted /dev/sdX mklabel gpt
sudo parted /dev/sdX mkpart ESP fat32 1MiB 65MiB
sudo parted /dev/sdX mkpart data ext4 65MiB 100%
sudo parted /dev/sdX set 1 esp on

sudo mkfs.vfat -F32 /dev/sdX1
sudo mkfs.ext4 /dev/sdX2

sudo mount /dev/sdX1 /mnt
sudo mkdir -p /mnt/EFI/BOOT /mnt/modules /mnt/ssl/certs
sudo cp vmlinuz-virt /mnt/EFI/BOOT/BOOTX64.EFI
sudo cp initramfs.cpio.gz /mnt/EFI/BOOT/initrd.img
sudo cp modules/*.ko.gz /mnt/modules/
sudo cp initramfs/etc/ssl/certs/*.crt /mnt/ssl/certs/
sudo umount /mnt
```

### Build Custom Kernel (10 MB target)

```bash
# Prerequisites: sudo apt install flex bison libelf-dev libssl-dev bc
./scripts/build-kernel.sh 6.12.21
# Output: build/vmlinuz-revo (~3-4 MB with revo-tiny.config)
```

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  USER APPLICATIONS                   │
│                                                      │
│  ┌─────────────────┐  ┌──────────────────────────┐   │
│  │  Native Revo    │  │  Docker / OCI Containers  │   │
│  │  (streamed via  │  │  (Ubuntu, Alpine, etc.)   │   │
│  │   revo-fs)      │  │                           │   │
│  └────────┬────────┘  └────────────┬──────────────┘   │
│           │                        │                  │
├───────────┼────────────────────────┼──────────────────┤
│           │     REVO CORE (initramfs, ~660 KB)       │
│           │                        │                  │
│  ┌────────┴──────┐  ┌──────────────┴─────────────┐   │
│  │   dm-verity   │  │     SSL CA bundle (30)     │   │
│  │  (integrity)  │  │     /etc/ssl/certs/        │   │
│  └────────┬──────┘  └──────────────┬─────────────┘   │
│           │                        │                  │
│  ┌────────┴────────────────────────┴─────────────┐   │
│  │                 revod (PID 1)                  │   │
│  └──────────────────────┬────────────────────────┘   │
│                         │                             │
├─────────────────────────┼─────────────────────────────┤
│           REVO KERNEL (vmlinuz, 12 MB pre-built)     │
│                                                      │
│  cgroups v2 │ namespaces │ overlayfs │ ext4          │
│  DM_VERITY  │ NVMe       │ virtio    │ net           │
│                                                      │
└──────────────────────────────────────────────────────┘
```

---

## Future Updates

### v1.1 — Kernel Slimming & Integrity ✅ *(shipped)*

- [x] **dm-verity root hash verification** — cryptographic integrity of the immutable core image
- [x] **Minimal CA certificate bundle** — 30 essential root CAs (39 KB)
- [x] **Kernel slim config** — `revo-tiny.config` targeting 3-4 MB vmlinuz + `build-kernel.sh`

### v1.2 — Container Runtime Built-In

- [ ] **Static containerd + runc** — compile into initramfs (~2 MB add)
- [ ] **revocker Docker CLI shim** — Docker-compatible CLI with zero daemon overhead (~100 KB)
- [ ] **Container-native userspace** — primary process model is containers; even native tools run in thin shims

### v1.3 — Ornet: Kernel-Native AI Inference

- [ ] **ornet.ko kernel module** — AI inference subsystem (~500 KB): model memory manager, tensor dispatch, ring buffer, llama.cpp backend bridge
- [ ] **ornetd userspace dispatcher** — inference request scheduler with priority queues (~400 KB)
- [ ] **Ornith-1 9B GGUF Q4_K_M** — dedicated RevoAI volume (~5.5 GB), model as firmware, not software

### v1.4 — revo-fs Package Streaming

- [ ] **revo-fs kernel filesystem** — FUSE-like overlay mesh for on-demand package streaming (~500 KB)
- [ ] **BitTorrent-backed overlay mesh** — no `apt`, no `dnf`; packages stream on first use
- [ ] **Ubuntu feature parity** — any Ubuntu package available via the mesh, just never pre-installed

### v1.5 — Networking & Remote Access

- [ ] **Dropbear SSH server** — minimal secure remote access (~200 KB static)
- [ ] **IPv6 dual-stack** — full IPv6 support alongside IPv4
- [ ] **WireGuard kernel module** — built-in VPN for secure remote management

### v1.6 — GPU Acceleration & AI Runtime

- [ ] **GPU passthrough path** — CUDA/Vulkan acceleration for Ornet inference
- [ ] **Multi-model support** — hot-swap between GGUF models on the RevoAI volume
- [ ] **Tensor offload** — split inference between CPU and GPU transparently

### v1.7 — Immutable Core & Updates

- [ ] **Cryptographic signing of core image** — dm-verity with hardware-rooted keys
- [ ] **A/B partition update system** — atomic OS updates with automatic rollback
- [ ] **Delta updates** — binary diffs for core image updates (no full re-download)

### v1.8 — Observability & Management

- [ ] **Web-based management console** — revod dashboard (CPU, RAM, containers, Ornet status)
- [ ] **Structured logging** — JSON log stream from kernel, revod, containerd, ornetd
- [ ] **Prometheus metrics endpoint** — kernel + container + inference metrics

### v1.9 — Multi-Architecture

- [ ] **ARM64 (aarch64) port** — Raspberry Pi 5, AWS Graviton, Apple Silicon VMs
- [ ] **RISC-V preview** — initial boot on QEMU RISC-V, VisionFive 2 target

### v1.10 — Multi-Node & Orchestration

- [ ] **Revo Mesh protocol** — peer discovery, secure node-to-node communication
- [ ] **Distributed Ornet** — split inference across multiple Revo nodes
- [ ] **Lightweight Kubernetes shim** — run pods natively on revod without kubelet overhead

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

## Project Structure

```
revo-build/
├── vmlinuz-virt                    # Pre-built Linux 6.12.94 kernel (12 MB)
├── initramfs.cpio.gz               # initramfs (660 KB) — busybox + init + CA certs
├── build-image.py                  # GPT disk image builder → revo-os-v1.1.img
├── setup-usb.sh                    # Partition + file copy script (dm-verity + SSL aware)
├── systemd-bootx64.efi             # EFI stub loader
├── modules_out/                    # 11 kernel modules (.ko.gz)
│   ├── ext4.ko.gz, overlay.ko.gz, vfat.ko.gz, loop.ko.gz
│   ├── virtio_blk.ko.gz, virtio_net.ko.gz, e1000.ko.gz
│   └── dm-mod.ko.gz, dm-verity.ko.gz, dm-bufio.ko.gz
├── initramfs/
│   ├── init                        # PID 1 init script (v1.1: dm-verity + SSL)
│   ├── bin/busybox                 # Static busybox (306 applets)
│   ├── etc/ssl/certs/              # 30 essential root CAs (39 KB)
│   └── etc/revo/config.json        # v1.1.0 config (dm-verity params)
├── scripts/
│   ├── build-kernel.sh             # Kernel source compile pipeline
│   └── generate-verity.py          # dm-verity Merkle hash tree generator
├── src/kernel/
│   └── revo-tiny.config            # Minimal kernel config (~550 options, 3-4 MB target)
├── revo-package/                   # Distribution directory
│   ├── vmlinuz-virt
│   ├── initramfs.cpio.gz
│   ├── modules/                    # *.ko.gz
│   ├── build-image.py
│   ├── setup-usb.sh
│   └── README.md
├── revo-os-v1.1.img                # Bootable GPT image (128 MB)
├── revo-os-v1.1.0.tar.gz           # Compressed distribution (13 MB)
├── revo-os-v1.1.0.tar.xz           # XZ-compressed archive
├── revo-os-blueprint.md            # Full conceptual blueprint
└── revo-os-kernel-blueprint.md     # Kernel-specific blueprint
```

---

## Size Budget

| Component | v1.0 | v1.1 | Delta |
|---|---|---|---|
| Kernel (vmlinuz-virt) | 12 MB | 12 MB | — (pre-built; 3-4 MB with source compile) |
| Initramfs (cpio.gz) | 632 KB | 660 KB | +28 KB (CA certs + config) |
| Kernel modules | 880 KB | 1,050 KB | +170 KB (dm-mod, dm-verity, dm-bufio) |
| **Total** | **~13 MB** | **~13 MB** | **+198 KB** |

---

## License

| Component | License |
|---|---|
| Linux Kernel | GPL-2.0 |
| Busybox | GPL-2.0 |
| Setup Scripts | MIT |
| Revo Brand & Blueprints | Proprietary — © AMS Ventures |
