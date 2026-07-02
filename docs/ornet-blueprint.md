# Ornet Kernel Module — Design Blueprint

**Version:** 1.3.0  
**Module:** `ornet.ko`  
**Target Size:** ~500 KB  
**Status:** Design phase — kernel module implementation planned for v1.3.1

---

## Overview

`ornet.ko` is a Linux kernel module that provides **native AI inference at the kernel level**. It manages the memory lifecycle of large language models (GGUF format), dispatches tensor operations to the CPU (and eventually GPU), and exposes a ring-buffer interface for userspace inference clients like `ornetd`. The module bridges the llama.cpp backend — the model stays resident in kernel-managed memory, eliminating the page-fault and context-switch overhead of userspace-only inference.

### Design Goals

| Goal | Rationale |
|------|-----------|
| **Model stays resident** | Once loaded, the GGUF model is pinned in kernel memory — no page-out, no swap, no userspace context switches on inference |
| **Ring-buffer dispatch** | Inference requests from userspace enqueue via a lock-free ring buffer; results dequeue the same way — single-copy IPC |
| **Zero-copy tensors** | Tensor data flows between model memory and compute via kernel-space DMA, not userspace memcpy |
| **Priority scheduler** | High-priority requests (interactive chat) preempt batch jobs (embedding generation) |
| **Dedicated RevoAI volume** | The model lives on a separate dm-verity-protected GPT partition — firmware, not software |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      USERSPACE                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │ ornetd   │  │ revocker │  │  shell   │                  │
│  │(dispatch)│  │(containr)│  │(infer)   │                  │
│  └────┬─────┘  └──────────┘  └────┬─────┘                  │
│       │         /dev/ornet        │                         │
├───────┼─────────────┬─────────────┼─────────────────────────┤
│       │    KERNEL   │             │                         │
│  ┌────┴──────────┐  │  ┌──────────┴──────────┐              │
│  │  ornet.ko     │  │  │  Character Device   │              │
│  │               │  │  │  /dev/ornet (major  │              │
│  │ ┌───────────┐ │  │  │   240)              │              │
│  │ │ Model Mem │ │  │  └──────────┬──────────┘              │
│  │ │ Manager   │ │  │             │                          │
│  │ └─────┬─────┘ │  │  ┌──────────┴──────────┐              │
│  │       │       │  │  │   Ring Buffer       │              │
│  │ ┌─────┴─────┐ │  │  │   (lock-free SPSC)  │              │
│  │ │ Tensor    │ │  │  │   4 × 4KB pages     │              │
│  │ │ Dispatch  │ │  │  └──────────┬──────────┘              │
│  │ └─────┬─────┘ │  │             │                          │
│  │       │       │  │  ┌──────────┴──────────┐              │
│  │ ┌─────┴─────┐ │  │  │   Priority Queue    │              │
│  │ │ llama.cpp │ │  │  │   High/Med/Low      │              │
│  │ │ Backend   │ │  │  └─────────────────────┘              │
│  │ │ Bridge    │ │  │                                       │
│  │ └───────────┘ │  │                                       │
│  └───────────────┘  │                                       │
│                     │                                       │
│  ┌──────────────────┴───────────────────────────────────┐   │
│  │              Linux Kernel 6.12.94                      │   │
│  │  cgroups v2 │ namespaces │ ext4 │ overlayfs │ virtio  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Subsystems

### 1. Model Memory Manager (MMM)

Manages the GGUF model in kernel-space memory.

```
Allocation strategy:
  Phase 1: Probe model size from GGUF header (offset 8: uint64_t)
  Phase 2: vmalloc() contiguous virtual region for the full model
  Phase 3: Map each GGUF tensor slot with vmap() for per-tensor access
  Phase 4: Pin all pages with SetPageReserved() — model never swapped

Memory budget (Q4_K_M, 9B params):
  Weights:  ~4.7 GB (4-bit quantized)
  KV cache: ~1.0 GB (4096 ctx × 64 layers × hidden_dim)
  Metadata: ~50 MB (tokenizer, config, GGUF headers)
  Total:    ~5.75 GB pinned kernel memory
```

**PITFALL**: The kernel's `vmalloc` address space is limited to ~64 TB on x86_64 4-level paging. A 5.75 GB allocation is well within limits but requires `vmalloc=8G` on the kernel command line for older configs. The tinyconfig kernel must enable `CONFIG_HAVE_VMALLOC_ARRAY=y`.

### 2. Tensor Dispatch Engine

Routes inference operations to the appropriate compute backend.

