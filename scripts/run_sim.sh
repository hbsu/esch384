#!/bin/bash
# Usage: scripts/run_sim.sh <tb_name> [extra plusargs...]
#   Compiles rtl/*.sv + tb/<tb_name>.sv with xvlog, elaborates with xelab,
#   runs xsim in sim/<tb_name>/ (log: sim/<tb_name>/xsim.log).
#   Always passes VEC_DIR=$REPO_ROOT/ref/vectors; TBs use it unless +VEC= given.
#   Extra args are plusargs without '+', e.g. VEC=/path/file.txt
#   Exit 0 only if the log contains "TEST PASSED".
set -u
source "$(dirname "$0")/env.sh"
[ $# -ge 1 ] || { echo "usage: $0 <tb_name> [plusargs...]"; exit 1; }
TB="$1"; shift
TBFILE="$REPO_ROOT/tb/$TB.sv"
[ -f "$TBFILE" ] || { echo "no such testbench: $TBFILE"; exit 1; }

WORK="$REPO_ROOT/sim/$TB"
mkdir -p "$WORK" && cd "$WORK" || exit 1

PLUS=(-testplusarg "VEC_DIR=$REPO_ROOT/ref/vectors")
for a in "$@"; do PLUS+=(-testplusarg "$a"); done

xvlog -sv "$REPO_ROOT"/rtl/*.sv "$TBFILE" || { echo "xvlog failed"; exit 1; }
xelab --debug off -s "${TB}_snap" "$TB" || { echo "xelab failed"; exit 1; }
xsim "${TB}_snap" -R "${PLUS[@]}" -log xsim.log || { echo "xsim failed"; exit 1; }

grep -q "TEST PASSED" xsim.log && exit 0
exit 1
