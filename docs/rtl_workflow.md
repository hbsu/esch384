# RTL Workflow

How to complete each RTL task in this repo, from spec to commit.
Tasks 1–3 (Alzette, linear layer, SPARKLE512) followed this exact flow;
use them as examples.

## 0. One-time setup (Grendel)

    git clone https://github.com/hbsu/esch384.git && cd esch384
    python3 -m venv .venv && .venv/bin/pip install python-pptx graphviz matplotlib
    source scripts/env.sh          # loads Vivado/xsim 2026.1 + the venv
    cd ref && make check && cd ..  # reference model: all lines must say PASS

## 1. The flow for every task

| # | Step | Done when |
|---|------|-----------|
| 1 | **Read the spec** for your piece: `docs/architecture.md` (parameters, page refs) and `docs/spec/sparkle-spec-final.pdf`. | You can write the behavior down in a few lines. |
| 2 | **Fix the interface first**: port names, widths, latency, handshake. Write it in the module header comment before any logic. | Header has purpose, ports, latency in cycles. |
| 3 | **Write the RTL** in `rtl/<module>.sv` (style rules below). | Compiles: `xvlog -sv rtl/<module>.sv` with no warnings. |
| 4 | **Get expected values** from the reference model (`ref/`, section 3). Never hand-compute them. | You have a vector file or trace to compare against. |
| 5 | **Write a self-checking testbench** `tb/tb_<module>.sv` (rules below). | It prints `TEST PASSED (N/N)` or `TEST FAILED (...)`. |
| 6 | **Run it**: `scripts/run_sim.sh tb_<module>`. Check the exit code (0 = pass). | `TEST PASSED`, exit 0. |
| 7 | **Prove the test can fail**: copy the RTL somewhere outside the repo, add one small bug (wrong constant, off-by-one count), run the TB on the copy. | The broken copy gives `TEST FAILED`. |
| 8 | **Re-run all older tests** (section 4). | Every TB still passes. |
| 9 | **Check it synthesizes**: `scripts/check_synth.sh <module>`. | `SYNTH PASSED`, no latches, no critical warnings. Note LUT/FF counts. |
| 10 | **Log it**: add a row to `docs/task_log.md` (task, owner, status, test result, date) and, if AI helped, to `docs/ai_log.md`. | Both logs updated. |
| 11 | **Commit** with a clear message, e.g. `Phase 3 task 4: datapath + tb (N/N pass)`. Push. | On GitHub. |

**Don't start the next task until the current one passes steps 6–9.**

## 2. Coding rules

### RTL (`rtl/`)
- SystemVerilog kept close to Verilog-2001.
- Allowed: `logic`, `always_ff`, `always_comb`, `assign`, `localparam`, `parameter`, `generate`/`genvar`.
- Not allowed: interfaces, packages, structs, classes, `unique`/`priority`, assertions, `initial` blocks, `#` delays.
- One module per file, file name = module name, `.sv`.
- Synchronous, active-high reset (`if (rst)` inside `always_ff @(posedge clk)`).
- In `always_comb`, assign every output on every path (otherwise you get a latch; `check_synth.sh` will fail).
- Header comment: purpose, ports, latency in cycles.

### Testbenches (`tb/`)
- Module name `tb_<module>`, file `tb/tb_<module>.sv`.
- Self-checking: compare against reference values, count errors.
- Last line printed must be exactly `TEST PASSED (N/N)` or `TEST FAILED (...)`, then `$finish`.
- Treat "0 vectors read" as a failure.
- Vector files: read path from `+VEC=<file>`, otherwise `<VEC_DIR>/<name>.txt`
  (`run_sim.sh` always passes `VEC_DIR=<repo>/ref/vectors`). See `tb/tb_sparkle_linear.sv`.
- On mismatch, print which vector, which word, expected and got.
- **xsim gotcha:** passing `cond ? "a" : "b"` straight into a task crashes xsim. Put the string in a variable first.

## 3. Reference model: where expected values come from

Build once: `cd ref && make`. Tool: `sim/ref_build/esch_tool`.

| Command | Gives you |
|---------|-----------|
| `esch_tool hash <hexmsg>` | 48-byte digest (use `""` for empty message) |
| `esch_tool debug <hexmsg>` | State after every injection and every step, then the digest |
| `esch_tool alzette/linear <count> <seed>` | Unit vectors (already in `ref/vectors/`) |
| `esch_tool sparkle <steps> <count> <seed>` | Permutation vectors |

KAT files (format `Count / Msg / MD`):
- `ref/official/LWC_HASH_KAT_384.txt`: official, 1025 messages, 0–1024 bytes
- `ref/kat/esch384_custom_kat.txt`: ours, 34 messages around block edges, 3 data patterns

Compare a KAT file your testbench writes against the expected one:

    python3 scripts/compare_kat.py ref/official/LWC_HASH_KAT_384.txt sim/<tb>/out_kat.txt

### Debug trace format
    TRACE <tag> x0 y0 x1 y1 x2 y2 x3 y3 x4 y4 x5 y5 x6 y6 x7 y7

Tags, in order: `init`, `b0.inj` (after injecting block 0), `b0.s0` … `b0.s7`
(after each step), `b1.inj`, …, final block `bN.s0` … `bN.s11`, then
squeezes `sq1.s0` … `sq1.s7`, `sq2.s0` … `sq2.s7`.

