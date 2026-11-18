# Esch384 Architecture

## 1. Algorithm parameters (confirmed from the spec)

Spec: `docs/spec/sparkle-spec-final.pdf` (SPARKLE Round 3 / final-round
spec, same file as `Documents/` in the NIST submission zip).
Page numbers below are the **printed** page numbers (PDF page = printed + 4).

The official C code (`ref/official/esch384v2_ref/`) agrees with every item
below, and reproduces all 1025 official KATs.

| Item | Value | Spec reference |
|------|-------|----------------|
| Permutation | SPARKLE512: 8 branches, each (x_i, y_i) = 2 x 32-bit words, 512-bit state | Alg. 2.3, p.7 |
| Steps, slim | 8 (absorbing non-final blocks, and squeezing) | Table 2.1, p.8; Alg. 2.10, p.12 |
| Steps, big | 12 (after the final message block) | Table 2.1, p.8; Alg. 2.10, p.12 |
| Step constant | before each step s: y0 ^= c[s mod 8], y1 ^= s | Alg. 2.3, p.7 |
| Branch constants c0..c7 | B7E15162 BF715880 38B4DA56 324E7738 BB1185EB 4F7C7B57 CFBFA1C8 C2B3293D | Alg. 2.3, p.7 |
| Alzette (ARX-box) | 4 rounds, rotations (31,24) (17,17) (0,31) (24,16), XOR c into x after each round | Alg. 2.4, p.8 |
| Linear layer L8 | Feistel with l(t) = rotl16(t ^ (t<<16)); then branch permutation (5,6,7,4,0,1,2,3) | Def. 2.1.2, p.9; Alg. 2.7, p.10 |
| Rate r | 128 bits (16 bytes) per message block | Sec. 2.2.2, p.11; Table 2.2, p.10 |
| Capacity c | 384 bits | Table 2.2, p.10 |
| Padding | only if last block < 16 bytes: append 0x80 then zeros ("10*") | Alg. 2.8, p.11 |
| Empty message | treated as one padded block (0x80 00 .. 00) | Alg. 2.10, p.12 |
| Message injection | block P (4 words) -> M4(P ‖ 0^128) -> XOR into left 4 branches | Alg. 2.10, p.12; Sec. 2.2.2, p.11 |
| Final-block constant ConstM | padded: 1<<256 ; full: 2<<256. In words: y3 ^= 0x01000000 (M1) or 0x02000000 (M2) | Alg. 2.10, p.12; Fig. 2.4, p.12 |
| Digest | 384 bits = 3 x 128-bit squeezes of (x0,y0,x1,y1), slim permutation between them | Alg. 2.10, p.12 |
| Byte order | little-endian: message byte 0 = bits 7:0 of word x0 | Sec. 2, p.6 |
| State word order | x0 y0 x1 y1 ... x7 y7 | Sec. 2.1, p.6 |

### Message injection, written out
For block words m0..m3 (after padding):

    tx = l(m0 ^ m2)        ty = l(m1 ^ m3)
    x0 ^= m0 ^ ty          y0 ^= m1 ^ tx
    x1 ^= m2 ^ ty          y1 ^= m3 ^ tx
    x2 ^= ty               y2 ^= tx
    x3 ^= ty               y3 ^= tx

On the final block, ConstM is XORed into y3 too (directly, not through M4).

### Hash flow

    S = 0
    for each non-final block:  inject; SPARKLE512 slim (8 steps)
    final block:               pad if short; y3 ^= ConstM; inject; SPARKLE512 big (12 steps)
    D0 = x0 y0 x1 y1
    SPARKLE512 slim; D1 = x0 y0 x1 y1
    SPARKLE512 slim; D2 = x0 y0 x1 y1
    digest = D0 ‖ D1 ‖ D2   (each word output as 4 bytes, little-endian)

### Step count for one hash (one step per cycle design)
For a message of L bytes, with n = max(1, ceil(L/16)) blocks:
steps = 8*(n-1) + 12 + 8 + 8 = 8n + 20.

## 2. Reference model

See `ref/README.md`.

## 3. Datapath, controller, timing

### Module tree

    esch384              top level: wires the two blocks below together
      esch384_ctrl       FSM: when to inject, when to squeeze, handshake
      esch384_datapath   state path
        esch_inject      pad + XOR one block (and ConstM) into the state
        sparkle512       the permutation, one step per cycle
          sparkle_step   one step (Alzette x8 + linear layer)

The state register lives inside `sparkle512`; the datapath feeds it either a
freshly injected state (`do_inject`) or its own output (`do_squeeze`), and
`first` forces a zero state at the start of a new message.

