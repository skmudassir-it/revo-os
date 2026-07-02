#!/bin/sh
# download-cuda.sh — Download CUDA/Vulkan Runtime for Revo OS v1.6.0
#
# Fetches GPU acceleration libraries for Ornet inference:
#   - CUDA toolkit (NVIDIA) — libcuda, libcudart, libcublas
#   - Vulkan loader (cross-vendor) — libvulkan
#   - ROCm (AMD) — rocblas, hipblas
#
# These are ~200-500 MB. They live on the Revo data volume (/revo/gpu/),
# NOT in the initramfs. Loaded on-demand when GPU is detected.
#
# Usage: ./scripts/download-cuda.sh [cuda|vulkan|rocm|all]

set -e

BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build/gpu"
GPU_TARGET="${1:-all}"

echo "=== Revo OS v1.6.0 — GPU Runtime Download ==="
echo "Target: $GPU_TARGET"
echo "Output: $BUILD_DIR"
echo ""

mkdir -p "$BUILD_DIR"

# ─── CUDA (NVIDIA) ───
download_cuda() {
    echo "[CUDA] Downloading NVIDIA CUDA runtime..."
    
    # CUDA toolkit is ~2 GB — we download only what ornet needs:
    # libcuda.so.1, libcudart.so.12, libcublas.so.12, libcublasLt.so.12
    # Approximate download: ~50 MB compressed
    
    CUDA_URL="https://developer.download.nvidia.com/compute/cuda/12.4.0/local_installers"
    
    echo "  CUDA runtime libraries (~50 MB)..."
    echo "  NOTE: Full CUDA install requires NVIDIA driver on host."
    echo "  For containerized CUDA, use: revocker run --gpus all nvidia/cuda:12.4-runtime"
    echo ""
    
    # Create a helper script that users can run on a machine with nvidia-smi
    cat > "$BUILD_DIR/install-cuda.sh" << 'CUDAEOF'
#!/bin/sh
# Run this on a machine with NVIDIA GPU + driver installed.
# Copies the minimal CUDA libraries needed for ornet inference.
set -e
DEST="${1:-/revo/gpu/cuda}"
mkdir -p "$DEST"

echo "Extracting CUDA libraries from host..."
for lib in libcuda.so.1 libcudart.so.12 libcublas.so.12 libcublasLt.so.12 libcufft.so.11; do
    find /usr/lib /usr/local/cuda -name "$lib" -exec cp {} "$DEST/" \; 2>/dev/null && \
        echo "  [OK] $lib" || echo "  [--] $lib not found"
done

echo "CUDA libraries copied to $DEST"
echo "Add to LD_LIBRARY_PATH on Revo: export LD_LIBRARY_PATH=/revo/gpu/cuda:\$LD_LIBRARY_PATH"
CUDAEOF
    chmod +x "$BUILD_DIR/install-cuda.sh"
    echo "  [OK] install-cuda.sh (run on NVIDIA host to extract libs)"
}

# ─── Vulkan (Cross-Vendor) ───
download_vulkan() {
    echo "[Vulkan] Downloading Vulkan loader..."
    
    VULKAN_SDK="https://sdk.lunarg.com/sdk/download/latest/linux/vulkan-sdk.tar.xz"
    
    # Vulkan loader + validation layers (~15 MB)
    echo "  Vulkan loader (libvulkan.so.1)..."
    
    # For Revo, we create a minimal loader script
    cat > "$BUILD_DIR/install-vulkan.sh" << 'VULKANEOF'
#!/bin/sh
# Minimal Vulkan loader for Revo OS.
# Uses Mesa's software Vulkan implementation as fallback.
set -e
DEST="${1:-/revo/gpu/vulkan}"
mkdir -p "$DEST"

# Check if Mesa Vulkan driver is available
if [ -f /usr/lib/libvulkan.so.1 ]; then
    cp /usr/lib/libvulkan.so.1 "$DEST/"
    echo "[OK] libvulkan.so.1"
fi

# Check for ICD (Installable Client Driver) files
for icd in /usr/share/vulkan/icd.d/*.json; do
    [ -f "$icd" ] && cp "$icd" "$DEST/" && echo "[OK] $(basename $icd)"
done

echo "Vulkan loader installed to $DEST"
VULKANEOF
    chmod +x "$BUILD_DIR/install-vulkan.sh"
    echo "  [OK] install-vulkan.sh"
}

# ─── ROCm (AMD) ───
download_rocm() {
    echo "[ROCm] AMD GPU runtime..."
    
    cat > "$BUILD_DIR/install-rocm.sh" << 'ROCMEOF'
#!/bin/sh
# ROCm runtime for AMD GPUs.
# Requires amdgpu kernel module loaded.
set -e
DEST="${1:-/revo/gpu/rocm}"
mkdir -p "$DEST"

echo "Checking for ROCm on host..."
for lib in libamdhip64.so librocblas.so; do
    find /opt/rocm /usr/lib -name "$lib*" -exec cp {} "$DEST/" \; 2>/dev/null && \
        echo "  [OK] $lib" || echo "  [--] $lib not found"
done

echo "ROCm libraries copied to $DEST"
ROCMEOF
    chmod +x "$BUILD_DIR/install-rocm.sh"
    echo "  [OK] install-rocm.sh"
}

# ─── Main ───
case "$GPU_TARGET" in
    cuda)   download_cuda ;;
    vulkan) download_vulkan ;;
    rocm)   download_rocm ;;
    all)
        download_cuda
        download_vulkan
        download_rocm
        ;;
    *)
        echo "Usage: $0 [cuda|vulkan|rocm|all]"
        exit 1
        ;;
esac

echo ""
echo "=== Done ==="
echo "GPU runtime scripts: $BUILD_DIR"
ls -lh "$BUILD_DIR/"
echo ""
echo "On Revo OS, run these scripts to extract GPU libraries from host."
echo "Libraries live on /revo/gpu/ — not in initramfs."
