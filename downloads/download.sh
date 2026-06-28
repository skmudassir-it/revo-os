#!/bin/bash
# Revo OS — Alpine Linux Download Script
# Fetches Alpine Linux for any supported device/architecture
# 
# Usage:
#   ./download.sh                  # Interactive menu
#   ./download.sh --list           # List all available downloads
#   ./download.sh --device pi5     # Download for Raspberry Pi 5
#   ./download.sh --arch x86_64 --variant extended  # Specific arch+variant
#   ./download.sh --arch aarch64 --variant rpi --type img.gz
#
# Source: https://alpinelinux.org/downloads/ (scraped live via TinyFish)

set -e

BASE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.24/releases"
MANIFEST="$(dirname "$0")/alpine-manifest.json"
OUTPUT_DIR="${REVO_DOWNLOAD_DIR:-./revo-downloads}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

banner() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     🌀 Revo OS — Alpine Download Tool       ║${NC}"
    echo -e "${GREEN}║     Multi-architecture Linux for any device  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

list_all() {
    echo "Available Alpine Linux v3.24.1 downloads:"
    echo ""
    printf "%-14s %-12s %-8s %s\n" "ARCH" "VARIANT" "TYPE" "FILENAME"
    printf "%-14s %-12s %-8s %s\n" "────" "───────" "────" "────────"
    
    if [ -f "$MANIFEST" ]; then
        python3 -c "
import json
with open('$MANIFEST') as f:
    data = json.load(f)
for f in data['files']:
    print(f\"{f['arch']:14s} {f['variant']:12s} {f['type']:8s} {f['file']}\")
"
    else
        echo "Error: manifest not found at $MANIFEST"
        exit 1
    fi
    echo ""
}

download_file() {
    local arch="$1"
    local file="$2"
    local url="${BASE_URL}/${arch}/${file}"
    
    mkdir -p "$OUTPUT_DIR/${arch}"
    local dest="$OUTPUT_DIR/${arch}/${file}"
    
    if [ -f "$dest" ]; then
        echo -e "${YELLOW}[SKIP]${NC} Already downloaded: $file"
    else
        echo -e "${BLUE}[DOWNLOAD]${NC} $url"
        echo -e "  → $dest"
        curl -# -L -o "$dest" "$url"
        echo ""
    fi
    
    # Also download checksum
    local sha_url="${url}.sha256"
    local sha_dest="${dest}.sha256"
    if [ ! -f "$sha_dest" ]; then
        curl -sL -o "$sha_dest" "$sha_url" 2>/dev/null && \
            echo -e "  ${GREEN}[SHA256]${NC} $(cat $sha_dest)" || true
    fi
}

download_by_device() {
    local device="$1"
    local arch variant file
    
    case "$device" in
        desktop|pc|x86_64)
            arch="x86_64"; variant="extended"
            file="alpine-extended-3.24.1-x86_64.iso"
            echo "→ Desktop/Laptop (x86_64 Extended)"
            ;;
        server|vm|virtual)
            arch="x86_64"; variant="virt"
            file="alpine-virt-3.24.1-x86_64.iso"
            echo "→ Server/VM (x86_64 Virtual)"
            ;;
        pi5|rpi5|raspberrypi5)
            arch="aarch64"; variant="rpi"
            file="alpine-rpi-3.24.1-aarch64.img.gz"
            echo "→ Raspberry Pi 5 (aarch64 RPi image)"
            ;;
        pi4|rpi4|raspberrypi4)
            arch="aarch64"; variant="rpi"
            file="alpine-rpi-3.24.1-aarch64.img.gz"
            echo "→ Raspberry Pi 4 (aarch64 RPi image)"
            ;;
        pi3|rpi3|raspberrypi3)
            arch="aarch64"; variant="rpi"
            file="alpine-rpi-3.24.1-aarch64.img.gz"
            echo "→ Raspberry Pi 3 (aarch64 RPi image)"
            ;;
        pi0|pi1|rpi0|rpi1|raspberrypizero)
            arch="armhf"; variant="rpi"
            file="alpine-rpi-3.24.1-armhf.img.gz"
            echo "→ Raspberry Pi Zero/1 (armhf RPi image)"
            ;;
        container|docker)
            arch="x86_64"; variant="minirootfs"
            file="alpine-minirootfs-3.24.1-x86_64.tar.gz"
            echo "→ Docker/Container (x86_64 minirootfs)"
            ;;
        arm|embedded|armboard)
            arch="aarch64"; variant="uboot"
            file="alpine-uboot-3.24.1-aarch64.tar.gz"
            echo "→ ARM Board / U-Boot (aarch64)"
            ;;
        netboot|pxe)
            arch="x86_64"; variant="netboot"
            file="alpine-netboot-3.24.1-x86_64.tar.gz"
            echo "→ Network/PXE Boot (x86_64 netboot)"
            ;;
        *)
            echo "Unknown device: $device"
            echo "Supported: desktop, server, pi3, pi4, pi5, pi0, container, arm, netboot"
            exit 1
            ;;
    esac
    
    download_file "$arch" "$file"
}

