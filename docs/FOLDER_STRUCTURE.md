# Revo OS — Folder Structure

**Version:** 0.1.0 · **Author:** Mudassir  

---

## Complete Directory Tree

```
revo-os/                              # Project root
│
├── README.md                         # Project overview, quick start, credits
├── LICENSE                           # MIT License
├── .gitignore                        # Git ignore rules
│
├── src/                              # SOURCE CODE
│   ├── kernel/                       #   Kernel configuration
│   │   └── config-6.12.94-0-virt     #     Alpine virt kernel .config file
│   │                                 #     CONFIG_EFI_STUB=y, CONFIG_CGROUPS=y, etc.
│   │
│   ├── initramfs/                    #   Initramfs source files
│   │   ├── init                      #     PID 1 init script (ash, 2.3 KB)
│   │   │                             #     Mounts filesystems, loads modules,
│   │   │                             #     configures network, spawns shell
│   │   ├── config.json               #     System configuration file
│   │   │                             #     hostname, version, codename
│   │   ├── inittab                   #     Console configuration
│   │   │                             #     Spawns getty on tty1, tty2
│   │   ├── passwd                    #     User database (root only)
│   │   └── group                     #     Group database
│   │
│   └── modules/                      #   Kernel modules
│       ├── ext4.ko.gz                #     ext4 filesystem (536 KB compressed)
│       ├── overlay.ko.gz             #     OverlayFS (115 KB compressed)
│       ├── vfat.ko.gz                #     VFAT/FAT32 (16 KB compressed)
│       ├── loop.ko.gz                #     Loopback device (24 KB compressed)
│       ├── virtio_blk.ko.gz          #     VirtIO block driver (18 KB compressed)
│       ├── virtio_net.ko.gz          #     VirtIO network driver (68 KB compressed)
│       └── e1000.ko.gz               #     Intel e1000 NIC driver (96 KB compressed)
│
├── scripts/                          # BUILD SCRIPTS
│   ├── build-image.py                #   GPT disk image builder (Python 3)
│   │                                 #   Creates 128 MB image with:
│   │                                 #     - Protective MBR
│   │                                 #     - GPT header + partition entries
│   │                                 #     - EFI System Partition (64 MB)
│   │                                 #     - Revo Data Partition (62 MB)
│   │                                 #     - Backup GPT at end of disk
│   │
│   └── setup-usb.sh                  #   USB image setup script (Bash)
│                                     #   Formats partitions, copies boot files,
│                                     #   creates loader configuration
│
├── docs/                             # DOCUMENTATION
│   ├── ARCHITECTURE.md               #   Full system architecture
│   │                                 #   Boot sequence, component interaction,
│   │                                 #   filesystem layout, kernel config
│   │
│   ├── BUILD.md                      #   Build instructions
│   │                                 #   Step-by-step guide from source,
│   │                                 #   prerequisites, verification steps
│   │
│   ├── DEVELOPMENT.md                #   Development details
│   │                                 #   Implementation explanations,
│   │                                 #   algorithms, design decisions,
│   │                                 #   error handling philosophy
│   │
│   ├── SPECS.md                      #   Technical specifications
│   │                                 #   System, kernel, userspace specs,
│   │                                 #   partition schema, boot times,
│   │                                 #   hardware compatibility
│   │
│   ├── FOLDER_STRUCTURE.md           #   This document
│   │
│   ├── FILE_TYPES.md                 #   File type explanations
│   │
│   └── USER_GUIDE.md                #   End-user guide
│                                     #   How to boot, available commands,
│                                     #   troubleshooting
│
└── dist/                             # PREBUILT BINARIES
    └── initramfs.cpio.gz             #   Pre-compiled initramfs (631 KB)
                                      #   Ready to use with kernel in QEMU
                                      #   or for USB image creation
```

---

## Directory Purposes

### `src/` — Source Code

All human-authored and curated source files that constitute Revo OS. This directory contains everything needed to reproduce the initramfs and configure the kernel. No build artifacts or downloaded binaries go here.

**Subdirectories:**

- **`src/kernel/`** — Contains the kernel configuration file used to build the Linux 6.12.94 kernel with Revo's feature set. This is the `.config` that was used by Alpine to produce `linux-virt`. Key options are documented inline with comments.

- **`src/initramfs/`** — Contains all files that go inside the initramfs cpio archive. The `init` script is the most critical file — it is PID 1 and responsible for the entire boot sequence. Configuration files (`config.json`, `passwd`, `group`) define the system's identity and user database.

- **`src/modules/`** — Contains the 7 essential kernel modules that are loaded at boot. These are the only modules from Alpine's full 200+ module set that Revo needs. Each is shipped in its already-compressed `.ko.gz` form for direct use with `insmod`.

### `scripts/` — Build Scripts

Automation scripts that transform source files and prebuilt binaries into bootable disk images.

- **`build-image.py`** — Creates a raw GPT-partitioned disk image. This is a pure Python 3 script with zero dependencies beyond the standard library. It manually constructs the MBR, GPT header, and partition entries at the byte level, following the UEFI specification.

- **`setup-usb.sh`** — Takes the raw GPT image from `build-image.py`, formats the partitions with actual filesystems, and copies all boot files into place. This script requires `sudo` for the `mkfs` and `mount` operations.

### `docs/` — Documentation

Comprehensive documentation covering every aspect of Revo OS. Six documents covering architecture, build process, development methodology, technical specifications, file type explanations, and the folder structure.

### `dist/` — Prebuilt Binaries

Distribution-ready binary artifacts. Currently contains the pre-compiled initramfs. The kernel binary is NOT included in the repository due to its size (12 MB) and licensing (GPL-2.0). Users download the kernel from Alpine Linux repositories as part of the build process.

---

## File Count Summary

| Directory | Files | Total Size |
|-----------|-------|------------|
| `src/kernel/` | 1 | ~200 KB (config file) |
| `src/initramfs/` | 5 | ~6 KB |
| `src/modules/` | 7 | ~880 KB |
| `scripts/` | 2 | ~5 KB |
| `docs/` | 7 | ~45 KB |
| `dist/` | 1 | ~631 KB |
| Root | 3 | ~8 KB |
| **Total** | **26** | **~1.8 MB** (excluding kernel binary) |

---

*Document version: 1.0 · Last updated: June 2026*
