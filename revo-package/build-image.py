#!/usr/bin/env python3
"""Build Revo OS GPT disk image (partition table only, no filesystems)."""
import struct, os, uuid

BUILD = "/home/shaik/revo-build"
IMG = f"{BUILD}/revo-os-v1.1.img"
IMG_SIZE = 128 * 1024 * 1024  # 128 MB
SECTOR = 512

ESP_START = 2048
ESP_SECTORS = 64 * 1024 * 1024 // SECTOR
DATA_START = ESP_START + ESP_SECTORS
DATA_SECTORS = (IMG_SIZE // SECTOR) - DATA_START - 34

print(f"Creating {IMG_SIZE//1024//1024} MB image: {IMG}")
print(f"  ESP:  sector {ESP_START}, {ESP_SECTORS} sectors ({ESP_SECTORS*SECTOR//1024//1024} MB)")
print(f"  DATA: sector {DATA_START}, {DATA_SECTORS} sectors ({DATA_SECTORS*SECTOR//1024//1024} MB)")

# Create sparse file
with open(IMG, "wb") as f:
    f.seek(IMG_SIZE - 1)
    f.write(b'\0')

# Protective MBR
mbr = bytearray(SECTOR)
mbr[440:444] = b'REVO'
mbr[446:462] = struct.pack("<BBBBBBBBII",
    0x80, 0, 0, 0, 0xEF, 0, 0, 0,
    ESP_START, ESP_SECTORS)
mbr[510:512] = b'\x55\xAA'
with open(IMG, "r+b") as f:
    f.seek(0); f.write(mbr)

# GPT Header at LBA 1
gh = bytearray(SECTOR)
gh[0:8] = b"EFI PART"
gh[8:12] = struct.pack("<I", 0x00010000)
gh[12:16] = struct.pack("<I", 92)
gh[24:32] = struct.pack("<Q", 1)
gh[32:40] = struct.pack("<Q", IMG_SIZE // SECTOR - 1)
gh[40:48] = struct.pack("<Q", 34)
gh[48:56] = struct.pack("<Q", IMG_SIZE // SECTOR - 34)
gh[72:80] = struct.pack("<Q", 2)
gh[80:84] = struct.pack("<I", 4)
gh[84:88] = struct.pack("<I", 128)
with open(IMG, "r+b") as f:
    f.seek(SECTOR); f.write(gh)

# Partition entries at LBA 2
ESP_GUID = uuid.uuid4().bytes
DATA_GUID = uuid.uuid4().bytes
ESP_TYPE  = bytes.fromhex("28732AC11FF8D211BA4B00A0C93EC93B")
DATA_TYPE = bytes.fromhex("0FC63DAF848372478E793D69D8477DE4")

entries = bytearray(4 * 128)
# Entry 0: ESP
entries[0:16] = ESP_TYPE
entries[16:32] = ESP_GUID
entries[32:40] = struct.pack("<Q", ESP_START)
entries[40:48] = struct.pack("<Q", ESP_START + ESP_SECTORS - 1)
entries[56:128] = b"REVO_ESP\0" + b'\0' * (72 - 8)
# Entry 1: Data
entries[128:144] = DATA_TYPE
entries[144:160] = DATA_GUID
entries[160:168] = struct.pack("<Q", DATA_START)
entries[168:176] = struct.pack("<Q", DATA_START + DATA_SECTORS - 1)
entries[184:256] = b"REVO_DATA\0" + b'\0' * (72 - 9)

with open(IMG, "r+b") as f:
    f.seek(2 * SECTOR); f.write(entries)

# Backup GPT at end
with open(IMG, "r+b") as f:
    f.seek(IMG_SIZE - SECTOR); f.write(entries)
    # Backup header
    gh2 = bytearray(gh)
    gh2[24:32] = struct.pack("<Q", IMG_SIZE // SECTOR - 1)
    gh2[32:40] = struct.pack("<Q", 1)
    gh2[72:80] = struct.pack("<Q", IMG_SIZE // SECTOR - 33)
    f.seek(IMG_SIZE - 2 * SECTOR); f.write(gh2)

final_size = os.path.getsize(IMG)
print(f"Done. Image: {IMG} ({final_size//1024//1024} MB, {final_size} bytes)")
print("Next: run setup-usb.sh to format partitions and copy files.")
