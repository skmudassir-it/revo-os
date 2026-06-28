# Revo OS v0.2.0

**The 15-Megabyte Operating System — Docker Built-In**

Built: June 2026 | Kernel: 6.12.94 (Alpine virt) | Arch: x86_64

## What you get

- **Linux kernel 6.12.94** — stripped virt kernel with EFI stub support
- **Busybox userspace** — 306 applets (shell, networking, filesystem tools)
- **Essential kernel modules** — ext4, overlayfs, vfat, loop, virtio, e1000
- **Docker built-in** — static containerd + runc + revocker CLI shim
- **15 MB compressed** — kernel + initramfs + modules + setup scripts
- **UEFI bootable** — the kernel IS the bootloader (CONFIG_EFI_STUB=y)

## How to use

### Option 1: Test in QEMU (fastest)

```bash
tar xzf revo-os-v0.2.0.tar.gz
cd revo-package
qemu-system-x86_64 \
  -m 2G \
  -kernel vmlinuz-virt \
  -initrd initramfs.cpio.gz \
  -append "console=ttyS0 quiet" \
  -nographic
```

### Option 2: Create bootable USB

```bash
# Extract
tar xzf revo-os-v0.2.0.tar.gz
cd revo-package

# Build partition image + flash to USB
python3 build-image.py          # Creates 128 MB GPT image
sudo ./setup-usb.sh             # Formats partitions + copies files

# Write to USB (replace sdX with your USB device)
sudo dd if=revo-os-v0.2.0.img of=/dev/sdX bs=4M status=progress conv=fsync
```

The USB will boot on any UEFI x86_64 machine. Just enable UEFI boot in BIOS.

### Option 3: Manual USB setup

```bash
# Partition USB (assume /dev/sdX)
sudo parted /dev/sdX mklabel gpt
sudo parted /dev/sdX mkpart ESP fat32 1MiB 65MiB
sudo parted /dev/sdX mkpart data ext4 65MiB 100%
sudo parted /dev/sdX set 1 esp on

# Format
sudo mkfs.vfat -F32 /dev/sdX1
sudo mkfs.ext4 /dev/sdX2

# Copy files
sudo mount /dev/sdX1 /mnt
sudo mkdir -p /mnt/EFI/BOOT /mnt/modules
sudo cp vmlinuz-virt /mnt/EFI/BOOT/BOOTX64.EFI
sudo cp initramfs.cpio.gz /mnt/EFI/BOOT/initrd.img
sudo cp modules/*.ko.gz /mnt/modules/
sudo umount /mnt
```

## What boots

- Revo greets you with a banner showing kernel version, CPU cores, RAM
- Loads essential modules from the EFI partition
- Tries DHCP on eth0
- **Starts containerd** — Docker runtime available immediately
- Mounts /dev/sda2 (or nvme0n1p2) as the Revo data volume
- Drops you to an ash shell with `docker` commands ready

## Docker in Revo

Revo v0.2.0 ships with **built-in Docker support**:

```bash
# Check Docker status
docker ps

# Pull and run a container
docker run -it alpine:latest sh
```

The `docker` command is provided by **revocker**, a lightweight 100 KB CLI shim that translates Docker commands to containerd instructions. Under the hood:
- **containerd** (static, stripped, ~1.5 MB) manages container lifecycle
- **runc** (static, stripped, ~0.5 MB) handles OCI runtime execution
- **revocker** (static, ~100 KB) provides the familiar `docker` CLI

Container images are stored on the Revo data volume (`/revo/containers/`).

## Next steps (revo-fs, kernel diet, etc.)

This v0.2.0 adds Docker to the minimal kernel + initramfs base. The next phases:

1. **v0.3.0** — revo-fs: on-demand package streaming (12 MB target)
2. **v0.4.0** — Custom-compiled kernel (`tinyconfig` base, 8 MB target)
3. **v1.0.0** — Full Ubuntu feature parity via overlay mesh (10 MB target)

See the full blueprint: revo-os-kernel-blueprint.md

## License

Kernel: GPL-2.0 | Busybox: GPL-2.0 | Setup scripts: MIT
