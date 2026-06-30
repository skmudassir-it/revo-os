# Downloads

Alpine Linux base images for all supported architectures and devices. Sourced from [alpinelinux.org/downloads](https://alpinelinux.org/downloads/).

## Quick Download

```bash
# Interactive menu
./downloads/download.sh

# Or target a specific device:
./downloads/download.sh --device pi5       # Raspberry Pi 5
./downloads/download.sh --device desktop   # PC/Laptop
./downloads/download.sh --device server    # VM/Server
./downloads/download.sh --device container # Docker
./downloads/download.sh --device arm       # ARM board

# List all options
./downloads/download.sh --list

# Download everything
./downloads/download.sh --all
```

## Manifest

See [`alpine-manifest.json`](alpine-manifest.json) for the complete listing of all 40 unique download files across 9 architectures and 8 variants.

## Supported Architectures

| Architecture | Devices | Variants |
|-------------|---------|----------|
| **x86_64** | Desktops, laptops, servers, VMs, containers | standard, extended, netboot, virt, minirootfs, xen |
| **x86** | 32-bit PCs, older hardware | standard, extended, netboot, virt, minirootfs |
| **aarch64** | ARM64: Raspberry Pi 3/4/5, AWS Graviton, Apple Silicon VMs | standard, netboot, virt, rpi, minirootfs, uboot |
| **armv7** | ARM32: Raspberry Pi 2/3, older ARM boards | standard, netboot, virt, rpi, minirootfs, uboot |
| **armhf** | ARM hard-float: Raspberry Pi Zero/1 | netboot, rpi, minirootfs |
| **ppc64le** | IBM POWER8/9/10 servers | standard, netboot, minirootfs |
| **s390x** | IBM Z / LinuxONE mainframes | standard, netboot, minirootfs |
| **riscv64** | RISC-V development boards | standard, minirootfs, uboot |
| **loongarch64** | Loongson CPUs | standard, minirootfs |

## Device Quick Reference

| Your Device | Command | File |
|------------|---------|------|
| 💻 Desktop / Laptop | `--device desktop` | alpine-extended-3.24.1-x86_64.iso |
| 🖥️ Server / VM | `--device server` | alpine-virt-3.24.1-x86_64.iso |
| 🥧 Raspberry Pi 5 | `--device pi5` | alpine-rpi-3.24.1-aarch64.img.gz |
| 🥧 Raspberry Pi 4 | `--device pi4` | alpine-rpi-3.24.1-aarch64.img.gz |
| 🥧 Raspberry Pi 3 | `--device pi3` | alpine-rpi-3.24.1-aarch64.img.gz |
| 🥧 Raspberry Pi Zero/1 | `--device pi0` | alpine-rpi-3.24.1-armhf.img.gz |
| 📦 Docker | `--device container` | alpine-minirootfs-3.24.1-x86_64.tar.gz |
| 🔧 ARM Board (U-Boot) | `--device arm` | alpine-uboot-3.24.1-aarch64.tar.gz |
| 🌐 Network Boot (PXE) | `--device netboot` | alpine-netboot-3.24.1-x86_64.tar.gz |

## Verifying Downloads

Every file has a SHA-256 checksum automatically downloaded alongside it:

```bash
sha256sum -c revo-downloads/x86_64/alpine-extended-3.24.1-x86_64.iso.sha256
```

GPG signatures are also available at `{file_url}.asc`.
