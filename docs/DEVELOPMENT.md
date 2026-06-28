# Revo OS — Development Details

**Version:** 0.3.0 · **Author:** Mudassir  

This document provides in-depth technical explanations of every design decision, algorithm, and implementation detail in Revo OS. It is written for developers who want to understand not just *what* was built, but *why* and *how*.

---

## 1. Init Script Implementation (`src/initramfs/init`)

### 1.1 Design Philosophy

The init script is the heart of Revo OS — it is the first userspace process (PID 1) and responsible for bringing the entire system to a usable state. It is written as a Busybox `ash` shell script because:

- **No compilation needed** — a shell script is the smallest possible init implementation (~2 KB vs 150 KB+ for a compiled C init daemon)
- **Transparent** — the boot sequence is fully auditable by reading one file
- **Deterministic** — shell commands run sequentially with predictable outcomes
- **Extensible** — users can modify the boot sequence without recompiling

### 1.2 PID 1 Responsibilities

As PID 1, the init script has special responsibilities in the Linux kernel:

```bash
#!/bin/busybox sh
# PID 1 gets:
#   - All orphan processes re-parented to it
#   - Default SIGCHLD handler (must reap zombies)
#   - Shutdown on exit (kernel panics if PID 1 exits)
```

### 1.3 Filesystem Mounting Algorithm

```
ALGORITHM: mount_essential_filesystems()
  PURPOSE: Provide kernel interfaces for process and device management
  
  Step 1: mount procfs
    mount -t proc none /proc
    → Creates /proc/cpuinfo, /proc/meminfo, /proc/mounts, /proc/*/...
    → Kernel fills these dynamically; no persistent storage needed
    
  Step 2: mount sysfs
    mount -t sysfs none /sys
    → Creates /sys/class/net/eth0, /sys/block/sda, /sys/devices/...
    → Used by ip/ifconfig to discover network interfaces
    
  Step 3: mount devtmpfs
    mount -t devtmpfs devtmpfs /dev
    → Auto-creates device nodes: /dev/sda*, /dev/nvme*, /dev/tty*
    → Kernel-managed; no udev daemon needed
    → CONFIG_DEVTMPFS=y in kernel config enables this
```

### 1.4 ESP Discovery Algorithm

```
ALGORITHM: find_and_mount_esp()
  PURPOSE: Locate the EFI System Partition to load kernel modules
  
  INPUT: None (probes all known device paths)
  OUTPUT: /boot mounted (vfat) or skip message
  
  Attempt order (tries each in sequence, first success wins):
    1. mount -t vfat /dev/sda1 /boot   → Physical SATA disk
    2. mount -t vfat /dev/nvme0n1p1 /boot → NVMe SSD
    3. mount -t vfat /dev/vda1 /boot   → Virtio block (VM/QEMU)
  
  Each mount is wrapped in '2>/dev/null || true' to silently skip failures.
  This avoids complex device detection logic in favor of brute-force probing,
  which adds negligible boot time (< 10ms per failed mount).
  
  RATIONALE: Linux device naming is predictable on common hardware.
  SATA = sda, NVMe = nvme0n1, VirtIO = vda. Covering these three
  covers 99% of deployment scenarios (bare metal, VM, QEMU).
```

### 1.5 Module Loading Strategy

```
ALGORITHM: load_essential_modules()
  PURPOSE: Add kernel functionality not compiled into the vmlinuz
  
  INPUT: /boot/modules/ directory (mounted from ESP)
  OUTPUT: Kernel modules inserted, dmesg output
  
  Load order (dependency-aware):
    1. ext4.ko.gz    → Filesystem support for data partition
    2. overlay.ko.gz → OverlayFS for future Docker support
    3. vfat.ko.gz    → Already mounted ESP, but useful for USB
    4. loop.ko.gz    → Loopback device for squashfs/FUSE
    5. virtio_blk.ko.gz → VM block device driver
    6. virtio_net.ko.gz → VM network driver
  
  Each module is loaded via:
    insmod /boot/modules/${mod}.ko.gz 2>/dev/null
  
  The kernel's module loader handles .gz decompression transparently.
  Failed loads are silently skipped (module might already be built-in).
  e1000.ko.gz is intentionally NOT loaded automatically — it is loaded
  on-demand if the user needs physical NIC support.
```

