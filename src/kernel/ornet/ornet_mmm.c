/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ornet_mmm.c — Model Memory Manager Implementation
 *
 * Handles loading GGUF-format language models into kernel virtual memory.
 * The model is allocated via vmalloc() as a contiguous virtual region,
 * then each underlying physical page is pinned with SetPageReserved().
 *
 * This ensures:
 *   - The model never gets swapped out (no page faults during inference)
 *   - TLB entries stay hot (contiguous virtual mapping)
 *   - NUMA-aware allocation on multi-socket systems (future)
 *
 * GGUF format reference: https://github.com/ggerganov/ggml/blob/master/docs/gguf.md
 *
 * v1.3.1: Initial implementation — model load/unload, GGUF header parsing,
 *         page pinning, basic sanity checks. Inference dispatch is in
 *         ornet_main.c (future versions will add the llama.cpp bridge).
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/vmalloc.h>
#include <linux/mm.h>
#include <linux/fs.h>
#include <linux/file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/delay.h>
#include <asm/page.h>
#include "ornet.h"
#include "ornet_mmm.h"

/* ─── GGUF Header Validation ─── */

/*
 * Read and validate the GGUF header from a kernel file pointer.
 * GGUF format:
 *   Offset 0:  uint32 magic   (0x46554747 = "GGUF")
 *   Offset 4:  uint32 version (2 or 3)
 *   Offset 8:  uint64 tensor_count
 *   Offset 16: uint64 metadata_kv_count
 *
 * Returns: 0 on valid header, -EINVAL on bad magic/version,
 *          -EIO on read error.
 */
static int ornet_mmm_validate_gguf(struct file *filp, u64 *model_size)
{
	struct gguf_header header;
	loff_t pos = 0;
	ssize_t ret;

	ret = kernel_read(filp, &header, sizeof(header), &pos);
	if (ret < 0)
		return ret;
	if (ret != sizeof(header))
		return -EIO;

	if (header.magic != GGUF_MAGIC) {
		pr_err("ornet: bad GGUF magic: 0x%08x (expected 0x%08x)\n",
		       header.magic, GGUF_MAGIC);
		return -EINVAL;
	}

	if (header.version < 2 || header.version > 3) {
		pr_err("ornet: unsupported GGUF version %u\n", header.version);
		return -EINVAL;
	}

	pr_info("ornet: GGUF v%u — %llu tensors, %llu metadata KVs\n",
		header.version, header.tensor_count, header.metadata_kv_count);

	/*
	 * Model size = total file size (userspace tells us the path,
	 * we stat it). For now, return the file size as an approximation.
	 * The full GGUF parsing (tensor offsets + sizes) will be in the
	 * llama.cpp bridge in a future version.
	 */
	*model_size = i_size_read(file_inode(filp));

	return 0;
}

/* ─── Page Pinning ─── */

/*
 * Pin all physical pages backing a vmalloc'd region.
 * This prevents the kernel from swapping or migrating these pages.
 *
 * Strategy:
 *   1. Walk the vmalloc area's page table entries
 *   2. For each present PTE, get the struct page
 *   3. Call SetPageReserved() on each page
 *
 * PITFALL: vmalloc_to_page() only works for vmalloc'd pages, not
 * kmalloc or stack pages. We only call this on MMM's vmalloc region.
 *
 * WARNNIG: This pins potentially gigabytes of memory permanently.
 * Call ornet_mmm_unpin_pages() before vfree().
 */
static int ornet_mmm_pin_pages(void *vaddr, size_t size)
{
	unsigned long start = (unsigned long)vaddr;
	unsigned long end = start + size;
	unsigned long addr;
	int pinned = 0;

	pr_info("ornet: pinning pages %lx → %lx (%zu bytes)\n",
		start, end, size);

	for (addr = start; addr < end; addr += PAGE_SIZE) {
		struct page *page = vmalloc_to_page((void *)addr);

		if (!page) {
			pr_warn("ornet: no page at vaddr 0x%lx (offset %lu)\n",
				addr, addr - start);
			continue;
		}

		/*
		 * SetPageReserved marks the page as reserved so the
		 * kernel never swaps, migrates, or reclaims it.
		 * This is what GPU drivers do for pinned DMA buffers.
		 */
		SetPageReserved(page);
		pinned++;
	}

	pr_info("ornet: pinned %d pages (%lu MB)\n",
		pinned, (pinned * PAGE_SIZE) / (1024 * 1024));

	return 0;
}

/*
 * Unpin pages before freeing the vmalloc region.
 * Must be called before vfree() on a previously-pinned region.
 */
static void ornet_mmm_unpin_pages(void *vaddr, size_t size)
{
	unsigned long start = (unsigned long)vaddr;
	unsigned long end = start + size;
	unsigned long addr;

	for (addr = start; addr < end; addr += PAGE_SIZE) {
		struct page *page = vmalloc_to_page((void *)addr);

		if (page)
			ClearPageReserved(page);
	}

	pr_info("ornet: unpinned model pages\n");
}

/* ─── Public API ─── */

void ornet_mmm_init(struct ornet_mmm *mmm)
{
	memset(mmm, 0, sizeof(*mmm));
	mutex_init(&mmm->lock);
	mmm->temperature_mc = 700;	/* 0.7 */
	mmm->context_size = 4096;
}