### Top-level ports (`rtl/esch384.sv`)

| Port | Dir | Width | Meaning |
|------|-----|-------|---------|
| `clk`, `rst` | in | 1 | clock, synchronous active-high reset |
| `blk_data` | in | 128 | message block, byte i at bits [8i+7:8i] |
| `blk_bytes` | in | 5 | valid bytes 0-16; only read on the last block |
| `in_last` | in | 1 | this is the last block of the message |
| `in_valid` | in | 1 | sender has a block ready |
| `in_ready` | out | 1 | core takes a block this cycle |
| `digest_chunk` | out | 128 | D0, D1, or D2, bytes little-endian |
| `out_valid` | out | 1 | a digest chunk is on `digest_chunk` now |
| `out_ready` | in | 1 | receiver takes the chunk this cycle |

A block moves only when `in_valid` and `in_ready` are both high at a rising
edge; a chunk moves only when `out_valid` and `out_ready` are both high.
The empty message is one block with `blk_bytes = 0` and `in_last = 1`.
After D2 is taken the core returns to its start state by itself, so
back-to-back messages need no reset.

### Controller FSM (`rtl/esch384_ctrl.sv`)

| State | Meaning | Outputs high | Next state |
|-------|---------|--------------|------------|
| `S_ABSORB` | waiting for a block | `in_ready`; `do_inject` when `in_valid` | `S_PERM_A` when `in_valid`, else stay |
| `S_PERM_A` | permuting after a block | - | `S_OUT` when `perm_done` and the block was last; `S_ABSORB` when `perm_done` otherwise; else stay |
| `S_OUT` | a digest chunk is showing | `out_valid`; `do_squeeze` when `out_ready` and chunk < 2 | `S_PERM_S` when `out_ready` and chunk < 2; `S_ABSORB` when `out_ready` and chunk = 2; else stay |
| `S_PERM_S` | permuting between chunks | - | `S_OUT` when `perm_done`, else stay |

Registers: `first_r` (1 after reset and after D2, cleared when a block is
taken), `last_seen` (the `in_last` of the block being permuted), `chunk`
(0, 1, 2 - which digest chunk is showing).

The permutation is big (12 steps) only when a block is injected with
`in_last` high; every other permutation is slim (8 steps), which gives the
8n + 20 steps the spec asks for.

### Timing, one-block message (empty message, measured)

`sparkle512` reports `done` 9 cycles after the start cycle for a slim
permutation and 13 for a big one. Cycle 0 is the cycle the block is taken.

| Cycle | State | What happens |
|-------|-------|--------------|
| 0 | `S_ABSORB` | block taken (`in_valid` and `in_ready`), `do_inject`, injected state loaded |
| 1-12 | `S_PERM_A` | the 12 big steps |
| 13 | `S_PERM_A` | `perm_done` |
| 14 | `S_OUT` | D0 on `digest_chunk`; taken here, `do_squeeze` |
| 15-22 | `S_PERM_S` | 8 slim steps |
| 23 | `S_PERM_S` | `perm_done` |
| 24 | `S_OUT` | D1 taken, `do_squeeze` |
| 25-33 | `S_PERM_S` | 8 slim steps, `perm_done` in 33 |
| 34 | `S_OUT` | D2 taken, back to `S_ABSORB` |

So with a sender and receiver that never stall, an n-block message takes
**10n + 24 cycles** (34 for one block): 10 cycles per absorbed block, 4 extra
for the bigger final permutation, and 20 for the two squeeze permutations
plus the three output cycles. `tb_esch384` checks this number on every
message it runs without stalls.

### Verification

`tb/tb_esch384.sv` feeds every message of a KAT file through the core 16
bytes at a time and compares the 48-byte digest.

| Check | Result |
|-------|--------|
| `ref/official/LWC_HASH_KAT_384.txt` (0-1024 bytes) | 1025/1025 |
| `ref/kat/esch384_custom_kat.txt` (block edges, 3 patterns) | 34/34 |
| Cycle count against 10n + 24 | every no-stall message |
| Handshake: slow sender, slow receiver, chunk held under backpressure | every message (stall pattern varies per record) |
| Per-step `TRACE` output vs. `esch_tool debug` | identical, empty and 2-block messages |

Mutation check (a deliberately broken copy must fail): wrong ConstM for a
full final block 12/34 fail, final block permuted slim 34/34 fail, injection
dropping `ty` from x2 24/34 fail, digest read from the capacity 34/34 fail.