```
Operation pipeline:
  1. Userspace writes prompt to /dev/ornet (ring buffer slot)
  2. Tokenizer in llama.cpp bridge converts to token IDs
  3. For each token:
     a. Embedding lookup (from MMM)
     b. Transformer layers × 64 (Q, K, V, O, FFN)
     c. Attention: RoPE + flash-attn kernel
     d. Logits → softmax → sample
  4. Token written to output ring buffer slot
  5. Userspace reads result from /dev/ornet

Backend dispatch:
  - CPU (default): llama.cpp's GGML backend, AVX2/AVX512 if available
  - GPU (future): v1.6 — CUDA/Vulkan passthrough via DMA-BUF
  - Split (future): CPU for prompt processing, GPU for token generation
```

### 3. Ring Buffer (Lock-Free SPSC)

Single-producer, single-consumer ring buffer for zero-copy IPC.

```
Layout:
  Page 0: Request ring (userspace → kernel)
    - 4096 bytes, 64 slots × 64 bytes each
    - Each slot: { uint32_t id, uint32_t priority, char prompt[56] }
  
  Page 1: Response ring (kernel → userspace)
    - 4096 bytes, 64 slots × 64 bytes each
    - Each slot: { uint32_t id, uint32_t token_count, char tokens[56] }
  
  Page 2: Status page (read-only for userspace)
    - Model loaded flag, uptime, tokens generated, RAM used, temp

  Page 3: Control page (write-only for userspace)
    - Load model, unload model, set temperature, set context size

Synchronization:
  - Head/tail pointers: atomic uint32_t (lock-free)
  - Memory barriers: smp_mb() on enqueue/dequeue
  - Backpressure: if ring full, write() blocks with TASK_INTERRUPTIBLE
```

### 4. Priority Scheduler

Three priority tiers for inference requests:

```
HIGH (interactive):   Preempts medium/low. For chat sessions, REPL.
MEDIUM (batch):       Standard priority. For bulk processing, evals.
LOW (background):     Best-effort. For embeddings, re-ranking.

Scheduling algorithm:
  - Round-robin within each tier
  - Starvation prevention: low-priority guaranteed 1 slot per 10 dispatches
  - Time slice: 100ms per inference request (preemptible at token boundaries)
  - Max queue depth: 64 pending requests across all tiers
```

### 5. llama.cpp Backend Bridge

Thin wrapper that calls llama.cpp's C API from kernel context.

```
Key adaptations:
  - Replace malloc/free with kmalloc/kfree
  - Replace fprintf with printk (rate-limited)
  - Replace file I/O with vmap'd model memory
  - Thread pool → workqueue (kernel workqueues)
  - SIMD: AVX2/AVX512 kernel_fpu_begin()/end() wrappers

Linkage:
  - llama.cpp compiled as a static library (libllama.a)
  - Linked into ornet.ko at build time
  - ggml tensor ops compiled with -mavx2 -mfma
  - No dynamic dependencies — fully self-contained module
```

---

## Character Device Interface

```
Device: /dev/ornet (major 240, minor 0)

ioctl commands:
  ORNET_LOAD_MODEL     — Load GGUF model from path
  ORNET_UNLOAD_MODEL   — Unload and free model memory
  ORNET_GET_STATUS     — Get ornet_status struct
  ORNET_SET_TEMP       — Set sampling temperature (0.0–2.0)
  ORNET_SET_CTX        — Set context window size
  ORNET_GET_STATS      — Get inference statistics

read():
  - Blocking read from response ring buffer
  - Returns next available token(s)
  - Non-blocking with O_NONBLOCK

write():
  - Write prompt to request ring buffer
  - Priority encoded in high bits of first 32-bit word
  - Returns request ID for matching responses

mmap():
  - Map status page (PAGE 2): read-only for userspace
  - Map control page (PAGE 3): write-only for userspace
  - Ring buffer pages accessible through read/write syscalls only
```

---

## Kernel Configuration Requirements

The `revo-tiny.config` must additionally enable:

```
# Ornet kernel module
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_HAVE_VMALLOC_ARRAY=y

# Memory management
CONFIG_MMU=y
CONFIG_VMALLOC=y
CONFIG_TRANSPARENT_HUGEPAGE=y           # 2MB pages for model memory

# FPU in kernel
CONFIG_KERNEL_FPU=y                      # AVX2 in kernel context

# Character devices
CONFIG_CHR_DEV=y

# Workqueues (for inference thread pool)
CONFIG_WQ=y

# Cryptographic (for dm-verity on RevoAI volume)
CONFIG_DM_VERITY=y
CONFIG_CRYPTO_SHA256=y
```

