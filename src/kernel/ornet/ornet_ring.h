/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ornet_ring.h — Lock-Free SPSC Ring Buffer
 *
 * Single-producer, single-consumer ring buffer for zero-copy IPC
 * between userspace (/dev/ornet) and the kernel inference engine.
 *
 * Page 0: Request ring  (userspace → kernel)
 * Page 1: Response ring (kernel → userspace)
 * Page 2: Status page   (kernel → userspace, read-only)
 * Page 3: Control page  (userspace → kernel, write-only)
 */

#ifndef _ORNET_RING_H
#define _ORNET_RING_H

#include "ornet.h"

/* Initialize the ring buffer pages (zero all slots and pointers) */
void ornet_ring_init(struct ornet_ring *ring);

/* ─── Request Ring (userspace → kernel) ─── */

/* Enqueue a request. Returns 0 on success, -ENOSPC if full. */
int ornet_ring_enqueue_request(struct ornet_ring *ring,
			       const struct ornet_request *req);

/* Dequeue a request. Returns 0 on success, -ENODATA if empty. */
int ornet_ring_dequeue_request(struct ornet_ring *ring,
			       struct ornet_request *req);

/* Check if request ring is full */
bool ornet_ring_request_full(struct ornet_ring *ring);

/* Check if request ring is empty */
bool ornet_ring_request_empty(struct ornet_ring *ring);

/* ─── Response Ring (kernel → userspace) ─── */

/* Enqueue a response. Returns 0 on success, -ENOSPC if full. */
int ornet_ring_enqueue_response(struct ornet_ring *ring,
				const struct ornet_response *resp);

/* Dequeue a response. Returns 0 on success, -ENODATA if empty. */
int ornet_ring_dequeue_response(struct ornet_ring *ring,
				struct ornet_response *resp);

/* ─── Status helpers ─── */

void ornet_ring_update_status(struct ornet_ring *ring, __u32 flags);
void ornet_ring_increment_tokens(struct ornet_ring *ring, __u32 count);

/* ─── Control helpers ─── */

int ornet_ring_read_control(struct ornet_ring *ring,
			    struct ornet_control *ctrl);

/* Reset control page after processing (prevents re-execution) */
void ornet_ring_clear_control(struct ornet_ring *ring);

#endif /* _ORNET_RING_H */
