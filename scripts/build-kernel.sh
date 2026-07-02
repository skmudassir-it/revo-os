#!/bin/sh
# Revo OS v1.3.1 — Kernel Build Script (10 MB target + Ornet module)
# Compiles Linux kernel with minimal config + ornet.ko AI inference module
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
ORNET_SRC="$WORKDIR/src/kernel/ornet"
OUTPUT="$WORKDIR/build/vmlinuz-revo"
ORNET_OUTPUT="$WORKDIR/modules_out/ornet.ko.gz"

echo "=== Revo OS v1.3.1 Kernel + Ornet Builder ==="
echo "Target: Linux ${KVER}, config: revo-tiny (10 MB budget)"
echo "Ornet:  Kernel-native AI inference module"
echo ""

# Step 1: Download kernel source
if [ ! -d "$KERNEL_DIR" ]; then
    echo "[1/6] Downloading Linux ${KVER}..."
    mkdir -p "$WORKDIR/build"
    MAJOR=$(echo "$KVER" | cut -d. -f1)
    wget -q "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR}.x/linux-${KVER}.tar.xz" \
        -O "$WORKDIR/build/linux-${KVER}.tar.xz"
    echo "  Extracting..."
    tar xf "$WORKDIR/build/linux-${KVER}.tar.xz" -C "$WORKDIR/build"
    rm "$WORKDIR/build/linux-${KVER}.tar.xz"
else
    echo "[1/6] Kernel source already downloaded"
fi

# Step 2: Apply Revo tiny config + Ornet requirements
echo "[2/6] Applying Revo tinyconfig + Ornet kernel options..."
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

# Enable Ornet-specific kernel requirements
echo "  Enabling Ornet kernel requirements..."
./scripts/config --enable MODULES --enable MODULE_UNLOAD
./scripts/config --enable KERNEL_FPU          # AVX2 in kernel context
./scripts/config --enable TRANSPARENT_HUGEPAGE # 2MB pages for model memory
./scripts/config --enable CHR_DEV             # Character devices (/dev/ornet)
./scripts/config --set-val VMALLOC 0x200000000 # 8 GB vmalloc space for model
make olddefconfig

# Step 3: Build kernel
echo "[3/6] Building kernel (this takes 10-30 minutes)..."
make -j$(nproc) bzImage 2>&1 | tail -20

# Step 4: Build kernel modules (for Module.symvers)
echo "[4/6] Building kernel modules (needed for external module compilation)..."
make -j$(nproc) modules_prepare 2>&1 | tail -5

# Step 5: Build ornet.ko
echo "[5/6] Building ornet.ko — Kernel-Native AI Inference Module..."
if [ -d "$ORNET_SRC" ]; then
    make -C "$KERNEL_DIR" M="$ORNET_SRC" modules 2>&1 | tail -20
    
    if [ -f "$ORNET_SRC/ornet.ko" ]; then
        ORNET_SIZE=$(du -h "$ORNET_SRC/ornet.ko" | cut -f1)
        echo "  ornet.ko built: $ORNET_SIZE"
        
        # Strip debug symbols
        strip --strip-debug "$ORNET_SRC/ornet.ko" 2>/dev/null || true
        
        # Copy to modules output directory
        mkdir -p "$WORKDIR/modules_out"
        cp "$ORNET_SRC/ornet.ko" "$WORKDIR/modules_out/"
        gzip -9f "$WORKDIR/modules_out/ornet.ko"
        
        ORNET_GZ_SIZE=$(du -h "$ORNET_OUTPUT" | cut -f1)
        echo "  ornet.ko.gz: $ORNET_GZ_SIZE"
    else
        echo "  [WARN] ornet.ko failed to build — continuing with kernel only"
        echo "  Check kernel headers and try: make -C $KERNEL_DIR M=$ORNET_SRC modules"
    fi
else
    echo "  [SKIP] Ornet source not found at $ORNET_SRC"
    echo "  Run from revo-build/ root directory"
fi

# Step 6: Copy outputs and report
echo "[6/6] Done!"
cp arch/x86/boot/bzImage "$OUTPUT"
KERNEL_SIZE=$(du -h "$OUTPUT" | cut -f1)

echo ""
echo "═══════════════════════════════════════════════"
echo "  Revo OS v1.3.1 Build Complete"
echo "═══════════════════════════════════════════════"
echo "  Kernel:  $OUTPUT ($KERNEL_SIZE)"

if [ -f "$ORNET_OUTPUT" ]; then
    ORNET_SIZE=$(du -h "$ORNET_OUTPUT" | cut -f1)
    echo "  Ornet:   $ORNET_OUTPUT ($ORNET_SIZE)"
else
    echo "  Ornet:   (not built — run build step manually)"
fi

echo ""
echo "  Next steps:"
echo "  1. Copy kernel: cp $OUTPUT revo-package/vmlinuz-virt"
echo "  2. Ornet module already in modules_out/"
echo "  3. Rebuild initramfs: cd initramfs && find . | cpio -oH newc | gzip > ../initramfs.cpio.gz"
echo "  4. Build USB image: python3 build-image.py"
echo ""
echo "  NOTE: Pre-built Alpine kernel is ~12 MB."
echo "        Tinyconfig target: ~3-4 MB vmlinuz."
echo ""
