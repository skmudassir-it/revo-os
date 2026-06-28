# Revo OS — Build Guide

**Version:** 0.3.0 · **Author:** Mudassir  

---

## 1. Build Overview

Revo OS v0.3.0 is built by assembling pre-compiled components and adding the revo-fs package streaming daemon. The initramfs is leaner because packages are fetched on-demand rather than bundled.

### Build Pipeline

```
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│ Alpine Linux     │    │ Alpine Busybox   │    │ Init Script      │
│ linux-virt 6.12  │    │ static 1.37.0    │    │ (hand-written)   │
│ (prebuilt .apk)  │    │ (prebuilt .apk)  │    │                  │
│ + containerd     │    │ + runc binaries  │    │ + revocker.sh    │
│                  │    │ + revo-fs daemon │    │ + revo-fs hooks  │
└────────┬─────────┘    └────────┬─────────┘    └────────┬─────────┘
         │                       │                       │
         ├─ vmlinuz-virt (12 MB) │                       │
         ├─ modules/*.ko.gz      │                       │
         │                       │                       │
         │              ┌────────┴────────┐              │
         │              │ busybox.static  │              │
         │              │ symlink farm    │              │
         │              └────────┬────────┘              │
         │                       │                       │
         └───────────┬───────────┴───────────┬───────────┘
                     │                       │
              ┌──────┴───────────────────────┴──────┐
              │     cpio + gzip                    │
              │     → initramfs.cpio.gz (~2.4 MB)     │
              └──────────────────┬─────────────────┘
                                 │
              ┌──────────────────┴─────────────────┐
              │  build-image.py (GPT partitioner)   │
              │  + setup-usb.sh (format + copy)     │
              │  → revo-os-v0.3.0.img (128 MB)     │
              └──────────────────┬─────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │  REVO OS BOOTABLE IMAGE  │
                    └─────────────────────────┘
```

---

## 2. Build Prerequisites

### Required Tools (for full build from prebuilt components)

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| `python3` | 3.8+ | GPT image builder |
| `bash` | 4.0+ | Setup scripts |
| `busybox cpio` | any | Initramfs packaging (or `cpio` command) |
| `gzip` | any | Initramfs compression |
| `sudo` | any | Partition formatting (mkfs) |
| `mkfs.vfat` | any (dosfstools) | EFI partition formatting |
| `mkfs.ext4` | any (e2fsprogs) | Data partition formatting |
| `losetup` | any (util-linux) | Loopback device setup |

### Optional

| Tool | Purpose |
|------|---------|
| `qemu-system-x86_64` | Testing without physical hardware |
| `wget` | Downloading Alpine packages |

---

## 3. Step-by-Step Build Instructions

### Step 1: Download Alpine Kernel

```bash
# Download the linux-virt kernel package
wget https://dl-cdn.alpinelinux.org/alpine/v3.21/main/x86_64/linux-virt-6.12.94-r0.apk

# Extract
tar xzf linux-virt-6.12.94-r0.apk
# Produces: boot/vmlinuz-virt, boot/config-*, lib/modules/
```

**What this gives you:**
- `boot/vmlinuz-virt` — The compressed kernel (12 MB)
- `boot/config-6.12.94-0-virt` — Kernel configuration file
- `lib/modules/6.12.94-0-virt/` — All kernel modules (31 MB)
- `boot/System.map-*` — Kernel symbol map

### Step 2: Download Busybox

```bash
wget https://dl-cdn.alpinelinux.org/alpine/v3.21/main/x86_64/busybox-static-1.37.0-r14.apk
tar xzf busybox-static-1.37.0-r14.apk
# Produces: bin/busybox.static (1 MB, statically linked)
```

### Step 3: Build the Initramfs

