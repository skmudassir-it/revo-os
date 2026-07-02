/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ornet_ring.c — Lock-Free SPSC Ring Buffer Implementation
 *
 * Uses atomic head/tail pointers with SMP memory barriers.
 * Single-producer, single-consumer design — no locks needed
 * for enqueue/dequeue on their respective rings.
 *
 * Memory ordering:
 *   - smp_wmb() before updating head (ensure slot data is visible)
 *   - smp_rmb() before reading slot (ensure head/tail are current)
 *   - smp_mb()  for full barrier on status/control pages
 */

#include <linux/kernel.h>
#include <linux/string.h>
#include <asm/barrier.h>
#include "ornet.h"
#include "ornet_ring.h"

/* ─── Ring Buffer Initialization ─── */

void ornet_ring_init(struct ornet_ring *ring)
{
	/* Zero all pages */
	memset(ring, 0, ORNET_RING_PAGES * PAGE_SIZE);

	/* Initialize head/tail pointers (already zero from memset) */

	/* Initialize status magic and version */
	ring->status.magic = 0x4F524E45;	/* "ORNE" */
	ring->status.version = (ORNET_VERSION_MAJOR << 16) |
			       (ORNET_VERSION_MINOR << 8) |
			       ORNET_VERSION_PATCH;
	ring->status.temperature_mc = 700;	/* Default 0.7 */
	ring->status.context_size = 4096;

	/* Ensure initialization is visible before any access */
	smp_wmb();
}

/* ─── Request Ring ─── */

int ornet_ring_enqueue_request(struct ornet_ring *ring,
			       const struct ornet_request *req)
{
	__u32 head, tail, next;

	head = ring->req_head;
	tail = READ_ONCE(ring->req_tail);

	next = (head + 1) % ORNET_RING_SLOTS;

	/* Full if next == tail (one slot always empty for SPSC) */
	if (next == tail)
		return -ENOSPC;

	/* Write slot data before updating head */
	memcpy(&ring->requests[head], req, sizeof(*req));

	/* Ensure slot write is visible before head update */
	smp_wmb();
	WRITE_ONCE(ring->req_head, next);

	return 0;
}

int ornet_ring_dequeue_request(struct ornet_ring *ring,
			       struct ornet_request *req)
{
	__u32 head, tail;

	head = READ_ONCE(ring->req_head);
	tail = ring->req_tail;

	/* Empty if head == tail */
	if (head == tail)
		return -ENODATA;

	/* Ensure we see the latest slot data */
	smp_rmb();
	memcpy(req, &ring->requests[tail], sizeof(*req));

	/* Clear slot (defense-in-depth against info leaks) */
	memset(&ring->requests[tail], 0, sizeof(*req));

	/* Ensure slot clear is visible before tail update */
	smp_wmb();
	WRITE_ONCE(ring->req_tail, (tail + 1) % ORNET_RING_SLOTS);

	return 0;
}

bool ornet_ring_request_full(struct ornet_ring *ring)
{
	__u32 head, tail;

	head = ring->req_head;
	tail = READ_ONCE(ring->req_tail);

	return ((head + 1) % ORNET_RING_SLOTS) == tail;
}

bool ornet_ring_request_empty(struct ornet_ring *ring)
{
	__u32 head, tail;

	head = READ_ONCE(ring->req_head);
	tail = ring->req_tail;

	return head == tail;
}

/* ─── Response Ring ─── */

int ornet_ring_enqueue_response(struct ornet_ring *ring,
				const struct ornet_response *resp)
{
	__u32 head, tail, next;

	head = ring->resp_head;
	tail = READ_ONCE(ring->resp_tail);

	next = (head + 1) % ORNET_RING_SLOTS;

	if (next == tail)
		return -ENOSPC;

	memcpy(&ring->responses[head], resp, sizeof(*resp));
	smp_wmb();
	WRITE_ONCE(ring->resp_head, next);

	return 0;
}

int ornet_ring_dequeue_response(struct ornet_ring *ring,
				struct ornet_response *resp)
{
	__u32 head, tail;

	head = READ_ONCE(ring->resp_head);
	tail = ring->resp_tail;

	if (head == tail)
		return -ENODATA;

	smp_rmb();
	memcpy(resp, &ring->responses[tail], sizeof(*resp));
	memset(&ring->responses[tail], 0, sizeof(*resp));
	smp_wmb();
	WRITE_ONCE(ring->resp_tail, (tail + 1) % ORNET_RING_SLOTS);

	return 0;
}

/* ─── Status ─── */

void ornet_ring_update_status(struct ornet_ring *ring, __u32 flags)
{
	ring->status.flags = flags;
	smp_wmb();	/* Ensure status write is visible to userspace */
}

void ornet_ring_increment_tokens(struct ornet_ring *ring, __u32 count)
{
	ring->status.tokens_generated += count;
	/* No barrier needed — tokens_generated is best-effort visible */
}

/* ─── Control ─── */

int ornet_ring_read_control(struct ornet_ring *ring,
			    struct ornet_control *ctrl)
{
	/* Ensure we see the latest control write from userspace */
	smp_rmb();

	if (ring->control.command == ORNET_CMD_NONE)
		return -ENODATA;

	memcpy(ctrl, &ring->control, sizeof(*ctrl));
	return 0;
}

void ornet_ring_clear_control(struct ornet_ring *ring)
{
	memset(&ring->control, 0, sizeof(ring->control));
	smp_wmb();	/* Ensure clear is visible */
}
