#!/usr/bin/env python3
"""Revo OS v1.1 — dm-verity Hash Tree Generator

Generates a Merkle hash tree for the root filesystem image
and outputs the root hash + hash tree file for dm-verity.

Usage:
  python3 generate-verity.py <data_image> <hash_output>
  python3 generate-verity.py revo-data.img verity.hash

Outputs:
  - verity.hash: the hash tree file (for dm-verity)
  - Prints root hash to stdout (for embedding in kernel cmdline)
"""

import hashlib
import os
import struct
import sys

# Config
HASH_ALG = 'sha256'
DATA_BLOCK_SIZE = 4096  # 4 KB data blocks
HASH_BLOCK_SIZE = 4096  # 4 KB hash blocks
SALT = b'RevoOS-dm-verity-v1.1'  # Fixed salt for reproducibility


def compute_verity(data_path: str, hash_path: str) -> str:
    """Build Merkle hash tree and return root hash hex string."""
    file_size = os.path.getsize(data_path)
    data_blocks = (file_size + DATA_BLOCK_SIZE - 1) // DATA_BLOCK_SIZE

    # Level 0: hash of each data block
    level_hashes = []
    with open(data_path, 'rb') as f:
        for i in range(data_blocks):
            block = f.read(DATA_BLOCK_SIZE)
            h = hashlib.new(HASH_ALG, SALT + block).digest()
            level_hashes.append(h)

    # Build Merkle tree levels
    while len(level_hashes) > 1:
        next_level = []
        for i in range(0, len(level_hashes), 2):
            left = level_hashes[i]
            right = level_hashes[i + 1] if i + 1 < len(level_hashes) else left
            h = hashlib.new(HASH_ALG, SALT + left + right).digest()
            next_level.append(h)
        level_hashes = next_level

    root_hash = level_hashes[0] if level_hashes else b'\x00' * 32
    root_hex = root_hash.hex()

    # Write hash tree (all leaf hashes concatenated, padded to block boundary)
    with open(hash_path, 'wb') as f:
        # Level 0 leaf hashes
        with open(data_path, 'rb') as df:
            for i in range(data_blocks):
                block = df.read(DATA_BLOCK_SIZE)
                h = hashlib.new(HASH_ALG, SALT + block).digest()
                f.write(h)
        # Pad to block boundary
        remainder = f.tell() % HASH_BLOCK_SIZE
        if remainder:
            f.write(b'\x00' * (HASH_BLOCK_SIZE - remainder))

    return root_hex


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <data_image> <hash_output>")
        print(f"Example: {sys.argv[0]} revo-data.img verity.hash")
        sys.exit(1)

    data_img = sys.argv[1]
    hash_out = sys.argv[2]

    if not os.path.exists(data_img):
        print(f"ERROR: Data image not found: {data_img}")
        sys.exit(1)

    print(f"Data image: {data_img} ({os.path.getsize(data_img)} bytes)")
    print(f"Hash algorithm: {HASH_ALG}")
    print(f"Data block size: {DATA_BLOCK_SIZE} bytes")

    root_hash = compute_verity(data_img, hash_out)

    hash_size = os.path.getsize(hash_out)
    print(f"Hash tree: {hash_out} ({hash_size} bytes)")
    print(f"\nROOT_HASH={root_hash}")
