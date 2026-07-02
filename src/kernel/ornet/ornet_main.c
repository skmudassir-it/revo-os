/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ornet_main.c — Ornet Kernel Module: Character Device + IOCTL Interface
 *
 * Revo OS v1.3.1 — First kernel module implementation.
 *
 * Provides /dev/ornet (major 240, minor 0) — a character device
 * for zero-copy AI inference IPC between userspace (ornetd) and
 * the kernel-resident Ornith-1 language model.
 *
 * Architecture:
 *   ┌─────────────────────────────────────────────┐
 *   │  userspace: ornetd, shell, tools            │
 *   │         ↕ read/write/ioctl/mmap             │
 *   │  ┌───────────────────────────────────────┐  │
 *   │  │  /dev/ornet  character device          │  │
 *   │  │  ┌─────────────────────────────────┐  │  │
 *   │  │  │  Ring Buffer (4 pages)          │  │  │
 *   │  │  │  Page 0: Request ring (U→K)     │  │  │
 *   │  │  │  Page 1: Response ring (K→U)    │  │  │
 *   │  │  │  Page 2: Status (K→U, RO)       │  │  │
 *   │  │  │  Page 3: Control (U→K, WO)      │  │  │
 *   │  │  └─────────────────────────────────┘  │  │
 *   │  │  ┌─────────────────────────────────┐  │  │
 *   │  │  │  Model Memory Manager (MMM)     │  │  │
 *   │  │  │  vmalloc'd + pinned model       │  │  │
 *   │  │  └─────────────────────────────────┘  │  │
 *   │  └───────────────────────────────────────┘  │
 *   └─────────────────────────────────────────────┘
 *
 * Author: Mudassir (github.com/skmudassir-it)
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/mm.h>
#include <linux/vmalloc.h>
#include <linux/version.h>
#include <asm/io.h>

#include "ornet.h"
#include "ornet_ring.h"
#include "ornet_mmm.h"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Mudassir <skmudassir.it@gmail.com>");
MODULE_DESCRIPTION("Revo OS Ornet — Kernel-Native AI Inference Engine");
MODULE_VERSION("1.3.1");

/* ─── Module Parameters ─── */

static int major = 240;			/* Static major (traditional for ornet) */
module_param(major, int, 0444);
MODULE_PARM_DESC(major, "Major device number (default 240)");

static char *model_path = "";
module_param(model_path, charp, 0444);
MODULE_PARM_DESC(model_path, "Auto-load model at module init (path to GGUF file)");

/* ─── Global State ─── */

static struct class    *ornet_class;
static struct device   *ornet_device;
static struct cdev      ornet_cdev;
static dev_t            ornet_devt;

static struct ornet_ring *ornet_ring;	/* 4-page ring buffer (vmalloc'd) */
static struct ornet_mmm   ornet_mmm;	/* Model memory manager state */
static u64                uptime_jiffies;	/* Module load timestamp */

/* ─── File Operations ─── */

/*
 * mmap — Map the ring buffer pages into userspace.
 *
 * Supports four mappings, one per ring buffer page:
 *   offset 0 (PAGE 0): Request ring  — PROT_WRITE for userspace
 *   offset 1 (PAGE 1): Response ring — PROT_READ  for userspace
 *   offset 2 (PAGE 2): Status page   — PROT_READ  for userspace (kernel writes)
 *   offset 3 (PAGE 3): Control page  — PROT_WRITE for userspace (kernel reads)
 *
 * Each mmap call maps exactly one page. Userspace calls mmap 4 times
 * to get the full ring buffer mapped.
 */
static int ornet_mmap(struct file *filp, struct vm_area_struct *vma)
{
	unsigned long pfn;
	unsigned long size = vma->vm_end - vma->vm_start;
	unsigned long offset = vma->vm_pgoff << PAGE_SHIFT;
	struct page *page;

	/* Only allow single-page mappings */
	if (size != PAGE_SIZE)
		return -EINVAL;

	/* Validate page index (0–3) */
	if (offset >= ORNET_RING_PAGES * PAGE_SIZE)
		return -EINVAL;

	/* Get the physical page backing this ring buffer offset */
	page = vmalloc_to_page((void *)ornet_ring + offset);
	if (!page)
		return -ENOMEM;

	pfn = page_to_pfn(page);

	/*
	 * Set page protection based on which ring page is being mapped:
	 *   Page 0 (requests):  writable by userspace (producer)
	 *   Page 1 (responses): readable by userspace (consumer)
	 *   Page 2 (status):    readable by userspace (kernel is producer)
	 *   Page 3 (control):   writable by userspace (userspace is producer)
	 */
	switch (offset / PAGE_SIZE) {
	case 0:	/* Request ring — userspace writes */
	case 3:	/* Control page — userspace writes */
		vma->vm_page_prot = pgprot_writecombine(vma->vm_page_prot);
		vma->vm_flags |= VM_SHARED;
		break;
	case 1:	/* Response ring — userspace reads */
	case 2:	/* Status page — userspace reads */
		vma->vm_page_prot = pgprot_noncached(vma->vm_page_prot);
		vma->vm_flags |= VM_SHARED | VM_MAYREAD;
		break;
	}

	/* Remap the physical page into userspace */
	if (remap_pfn_range(vma, vma->vm_start, pfn, size, vma->vm_page_prot))
		return -EAGAIN;

	return 0;
}

