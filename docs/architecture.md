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

### 3.1 Controller `esch_ctrl` (rtl/esch_ctrl.sv)

Block data and byte count go straight from the input bus to the datapath.
The controller only makes the control signals.

| Port | Dir | Width | Meaning |
|------|-----|-------|---------|
| clk, rst | in | 1 | clock; sync active-high reset -> WAIT |
| in_valid | in | 1 | sender has a block on the bus |
| in_ready | out | 1 | 1 only in WAIT; block accepted when in_valid && in_ready |
| in_last | in | 1 | this block is the final one |
| in_bytes | in | 5 | bytes in the block, 0..16 (0 only for empty message); used by the datapath, not the FSM |
| out_valid | out | 1 | 1 only in OUT: datapath digest_chunk holds D0/D1/D2 |
| out_ready | in | 1 | receiver takes the chunk when out_valid && out_ready |
| out_last | out | 1 | 1 with out_valid on D2 |
| dp_clear | out | 1 | 1 on the cycle D2 is accepted (state <- 0) |
| dp_inject | out | 1 | = in_valid && in_ready |
| dp_step_en | out | 1 | 1 in ABS and SQZ |
| dp_step_idx | out | 4 | step number (0..7 slim, 0..11 big) |
| dp_msg_last | out | 1 | = in_last (used with dp_inject) |
| busy | out | 1 | 1 from the cycle after the first block is accepted until the D2 accept cycle |

Registers: `state` (2 bits), step counter `cnt` (4), `big` (final block
absorbing), `chunk` (0..2), `in_msg` (between blocks of a message).

### 3.2 FSM states and transitions

| State | Outputs | Condition | Next | Register updates |
|-------|---------|-----------|------|------------------|
| WAIT | in_ready=1; dp_inject=in_valid | in_valid=0 | WAIT | - |
| WAIT | | in_valid=1 | ABS | cnt<=0, big<=in_last, in_msg<=!in_last |
| ABS | dp_step_en=1, idx=cnt | cnt < last (7, or 11 if big) | ABS | cnt++ |
| ABS | | cnt = last, big=0 | WAIT | cnt<=0 |
| ABS | | cnt = last, big=1 | OUT | cnt<=0 (chunk=0) |
| OUT | out_valid=1, out_last=(chunk=2) | out_ready=0 | OUT | hold |
| OUT | | out_ready=1, chunk<2 | SQZ | chunk++, cnt<=0 |
| OUT | dp_clear=1 | out_ready=1, chunk=2 | WAIT | chunk<=0 |
| SQZ | dp_step_en=1, idx=cnt | cnt < 7 | SQZ | cnt++ |
| SQZ | | cnt = 7 | OUT | cnt<=0 |

All outputs not listed are 0. busy = (state != WAIT) || in_msg.

### 3.3 Latency

n blocks, no stalls, counted from the cycle the first block is accepted
(cycle 1) to the cycle D2 is accepted:

    9(n-1) + 13 + (1 + 8 + 1 + 8 + 1) = 9n + 23 cycles

Each non-final block costs 1 accept cycle + 8 steps. Steps = 8n + 20.
The next message's first block can be accepted the cycle after D2.

### 3.4 Cycle-by-cycle example: 1-block message (n = 1, no stalls)

| Cycle | State | in_ready | dp_inject | dp_step_en / idx | out_valid | Notes |
|-------|-------|----------|-----------|------------------|-----------|-------|
| 1 | WAIT | 1 | 1 | 0 | 0 | block accepted, injected at end of cycle |
| 2..13 | ABS | 0 | 0 | 1 / 0..11 | 0 | 12 big steps |
| 14 | OUT | 0 | 0 | 0 | 1 | D0 accepted |
| 15..22 | SQZ | 0 | 0 | 1 / 0..7 | 0 | 8 slim steps |
| 23 | OUT | 0 | 0 | 0 | 1 | D1 accepted |
| 24..31 | SQZ | 0 | 0 | 1 / 0..7 | 0 | 8 slim steps |
| 32 | OUT | 0 | 0 | 0 | 1 | D2 accepted, out_last=1, dp_clear=1 |
| 33 | WAIT | 1 | | 0 | 0 | ready for next message |
