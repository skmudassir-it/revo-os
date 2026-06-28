# Kernel Modules

These 7 kernel modules are the minimal set required for Revo OS v0.3.0. They are extracted from the Alpine Linux `linux-virt` package (6.12.94-r0).

## Module List

| Module | Purpose | Dependency |
|--------|---------|------------|
| `ext4.ko.gz` | ext4 filesystem (for data partition) | None |
| `overlay.ko.gz` | OverlayFS (for container image layering) | None |
| `vfat.ko.gz` | VFAT/FAT32 (for ESP and USB drives) | None |
| `loop.ko.gz` | Loopback block device | None |
| `virtio_blk.ko.gz` | VirtIO block driver (VMs) | None |
| `virtio_net.ko.gz` | VirtIO network driver (VMs) | None |
| `e1000.ko.gz` | Intel PRO/1000 NIC driver | None |

## Load Order

Modules are loaded in the order listed above by the init script (`src/initramfs/init`). Each module has zero dependencies on other loadable modules — they can be loaded in any order.

## Compression

All modules use `.ko.gz` (gzip) compression. The Linux kernel's module loader (`insmod`) decompresses `.ko.gz` files transparently at load time. No manual decompression is needed.

## Source

These modules are built from:
- Alpine Linux `linux-virt-6.12.94-r0`
- Package URL: `https://dl-cdn.alpinelinux.org/alpine/v3.21/main/x86_64/`
- Kernel source: `https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.tar.xz`

## Future

In Revo v0.3.0+, modules may be rebuilt from source with further size optimization (stripping debug sections, LTO, etc.).
