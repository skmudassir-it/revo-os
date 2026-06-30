# Prebuilt Binaries

This directory contains pre-compiled binary artifacts for Revo OS.

## initramfs.cpio.gz

- **Size:** 631 KB (compressed)
- **Format:** cpio archive (newc format) + gzip compression
- **Contents:** Busybox userspace (306 applets), init script, system configuration
- **Built from:** `src/initramfs/` source files + Alpine Busybox static binary

## Kernel

The kernel binary (`vmlinuz-virt`) is **not included** in the repository due to:
1. File size (12 MB would bloat the repository)
2. Licensing (GPL-2.0 requires source distribution alongside binary)

Download it from Alpine Linux:
```bash
wget https://dl-cdn.alpinelinux.org/alpine/v3.21/main/x86_64/linux-virt-6.12.94-r0.apk
tar xzf linux-virt-6.12.94-r0.apk
cp boot/vmlinuz-virt ../dist/
```

See [BUILD.md](../docs/BUILD.md) for full instructions.
