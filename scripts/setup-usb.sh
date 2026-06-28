#!/bin/bash
# Revo OS — USB Setup Script
# Creates a bootable Revo OS USB image

set -e
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REVO_IMG="$BUILD_DIR/revo-os-v0.2.0.img"

echo "=== Revo OS USB Creator ==="
echo ""

# Check if image exists
if [ ! -f "$REVO_IMG" ]; then
    echo "Error: $REVO_IMG not found."
    echo "Run build-image.sh first."
    exit 1
fi

SIZE_MB=$(du -m "$REVO_IMG" | cut -f1)
echo "Image: $REVO_IMG ($SIZE_MB MB)"
echo ""

# Option 1: Loopback mount + format
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
sudo cp "$BUILD_DIR/boot/vmlinuz-virt" /mnt/revo-esp/EFI/BOOT/BOOTX64.EFI
sudo cp "$BUILD_DIR/initramfs.cpio.gz" /mnt/revo-esp/EFI/BOOT/initrd.img
sudo cp "$BUILD_DIR/modules_out/"*.ko.gz /mnt/revo-esp/modules/
echo ""

echo "Step 4: Creating boot loader config..."
sudo tee /mnt/revo-esp/loader/entries/revo.conf > /dev/null << 'CONFEOF'
title   Revo OS
linux   /EFI/BOOT/BOOTX64.EFI
initrd  /EFI/BOOT/initrd.img
options console=tty0 console=ttyS0 quiet
CONFEOF
echo ""

echo "=== Files on ESP ==="
ls -lhR /mnt/revo-esp/
echo ""

echo "Step 5: Cleaning up..."
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