### 1.6 Data Volume Discovery

```
ALGORITHM: find_and_mount_data()
  PURPOSE: Locate the ext4 data partition for persistent storage
  
  INPUT: None (probes /dev)
  OUTPUT: /revo mounted (ext4) or skip message
  
  Attempt order:
    1. /dev/sda2  → Second SATA partition
    2. /dev/sda3  → Third SATA partition (fallback)
    3. /dev/nvme0n1p2 → Second NVMe partition
    4. /dev/nvme0n1p3 → Third NVMe partition
    5. /dev/vda2  → Second VirtIO partition
    6. /dev/vda3  → Third VirtIO partition
  
  Only attempts ext4 mount. If the partition exists but has a different
  filesystem, the mount fails silently.
  
  RATIONALE: The build-image.py script creates partition 2 as ext4.
  This algorithm finds it regardless of storage type. Supporting both
  partition 2 and 3 allows users to customize partition layouts.
```

### 1.7 Network Configuration

```
ALGORITHM: configure_network()
  PURPOSE: Bring up loopback and attempt DHCP on the first ethernet interface
  
  Step 1: Loopback
    ip link set lo up
    → Always succeeds; required for localhost communication
    
  Step 2: DHCP on eth0
    if ip link set eth0 up; then
        udhcpc -q -t 3 -n -i eth0
    fi
    
    Flags:
      -q : Quiet mode (no verbose output)
      -t 3 : Three discovery attempts
      -n  : Exit if no lease obtained (don't background)
      -i eth0 : Interface to configure
    
    If DHCP succeeds: IP address, netmask, gateway, DNS configured
    If DHCP fails: Message displayed, system continues booting
```

### 1.8 containerd Startup (v0.2.0+)

```
ALGORITHM: start_containerd()
  PURPOSE: Launch the Docker container runtime as a background process

  Step 1: Check binaries
    Test that /bin/containerd and /bin/runc are executable.
    If either is missing, skip with a notice and continue booting.

  Step 2: Create runtime directory
    mkdir -p /run/containerd
    → containerd uses this for its Unix socket and state files

  Step 3: Launch containerd
    containerd &
    CONTAINERD_PID=$!

  Step 4: Verify startup
    sleep 1 (wait for daemon to initialize)
    kill -0 $CONTAINERD_PID → test if process is alive
    
    On success: "containerd running (PID N)" + "revocker ready"
    On failure: "containerd failed to start"

  RATIONALE: containerd runs as a background process supervised
  by PID 1. If it crashes, PID 1 reaps it. The user can restart
  it manually. This is simpler than systemd/s6 and adds only
  ~200ms to boot time.
```

### 1.9 revo-fs Startup (v0.3.0+)

```
ALGORITHM: start_revo_fs()
  PURPOSE: Launch the on-demand package streaming daemon

  Step 1: Check binary
    Test that /bin/revo-fs is executable.
    If missing, skip with a notice (packages pre-bundled).

  Step 2: Create cache directories
    mkdir -p /revo/pkgs          → squashfs package cache
    mkdir -p /revo/overlay-cache → FUSE overlay mount points

  Step 3: Launch revo-fs
    revo-fs --cache /revo/pkgs --mesh /revo/overlay-cache &
    REVOFS_PID=$!

    Flags:
      --cache /revo/pkgs     → Where downloaded .revo-pkg files are stored
      --mesh /revo/overlay-cache → DHT state + overlay mount points

  Step 4: Verify startup
    sleep 1 (wait for FUSE mount + DHT bootstrap)
    kill -0 $REVOFS_PID → test if process is alive

    On success: "revo-fs running" + "Package mesh connected"
    On failure: "revo-fs failed to start"

  RATIONALE: revo-fs uses FUSE (Filesystem in Userspace) to
  intercept missing exec() calls. The kernel's FUSE module
  (CONFIG_FUSE_FS=y) routes filesystem ops to the userspace
  daemon. No custom kernel module needed.
```

