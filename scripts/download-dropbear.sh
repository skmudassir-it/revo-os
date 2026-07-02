#!/bin/sh
# download-dropbear.sh — Download Dropbear SSH for Revo OS v1.5.0
#
# Dropbear is a ~200 KB SSH server/client designed for embedded systems.
# We fetch the static binary from Alpine's repository.
#
# Usage: ./scripts/download-dropbear.sh
# Output: build/dropbear/ (dropbear, dropbearkey, dropbearconvert, dbclient)

set -e

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ALPINE_VERSION="${ALPINE_VERSION:-v3.21}"
ALPINE_ARCH="x86_64"
ALPINE_REPO="$ALPINE_MIRROR/$ALPINE_VERSION/main/$ALPINE_ARCH"

BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build/dropbear"
mkdir -p "$BUILD_DIR"

echo "=== Revo OS v1.5.0 — Dropbear SSH Download ==="
echo "Source: $ALPINE_REPO"
echo "Target: $BUILD_DIR"
echo ""

# ─── Download APKINDEX ───
echo "[1/3] Fetching APKINDEX..."
APKINDEX_URL="$ALPINE_REPO/APKINDEX.tar.gz"
if command -v wget > /dev/null 2>&1; then
    wget -q "$APKINDEX_URL" -O /tmp/apkindex.tar.gz
else
    curl -sL "$APKINDEX_URL" -o /tmp/apkindex.tar.gz
fi

# ─── Find latest dropbear version ───
echo "[2/3] Resolving dropbear version..."
DROPBEAR_VERSION=$(tar xzf /tmp/apkindex.tar.gz -O APKINDEX 2>/dev/null | \
    grep -A10 "^P:dropbear$" | grep "^V:" | head -1 | cut -d: -f2)
echo "  Dropbear: $DROPBEAR_VERSION"

if [ -z "$DROPBEAR_VERSION" ]; then
    echo "  [FALLBACK] Using known version 2024.86-r0"
    DROPBEAR_VERSION="2024.86-r0"
fi

# ─── Download + extract ───
echo "[3/3] Downloading dropbear..."
DROPBEAR_URL="$ALPINE_REPO/dropbear-${DROPBEAR_VERSION}.apk"

if command -v wget > /dev/null 2>&1; then
    wget -q "$DROPBEAR_URL" -O /tmp/dropbear.apk
else
    curl -sL "$DROPBEAR_URL" -o /tmp/dropbear.apk
fi

echo "  Extracting..."
mkdir -p /tmp/dropbear-extract
tar xzf /tmp/dropbear.apk -C /tmp/dropbear-extract 2>/dev/null

# Copy binaries
for bin in dropbear dropbearkey dropbearconvert dbclient scp; do
    if [ -f "/tmp/dropbear-extract/usr/sbin/$bin" ]; then
        cp "/tmp/dropbear-extract/usr/sbin/$bin" "$BUILD_DIR/"
        strip "$BUILD_DIR/$bin" 2>/dev/null || true
        echo "  [OK] $bin ($(du -h "$BUILD_DIR/$bin" | cut -f1))"
    elif [ -f "/tmp/dropbear-extract/usr/bin/$bin" ]; then
        cp "/tmp/dropbear-extract/usr/bin/$bin" "$BUILD_DIR/"
        strip "$BUILD_DIR/$bin" 2>/dev/null || true
        echo "  [OK] $bin ($(du -h "$BUILD_DIR/$bin" | cut -f1))"
    fi
done

# Cleanup
rm -rf /tmp/dropbear-extract /tmp/dropbear.apk /tmp/apkindex.tar.gz

echo ""
echo "=== Done ==="
echo "Dropbear binaries: $BUILD_DIR"
ls -lh "$BUILD_DIR/"
echo ""
echo "On Revo OS, place in /usr/sbin/ for SSH server."
echo "Init script auto-starts dropbear if binaries are present."
echo ""
echo "Default port: 2222 (non-privileged, no root needed for binding)"
echo "Key generation: dropbearkey -t rsa -f /revo/etc/dropbear_rsa_host_key"
