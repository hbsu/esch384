#!/bin/bash
# Usage: scripts/area_sweep.sh [nalz ...]        (default: 8 4 2 1)
#   For each number of Alzettes (NALZ):
#     1. tb_sparkle512, tb_esch384 (custom KAT) and tb_esch384 (official
#        KAT, 1025 messages) must all print TEST PASSED.
#     2. Out-of-context place-and-route of esch384 (syn/fmax_ooc.tcl):
#        LUTs, FFs, Fmax, vectorless power.
#   Then prints a results table (markdown) and writes it to
#   sim/area_sweep/results.md and sim/area_sweep/results.csv.
#   PERIOD=<ns> sets the clock target for place-and-route (default 5.0).
#
# Derived columns (NSUB = 8/NALZ cycles per step):
#   cyc/blk    = 8*NSUB + 2       cycles per 16-byte block, long messages
#   cyc/hash1  = 28*NSUB + 6      cycles for a one-block message
#   Mbps       = 128 * Fmax / cyc/blk
#   nJ/blk     = dynamic power * clock period * cyc/blk  (energy per block;
#                does not depend on the clock rate)
#   Mbps/kLUT  = throughput per 1000 LUTs (higher = more efficient)
set -u
source "$(dirname "$0")/env.sh"
LIST=("$@"); [ ${#LIST[@]} -gt 0 ] || LIST=(8 4 2 1)
PERIOD="${PERIOD:-5.0}"
OUT="$REPO_ROOT/sim/area_sweep"
mkdir -p "$OUT"
CSV="$OUT/results.csv"
echo "nalz,tests,luts,ffs,fmax_mhz,cyc_blk,cyc_hash1,mbps,dyn_w,static_w,nj_blk,mbps_per_klut" > "$CSV"

for N in "${LIST[@]}"; do
  echo "=== NALZ=$N: simulation ==="
  tests=PASS
  NALZ=$N "$REPO_ROOT/scripts/run_sim.sh" tb_sparkle512 >/dev/null 2>&1 \
    && echo "  PASS tb_sparkle512" || { echo "  FAIL tb_sparkle512"; tests=FAIL; }
  NALZ=$N "$REPO_ROOT/scripts/run_sim.sh" tb_esch384 >/dev/null 2>&1 \
    && echo "  PASS tb_esch384 (custom KAT)" || { echo "  FAIL tb_esch384 (custom KAT)"; tests=FAIL; }
  NALZ=$N "$REPO_ROOT/scripts/run_sim.sh" tb_esch384 \
      "KAT=$REPO_ROOT/ref/official/LWC_HASH_KAT_384.txt" >/dev/null 2>&1 \
    && echo "  PASS tb_esch384 (official KAT)" || { echo "  FAIL tb_esch384 (official KAT)"; tests=FAIL; }
  # the last run's log is the official KAT one
  grep -h "TEST " "$REPO_ROOT/sim/tb_esch384_nalz$N/xsim.log" 2>/dev/null | tail -1 | sed 's/^/  /'

  echo "=== NALZ=$N: place and route (period $PERIOD ns) ==="
  W="$OUT/impl_nalz$N"
  mkdir -p "$W"
  ( cd "$W" && vivado -mode batch -nojournal -log impl.log \
      -source "$REPO_ROOT/syn/fmax_ooc.tcl" \
      -tclargs "$REPO_ROOT" esch384 "$PERIOD" "$N" >/dev/null 2>&1 )
  if grep -iqE "inferring latch|Synth 8-327" "$W/impl.log"; then
    echo "  WARNING: latch inferred, see $W/impl.log"; tests=FAIL
  fi
  R=$(grep -m1 "^RESULT" "$W/impl.log")
  if [ -z "$R" ]; then
    echo "  FAIL: no RESULT line, see $W/impl.log"
    echo "$N,$tests,,,,,,,,,," >> "$CSV"
    continue
  fi
  echo "  $R"
  get() { echo "$R" | tr ' ' '\n' | sed -n "s/^$1=//p"; }
  luts=$(get luts); ffs=$(get ffs); fmax=$(get fmax_mhz)
  dyn=$(get dyn_w); stat=$(get static_w)
  awk -v n="$N" -v t="$tests" -v l="$luts" -v f="$ffs" -v fm="$fmax" \
      -v d="$dyn" -v s="$stat" -v p="$PERIOD" 'BEGIN {
    nsub = 8 / n; cb = 8 * nsub + 2; ch = 28 * nsub + 6
    mbps = 128 * fm / cb; nj = d * p * cb; eff = mbps / (l / 1000)
    printf "%d,%s,%d,%d,%.1f,%d,%d,%.1f,%.3f,%.3f,%.2f,%.1f\n",
           n, t, l, f, fm, cb, ch, mbps, d, s, nj, eff }' >> "$CSV"
done

# Markdown table
{
  echo "| NALZ | Tests | LUTs | FFs | Fmax (MHz) | Cycles/block | Cycles (1-block hash) | Throughput (Mbps) | Dynamic (W) | Static (W) | Energy/block (nJ) | Mbps per kLUT |"
  echo "|---|---|---|---|---|---|---|---|---|---|---|---|"
  tail -n +2 "$CSV" | awk -F, '{ printf "| %s |", $1; for (i = 2; i <= NF; i++) printf " %s |", $i; printf "\n" }'
} > "$OUT/results.md"
echo
cat "$OUT/results.md"
echo
echo "Saved: $OUT/results.md and $OUT/results.csv"
