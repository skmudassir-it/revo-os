#!/bin/bash
# download-ornith.sh — Download Ornith-1 9B GGUF for Revo OS Ornet subsystem
# Fetches from HuggingFace: deepreinforce-ai/Ornith-1.0-9B-GGUF
# v1.3.0

set -e

MODEL_FILE="${MODEL_FILE:-ornith-1.0-9b-Q4_K_M.gguf}"
MODEL_DIR="${MODEL_DIR:-/home/shaik/revo-build/models}"
HF_REPO="deepreinforce-ai/Ornith-1.0-9B-GGUF"
HF_URL="https://huggingface.co/$HF_REPO/resolve/main/$MODEL_FILE"

echo "=== Revo OS Ornet — Ornith-1 9B Model Download ==="
echo ""
echo "Model:   $MODEL_FILE"
echo "Repo:    $HF_REPO"
echo "Quant:   Q4_K_M (4-bit, balanced quality/speed)"
echo "Size:    ~5.5 GB"
echo "Dest:    $MODEL_DIR/$MODEL_FILE"
echo ""

# Create model directory
mkdir -p "$MODEL_DIR"

# Check if already downloaded
if [ -f "$MODEL_DIR/$MODEL_FILE" ]; then
    SIZE=$(du -h "$MODEL_DIR/$MODEL_FILE" 2>/dev/null | cut -f1)
    echo "[SKIP] Model already exists: $SIZE"
    echo "To re-download: rm $MODEL_DIR/$MODEL_FILE && $0"
    exit 0
fi

# Check available disk space
if command -v df > /dev/null 2>&1; then
    AVAIL_MB=$(df -m "$MODEL_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$AVAIL_MB" ] && [ "$AVAIL_MB" -lt 7000 ]; then
        echo "[WARN] Only ${AVAIL_MB}MB available. Download needs ~6000MB."
        echo "Continue? (y/N)"
        read -r answer
        [ "$answer" != "y" ] && [ "$answer" != "Y" ] && exit 1
    fi
fi

# Download
echo "[INFO] Starting download from HuggingFace..."
echo "[INFO] This will take a while (~5.5 GB). Press Ctrl+C to cancel."
echo ""

if command -v wget > /dev/null 2>&1; then
    wget -c --show-progress "$HF_URL" -O "$MODEL_DIR/$MODEL_FILE"
elif command -v curl > /dev/null 2>&1; then
    curl -L -C - --progress-bar "$HF_URL" -o "$MODEL_DIR/$MODEL_FILE"
else
    echo "[ERROR] Neither wget nor curl found."
    echo "Install one: apt install wget curl"
    echo "Or download manually: $HF_URL"
    exit 1
fi

echo ""
echo "=== Download Complete ==="
SIZE=$(du -h "$MODEL_DIR/$MODEL_FILE" 2>/dev/null | cut -f1)
echo "Model: $MODEL_DIR/$MODEL_FILE ($SIZE)"
echo ""
echo "Next steps:"
echo "  1. Copy to RevoAI volume: cp $MODEL_DIR/$MODEL_FILE /revo/ai/models/"
echo "  2. Install llama.cpp: apk add llama-cpp"
echo "  3. Start ornetd: ornetd start"
echo "  4. Test inference: ornetd infer 'Hello, who are you?'"
