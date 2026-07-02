/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ornet_mmm.h — Model Memory Manager
 *
 * Manages GGUF model loading, kernel-space memory allocation,
 * and page pinning for the Ornith-1 language model.
 */

#ifndef _ORNET_MMM_H
#define _ORNET_MMM_H

#include <linux/types.h>
#include <linux/mutex.h>
#include "ornet.h"

/* Initialize the MMM subsystem */
void ornet_mmm_init(struct ornet_mmm *mmm);

/*
 * Load a GGUF model from the given filesystem path.
 * Allocates kernel virtual memory via vmalloc() and pins pages
 * with SetPageReserved() so the model never swaps.
 *
 * Returns: 0 on success, negative errno on failure.
 */
int ornet_mmm_load_model(struct ornet_mmm *mmm, const char *path);

/*
 * Unload the current model and free all associated memory.
 * Safe to call when no model is loaded (no-op).
 */
void ornet_mmm_unload_model(struct ornet_mmm *mmm);

/* Check if a model is currently loaded */
static inline bool ornet_mmm_is_loaded(struct ornet_mmm *mmm)
{
	return mmm->loaded;
}

/* Get the virtual address of the loaded model (NULL if none) */
static inline void *ornet_mmm_get_vaddr(struct ornet_mmm *mmm)
{
	return mmm->model_vaddr;
}

/* Get model size in bytes */
static inline u64 ornet_mmm_get_size(struct ornet_mmm *mmm)
{
	return mmm->model_size;
}

#endif /* _ORNET_MMM_H */
