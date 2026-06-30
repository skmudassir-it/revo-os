#!/bin/sh
# Revo OS v1.2.0 — Download Container Runtime
# Fetches containerd + runc from Alpine community repo
# Run this on the build host to prepare container runtime binaries

set -e
ALPINE="https://dl-cdn.alpinelinux.org/alpine/v3.21/community/x86_64"
DEST="${1:-build/containerd}"

echo "=== Revo OS Container Runtime Download ==="
echo "Target: $DEST"
echo ""

mkdir -p "$DEST"

# Download containerd
echo "[1/2] Downloading containerd v2.0.0-r5..."
if [ ! -f "$DEST/containerd" ]; then
    wget -q "$ALPINE/containerd-2.0.0-r5.apk" -O /tmp/containerd.apk
    tar xzf /tmp/containerd.apk -C /tmp
    cp /tmp/usr/bin/containerd "$DEST/"
    cp /tmp/usr/bin/containerd-shim-runc-v2 "$DEST/"
    rm -rf /tmp/containerd.apk /tmp/usr /tmp/.PKGINFO 2>/dev/null
    echo "  containerd: $(du -h "$DEST/containerd" | cut -f1)"
    echo "  containerd-shim: $(du -h "$DEST/containerd-shim-runc-v2" | cut -f1)"
else
    echo "  already downloaded"
fi

# Download runc
echo "[2/2] Downloading runc v1.2.2-r5..."
if [ ! -f "$DEST/runc" ]; then
    wget -q "$ALPINE/runc-1.2.2-r5.apk" -O /tmp/runc.apk
    tar xzf /tmp/runc.apk -C /tmp
    cp /tmp/usr/bin/runc "$DEST/"
    rm -rf /tmp/runc.apk /tmp/usr /tmp/.PKGINFO 2>/dev/null
    echo "  runc: $(du -h "$DEST/runc" | cut -f1)"
else
    echo "  already downloaded"
fi

echo ""
TOTAL=$(du -sh "$DEST" | cut -f1)
echo "Container runtime: $TOTAL in $DEST"
echo ""
echo "Next: copy to initramfs or ESP for boot-time loading"
echo "  cp $DEST/* initramfs/bin/"
echo "  # or place on ESP:"
echo "  cp $DEST/* /mnt/revo-esp/containerd/"