```bash
# Create initramfs directory structure
mkdir -p initramfs/{bin,sbin,dev,proc,sys,tmp,run,etc/revo,root,boot,mnt,usr/{bin,lib}}

# Copy busybox and create symlink farm
cp bin/busybox.static initramfs/bin/busybox
chmod 755 initramfs/bin/busybox
for applet in $(./bin/busybox.static --list); do
    ln -sf /bin/busybox "initramfs/bin/$applet"
done

# Create /init script (see src/initramfs/init)
# Copy system config files
cp src/initramfs/init initramfs/init
cp src/initramfs/config.json initramfs/etc/revo/config.json
cp src/initramfs/passwd initramfs/etc/passwd
cp src/initramfs/group initramfs/etc/group
cp src/initramfs/inittab initramfs/etc/inittab
chmod 755 initramfs/init

# Package as cpio archive
cd initramfs
find . -print0 | busybox cpio -o -H newc --null | gzip > ../initramfs.cpio.gz
cd ..

# Result: initramfs.cpio.gz (~2.7 MB, includes containerd + runc)
```

### Step 3c: Add revo-fs Package Streaming Daemon

```bash
# Build revo-fs from source (static binary)
git clone https://github.com/skmudassir-it/revo-fs.git
cd revo-fs
make static REVOFS_VERSION=0.3.0
cp revo-fs ../initramfs/bin/revo-fs
strip ../initramfs/bin/revo-fs
cd ..

# Create revo-fs FUSE mount point helper
mkdir -p initramfs/usr/local
chmod 755 initramfs/bin/revo-fs

# Package initramfs (now ~2.4 MB — smaller because revo-fs streams pkgs on-demand)
cd initramfs
find . -print0 | busybox cpio -o -H newc --null | gzip > ../initramfs.cpio.gz
cd ..
```

### Step 3b: Add Docker Runtime (containerd + runc + revocker)

```bash
# Download containerd static binary
wget https://github.com/containerd/containerd/releases/download/v2.0.0/containerd-2.0.0-linux-amd64.tar.gz
tar xzf containerd-2.0.0-linux-amd64.tar.gz -C containerd-bin/
cp containerd-bin/bin/containerd initramfs/bin/containerd
strip initramfs/bin/containerd

# Get runc static binary
wget https://github.com/opencontainers/runc/releases/download/v1.2.0/runc.amd64
cp runc.amd64 initramfs/bin/runc
chmod 755 initramfs/bin/runc
strip initramfs/bin/runc

# Create revocker Docker CLI shim (lightweight wrapper script)
cat > initramfs/bin/docker << 'REVOCKER_EOF'
#!/bin/busybox sh
# revocker — Docker CLI compatibility shim for containerd
# Translates 'docker' commands to 'ctr' (containerd CLI)
CMD="$1"; shift
case "$CMD" in
    ps)     ctr task ls ;;
    images) ctr image ls ;;
    run)    ctr run --rm "$@" ;;
    pull)   ctr image pull "$@" ;;
    *)      echo "revocker: unknown command '$CMD'"; exit 1 ;;
esac
REVOCKER_EOF
chmod 755 initramfs/bin/docker

# Package initramfs (now ~2.7 MB)
cd initramfs
find . -print0 | busybox cpio -o -H newc --null | gzip > ../initramfs.cpio.gz
cd ..

### Step 4: Select Essential Kernel Modules

```bash
mkdir -p modules_out

