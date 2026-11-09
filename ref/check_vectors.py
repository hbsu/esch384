#!/usr/bin/env python3
"""Independent check of the unit-test vectors, written from the spec's
pseudocode (not the C code): Alzette = Alg. 2.4 (spec p.8),
L8 = Alg. 2.7 (p.10), SPARKLE512 = Alg. 2.3 (p.7)."""
import sys, os
M = 0xFFFFFFFF
C = [0xB7E15162, 0xBF715880, 0x38B4DA56, 0x324E7738,
     0xBB1185EB, 0x4F7C7B57, 0xCFBFA1C8, 0xC2B3293D]
ror = lambda v, n: ((v >> n) | (v << (32 - n))) & M
rol = lambda v, n: ror(v, 32 - n) if n else v

def alzette(x, y, c):
    for r1, r2 in ((31, 24), (17, 17), (0, 31), (24, 16)):
        x = (x + ror(y, r1)) & M
        y ^= ror(x, r2)
        x ^= c
    return x, y

def L8(x, y):
    tx = x[0] ^ x[1] ^ x[2] ^ x[3]
    ty = y[0] ^ y[1] ^ y[2] ^ y[3]
    tx = rol(tx ^ ((tx << 16) & M), 16)
    ty = rol(ty ^ ((ty << 16) & M), 16)
    y = y[:4] + [y[4+i] ^ y[i] ^ tx for i in range(4)]
    x = x[:4] + [x[4+i] ^ x[i] ^ ty for i in range(4)]
    perm = [5, 6, 7, 4, 0, 1, 2, 3]
    return [x[p] for p in perm], [y[p] for p in perm]

def sparkle512(x, y, ns):
    x, y = list(x), list(y)
    for s in range(ns):
        y[0] ^= C[s % 8]; y[1] ^= s
        for i in range(8):
            x[i], y[i] = alzette(x[i], y[i], C[i])
        x, y = L8(x, y)
    return x, y

def split(words):          # x0 y0 x1 y1 ... -> x[], y[]
    return words[0::2], words[1::2]

d = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vectors")
ok = True
for line in open(os.path.join(d, "alzette.txt")):
    c, x, y, u, v = (int(t, 16) for t in line.split())
    ok &= alzette(x, y, c) == (u, v)
for name, fn in (("linear.txt", lambda x, y: L8(x, y)),
                 ("sparkle512_slim8.txt", lambda x, y: sparkle512(x, y, 8)),
                 ("sparkle512_big12.txt", lambda x, y: sparkle512(x, y, 12))):
    for line in open(os.path.join(d, name)):
        a, b = line.split("|")
        xi, yi = split([int(t, 16) for t in a.split()])
        xo, yo = split([int(t, 16) for t in b.split()])
        ok &= fn(xi, yi) == (xo, yo)
print("PASS: vectors match spec pseudocode" if ok else "FAIL: vector mismatch")
sys.exit(0 if ok else 1)
