#!/usr/bin/env python3
"""Convert KAT files into simple vector files for tb/tb_esch384.sv.

Usage: python3 scripts/gen_kat_vectors.py
  ref/official/LWC_HASH_KAT_384.txt -> ref/vectors/kat_official.txt
  ref/kat/esch384_custom_kat.txt    -> ref/vectors/kat_custom.txt

File format (whitespace-separated tokens, one record per line):
  M <count> <length_bytes> <num_blocks>
      start of a message. <count> is the KAT "Count" value.
  B <bytes> <block>
      one input block, num_blocks of them in order (the last one is the
      final block). bytes = valid bytes 0..16. block = 32 hex chars =
      128-bit value, byte k at bits [8k+7:8k] (so the LAST 2 hex chars
      are the block's first message byte). Bytes >= <bytes> are filled
      with junk (0xA5 ^ k) to check that the hardware ignores them.
  D <md>
      expected 48-byte digest, 96 hex chars, digest byte 0 first.

Block split (same as ProcessMessage in ref/official/esch384v2_ref/hash.c,
`while (inlen > RATE_BYTES)`): 16-byte blocks; the final block holds the
remaining 1..16 bytes, so a message of exactly 16k bytes ends with a full
block (no extra padding block). The empty message is one block with 0 bytes.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JOBS = [
    ("ref/official/LWC_HASH_KAT_384.txt", "ref/vectors/kat_official.txt"),
    ("ref/kat/esch384_custom_kat.txt", "ref/vectors/kat_custom.txt"),
]


def parse_kat(path):
    out, cur = [], {}
    for line in open(path):
        if "=" not in line:
            continue
        k, v = (s.strip() for s in line.split("=", 1))
        cur[k] = v
        if k == "MD":
            out.append((int(cur["Count"]), bytes.fromhex(cur.get("Msg", "")),
                        cur["MD"].upper()))
            cur = {}
    return out


def split_blocks(msg):
    if len(msg) == 0:
        return [b""]
    blocks = []
    while len(msg) > 16:
        blocks.append(msg[:16])
        msg = msg[16:]
    blocks.append(msg)
    return blocks


def block_hex(blk):
    full = bytes(blk) + bytes((0xA5 ^ k) for k in range(len(blk), 16))
    return full[::-1].hex()   # byte 15 first = MSB first


def main():
    for src, dst in JOBS:
        kats = parse_kat(os.path.join(ROOT, src))
        lines = []
        for count, msg, md in kats:
            blocks = split_blocks(msg)
            lines.append(f"M {count} {len(msg)} {len(blocks)}")
            for b in blocks:
                lines.append(f"B {len(b)} {block_hex(b)}")
            lines.append(f"D {md}")
        with open(os.path.join(ROOT, dst), "w") as f:
            f.write("\n".join(lines) + "\n")
        print(f"{dst}: {len(kats)} messages")


if __name__ == "__main__":
    main()
