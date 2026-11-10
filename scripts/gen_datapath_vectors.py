#!/usr/bin/env python3
"""Generate ref/vectors/datapath.txt for tb/tb_esch_datapath.sv.

Runs `sim/ref_build/esch_tool debug <hexmsg>` for each test message and
writes the per-block inputs and the expected state after every injection
and every step. Usage: python3 scripts/gen_datapath_vectors.py

File format (whitespace-separated tokens, one record per line):
  M <msg_index> <length_bytes> <num_blocks>
      start of a message (TB clears the state)
  B <msg_bytes> <msg_last> <msg_block>
      one input block. msg_bytes = valid bytes (0..16), msg_last = 0/1,
      msg_block = 32 hex chars = 128-bit value, byte k at bits [8k+7:8k]
      (so the last 2 hex chars are message byte 0). Bytes >= msg_bytes
      are filled with junk (0xA5 ^ k) to test that the RTL masks them.
  S <tag> <w0> ... <w15>
      expected state (16 hex words, x0 y0 ... x7 y7) after an action.
      Order per block: <b>.inj, then <b>.s0 .. s7 (s11 for the final block).
      After the final block: sq1.s0 .. sq1.s7, sq2.s0 .. sq2.s7.
  D <digest>
      expected 48-byte digest, 96 hex chars, byte 0 first.
"""
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "sim", "ref_build", "esch_tool")
OUT = os.path.join(ROOT, "ref", "vectors", "datapath.txt")

LENGTHS = [0, 1, 15, 16, 17, 31, 32, 33, 48]
PATTERNS = {
    "inc": lambda i: i & 0xFF,
    "ff": lambda i: 0xFF,
    "mix": lambda i: (i * 37 + 11) & 0xFF,
}


def trace(msg):
    r = subprocess.run([TOOL, "debug", msg.hex()], capture_output=True,
                       text=True)
    if r.returncode != 0:
        sys.exit("esch_tool debug failed for %s:\n%s" % (msg.hex(), r.stdout))
    states, digest = [], None
    for line in r.stdout.splitlines():
        f = line.split()
        if f and f[0] == "TRACE":
            states.append((f[1], f[2:]))
        elif f and f[0] == "DIGEST":
            digest = f[1].lower()
    assert len(states[0][1]) == 16 and states[0][0] == "init"
    return dict(states), [t for t, _ in states], digest


def main():
    if not os.path.exists(TOOL):
        subprocess.run(["make", "-C", os.path.join(ROOT, "ref")], check=True)
    out = []
    idx = 0
    for pname, pat in PATTERNS.items():
        for L in LENGTHS:
            msg = bytes(pat(i) for i in range(L))
            st, order, digest = trace(msg)
            nblk = max(1, (L + 15) // 16)
            out.append("M %d %d %d" % (idx, L, nblk))
            expect = []
            for b in range(nblk):
                last = b == nblk - 1
                chunk = msg[16 * b:16 * b + 16]
                n = len(chunk)
                blk = bytearray((0xA5 ^ k) for k in range(16))
                blk[:n] = chunk
                val = int.from_bytes(bytes(blk), "little")
                out.append("B %d %d %032x" % (n, int(last), val))
                tags = ["b%d.inj" % b] + ["b%d.s%d" % (b, s)
                                          for s in range(12 if last else 8)]
                for t in tags:
                    out.append("S %s %s" % (t, " ".join(st[t])))
                expect += tags
            sq = ["sq%d.s%d" % (q, s) for q in (1, 2) for s in range(8)]
            for t in sq:
                out.append("S %s %s" % (t, " ".join(st[t])))
            expect += sq
            if order[1:] != expect:
                sys.exit("unexpected trace tag order for msg %d" % idx)
            out.append("D %s" % digest)
            idx += 1
    with open(OUT, "w") as f:
        f.write("\n".join(out) + "\n")
    print("wrote %s (%d messages)" % (OUT, idx))


if __name__ == "__main__":
    main()
