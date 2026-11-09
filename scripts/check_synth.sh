#!/bin/bash
# Usage: scripts/check_synth.sh <module>
#   Synthesizes rtl/*.sv with <module> as top (Vivado, out-of-context, part
#   from syn/part.tcl). Runs in sim/synth_<module>/ (gitignored).
#   Fails (exit 1) on: synthesis errors, critical warnings, inferred latches,
#   or multi-driven nets. Prints LUT/FF counts on success.
#   This is only a "does it synthesize cleanly" check; real results are task 7.
set -u
source "$(dirname "$0")/env.sh"
[ $# -eq 1 ] || { echo "usage: $0 <module>"; exit 1; }
TOP="$1"
WORK="$REPO_ROOT/sim/synth_$TOP"
mkdir -p "$WORK" && cd "$WORK" || exit 1

vivado -mode batch -nojournal -log synth.log \
       -source "$REPO_ROOT/syn/check_synth.tcl" -tclargs "$REPO_ROOT" "$TOP" >/dev/null 2>&1
status=$?

fail=0
grep -E "^ERROR:" synth.log && fail=1
grep -E "^CRITICAL WARNING:" synth.log && fail=1
grep -iE "inferring latch|Synth 8-327" synth.log && fail=1
grep -iE "multi-driven|Synth 8-6859" synth.log && fail=1
[ $status -eq 0 ] || fail=1
[ -f "util_$TOP.rpt" ] || fail=1

if [ $fail -eq 0 ]; then
  luts=$(grep -m1 -E "^\| (Slice|CLB) LUTs" "util_$TOP.rpt" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
  ffs=$(grep -m1 -E "^\| (Slice|CLB) Registers" "util_$TOP.rpt" | awk -F'|' '{gsub(/ /,"",$3); print $3}')
  echo "SYNTH PASSED: $TOP  LUTs=$luts  FFs=$ffs  (log: sim/synth_$TOP/synth.log)"
  exit 0
fi
echo "SYNTH FAILED: $TOP  (see sim/synth_$TOP/synth.log)"
exit 1
