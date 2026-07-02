#!/bin/bash
# Revo OS v1.4.0 — USB Setup Script
# Creates a bootable Revo OS USB image with dm-verity + CA bundle

set -e
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REVO_IMG="$BUILD_DIR/revo-os-v1.4.0.img"

echo "=== Revo OS v1.4.0 USB Creator ==="
echo ""

# Check if image exists
if [ ! -f "$REVO_IMG" ]; then
    echo "Error: $REVO_IMG not found."
    echo "Run build-image.py first."
    exit 1
fi

SIZE_MB=$(du -m "$REVO_IMG" | cut -f1)
echo "Image: $REVO_IMG ($SIZE_MB MB)"
echo ""

# Step 1: Loopback mount + format
echo "Step 1: Setting up loopback device..."
sudo losetup -P -f "$REVO_IMG"
LOOP_DEV=$(sudo losetup -j "$REVO_IMG" | cut -d: -f1)
echo "  Loop device: $LOOP_DEV"
echo "  Partition 1: ${LOOP_DEV}p1 (EFI System Partition)"
echo "  Partition 2: ${LOOP_DEV}p2 (Revo Data)"
echo ""

echo "Step 2: Formatting partitions..."
sudo mkfs.vfat -F32 -n REVO_ESP "${LOOP_DEV}p1"
sudo mkfs.ext4 -L revo-data "${LOOP_DEV}p2"
echo ""

echo "Step 3: Copying Revo OS files..."
sudo mkdir -p /mnt/revo-esp
sudo mount "${LOOP_DEV}p1" /mnt/revo-esp
sudo mkdir -p /mnt/revo-esp/EFI/BOOT
sudo mkdir -p /mnt/revo-esp/modules
sudo mkdir -p /mnt/revo-esp/ssl/certs
sudo mkdir -p /mnt/revo-esp/containerd

# Kernel + initramfs
sudo cp "$BUILD_DIR/vmlinuz-virt" /mnt/revo-esp/EFI/BOOT/BOOTX64.EFI
sudo cp "$BUILD_DIR/initramfs.cpio.gz" /mnt/revo-esp/EFI/BOOT/initrd.img

# Kernel modules (including dm-verity)
sudo cp "$BUILD_DIR/modules/"*.ko.gz /mnt/revo-esp/modules/

# SSL CA certificates (for TLS in containers)
sudo cp "$BUILD_DIR/../initramfs/etc/ssl/certs/"*.crt /mnt/revo-esp/ssl/certs/ 2>/dev/null || true

# Revo config (version + verity params)
sudo cp "$BUILD_DIR/../initramfs/etc/revo/config.json" /mnt/revo-esp/revo-config.json 2>/dev/null || true

# Container runtime (containerd + runc) — optional, from download-containerd.sh
if [ -d "$BUILD_DIR/../build/containerd" ]; then
    sudo cp "$BUILD_DIR/../build/containerd/"* /mnt/revo-esp/containerd/ 2>/dev/null
    echo "  [OK] containerd + runc copied to ESP"
fi
echo ""

# Step 4: Generate dm-verity hash tree (optional, requires Python + openssl)
echo "Step 4: dm-verity hash tree..."
if command -v python3 &>/dev/null; then
    sudo mkdir -p /mnt/revo-data
    sudo mount "${LOOP_DEV}p2" /mnt/revo-data
    # Create a small test file so there's something to hash
    sudo touch /mnt/revo-data/.revo-ready
    sudo umount /mnt/revo-data
    rmdir /mnt/revo-data 2>/dev/null || true

    # Generate verity hash tree
    python3 "$BUILD_DIR/../scripts/generate-verity.py" "$REVO_IMG" /tmp/revo-verity.hash 2>/dev/null && {
        sudo cp /tmp/revo-verity.hash /mnt/revo-esp/verity.hash
        echo "  [OK] dm-verity hash tree generated"
        rm /tmp/revo-verity.hash
    } || echo "  [--] dm-verity skipped (no data partition yet)"
else
    echo "  [--] dm-verity skipped (no python3)"
fi
echo ""

# Step 5: Boot loader config
echo "Step 5: Creating boot loader config..."
sudo tee /mnt/revo-esp/loader/entries/revo.conf > /dev/null << 'CONFEOF'
title   Revo OS v1.3.0
linux   /EFI/BOOT/BOOTX64.EFI
initrd  /EFI/BOOT/initrd.img
options console=tty0 console=ttyS0 quiet
CONFEOF
echo ""

echo "=== Files on ESP ==="
ls -lhR /mnt/revo-esp/
echo ""

echo "Step 6: Cleaning up..."
sudo umount /mnt/revo-esp
sudo losetup -d "$LOOP_DEV"
rmdir /mnt/revo-esp 2>/dev/null || true

echo ""
FINAL_SIZE=$(du -m "$REVO_IMG" | cut -f1)
echo "=== DONE ==="
echo "Bootable image: $REVO_IMG ($FINAL_SIZE MB)"
echo ""
echo "To write to USB:"
echo "  sudo dd if=$REVO_IMG of=/dev/sdX bs=4M status=progress conv=fsync"
echo ""
echo "To test in QEMU:"
echo "  qemu-system-x86_64 -m 2G -enable-kvm -drive file=$REVO_IMG,format=raw"
echo ""
echo "IMPORTANT: This is a UEFI-only image."
echo "Enable UEFI boot in your BIOS/UEFI settings."
