# Results: Area vs. Speed

## Variant 1: shared Alzettes (parameter NALZ = 8, 4, 2, 1)

Branch `area/alzette-sharing`, starting from tag `v1-working`.

**Idea.** SPARKLE512 runs 8 Alzettes in parallel each step. With NALZ < 8
Alzettes, a step takes NSUB = 8/NALZ cycles. Each cycle the lowest NALZ
branches go through the Alzettes and the state shifts down by NALZ branches,
so after NSUB cycles all branches are done and back in place; the linear
layer runs in that last cycle. Only `rtl/sparkle512.sv` changes; its ports
stay the same, so the datapath and controller are untouched (they just pass
NALZ down).

**What to expect.**
- Area does not shrink 8x: the 512-bit state register (about 520 FFs), the
  linear layer, the injection logic and the shift/load selectors stay.
  Only the Alzettes (about 254 LUTs each) go away.
- The longest path is still one Alzette plus the linear layer (last cycle
  of each step), so Fmax should stay about the same.
- Cycles per block grow from 10 to 8*NSUB + 2: 18, 34, 66.

**How to run (Grendel).**

    scripts/area_sweep.sh            # all four: 8 4 2 1
    scripts/area_sweep.sh 1          # just one
    PERIOD=10 scripts/area_sweep.sh  # different clock target

Each variant must pass tb_sparkle512, tb_esch384 (custom KAT) and
tb_esch384 (official KAT) before its numbers count. The table is written to
`sim/area_sweep/results.md`; copy it below.

**Power note.** Power is Vivado's vectorless estimate (default switching
activity, no simulation data), so use it only to compare the variants with
each other. Energy per block = dynamic power x clock period x cycles per
block, which does not depend on the clock rate.

### Table (Artix-7 xc7a100tcsg324-1, out-of-context place and route)

(paste from sim/area_sweep/results.md)
