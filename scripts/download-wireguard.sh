#!/bin/sh
# download-wireguard.sh — Download WireGuard for Revo OS v1.5.0
#
# WireGuard is a modern, fast, and simple VPN. We need:
#   - wireguard.ko.gz — kernel module (from Alpine linux-virt)
#   - wg             — userspace configuration tool (from wireguard-tools)
#
# Usage: ./scripts/download-wireguard.sh
# Output: build/wireguard/ (wireguard.ko.gz, wg)

set -e

ALPINE_MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ALPINE_VERSION="${ALPINE_VERSION:-v3.21}"
ALPINE_ARCH="x86_64"
ALPINE_REPO="$ALPINE_MIRROR/$ALPINE_VERSION/main/$ALPINE_ARCH"

BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build/wireguard"
MODULES_DIR="$(cd "$(dirname "$0")/.." && pwd)/modules_out"
mkdir -p "$BUILD_DIR" "$MODULES_DIR"

echo "=== Revo OS v1.5.0 — WireGuard Download ==="
echo "Source: $ALPINE_REPO"
echo "Target: $BUILD_DIR"
echo ""

# ─── Download wireguard-tools (wg + wg-quick) ───
echo "[1/2] WireGuard tools..."
APKINDEX_URL="$ALPINE_REPO/APKINDEX.tar.gz"
if command -v wget > /dev/null 2>&1; then
    wget -q "$APKINDEX_URL" -O /tmp/apkindex.tar.gz
else
    curl -sL "$APKINDEX_URL" -o /tmp/apkindex.tar.gz
fi

WG_TOOLS_VERSION=$(tar xzf /tmp/apkindex.tar.gz -O APKINDEX 2>/dev/null | \
    grep -A10 "^P:wireguard-tools$" | grep "^V:" | head -1 | cut -d: -f2)
[ -z "$WG_TOOLS_VERSION" ] && WG_TOOLS_VERSION="1.0.20210914-r0"

echo "  wireguard-tools: $WG_TOOLS_VERSION"

if command -v wget > /dev/null 2>&1; then
    wget -q "$ALPINE_REPO/wireguard-tools-${WG_TOOLS_VERSION}.apk" -O /tmp/wg-tools.apk
else
    curl -sL "$ALPINE_REPO/wireguard-tools-${WG_TOOLS_VERSION}.apk" -o /tmp/wg-tools.apk
fi

mkdir -p /tmp/wg-extract
tar xzf /tmp/wg-tools.apk -C /tmp/wg-extract 2>/dev/null

if [ -f "/tmp/wg-extract/usr/bin/wg" ]; then
    cp "/tmp/wg-extract/usr/bin/wg" "$BUILD_DIR/"
    strip "$BUILD_DIR/wg" 2>/dev/null || true
    echo "  [OK] wg ($(du -h "$BUILD_DIR/wg" | cut -f1))"
fi

if [ -f "/tmp/wg-extract/usr/bin/wg-quick" ]; then
    cp "/tmp/wg-extract/usr/bin/wg-quick" "$BUILD_DIR/"
    echo "  [OK] wg-quick"
fi

rm -rf /tmp/wg-extract /tmp/wg-tools.apk

# ─── Download wireguard kernel module ───
echo "[2/2] WireGuard kernel module..."

# Try to find wireguard in linux-virt modules
LINUX_VIRT_VERSION=$(tar xzf /tmp/apkindex.tar.gz -O APKINDEX 2>/dev/null | \
    grep -A10 "^P:linux-virt$" | grep "^V:" | head -1 | cut -d: -f2 | sed 's/-r.*//')

if [ -n "$LINUX_VIRT_VERSION" ]; then
    echo "  Linux virt: $LINUX_VIRT_VERSION"
    LINUX_VIRT_URL="$ALPINE_REPO/linux-virt-${LINUX_VIRT_VERSION}-r0.apk"
    
    if command -v wget > /dev/null 2>&1; then
        wget -q "$LINUX_VIRT_URL" -O /tmp/linux-virt.apk 2>/dev/null || true
    else
        curl -sL "$LINUX_VIRT_URL" -o /tmp/linux-virt.apk 2>/dev/null || true
    fi
    
    if [ -f /tmp/linux-virt.apk ]; then
        mkdir -p /tmp/kmod-extract
        tar xzf /tmp/linux-virt.apk -C /tmp/kmod-extract 2>/dev/null
        
        # Find wireguard module
        WG_MODULE=$(find /tmp/kmod-extract -name "wireguard.ko*" 2>/dev/null | head -1)
        if [ -n "$WG_MODULE" ]; then
            cp "$WG_MODULE" "$MODULES_DIR/wireguard.ko.gz"
            echo "  [OK] wireguard.ko.gz ($(du -h "$MODULES_DIR/wireguard.ko.gz" | cut -f1))"
            cp "$WG_MODULE" "$BUILD_DIR/wireguard.ko.gz"
        else
            echo "  [WARN] wireguard.ko not found in linux-virt modules"
            echo "  WireGuard may be built into the kernel (check: zcat /proc/config.gz | grep WIREGUARD)"
            echo "  If built-in, no module needed — wg tool works directly."
            
            # Create placeholder so init script knows to check
            touch "$BUILD_DIR/wireguard.ko.gz"
        fi
        
        rm -rf /tmp/kmod-extract /tmp/linux-virt.apk
    fi
fi

rm -f /tmp/apkindex.tar.gz

echo ""
echo "=== Done ==="
echo "WireGuard files:"
ls -lh "$BUILD_DIR/"
echo ""
echo "On Revo OS, place in:"
echo "  wg              → /usr/bin/wg"
echo "  wireguard.ko.gz → /boot/modules/wireguard.ko.gz"
echo ""
echo "Quick setup:"
echo "  ip link add dev wg0 type wireguard"
echo "  wg set wg0 private-key /revo/etc/wg-private.key"
echo "  ip addr add 10.0.0.1/24 dev wg0"
echo "  ip link set wg0 up"