# Copy only what Revo needs (file sizes in compressed form)
cp lib/modules/*/kernel/fs/ext4/ext4.ko.gz modules_out/       # 536 KB
cp lib/modules/*/kernel/fs/overlayfs/overlay.ko.gz modules_out/ # 115 KB
cp lib/modules/*/kernel/fs/fat/vfat.ko.gz modules_out/        # 16 KB
cp lib/modules/*/kernel/drivers/block/loop.ko.gz modules_out/ # 24 KB
cp lib/modules/*/kernel/drivers/block/virtio_blk.ko.gz modules_out/ # 18 KB
cp lib/modules/*/kernel/drivers/net/virtio_net.ko.gz modules_out/ # 68 KB
cp lib/modules/*/kernel/drivers/net/ethernet/intel/e1000/e1000.ko.gz modules_out/ # 96 KB

# Total: ~880 KB
```

### Step 5: Build GPT Disk Image

```bash
python3 scripts/build-image.py
# Result: revo-os-v0.3.0.img (128 MB, GPT-partitioned)
# Partition 1: EFI System Partition (64 MB, type C12A7328-...)
# Partition 2: Revo Data (62 MB, type 0FC63DAF-...)
```

### Step 6: Format and Populate

```bash
sudo ./scripts/setup-usb.sh
# This script:
#   1. Sets up loopback device with the image
#   2. Formats p1 as FAT32 (REVO_ESP label)
#   3. Formats p2 as ext4 (revo-data label)
#   4. Copies vmlinuz-virt → /EFI/BOOT/BOOTX64.EFI
#   5. Copies initramfs.cpio.gz → /EFI/BOOT/initrd.img
#   6. Copies modules → /modules/
#   7. Cleans up loopback device
```

### Step 7: Flash to USB

```bash
sudo dd if=revo-os-v0.3.0.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

---

## 4. Custom Kernel Compilation (Advanced)

For users who want to compile their own kernel from source:

```bash
# Download kernel source
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.tar.xz
tar xJf linux-6.12.tar.xz
cd linux-6.12

# Start from minimal config
make tinyconfig

# Enable essential features
./scripts/config -e CONFIG_64BIT
./scripts/config -e CONFIG_SMP
./scripts/config -e CONFIG_EFI
./scripts/config -e CONFIG_EFI_STUB
./scripts/config -e CONFIG_EFI_HANDOVER_PROTOCOL
./scripts/config -e CONFIG_EFI_PARTITION
./scripts/config -e CONFIG_CGROUPS
./scripts/config -e CONFIG_NAMESPACES
./scripts/config -e CONFIG_BLK_DEV_NVME
./scripts/config -e CONFIG_EXT4_FS
./scripts/config -e CONFIG_OVERLAY_FS
./scripts/config -e CONFIG_VFAT_FS
./scripts/config -e CONFIG_DEVTMPFS
./scripts/config -e CONFIG_NET
./scripts/config -e CONFIG_INET
./scripts/config -e CONFIG_PACKET
./scripts/config -e CONFIG_NETDEVICES
./scripts/config -e CONFIG_E1000
./scripts/config -e CONFIG_VIRTIO_BLK
./scripts/config -e CONFIG_VIRTIO_NET
./scripts/config -e CONFIG_BLK_DEV_LOOP

# Build
make -j$(nproc) bzImage
make -j$(nproc) modules

# Result: arch/x86/boot/bzImage (~4-6 MB with tinyconfig base)
```

---

## 5. Verification

### Verify kernel has EFI stub

```bash
file boot/vmlinuz-virt
# Expected: "Linux kernel x86 boot executable bzImage..."
grep "CONFIG_EFI_STUB=y" boot/config-6.12.94-0-virt
# Expected: CONFIG_EFI_STUB=y
```

### Verify initramfs structure

```bash
gzip -dc initramfs.cpio.gz | cpio -t | head -20
# Should show: ., proc, bin, bin/sh, bin/busybox, init, etc/revo/config.json, ...
```

### Verify GPT image

```bash
python3 -c "
with open('revo-os-v0.3.0.img', 'rb') as f:
    f.seek(512)
    hdr = f.read(512)
    print('GPT Signature:', hdr[0:8])
    print('First usable LBA:', int.from_bytes(hdr[40:48], 'little'))
    print('Last usable LBA:', int.from_bytes(hdr[48:56], 'little'))
"
```

### Test boot in QEMU

```bash
qemu-system-x86_64 -m 2G \
  -kernel boot/vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" -nographic
# Should show Revo banner and drop to # prompt within 2 seconds
```

---

*Document version: 1.0 · Last updated: June 2026*
