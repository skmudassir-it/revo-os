# Revo OS — Architecture

**Version:** 0.4.0 · **Author:** Mudassir · **June 2026**

---

## 1. System Architecture Overview

Revo OS is organized into three distinct layers, each with a well-defined boundary and responsibility. This layered architecture enables the extreme size reduction while maintaining full system functionality.

```
┌──────────────────────────────────────────────────────────────┐
│                    LAYER 2: USERSPACE                        │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  /bin/busybox (static, 1.0 MB, 306 applets)          │    │
│  │  ash shell, mount, ls, cp, grep, awk, wget, ifconfig │    │
│  │  udhcpc, ip, ping, tar, gzip, vi, cat, echo, ...     │    │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  /init (shell script, 3.5 KB)                        │
│  -> mounts proc/sys/devtmpfs                         │
│  -> mounts EFI partition (vfat)                      │
│  -> loads kernel modules via insmod                  │
│  -> mounts Revo data volume (ext4)                   │
│  -> configures network (DHCP via udhcpc)             │
│  -> starts containerd (Docker runtime)               │
│  -> starts revo-fs (package streaming daemon)        │
│  -> drops to interactive shell                       │
│  └──────────────────────────────────────────────────────┘    │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                    LAYER 1: INITRAMFS (tmpfs)                │
│                                                              │
│  Format: cpio newc, gzip-compressed (~2.4 MB)               │
│  Contents: /bin, /sbin, /etc, /dev, /proc, /sys, /tmp       │
│  + containerd (static, 1.5 MB), runc (static, 0.5 MB)       │
│  + revocker Docker CLI shim (0.1 MB)                        │
│  + revo-fs package streaming daemon (0.3 MB)                │
│  Kernel extracts this into a tmpfs at boot                  │
│  Entirely in-memory, read-only after boot                    │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                    LAYER 0: KERNEL                           │
│                                                              │
│  Linux 6.12.94 (custom `tinyconfig` build)                   │
│  Format: bzImage, x86 boot executable (4.5 MB compressed)    │
│  Key built-in features:                                      │
│    CONFIG_EFI_STUB=y      → Kernel acts as UEFI executable   │
│    CONFIG_CGROUPS=y       → Container primitives             │
│    CONFIG_NAMESPACES=y    → Process isolation                │
│    CONFIG_NVME_CORE=y     → NVMe storage support             │
│    CONFIG_EXT4_FS=y       → ext4 built-in (no module needed) │
│    CONFIG_OVERLAY_FS=y    → OverlayFS built-in               │
│                                                              │
│  Config strategy: `make tinyconfig` base (~500 options)      │
│  + selective enablement of only what Revo requires.          │
│  Alpine virt kernel: 12 MB, ~2,800 options.                  │
│  Revo tinyconfig kernel: 4.5 MB, ~500 options.               │
│  62% size reduction.                                         │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│                    HARDWARE                                   │
│                                                              │
│  x86_64 CPU (any modern Intel/AMD)                           │
│  Minimum 128 MB RAM (512 MB recommended)                     │
│  UEFI firmware (for USB boot)                                │
│  Storage: any NVMe/SATA drive                                │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. Boot Sequence (Detailed)

The boot sequence is the critical path that transforms a 13 MB compressed archive into a running operating system. Each step is deliberately designed for minimal overhead.

### Phase 1: Firmware (0.0s – 0.1s)

```
UEFI firmware
  ├── Reads GPT from disk
  ├── Finds EFI System Partition (type C12A7328-F81F-11D2-...)
  ├── Loads EFI/BOOT/BOOTX64.EFI (the kernel, acting as EFI executable)
  └── Hands off execution via EFI boot services