download_all() {
    echo -e "${YELLOW}Downloading ALL Alpine Linux releases...${NC}"
    echo "This may take a while. Files go to $OUTPUT_DIR/"
    echo ""
    
    if [ -f "$MANIFEST" ]; then
        python3 -c "
import json, subprocess, sys
with open('$MANIFEST') as f:
    data = json.load(f)
count = 0
for f in data['files']:
    url = f\"${BASE_URL}/{f['arch']}/{f['file']}\"
    print(f\"  [{count+1}/{len(data['files'])}] {f['arch']}/{f['file']}\")
    count += 1
"
        echo ""
        read -p "Proceed with download? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Cancelled."
            exit 0
        fi
        
        python3 -c "
import json, subprocess, os
with open('$MANIFEST') as f:
    data = json.load(f)
for item in data['files']:
    arch = item['arch']
    file = item['file']
    url = f'${BASE_URL}/{arch}/{file}'
    dest_dir = f'$OUTPUT_DIR/{arch}'
    dest = f'{dest_dir}/{file}'
    os.makedirs(dest_dir, exist_ok=True)
    if os.path.exists(dest):
        print(f'  SKIP: {file} (already downloaded)')
    else:
        print(f'  DOWNLOAD: {file}')
        subprocess.run(['curl', '-sL', '-o', dest, url], check=False)
        # Download SHA256
        sha_dest = f'{dest}.sha256'
        subprocess.run(['curl', '-sL', '-o', sha_dest, f'{url}.sha256'], check=False)
    print(f'')
"
    fi
    
    echo -e "${GREEN}Done.${NC} Files saved to $OUTPUT_DIR/"
}

interactive_menu() {
    echo "Select your device:"
    echo ""
    echo "  1) 💻 Desktop / Laptop     (x86_64, extended ISO)"
    echo "  2) 🖥️  Server / Virtual     (x86_64, virt ISO)"
    echo "  3) 🥧 Raspberry Pi 5        (aarch64, RPi image)"
    echo "  4) 🥧 Raspberry Pi 3 / 4    (aarch64, RPi image)"
    echo "  5) 🥧 Raspberry Pi Zero / 1 (armhf, RPi image)"
    echo "  6) 📦 Docker / Container    (x86_64, minirootfs)"
    echo "  7) 🔧 ARM Embedded Board    (aarch64, U-Boot)"
    echo "  8) 🌐 Network / PXE Boot    (x86_64, netboot)"
    echo "  9) 📋 List all available"
    echo " 10) ⬇️  Download ALL"
    echo "  0) Exit"
    echo ""
    read -p "Choice [1]: " choice
    choice="${choice:-1}"
    
    case "$choice" in
        1)  download_by_device "desktop" ;;
        2)  download_by_device "server" ;;
        3)  download_by_device "pi5" ;;
        4)  download_by_device "pi3" ;;
        5)  download_by_device "pi0" ;;
        6)  download_by_device "container" ;;
        7)  download_by_device "arm" ;;
        8)  download_by_device "netboot" ;;
        9)  list_all ;;
        10) download_all ;;
        0)  exit 0 ;;
        *)  echo "Invalid choice." ;;
    esac
}

# Main
banner

case "${1:-}" in
    --list|-l)
        list_all
        ;;
    --device|-d)
        download_by_device "${2:-}"
        ;;
    --arch|-a)
        ARCH="${2:-}"
        VARIANT="${4:-standard}"
        if [ -f "$MANIFEST" ]; then
            FILE=$(python3 -c "
import json
with open('$MANIFEST') as f:
    data = json.load(f)
for f in data['files']:
    if f['arch'] == '$ARCH' and f['variant'] == '$VARIANT':
        print(f['file'])
        break
")
            if [ -n "$FILE" ]; then
                download_file "$ARCH" "$FILE"
            else
                echo "No match for arch=$ARCH variant=$VARIANT"
                echo "Use --list to see available options"
                exit 1
            fi
        fi
        ;;
    --all)
        download_all
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  (no args)       Interactive device selection menu"
        echo "  --list, -l      List all available downloads"
        echo "  --device, -d N  Download for device (desktop, server, pi5, pi3, pi0, container, arm, netboot)"
        echo "  --arch, -a       Download by architecture + variant"
        echo "  --all            Download ALL releases (large!)"
        echo "  --help, -h       This help"
        echo ""
        echo "Example:"
        echo "  $0 --device pi5"
        echo "  $0 --arch aarch64 --variant rpi"
        echo "  $0 --all"
        ;;
    *)
        interactive_menu
        ;;
esac