/*
 * read — Dequeue a response from the response ring.
 *
 * Blocking read: if the ring is empty, the process sleeps
 * (TASK_INTERRUPTIBLE) until a response is enqueued.
 *
 * Returns sizeof(struct ornet_response) bytes on success,
 * or -ERESTARTSYS if interrupted by a signal.
 */
static ssize_t ornet_read(struct file *filp, char __user *buf,
			  size_t count, loff_t *ppos)
{
	struct ornet_response resp;
	int ret;

	if (count < sizeof(resp))
		return -EINVAL;

	/* Block until a response is available */
	ret = wait_event_interruptible(
		__ornet_response_wq,
		!ornet_ring_request_empty(ornet_ring) || !ornet_mmm_is_loaded(&ornet_mmm)
	);

	if (ret)
		return ret;	/* Signal interrupted */

	if (!ornet_mmm_is_loaded(&ornet_mmm))
		return -ENODEV;	/* Model unloaded while we waited */

	ret = ornet_ring_dequeue_response(ornet_ring, &resp);
	if (ret)
		return ret;

	if (copy_to_user(buf, &resp, sizeof(resp)))
		return -EFAULT;

	return sizeof(resp);
}

/*
 * Declare the wait queue (defined at bottom of file).
 * This is a simple waitqueue_head_t used by ornet_read().
 */
static DECLARE_WAIT_QUEUE_HEAD(__ornet_response_wq);

/*
 * write — Enqueue a request into the request ring.
 *
 * Non-blocking: returns -ENOSPC if the ring is full.
 * The caller (ornetd) should retry or use poll().
 *
 * Expects exactly sizeof(struct ornet_request) bytes.
 */
static ssize_t ornet_write(struct file *filp, const char __user *buf,
			   size_t count, loff_t *ppos)
{
	struct ornet_request req;
	int ret;

	if (count != sizeof(req))
		return -EINVAL;

	if (copy_from_user(&req, buf, sizeof(req)))
		return -EFAULT;

	/* Assign a monotonic request ID */
	static atomic_t next_id = ATOMIC_INIT(1);
	req.id = atomic_inc_return(&next_id);

	ret = ornet_ring_enqueue_request(ornet_ring, &req);
	if (ret)
		return ret;	/* -ENOSPC: ring full */

	/*
	 * Wake up the inference workqueue (future: v1.4 llama.cpp bridge).
	 * Currently, requests are queued but inference is a no-op until
	 * the llama.cpp backend is integrated.
	 */

	return sizeof(req);
}

/*
 * ioctl — Device control operations.
 *
 * Supported commands:
 *   ORNET_LOAD_MODEL  — Load a GGUF model from a filesystem path
 *   ORNET_UNLOAD_MODEL — Unload and free model memory
 *   ORNET_GET_STATUS  — Copy ornet_status to userspace
 *   ORNET_SET_TEMP    — Set sampling temperature (millicelsius)
 *   ORNET_SET_CTX     — Set context window size
 *   ORNET_GET_STATS   — Alias for ORNET_GET_STATUS
 */
static long ornet_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
{
	char path[256];
	__u32 param;
	struct ornet_status status;

	switch (cmd) {
	case ORNET_LOAD_MODEL:
		if (copy_from_user(path, (void __user *)arg, sizeof(path)))
			return -EFAULT;
		path[sizeof(path) - 1] = '\0';	/* Ensure null-terminated */
		return ornet_mmm_load_model(&ornet_mmm, path);

	case ORNET_UNLOAD_MODEL:
		ornet_mmm_unload_model(&ornet_mmm);
		return 0;

	case ORNET_GET_STATUS:
	case ORNET_GET_STATS:
		/* Copy the current status from the ring buffer */
		memcpy(&status, &ornet_ring->status, sizeof(status));

		/* Update live fields */
		status.uptime_seconds =
			(jiffies - uptime_jiffies) / HZ;
		status.ram_used_mb =
			ornet_mmm_get_size(&ornet_mmm) / (1024 * 1024);

		if (ornet_mmm_is_loaded(&ornet_mmm))
			status.flags |= ORNET_FLAG_LOADED;
		else
			status.flags &= ~ORNET_FLAG_LOADED;

		if (copy_to_user((void __user *)arg, &status, sizeof(status)))
			return -EFAULT;
		return 0;

	case ORNET_SET_TEMP:
		if (copy_from_user(&param, (void __user *)arg, sizeof(param)))
			return -EFAULT;
		if (param > 2000)	/* Max 2.0 (2000 millicelsius) */
			return -EINVAL;
		ornet_mmm.temperature_mc = param;
		ornet_ring->status.temperature_mc = param;
		smp_wmb();
		return 0;

	case ORNET_SET_CTX:
		if (copy_from_user(&param, (void __user *)arg, sizeof(param)))
			return -EFAULT;
		if (param < 512 || param > 32768)
			return -EINVAL;
		ornet_mmm.context_size = param;
		ornet_ring->status.context_size = param;
		smp_wmb();
		return 0;

	default:
		return -ENOTTY;
	}
}

