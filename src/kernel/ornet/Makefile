# SPDX-License-Identifier: GPL-2.0
# ornet.ko — Kernel-Native AI Inference Module
# Revo OS v1.3.1
#
# Build:
#   make -C /lib/modules/$(uname -r)/build M=$(pwd) modules
#
# This Makefile follows the Linux kernel KBuild convention.
# The actual build is driven by the kernel's build system;
# this file only specifies which objects to link.

obj-m := ornet.o

ornet-y := ornet_main.o ornet_ring.o ornet_mmm.o

# Kernel module CFLAGS
ccflags-y := -Wall -Werror -O2

# Future: add llama.cpp static library
# ornet-y += ornet_llama_bridge.o
# ldflags-y += -L$(src)/llama.cpp/build -lllama -lggml

# Clean up generated files
clean:
	rm -f *.o *.ko *.mod.c *.mod.o Module.symvers modules.order
	rm -rf .tmp_versions