```

The kernel is compiled with `CONFIG_EFI_STUB=y`, which means it has a valid PE/COFF header embedded alongside the bzImage header. UEFI firmware treats the kernel as a standard EFI application.

### Phase 2: Kernel Initialization (0.1s – 0.5s)

```
Kernel entry (arch/x86/boot/header.S)
  ├── Decompresses bzImage payload (gzip → 25-30 MB uncompressed)
  ├── Initializes CPU: GDT, IDT, paging, SSE/AVX
  ├── Initializes memory: buddy allocator, slab allocator
  ├── Enumerates ACPI tables
  ├── Probes PCI bus, initializes NVMe/AHCI drivers
  ├── Mounts initial rootfs (initramfs from initrd.img)
  └── Executes /init (PID 1)
```

The EFI stub reads `initrd.img` from the same ESP directory as `BOOTX64.EFI` via the UEFI file protocol. The initramfs is loaded into a contiguous kernel memory region before userspace starts.

### Phase 3: Userspace Init (0.5s – 1.0s)

```
/init (Busybox ash script)
  │
  ├── mount -t proc none /proc
  │   Provides: /proc/cpuinfo, /proc/meminfo, /proc/mounts
  │
  ├── mount -t sysfs none /sys
  │   Provides: /sys/class, /sys/block, /sys/devices
  │
  ├── mount -t devtmpfs devtmpfs /dev
  │   Provides: /dev/sda, /dev/nvme0n1, /dev/tty*, /dev/null
  │
  ├── mount -t vfat <ESP> /boot
  │   Tries: /dev/sda1 → /dev/nvme0n1p1 → /dev/vda1
  │   Purpose: access kernel modules stored on ESP
  │
  ├── insmod /boot/modules/*.ko.gz
  │   Loads in order: ext4 → overlay → vfat → loop → virtio_blk → virtio_net
  │   Each module decompresses from .gz on the fly
  │
  ├── mount -t ext4 <data_partition> /revo
  │   Tries: /dev/sda2 → /dev/nvme0n1p2 → /dev/vda2
  │   Purpose: persistent storage for user data
  │
  ├── ip link set eth0 up
  ├── udhcpc -i eth0
  │   Purpose: DHCP network configuration
  │
  ├── containerd &
  │   Purpose: Start container runtime for Docker support
  │   containerd manages OCI container lifecycle via runc
  │   revocker CLI shim translates 'docker' commands
  │
  ├── revo-fs --cache /revo/pkgs --mesh /revo/overlay-cache &
  │   Purpose: On-demand package streaming via BitTorrent DHT
  │   Intercepts missing exec() calls, fetches .revo-pkg files
  │   Mounts squashfs overlays, creates symlinks on first use
  │
  └── exec /bin/sh
      Purpose: interactive shell for the user
```

---

## 3. Component Interaction Model

Revo uses a **flat component model with Docker support and package streaming** — the init script starts containerd and revo-fs as supervised background processes.

```
                    ┌─────────────┐
                    │   /bin/sh   │  (interactive user shell)
                    └──────┬──────┘
                           │ fork/exec
              ┌────────────┼────────────┐
              │            │            │
         ┌────┴────┐  ┌────┴────┐  ┌────┴────┐
         │ busybox │  │ busybox │  │ busybox │
         │  mount  │  │ udhcpc  │  │   vi    │
         └─────────┘  └─────────┘  └─────────┘
              │            │
    ┌─────────┴──┐    ┌───┴──────┐
    │ syscalls   │    │ syscalls │
    │ mount()    │    │ socket() │
    │ insmod()   │    │ ioctl()  │
    └──────┬─────┘    └────┬─────┘
           │               │
    ┌──────┴───────────────┴──────┐
    │         LINUX KERNEL        │
    │   (syscall interface)       │
    └─────────────────────────────┘
```

Key design choices:
- **No systemd/OpenRC/s6**: The init script directly mounts filesystems and starts networking. No supervision daemon is needed because Revo runs a single interactive session.
- **No udev**: Kernel devtmpfs (`CONFIG_DEVTMPFS=y`) auto-creates device nodes at `/dev/`.
- **No dbus**: No inter-process communication bus is required for a single-user, single-session system.
- **No syslog daemon**: Kernel messages go to `printk` ring buffer. Userspace output goes to the console.

---

## 4. Filesystem Architecture

```
/ (tmpfs, from initramfs — READ-ONLY after boot)
├── bin/          → Busybox binary + 306 symlinks
├── sbin/         → Symlinks to /bin/busybox
├── dev/          → devtmpfs (kernel-managed device nodes)
├── proc/         → procfs (kernel/process information)
├── sys/          → sysfs (kernel/driver information)
├── tmp/          → tmpfs (temporary files)
├── run/          → tmpfs (runtime state)
├── etc/
│   ├── revo/
│   │   └── config.json    → System configuration
│   ├── passwd             → User database (root only)
│   ├── group              → Group database
│   └── inittab            → Console configuration
├── root/         → Root user home directory
├── boot/         → Mount point for EFI System Partition (vfat)
├── mnt/          → General mount point
└── init          → Init script (PID 1)

/boot (EFI System Partition, vfat, mounted from ESP)
├── EFI/
│   └── BOOT/
│       ├── BOOTX64.EFI    → Kernel as EFI executable
│       └── initrd.img     → Initramfs cpio archive
└── modules/
    ├── ext4.ko.gz
    ├── overlay.ko.gz
    ├── vfat.ko.gz
    ├── loop.ko.gz
    ├── virtio_blk.ko.gz
    ├── virtio_net.ko.gz
    └── e1000.ko.gz

/revo (ext4 data partition — persistent storage)
├── user/        → User home directories
├── apps/        → Application data
└── cache/       → Package and runtime caches
```

---

## 5. Kernel Configuration Strategy

The custom Revo kernel compiled from `make tinyconfig` has approximately 500 configuration options enabled, down from Alpine's ~2,800. The full Revo vision targets this ultra-minimal build to achieve the 8 MB total system size.

### Built-In vs Module Decision

| Feature | Config | Rationale |
|---------|--------|-----------|
| cgroups v2 | `=y` (built-in) | Required for Docker container support |
| namespaces | `=y` (built-in) | Required for container isolation |
| NVMe core | `=y` (built-in) | Required to mount storage during early boot |
| devtmpfs | `=y` (built-in) | Auto-creates /dev nodes without udev |
| ext4 | `=y` (built-in) | Data partition — no module overhead |
| overlayfs | `=y` (built-in) | Docker image layering — no module overhead |
| e1000 | `=m` (module) | Network driver; loaded after boot |
| virtio | `=m` (module) | VM para-virtualized devices |

### EFI Stub Boot Flow

The `CONFIG_EFI_STUB=y` feature is what makes Revo bootable without a separate bootloader (GRUB, systemd-boot, etc.). The kernel's PE/COFF header is constructed at build time by `arch/x86/boot/tools/build.c`. When UEFI firmware loads `BOOTX64.EFI`, it:
1. Parses the PE/COFF header to find the entry point
2. Calls the EFI stub entry (`efi_pe_entry` in `arch/x86/boot/header.S`)
3. The stub sets up 64-bit mode, page tables, and calls the decompressor
4. The decompressor unpacks the real kernel and jumps to `startup_64`

---

## 6. Memory Layout at Runtime

```
0x0000000000000000  ┌──────────────────────┐
                    │  Kernel code (.text)  │  ~3.5 MB
0x0000000000800000  ├──────────────────────┤
                    │  Kernel data (.data)  │  ~2 MB
                    ├──────────────────────┤
                    │  Kernel BSS           │  ~1 MB
                    ├──────────────────────┤
                    │  Slab allocator       │
                    │  Page cache           │
                    ├──────────────────────┤
                    │  initramfs (tmpfs)    │  ~2 MB (uncompressed)
                    ├──────────────────────┤
                    │  Userspace            │
                    │  (busybox, shell)     │  ~3 MB
                    ├──────────────────────┤
                    │  Free memory          │  remaining RAM
                    └──────────────────────┘
```

Total kernel memory footprint: approximately 11 MB. Userspace adds approximately 5 MB. A system with 128 MB RAM has ~112 MB available for applications.

---

*Document version: 1.0 · Last updated: June 2026*
