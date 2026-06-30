#!/bin/sh
# Revo OS — Kernel Build Script (10 MB target)
# Compiles Linux kernel with minimal config for Revo OS
#
# Prerequisites: sudo apt install flex bison libelf-dev libssl-dev bc wget xz-utils
# Run from: revo-build/
#
# Usage: ./scripts/build-kernel.sh [kernel-version]

set -e

KVER="${1:-6.12.21}"
WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_DIR="$WORKDIR/build/linux-${KVER}"
CONFIG="$WORKDIR/src/kernel/revo-tiny.config"
OUTPUT="$WORKDIR/build/vmlinuz-revo"

echo "=== Revo OS Kernel Builder ==="
echo "Target: Linux ${KVER}, config: revo-tiny (10 MB budget)"
echo ""

# Step 1: Download kernel source
if [ ! -d "$KERNEL_DIR" ]; then
    echo "[1/5] Downloading Linux ${KVER}..."
    mkdir -p "$WORKDIR/build"
    MAJOR=$(echo "$KVER" | cut -d. -f1)
    wget -q "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${KVER}.tar.xz" \
        -O "$WORKDIR/build/linux-${KVER}.tar.xz"
    echo "  Extracting..."
    tar xf "$WORKDIR/build/linux-${KVER}.tar.xz" -C "$WORKDIR/build"
    rm "$WORKDIR/build/linux-${KVER}.tar.xz"
else
    echo "[1/5] Kernel source already downloaded"
fi

# Step 2: Apply Revo tiny config
echo "[2/5] Applying Revo tinyconfig..."
cd "$KERNEL_DIR"
make mrproper
if [ -f "$CONFIG" ]; then
    cp "$CONFIG" .config
else
    echo "  Generating config from scratch..."
    make tinyconfig
    # Enable essentials (see src/kernel/revo-tiny.config for full list)
    ./scripts/config --enable 64BIT
    ./scripts/config --enable SMP
    ./scripts/config --enable EFI --enable EFI_STUB --enable EFI_HANDOVER_PROTOCOL
    ./scripts/config --enable CGROUPS --enable NAMESPACES
    ./scripts/config --enable EXT4_FS --enable OVERLAY_FS
    ./scripts/config --enable DEVTMPFS
    ./scripts/config --enable NET --enable INET --enable PACKET
    ./scripts/config --enable BLK_DEV_NVME --enable SATA_AHCI
    ./scripts/config --enable E1000 --enable VIRTIO_BLK --enable VIRTIO_NET
    ./scripts/config --enable DM_VERITY --enable DM_MOD
    make olddefconfig
fi

# Step 3: Build kernel
echo "[3/5] Building kernel (this takes 10-30 minutes)..."
make -j$(nproc) bzImage 2>&1 | tail -20

# Step 4: Copy output
echo "[4/5] Copying kernel..."
cp arch/x86/boot/bzImage "$OUTPUT"

# Step 5: Report size
echo "[5/5] Done!"
SIZE=$(du -h "$OUTPUT" | cut -f1)
echo ""
echo "Kernel built: $OUTPUT ($SIZE)"
echo "Copy to: src/boot/vmlinuz-revo"
echo ""
echo "NOTE: This is a source-compiled kernel. The pre-built Alpine kernel"
echo "is ~12 MB. This config targets ~3-4 MB vmlinuz."
