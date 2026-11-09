# Esch384 on FPGA

Hardware implementation of **Esch384**, the 384-bit hash from the
SPARKLE family (NIST Lightweight Cryptography finalist).
NCSU ECE 545 course project. Team: Henry Su, Nick Ngo.

## Layout
    docs/      course notes, architecture, task log, AI log, diagrams
    ref/       reference model + known-answer tests (KATs)
    rtl/       synthesizable SystemVerilog
    tb/        testbenches
    sim/       simulation outputs (not in git)
    syn/       Vivado scripts, constraints, reports
    slides/    slide generator script + .pptx
    scripts/   env.sh, run_sim.sh, run_syn.sh, compare_kat.py

## Setup (NCSU Grendel)
    python3 -m venv .venv && .venv/bin/pip install python-pptx graphviz matplotlib
    source scripts/env.sh        # loads Vivado/xsim 2026.1 + venv

## Simulate
    scripts/run_sim.sh           # (coming in Phase 3)

## Synthesize
    scripts/run_syn.sh           # (coming in Phase 3, task 7)
    Target part is set in syn/part.tcl (default xc7a100tcsg324-1, Arty A7).