static const struct file_operations ornet_fops = {
	.owner		= THIS_MODULE,
	.mmap		= ornet_mmap,
	.read		= ornet_read,
	.write		= ornet_write,
	.unlocked_ioctl	= ornet_ioctl,
	.llseek		= noop_llseek,
};

/* ─── Module Init / Exit ─── */

static int __init ornet_init(void)
{
	int ret;

	pr_info("ornet: v%d.%d.%d — Kernel-Native AI Inference Engine\n",
		ORNET_VERSION_MAJOR, ORNET_VERSION_MINOR, ORNET_VERSION_PATCH);
	pr_info("ornet: (c) Mudassir — Revo OS | github.com/skmudassir-it\n");

	/* ── Allocate ring buffer ── */
	ornet_ring = vzalloc(ORNET_RING_PAGES * PAGE_SIZE);
	if (!ornet_ring) {
		pr_err("ornet: failed to allocate ring buffer (%d pages)\n",
		       ORNET_RING_PAGES);
		return -ENOMEM;
	}
	ornet_ring_init(ornet_ring);

	/* ── Initialize Model Memory Manager ── */
	ornet_mmm_init(&ornet_mmm);
	uptime_jiffies = jiffies;

	/* ── Register character device ── */
	ornet_devt = MKDEV(major, 0);

	ret = register_chrdev_region(ornet_devt, 1, ORNET_DEVICE_NAME);
	if (ret < 0) {
		pr_err("ornet: failed to register chrdev region %d: %d\n",
		       major, ret);
		goto err_ring;
	}

	cdev_init(&ornet_cdev, &ornet_fops);
	ornet_cdev.owner = THIS_MODULE;

	ret = cdev_add(&ornet_cdev, ornet_devt, 1);
	if (ret < 0) {
		pr_err("ornet: cdev_add failed: %d\n", ret);
		goto err_region;
	}

	/* ── Create device node ── */
	ornet_class = class_create(ORNET_DEVICE_CLASS);
	if (IS_ERR(ornet_class)) {
		ret = PTR_ERR(ornet_class);
		pr_err("ornet: class_create failed: %d\n", ret);
		goto err_cdev;
	}

	ornet_device = device_create(ornet_class, NULL, ornet_devt,
				     NULL, ORNET_DEVICE_NAME);
	if (IS_ERR(ornet_device)) {
		ret = PTR_ERR(ornet_device);
		pr_err("ornet: device_create failed: %d\n", ret);
		goto err_class;
	}

	pr_info("ornet: /dev/ornet ready (major %d, minor 0)\n", major);

	/* ── Auto-load model if specified ── */
	if (strlen(model_path) > 0) {
		pr_info("ornet: auto-loading model '%s'...\n", model_path);
		ret = ornet_mmm_load_model(&ornet_mmm, model_path);
		if (ret < 0) {
			pr_warn("ornet: auto-load failed (%d) — load manually via ioctl\n",
				ret);
		}
	}

	pr_info("ornet: module loaded — ring buffer + MMM ready\n");
	pr_info("ornet: model is firmware, not software\n");
	return 0;

err_class:
	class_destroy(ornet_class);
err_cdev:
	cdev_del(&ornet_cdev);
err_region:
	unregister_chrdev_region(ornet_devt, 1);
err_ring:
	vfree(ornet_ring);
	return ret;
}

static void __exit ornet_exit(void)
{
	pr_info("ornet: shutting down...\n");

	/* Unload model if loaded */
	if (ornet_mmm_is_loaded(&ornet_mmm))
		ornet_mmm_unload_model(&ornet_mmm);

	/* Tear down device */
	device_destroy(ornet_class, ornet_devt);
	class_destroy(ornet_class);
	cdev_del(&ornet_cdev);
	unregister_chrdev_region(ornet_devt, 1);

	/* Free ring buffer */
	vfree(ornet_ring);

	pr_info("ornet: module unloaded\n");
}

module_init(ornet_init);
module_exit(ornet_exit);