## 4. Regression: re-run everything

    for t in tb_alzette tb_sparkle_linear tb_sparkle512; do   # add new TBs here
      scripts/run_sim.sh $t > /dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"
    done
    (cd ref && make check)

## 5. Debugging a mismatch

1. Pick the smallest failing message (e.g. empty, or 1 byte).
2. `sim/ref_build/esch_tool debug <hexmsg> > sim/ref_trace.txt`
3. Make your testbench print the state in the same `TRACE <tag> ...` format at
   the same points (after each injection, after each step).
4. `diff sim/ref_trace.txt sim/<tb>/hw_trace.txt | head`: the **first** differing line is where the bug is.
   - Differs at `.inj`: injection, padding, ConstM, or byte order.
   - Differs at `.s0`: step constant or wrong step index.
   - Right values but wrong tags/count: controller step counts or ordering.
   - All trace lines match but the digest is wrong: output select or byte order.
5. Fix, then re-run **all** tests (section 4).

## 6. Building blocks already done (don't change their ports)

| Module | Ports | Latency |
|--------|-------|---------|
| `alzette` | `x_in, y_in, c [31:0]` → `x_out, y_out [31:0]` | 0 (combinational) |
| `sparkle_linear` | `state_in [511:0]` → `state_out [511:0]` | 0 |
| `sparkle_step` | `state_in [511:0], step_idx [3:0]` → `state_out [511:0]` | 0 |
| `sparkle512` | `clk, rst, start, big, state_in` → `state_out, busy, done` | 9 cycles (slim), 13 (big) |

**State bus convention (everywhere):** 16 words of 32 bits, word k at bits
`[32k+31:32k]`, order x0 y0 x1 y1 … x7 y7. So x_i = word 2i, y_i = word 2i+1.

**Byte order:** little-endian. Message byte 0 → bits 7:0 of word 0 (x0).

## 7. Remaining RTL tasks (Phase 3)

### Task 4: Datapath (owner: Nick)
**Goal:** state register + message injection + output select. Reuse `sparkle_step`
for the permutation (your own state register and step counter, or reuse `sparkle512`).

What it must do (details: `docs/architecture.md`, section 1):
- **Padding** (last block < 16 bytes): append byte `0x80`, then zeros.
- **Injection** of block words m0..m3, with `l(t) = rotl16(t ^ (t << 16))`:

      tx = l(m0 ^ m2)        ty = l(m1 ^ m3)
      x0 ^= m0 ^ ty          y0 ^= m1 ^ tx
      x1 ^= m2 ^ ty          y1 ^= m3 ^ tx
      x2 ^= ty               y2 ^= tx
      x3 ^= ty               y3 ^= tx

- **ConstM** on the final block only: `y3 ^= 0x01000000` if padded, `0x02000000` if full (16 bytes).
- **Output select:** digest chunk = x0 y0 x1 y1 (128 bits), little-endian bytes.

**Test idea:** start from the zero state, inject one block, compare with the
`b0.inj` line from `esch_tool debug <msg>`. Cover 0, 1, 15, 16 bytes
(padded vs. full) and a non-final block (use a 17+ byte message).

### Task 5: Controller FSM (owner: Nick)
**Goal:** run the sequence and the valid/ready handshake.

Sequence for n blocks (n = 1 for the empty message):

    reset state to 0
    blocks 0..n-2:  inject → 8 steps
    block n-1:      pad if short, ConstM, inject → 12 steps
    output D0 → 8 steps → output D1 → 8 steps → output D2

Total permutation steps = 8n + 20 (28 for a one-block message).

**Handshake:** a block is accepted only when `valid && ready` are both high in
the same cycle. The input side must say which block is last and how many bytes
(1–16) it holds. Design the exact ports yourself, and write them, plus an FSM
state/transition table, in `docs/architecture.md` section 3.

**Test idea:** check the order and count of steps per phase (8/12/8/8) and that
`ready`/`valid` behave (no block lost or double-counted, including when the
sender stalls). Full hash correctness is checked in task 6.

### Task 6: Top level + full KAT testbench (owner: Nick)
**Goal:** `rtl/esch384.sv` (datapath + controller), `tb/tb_esch384.sv`.
- The TB feeds every message from both KAT files, collects the 48-byte digest,
  and writes a KAT-format file, or compares directly.
- **Pass:** all 1025 official + 34 custom KATs match.
- Also print the cycle count per message and check it matches the expected latency.
- Add the per-step `TRACE` print (can be switched with a plusarg) for debugging (section 5).
- Run `scripts/check_synth.sh esch384`.
- When it passes, Phase 3 RTL is done → tag `v1-working` (Phase 4 starts from this tag).

### Task 7: Synthesis/implementation (owner: Henry)
Vivado non-project TCL in `syn/`, part from `syn/part.tcl`. Report LUTs, FFs,
Fmax, latency, throughput.

## 8. Checklist before you commit

- [ ] Header comment: purpose, ports, latency
- [ ] `TEST PASSED` and exit 0
- [ ] A deliberately broken copy fails
- [ ] All older testbenches still pass
- [ ] `check_synth.sh` passes (no latches)
- [ ] `docs/task_log.md` and `docs/ai_log.md` updated
- [ ] Clear commit message, pushed