### 1.10 How revo-fs Streams Packages

```
ALGORITHM: revo_fs_exec_intercept()
  Trigger: User runs a command not found in /bin

  Step 1: Shell searches PATH
    /bin/python3 → not found
    /usr/bin/python3 → not found (but revo-fs wrapper exists)
    /usr/local/python3 → revo-fs FUSE mount point

  Step 2: FUSE lookup sent to revo-fs daemon
    revo-fs receives FUSE_LOOKUP for "python3"

  Step 3: Check local cache
    Look for /revo/pkgs/python3-3.12.7.revo-pkg
    If found: mount squashfs at /usr/local/python3, return EEXIST

  Step 4: Query DHT
    infohash = SHA-256("python3-3.12.7.x86_64")
    DHT lookup → find peers seeding this package

  Step 5: Download
    BitTorrent v2 transfer (parallel from multiple peers)
    Verify SHA-256 of received .revo-pkg

  Step 6: Mount and link
    mount -t squashfs /revo/pkgs/python3-3.12.7.revo-pkg /usr/local/python3
    ln -sf /usr/local/python3/usr/bin/python3 /usr/bin/python3

  Step 7: Return
    revo-fs returns file attributes to kernel
    Kernel retries exec() → succeeds

  Cold start latencies:
    Package lookup + DHT query: ~100ms
    Download (100 Mbps, 15 MB package): ~1.2s
    SHA-256 verify + mount: ~50ms
    Total first use: ~1.4s

  Cached (warm):
    Squashfs mount: ~30ms
    Total: ~30ms
```

---

## 2. GPT Disk Image Builder (`scripts/build-image.py`)

### 2.1 Purpose

The GPT image builder creates a raw disk image with a valid GUID Partition Table (GPT) and protective MBR. This image can be flashed directly to a USB drive or booted in a VM.

### 2.2 Partition Layout

```
SECTOR    SIZE        CONTENTS
──────────────────────────────────────────────
0         512 B       Protective MBR (boot code + partition entry)
1         512 B       GPT Header (signature, table location, CRCs)
2-5       2 KB        GPT Partition Entries (4 entries × 128 bytes)
6-2047    ~1 MB       Unused (alignment boundary)
2048      64 MB       EFI System Partition (FAT32, empty)
133120    62 MB       Revo Data Partition (ext4, empty)
133120+   512 B       GPT Partition Entries (backup copy)
end-512   512 B       GPT Header (backup copy)
```

### 2.3 Protective MBR Construction

```
The protective MBR at sector 0 follows the UEFI specification:
  
  Bytes 0-439:    Boot code (prints "UEFI only" message for BIOS users)
  Bytes 440-443:  Disk signature ("REVO" = 0x5245564F)
  Bytes 444-445:  Zero (reserved)
  Bytes 446-461:  Single partition entry (type 0xEF, covers entire disk)
  Bytes 510-511:  Boot signature (0x55AA)
  
  The protective MBR exists for backward compatibility. Non-UEFI systems
  see one EFI partition spanning the disk, preventing them from
  accidentally damaging the GPT structure.
```

### 2.4 GPT Header Fields

```python
# GPT Header Layout (128 bytes at LBA 1)
gh[0:8]   = b"EFI PART"     # Signature
gh[8:12]  = 0x00010000      # Revision 1.0
gh[12:16] = 92              # Header size (bytes)
gh[16:20] = 0               # CRC32 (reserved, filled by some tools)
gh[20:24] = 0               # Reserved
gh[24:32] = 1               # This header's LBA (always 1)
gh[32:40] = last_lba        # Backup header's LBA
gh[40:48] = 34              # First usable LBA (after GPT entries)
gh[48:56] = last_usable     # Last usable LBA (before backup entries)
gh[56:72] = disk_guid       # Disk GUID (random UUID)
gh[72:80] = 2               # Partition entries starting LBA
gh[80:84] = 4               # Number of partition entries
gh[84:88] = 128             # Size of each entry (bytes)
gh[88:92] = 0               # CRC32 of partition entries
# Bytes 92-511: Reserved (zeros)
```