int ornet_mmm_load_model(struct ornet_mmm *mmm, const char *path)
{
	struct file *filp;
	u64 file_size;
	int ret;

	if (!path || strlen(path) == 0)
		return -EINVAL;

	mutex_lock(&mmm->lock);

	/* If already loaded, unload first */
	if (mmm->loaded)
		ornet_mmm_unload_model(mmm);

	/* Open the model file */
	filp = filp_open(path, O_RDONLY, 0);
	if (IS_ERR(filp)) {
		ret = PTR_ERR(filp);
		pr_err("ornet: cannot open model file '%s': %d\n", path, ret);
		goto out_unlock;
	}

	/* Validate GGUF header and get file size */
	ret = ornet_mmm_validate_gguf(filp, &file_size);
	if (ret < 0) {
		pr_err("ornet: invalid GGUF file '%s'\n", path);
		goto out_close;
	}

	/* Sanity-check model size */
	if (file_size > ORNET_MAX_MODEL_SIZE) {
		pr_err("ornet: model too large: %llu MB (max %llu MB)\n",
		       file_size / (1024 * 1024),
		       ORNET_MAX_MODEL_SIZE / (1024 * 1024));
		ret = -EFBIG;
		goto out_close;
	}

	if (file_size < ORNET_MIN_MODEL_SIZE) {
		pr_err("ornet: model too small: %llu bytes (min %llu)\n",
		       file_size, ORNET_MIN_MODEL_SIZE);
		ret = -EINVAL;
		goto out_close;
	}

	pr_info("ornet: loading model '%s' (%llu MB)...\n",
		path, file_size / (1024 * 1024));

	/*
	 * Allocate contiguous kernel virtual memory for the model.
	 *
	 * vmalloc() can allocate large regions (up to ~64 TB on x86_64
	 * with 4-level paging, bounded by vmalloc= kernel param).
	 * The allocation is virtually contiguous but physically scattered,
	 * which is fine — we pin each page individually.
	 *
	 * Use __GFP_NORETRY so a failed large allocation doesn't trigger
	 * the OOM killer — we fail gracefully instead.
	 */
	mmm->model_vaddr = __vmalloc(file_size,
				     GFP_KERNEL | __GFP_NORETRY | __GFP_NOWARN);
	if (!mmm->model_vaddr) {
		pr_err("ornet: vmalloc(%llu) failed — not enough kernel VA space\n",
		       file_size);
		pr_err("ornet: try adding 'vmalloc=12G' to kernel cmdline\n");
		ret = -ENOMEM;
		goto out_close;
	}

	/*
	 * Read the entire model file into kernel memory.
	 * For a 5.5 GB model on NVMe (~700 MB/s), this takes ~8 seconds.
	 *
	 * FUTURE (v1.6): DMA from NVMe directly into vmalloc region
	 * using PCIe peer-to-peer to eliminate the CPU copy.
	 */
	{
		loff_t pos = 0;
		ssize_t bytes = kernel_read(filp, mmm->model_vaddr,
					    file_size, &pos);
		if (bytes < 0) {
			pr_err("ornet: read error: %zd\n", bytes);
			ret = (int)bytes;
			goto out_free;
		}
		if ((u64)bytes != file_size) {
			pr_err("ornet: short read: %zd / %llu\n", bytes, file_size);
			ret = -EIO;
			goto out_free;
		}
	}

	pr_info("ornet: model read complete (%llu MB)\n",
		file_size / (1024 * 1024));

	/* Pin pages to prevent swapping */
	ret = ornet_mmm_pin_pages(mmm->model_vaddr, file_size);
	if (ret < 0) {
		pr_err("ornet: page pinning failed: %d\n", ret);
		goto out_unpin;
	}

	mmm->model_size = file_size;
	mmm->loaded = true;

	pr_info("ornet: model loaded — %llu MB pinned, never swapped\n",
		file_size / (1024 * 1024));

	filp_close(filp, NULL);
	mutex_unlock(&mmm->lock);
	return 0;

out_unpin:
	ornet_mmm_unpin_pages(mmm->model_vaddr, file_size);
out_free:
	vfree(mmm->model_vaddr);
	mmm->model_vaddr = NULL;
out_close:
	filp_close(filp, NULL);
out_unlock:
	mutex_unlock(&mmm->lock);
	return ret;
}

void ornet_mmm_unload_model(struct ornet_mmm *mmm)
{
	mutex_lock(&mmm->lock);

	if (!mmm->loaded || !mmm->model_vaddr) {
		mutex_unlock(&mmm->lock);
		return;
	}

	pr_info("ornet: unloading model (%llu MB)...\n",
		mmm->model_size / (1024 * 1024));

	/* Unpin pages first, then free the vmalloc region */
	ornet_mmm_unpin_pages(mmm->model_vaddr, mmm->model_size);
	vfree(mmm->model_vaddr);

	mmm->model_vaddr = NULL;
	mmm->model_size = 0;
	mmm->loaded = false;

	pr_info("ornet: model unloaded — memory freed\n");

	mutex_unlock(&mmm->lock);
}
