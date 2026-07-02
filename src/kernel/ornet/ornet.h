/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ornet.h — Revo OS Ornet AI Inference Kernel Module
 *
 * Shared types, ioctl definitions, and constants for the Ornet subsystem.
 * v1.3.1 — First kernel module implementation: MMM + Ring Buffer
 *
 * Author: Mudassir (github.com/skmudassir-it)
 */

#ifndef _ORNET_H
#define _ORNET_H

#include <linux/types.h>
#include <linux/ioctl.h>

#define ORNET_VERSION_MAJOR	1
#define ORNET_VERSION_MINOR	3
#define ORNET_VERSION_PATCH	1

#define ORNET_DEVICE_NAME	"ornet"
#define ORNET_DEVICE_CLASS	"ornet"

/* Ring buffer dimensions */
#define ORNET_RING_SLOTS	64
#define ORNET_RING_SLOT_SIZE	64
#define ORNET_RING_PAGE_ORDER	0	/* 4KB pages */
#define ORNET_RING_PAGES	4

/* Model memory limits */
#define ORNET_MAX_MODEL_SIZE	(12ULL * 1024 * 1024 * 1024)	/* 12 GB ceiling */
#define ORNET_MIN_MODEL_SIZE	(64ULL * 1024 * 1024)		/* 64 MB minimum */

/* GGUF magic number */
#define GGUF_MAGIC	0x46554747	/* "GGUF" in little-endian */

/* ─── Ring Buffer Slot ─── */
struct ornet_request {
	__u32 id;		/* Request ID (monotonic) */
	__u32 priority;		/* 0=HIGH, 1=MEDIUM, 2=LOW */
	char  prompt[56];	/* Null-terminated prompt */
} __attribute__((packed));

struct ornet_response {
	__u32 id;		/* Matching request ID */
	__u32 token_count;	/* Number of tokens generated */
	char  tokens[56];	/* Generated token text */
} __attribute__((packed));

/* ─── Status Page (read-only for userspace) ─── */
struct ornet_status {
	__u32 magic;			/* 0x4F524E45 "ORNE" */
	__u32 version;			/* (major << 16) | (minor << 8) | patch */
	__u32 flags;
#define ORNET_FLAG_LOADED	(1 << 0)	/* Model loaded in memory */
#define ORNET_FLAG_INFERRING	(1 << 1)	/* Currently processing */
#define ORNET_FLAG_ERROR	(1 << 2)	/* Error state */
#define ORNET_FLAG_GPU_AVAIL	(1 << 3)	/* GPU backend available (future) */

	__u32 uptime_seconds;		/* Seconds since module load */
	__u64 tokens_generated;		/* Lifetime inference counter */
	__u64 model_size_bytes;		/* Loaded model size */
	__u32 context_size;		/* Current context window */
	__u32 temperature_mc;		/* Temperature in millicelsius (e.g. 700 = 0.7) */
	__u32 ram_used_mb;		/* Kernel memory used by model */
	__u32 padding[3];		/* Future expansion (cache-aligned) */
} __attribute__((packed));

/* ─── Control Page (write-only for userspace) ─── */
struct ornet_control {
	__u32 command;
#define ORNET_CMD_NONE		0
#define ORNET_CMD_LOAD		1	/* Load model from path */
#define ORNET_CMD_UNLOAD	2	/* Unload model */
#define ORNET_CMD_SET_TEMP	3	/* Set temperature (mC) */
#define ORNET_CMD_SET_CTX	4	/* Set context window size */

	__u32 param;			/* Command parameter */
	char  path[56];			/* Model path for LOAD command */
} __attribute__((packed));

/* ─── Ring Buffer Layout (4 × 4KB pages) ─── */
struct ornet_ring {
	struct ornet_request  requests[ORNET_RING_SLOTS];	/* Page 0 */
	__u32 req_head __attribute__((aligned(64)));		/* Producer index */
	__u32 req_tail __attribute__((aligned(64)));		/* Consumer index */
	__u8  _pad0[4096 - (ORNET_RING_SLOTS * ORNET_RING_SLOT_SIZE) - 16];

	struct ornet_response responses[ORNET_RING_SLOTS];	/* Page 1 */
	__u32 resp_head __attribute__((aligned(64)));
	__u32 resp_tail __attribute__((aligned(64)));
	__u8  _pad1[4096 - (ORNET_RING_SLOTS * ORNET_RING_SLOT_SIZE) - 16];

	struct ornet_status status;				/* Page 2 */
	__u8  _pad2[4096 - sizeof(struct ornet_status)];

	struct ornet_control control;				/* Page 3 */
	__u8  _pad3[4096 - sizeof(struct ornet_control)];
} __attribute__((packed));

/* ─── GGUF Header (on-disk format) ─── */
struct gguf_header {
	__u32 magic;			/* GGUF_MAGIC = 0x46554747 */
	__u32 version;			/* GGUF format version (2 or 3) */
	__u64 tensor_count;		/* Number of tensors */
	__u64 metadata_kv_count;	/* Number of metadata key-value pairs */
} __attribute__((packed));

/* ─── Model Memory Manager State ─── */
struct ornet_mmm {
	void   *model_vaddr;		/* vmalloc'd region for model weights */
	__u64   model_size;		/* Total model size in bytes */
	__u32   num_tensors;		/* Number of GGUF tensors */
	__u32   context_size;		/* KV cache context window */
	__u32   temperature_mc;		/* Sampling temperature (millicelsius) */
	bool    loaded;		/* Model currently loaded */
	struct mutex lock;		/* Serialize load/unload */
};

/* ─── IOCTL Commands ─── */
#define ORNET_IOC_MAGIC		'o'

/* Load model from filesystem path */
#define ORNET_LOAD_MODEL	_IOW(ORNET_IOC_MAGIC, 1, char[256])

/* Unload model and free memory */
#define ORNET_UNLOAD_MODEL	_IO(ORNET_IOC_MAGIC, 2)

/* Get status (copies ornet_status to userspace) */
#define ORNET_GET_STATUS	_IOR(ORNET_IOC_MAGIC, 3, struct ornet_status)

/* Set sampling temperature (millicelsius, e.g. 700 = 0.7) */
#define ORNET_SET_TEMP		_IOW(ORNET_IOC_MAGIC, 4, __u32)

/* Set context window size */
#define ORNET_SET_CTX		_IOW(ORNET_IOC_MAGIC, 5, __u32)

/* Get inference statistics */
#define ORNET_GET_STATS		_IOR(ORNET_IOC_MAGIC, 6, struct ornet_status)

#define ORNET_IOC_MAXNR		6

#endif /* _ORNET_H */
