# 🌀 Revo OS — The 15-Megabyte Operating System

**Developed and coded by [Mudassir](https://github.com/skmudassir-it)**  
*Conceived June 2026 · Built from scratch · Open source under MIT*

[![OS Size](https://img.shields.io/badge/size-15_MB-00cc66)](https://github.com/skmudassir-it/revo-os)
[![Kernel](https://img.shields.io/badge/kernel-Linux_6.12.94-blue)](https://www.kernel.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Status](https://img.shields.io/badge/status-v0.2.0-brightgreen)](https://github.com/skmudassir-it/revo-os/releases)
[![Docker](https://img.shields.io/badge/docker-built--in-2496ED)](https://github.com/skmudassir-it/revo-os)

---

## Project Overview

**Revo OS** is an ultra-minimal operating system designed to answer a single, provocative question: *how small can a fully functional Linux OS be while remaining genuinely useful?* The answer, as of v0.2.0, is **15 megabytes** — with Docker built-in.

Revo is not a toy. It is a real, bootable, UEFI-native operating system built on Linux 6.12.94. It ships with a Busybox userspace of 306 Unix utilities, essential kernel modules for filesystem and network support, a GPT-partitioned disk image ready to flash to any USB drive, and **built-in Docker container support** via static containerd + runc binaries. The entire system — kernel, initramfs, modules, and setup scripts — compresses to 15 MB.

### Why Revo Exists

Modern operating systems have grown to tens of gigabytes. Ubuntu Server 24.04 is over 2 GB compressed. Even Alpine Linux, the gold standard of minimalism, is 130 MB for a full rootfs. Revo demonstrates that the Linux kernel itself can be stripped to its absolute essentials without sacrificing the core capabilities that make an OS useful: process management, filesystem support, networking, and an interactive shell.

This project is a personal exploration in OS minimalism by **Mudassir** — a study in what happens when every byte is interrogated, every kernel config option justified, and every binary stripped to its bare function.

### What Revo Is (and Isn't)

**Revo IS:**
- A bootable UEFI x86_64 operating system
- A minimal Linux environment with a usable shell
- A demonstration of extreme OS compaction
- A Docker / OCI container runtime (containerd + runc built-in)
- A foundation for embedded, container, and edge computing

**Revo IS NOT (yet):**
- A desktop OS with a GUI
- A production server OS
- A drop-in Ubuntu replacement

---

## Quick Start

### Test in QEMU (30 seconds)

```bash
tar xzf revo-os-v0.2.0.tar.gz
cd revo-package
qemu-system-x86_64 -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" -nographic
```

### Flash to USB

```bash
cd revo-package
python3 scripts/build-image.py    # Creates GPT disk image
sudo ./scripts/setup-usb.sh       # Formats + copies boot files
sudo dd if=revo-os-v0.2.0.img of=/dev/sdX bs=4M status=progress
```

Plug the USB into any UEFI x86_64 machine, enable UEFI boot, and Revo boots.

---

## Repository Structure

| Directory | Purpose |
|-----------|---------|
| `src/kernel/` | Kernel configuration (`.config` for 6.12.94-virt) |
| `src/initramfs/` | Init script, system config, user database |
| `src/modules/` | Essential kernel modules (ext4, overlay, virtio, e1000) |
| `src/containerd/` | Static containerd + runc binaries, revocker Docker CLI shim |
| `scripts/` | Image builder, USB setup automation |
| `docs/` | Full documentation suite |
| `dist/` | Prebuilt initramfs + containerd binaries |

For a complete breakdown, see [`docs/FOLDER_STRUCTURE.md`](docs/FOLDER_STRUCTURE.md).

---

## Documentation

| Document | Contents |
|----------|----------|
| [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Full system architecture, boot sequence, component interaction |
| [`BUILD.md`](docs/BUILD.md) | How to build from source, kernel compilation, initramfs creation |
| [`DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Design decisions, implementation details, algorithms |
| [`SPECS.md`](docs/SPECS.md) | Technical specifications, dependencies, system requirements |
| [`FOLDER_STRUCTURE.md`](docs/FOLDER_STRUCTURE.md) | Complete directory tree with file-by-file explanations |
| [`FILE_TYPES.md`](docs/FILE_TYPES.md) | Explanation of each file type in the repository |
| [`USER_GUIDE.md`](docs/USER_GUIDE.md) | End-user guide for booting and using Revo |

---

## Technical Specifications

- **Kernel:** Linux 6.12.94 (Alpine virt, EFI stub enabled)
- **Userspace:** Busybox 1.37.0 (306 applets, statically linked)
- **Container Runtime:** containerd (static, stripped) + runc (static) + revocker Docker CLI shim
- **libc:** musl (via Busybox static build)
- **Architecture:** x86_64 only
- **Boot:** UEFI native (CONFIG_EFI_STUB=y)
- **Partitioning:** GPT (EFI System Partition + ext4 data)
- **Compressed size:** 15 MB (tar.gz)
- **RAM requirement:** 256 MB minimum, 1 GB recommended

---

## Roadmap

| Version | Goal | Target Size |
|---------|------|-------------|
| v0.1.0 | ✅ Bootable kernel + shell | 13 MB |
| v0.2.0 | ✅ Static containerd + runc (Docker built-in) | 15 MB |
| v0.3.0 | revo-fs: on-demand package streaming | 12 MB |
| v0.4.0 | Custom-compiled kernel (`tinyconfig` base) | 8 MB |
| v1.0.0 | Full Ubuntu feature parity via overlay mesh | 10 MB |

---

## License

Revo OS source files (init script, build scripts, documentation) are licensed under the **MIT License**. See [`LICENSE`](LICENSE) for details.

The Linux kernel is GPL-2.0. Busybox is GPL-2.0. Alpine-provided kernel modules and binaries retain their original licenses.

---

## Credits

**Author & Developer:** Mudassir ([@skmudassir-it](https://github.com/skmudassir-it))  
**Kernel:** [Linux LTS](https://www.kernel.org) (6.12.94, Alpine virt build)  
**Userspace:** [Busybox](https://busybox.net) (1.37.0, Alpine static build)  
**Inspiration:** Alpine Linux, TinyCore Linux, Buildroot, Linux From Scratch  

---

*"Perfection is achieved not when there is nothing more to add, but when there is nothing left to take away." — Antoine de Saint-Exupéry*
