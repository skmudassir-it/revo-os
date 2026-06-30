#!/bin/bash
# Revo OS v1.1 — USB Setup Script
# Creates a bootable Revo OS USB image with dm-verity + CA bundle
# (master copy — mirrors revo-package/setup-usb.sh)

set -e
BUILD_DIR="$(cd "$(dirname "$0")" && pwd)"
REVO_IMG="$BUILD_DIR/revo-os-v1.2.0.img"

echo "=== Revo OS v1.2.0 USB Creator ==="
echo ""

if [ ! -f "$REVO_IMG" ]; then
    echo "Error: $REVO_IMG not found."
    echo "Run build-image.py first."
    exit 1
fi

SIZE_MB=$(du -m "$REVO_IMG" | cut -f1)
echo "Image: $REVO_IMG ($SIZE_MB MB)"
echo ""

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
sudo mkdir -p /mnt/revo-esp/EFI/BOOT /mnt/revo-esp/modules /mnt/revo-esp/ssl/certs

sudo cp "$BUILD_DIR/revo-package/vmlinuz-virt" /mnt/revo-esp/EFI/BOOT/BOOTX64.EFI
sudo cp "$BUILD_DIR/initramfs.cpio.gz" /mnt/revo-esp/EFI/BOOT/initrd.img
sudo cp "$BUILD_DIR/modules_out/"*.ko.gz /mnt/revo-esp/modules/
sudo cp "$BUILD_DIR/initramfs/etc/ssl/certs/"*.crt /mnt/revo-esp/ssl/certs/
sudo cp "$BUILD_DIR/initramfs/etc/revo/config.json" /mnt/revo-esp/revo-config.json
echo ""

echo "Step 4: dm-verity hash tree..."
if python3 "$BUILD_DIR/scripts/generate-verity.py" "$REVO_IMG" /tmp/revo-verity.hash 2>/dev/null; then
    sudo cp /tmp/revo-verity.hash /mnt/revo-esp/verity.hash
    echo "  [OK] dm-verity hash tree generated"
    rm /tmp/revo-verity.hash
else
    echo "  [--] dm-verity skipped"
fi
echo ""

echo "Step 5: Boot loader config..."
sudo tee /mnt/revo-esp/loader/entries/revo.conf > /dev/null << 'CONFEOF'
title   Revo OS v1.2.0
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
echo "=== DONE ==="
echo "Bootable image: $REVO_IMG ($(du -m "$REVO_IMG" | cut -f1) MB)"
echo ""
echo "To write to USB:"
echo "  sudo dd if=$REVO_IMG of=/dev/sdX bs=4M status=progress conv=fsync"
echo ""
echo "To test in QEMU:"
echo "  qemu-system-x86_64 -m 2G -kernel revo-package/vmlinuz-virt -initrd initramfs.cpio.gz -append 'console=ttyS0 quiet' -nographic"
echo ""
echo "IMPORTANT: This is a UEFI-only image."