### 2.5 Partition Entry Structure

```python
# Each GPT partition entry is 128 bytes
ENTRY_0 (ESP):
  type_guid  = C12A7328-F81F-11D2-BA4B-00A0C93EC93B  # EFI System Partition
  uniq_guid  = random UUID
  start_lba  = 2048                                    # Aligned at 1 MB
  end_lba    = 2048 + 131071                           # 64 MB total
  attributes = 0
  name       = "REVO_ESP" (36 UTF-16LE characters)

ENTRY_1 (Data):
  type_guid  = 0FC63DAF-8483-4772-8E79-3D69D8477DE4  # Linux filesystem
  uniq_guid  = random UUID
  start_lba  = 133120                                  # After ESP
  end_lba    = 133120 + 128989                         # Remaining space
  attributes = 0
  name       = "REVO_DATA" (36 UTF-16LE characters)
```

### 2.6 Backup GPT

```python
# The backup GPT is written at the END of the disk:
#   Backup Entries: last 33 sectors → LBA (end - 32)
#   Backup Header:  last sector    → LBA (end - 0)
#
# The backup header is identical except:
#   - Mirror of primary LBA and backup LBA fields are swapped
#   - Partition entries starting LBA points to the backup entries location
```

---

## 3. USB Setup Script (`scripts/setup-usb.sh`)

### 3.1 Workflow

```
setup-usb.sh executes these steps in order:

  1. LOSETUP: Attach image to loopback device
     sudo losetup -P -f revo-os-v0.3.0.img
     The -P flag auto-creates partition devices (loop0p1, loop0p2)
     
  2. MKFS: Format both partitions
     sudo mkfs.vfat -F32 -n REVO_ESP /dev/loop0p1
     sudo mkfs.ext4 -L revo-data /dev/loop0p2
     
  3. MOUNT: Mount the ESP
     sudo mount /dev/loop0p1 /mnt/revo-esp
     
  4. COPY: Place boot files
     kernel → /mnt/revo-esp/EFI/BOOT/BOOTX64.EFI
     initrd → /mnt/revo-esp/EFI/BOOT/initrd.img
     modules → /mnt/revo-esp/modules/*.ko.gz
     
  5. BOOTLOADER CONFIG: Create loader entry
     /mnt/revo-esp/loader/entries/revo.conf
     
  6. CLEANUP: Unmount and detach
     sudo umount /mnt/revo-esp
     sudo losetup -d /dev/loop0
```

---

## 4. Size Optimization Techniques

### 4.1 Kernel Size Reduction

| Technique | Savings | Status |
|-----------|---------|--------|
| Use prebuilt `linux-virt` instead of `linux-lts` | ~4 MB | Implemented |
| Disable unused drivers in config | ~2 MB | Partially (uses Alpine's config) |
| XZ compression instead of gzip | ~2 MB | Future (requires custom build) |
| `make tinyconfig` base + selective enablement | ~6 MB | Future (Phase 4) |

### 4.2 Initramfs Size Reduction

| Technique | Savings | Status |
|-----------|---------|--------|
| Busybox static binary (no separate libc) | ~2 MB | Implemented |
| Shell-based init script (no compiled init) | ~150 KB | Implemented |
| No udev, no modules at boot | ~1 MB | Implemented |
| No CA certificates bundle | ~200 KB | Implemented |
| Only essential /etc files | ~100 KB | Implemented |

### 4.3 Module Size Reduction

| Technique | Savings | Status |
|-----------|---------|--------|
| Only 7 modules (vs 200+ in full Alpine) | ~30 MB | Implemented |
| .gz compressed modules (kernel-supported) | ~50% | Implemented |

---

## 5. Error Handling Philosophy

Revo OS uses **graceful degradation** as its error handling strategy:

- **Mount failures**: Print notice, continue booting
- **Module load failures**: Skip silently (might be built-in)
- **Network failures**: Print notice, continue to shell
- **Data partition missing**: Boot into memory-only mode

The system never halts on non-critical failures. This ensures the user always reaches a shell where they can diagnose and fix issues.

---

*Document version: 1.0 · Last updated: June 2026*
