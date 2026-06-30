# Revo OS — File Types Reference

**Version:** 0.1.0 · **Author:** Mudassir  

This document catalogs every file type in the Revo OS repository, explaining its role, format, and how it fits into the build pipeline.

---

## 1. Shell Scripts (`.sh`)

| File | Purpose |
|------|---------|
| `src/initramfs/init` | PID 1 init script — the first userspace process |
| `scripts/setup-usb.sh` | USB image finalization — formats partitions, copies boot files |

**Format:** POSIX shell scripts executed by Busybox `ash`. Use only Busybox-compatible syntax (no Bash-isms like arrays or `[[`).

**Role in Build Pipeline:** The `init` script is embedded in the initramfs and executed by the kernel at boot. `setup-usb.sh` is run by the user during the build process.

**Design Constraints:**
- Maximum ~2.5 KB (init script)
- No external dependencies beyond busybox applets
- Must handle all error paths with graceful degradation

---

## 2. Python Scripts (`.py`)

| File | Purpose |
|------|---------|
| `scripts/build-image.py` | Creates GPT-partitioned raw disk image |

**Format:** Python 3 (compatible with 3.8+). No external dependencies beyond the Python standard library.

**Role in Build Pipeline:** Run during the build process to create a 128 MB raw disk image with protective MBR, GPT header, partition entries, and backup GPT structures.

**Key Libraries Used:**
- `struct` — Binary data packing (MBR, GPT headers)
- `os` — File I/O and path operations
- `uuid` — Random UUID generation for partition GUIDs

**Design Notes:**
- Manually constructs partition table structures at the byte level
- Follows UEFI Specification v2.10 for GPT format
- Creates sparse files for efficient storage

---

## 3. Kernel Modules (`.ko.gz`)

| File | Purpose |
|------|---------|
| `src/modules/ext4.ko.gz` | ext4 filesystem support |
| `src/modules/overlay.ko.gz` | OverlayFS for container image layering |
| `src/modules/vfat.ko.gz` | VFAT/FAT32 filesystem support |
| `src/modules/loop.ko.gz` | Loopback block device |
| `src/modules/virtio_blk.ko.gz` | VirtIO para-virtualized block driver |
| `src/modules/virtio_net.ko.gz` | VirtIO para-virtualized network driver |
| `src/modules/e1000.ko.gz` | Intel PRO/1000 network driver |

**Format:** Linux kernel modules (ELF64 relocatable objects) compressed with gzip. The `.ko.gz` extension allows `insmod` to decompress transparently.

**Role in Build Pipeline:** Extracted from Alpine Linux `linux-virt` package. Only 7 of 200+ available modules are included — the absolute minimum needed for filesystem and network support.

**Selection Criteria:**
- ext4 & vfat: Required for mounting the data partition and ESP
- overlay: Required for future Docker/container support
- loop: Required for squashfs and FUSE filesystems
- virtio_*: Required for running in VMs (QEMU, VirtualBox)
- e1000: Required for physical Intel NICs and QEMU's default network

---

## 4. Configuration Files (`.json`)

| File | Purpose |
|------|---------|
| `src/initramfs/config.json` | Revo OS system configuration |

**Format:** JavaScript Object Notation (JSON).

**Role:** Defines system identity and behavior parameters read by the init script.

**Contents:**
```json
{
  "hostname": "revo",
  "version": "0.1.0",
  "codename": "revo"
}
```

---

## 5. System Database Files

| File | Purpose |
|------|---------|
| `src/initramfs/passwd` | Unix user database |
| `src/initramfs/group` | Unix group database |
| `src/initramfs/inittab` | Console and terminal configuration |

### passwd Format

Standard Unix colon-delimited format:
```
root::0:0:root:/root:/bin/sh
```
Fields: username, password (empty = no password), UID, GID, GECOS, home directory, shell

### group Format

```
root:x:0:
```
Fields: group name, password placeholder, GID, member list

### inittab Format

Busybox init format (subset of SysV init):
```
::sysinit:/etc/init.d/rcS
tty1::respawn:/sbin/getty 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
```
Fields: terminal, runlevel, action, process

---

## 6. Documentation Files (`.md`)

| File | Purpose |
|------|---------|
| `README.md` | Project overview and quick start |
| `docs/ARCHITECTURE.md` | System architecture and boot sequence |
| `docs/BUILD.md` | Step-by-step build instructions |
| `docs/DEVELOPMENT.md` | Implementation details and design decisions |
| `docs/SPECS.md` | Technical specifications |
| `docs/FOLDER_STRUCTURE.md` | Directory tree breakdown |
| `docs/FILE_TYPES.md` | This document |
| `docs/USER_GUIDE.md` | End-user instructions |

**Format:** GitHub-Flavored Markdown (GFM).

---

## 7. Prebuilt Binary (`.cpio.gz`)

| File | Purpose |
|------|---------|
| `dist/initramfs.cpio.gz` | Pre-compiled initramfs archive |

**Format:** cpio archive (newc format) compressed with gzip.

**Role:** This is the bootable userspace — the kernel extracts it into a tmpfs at boot and executes `/init` inside it.

**Contents:**
- `/init` — Init script (PID 1)
- `/bin/busybox` — Static Busybox binary + 306 symlinks
- `/etc/` — System configuration files
- `/proc/`, `/sys/`, `/dev/`, `/tmp/` — Empty mount point directories

---

## 8. Kernel Configuration File (`.config`)

| File | Purpose |
|------|---------|
| `src/kernel/config-6.12.94-0-virt` | Linux kernel build configuration |

**Format:** Linux kernel Kconfig format — `CONFIG_OPTION=value` lines.

**Role:** Documents the exact kernel configuration used to produce the Revo-compatible kernel. Not used at runtime; used to reproduce or modify the kernel build.

**Key Options Documented:**
```properties
CONFIG_EFI_STUB=y            # Boot without bootloader
CONFIG_EFI_HANDOVER_PROTOCOL=y  # UEFI boot protocol
CONFIG_CGROUPS=y             # Container resource control
CONFIG_NAMESPACES=y          # Container isolation
CONFIG_DEVTMPFS=y            # Auto /dev population
CONFIG_EXT4_FS=m             # ext4 as module
CONFIG_OVERLAY_FS=m          # OverlayFS as module
```

---

## 9. License File

| File | Purpose |
|------|---------|
| `LICENSE` | MIT License text |

**Format:** Plain text.

---

## 10. Git Configuration

| File | Purpose |
|------|---------|
| `.gitignore` | Git ignore rules |

**Format:** Git ignore patterns.

**Purpose:** Prevents build artifacts, downloaded binaries, and system files from being committed to the repository. The kernel binary (12 MB) and Alpine packages are excluded — users must download them separately.

---

## File Type Summary

| Extension | Type | Count | Total Size |
|-----------|------|-------|------------|
| `.md` | Markdown documentation | 8 | ~52 KB |
| `.sh` | Shell script | 2 | ~5 KB |
| `.py` | Python script | 1 | ~3 KB |
| `.json` | JSON configuration | 1 | ~100 B |
| `.ko.gz` | Compressed kernel module | 7 | ~880 KB |
| `.cpio.gz` | Compressed initramfs | 1 | ~631 KB |
| (no ext) | System files (passwd, etc.) | 4 | ~200 B |
| `config-*` | Kernel configuration | 1 | ~200 KB |
| `LICENSE` | License text | 1 | ~1 KB |
| **Total** | | **26** | **~1.8 MB** |

---

*Document version: 1.0 · Last updated: June 2026*