---

## Build Pipeline

```bash
# 1. Compile llama.cpp as a static library
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
mkdir build && cd build
cmake .. -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON \
         -DBUILD_SHARED_LIBS=OFF -DGGML_STATIC=ON
make llama ggml -j$(nproc)
# Produces: libllama.a, libggml.a (~2 MB each)
cd ../..

# 2. Compile ornet.ko
make -C /lib/modules/$(uname -r)/build M=$PWD modules
# Produces: ornet.ko (~500 KB)
#   ornet_main.o       — char device, ioctl, module init/exit
#   ornet_mmm.o        — Model memory manager
#   ornet_ring.o       — Ring buffer implementation
#   ornet_sched.o      — Priority scheduler
#   ornet_llama_bridge.o — llama.cpp kernel adapter
#   +libllama.a, +libggml.a (statically linked)

# 3. Copy to kernel modules directory
cp ornet.ko modules_out/
gzip -9 modules_out/ornet.ko
```

---

## Memory Layout at Runtime

```
Kernel virtual address space (x86_64, 4-level paging):

  0xFFFF888000000000  ┌──────────────────────┐
                      │   Kernel text/data    │   ~10 MB
  0xFFFF8880A0000000  ├──────────────────────┤
                      │   ornet.ko (code)     │   ~500 KB
  0xFFFF8880A0080000  ├──────────────────────┤
                      │   Ring buffer         │   16 KB (4 × 4KB pages)
  0xFFFF8880A0084000  ├──────────────────────┤
                      │   Workqueue pool      │   ~2 MB (4 threads × 512KB stack)
  0xFFFF8880A0284000  ├──────────────────────┤
                      │   Model weights       │   ~4.7 GB (vmalloc)
  0xFFFF88B0A0284000  ├──────────────────────┤
                      │   KV cache            │   ~1.0 GB (vmalloc)
  0xFFFF88D0A0284000  ├──────────────────────┤
                      │   Tokenizer metadata  │   ~50 MB (kmalloc)
  0xFFFF88D328000000  └──────────────────────┘
```

---

## Performance Estimates

| Operation | Latency | Throughput |
|-----------|---------|------------|
| Model load (from NVMe) | ~8s (700 MB/s) | N/A |
| Single token (CPU, AVX2) | ~35ms | ~28 tok/s |
| Single token (CPU, AVX512) | ~22ms | ~45 tok/s |
| Ring buffer enqueue | ~50ns | ~20M ops/s |
| Prompt processing (512 tok) | ~2.1s | ~240 tok/s |
| Context switch overhead | 0 (kernel-resident) | — |

Comparison to userspace llama.cpp (same hardware):
- **Latency reduction**: ~15% (no page faults, no context switches per token)
- **Memory savings**: ~200 MB (no redundant page tables for model pages)
- **Cold-start**: ~500ms faster (model pinned, never evicted)

---

## Security Considerations

| Concern | Mitigation |
|---------|------------|
| Model poisoning | dm-verity on RevoAI volume — hash tree verified at mount |
| Prompt injection | No shell execution; tokens processed as raw IDs |
| Kernel panic on OOM | Model allocation uses `__GFP_NORETRY` — fails gracefully |
| Information leak | Ring buffer pages cleared on read; status page is read-only |
| DoS (queue flood) | Max 64 pending requests; write() blocks beyond capacity |

---

## Roadmap

| Version | Feature |
|---------|---------|
| v1.3.0 | Userspace ornetd + model download (shipped) |
| **v1.3.1** | **ornet.ko kernel module — MMM + ring buffer** |
| v1.4 | llama.cpp bridge + basic CPU inference in kernel |
| v1.5 | Priority scheduler + interactive chat support |
| v1.6 | GPU passthrough (CUDA/Vulkan via DMA-BUF) |
| v1.7 | Multi-model hot-swap + tensor offload (CPU↔GPU) |

---

## References

- [llama.cpp](https://github.com/ggerganov/llama.cpp) — Inference backend
- [Ornith-1 9B](https://huggingface.co/deepreinforce-ai/Ornith-1.0-9B-GGUF) — Model weights
- [GGUF format spec](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md) — File format
- [Linux Kernel Module Programming Guide](https://sysprog21.github.io/lkmpg/) — LKM reference
- [Linux Device Drivers, 3rd Ed.](https://lwn.net/Kernel/LDD3/) — Char device + ioctl
