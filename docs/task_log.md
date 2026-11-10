# Task Log

| Task | Owner | Status | Test result | Date |
|------|-------|--------|-------------|------|
| Phase 1: setup (env, course notes, repo) | Henry Su | Done | env.sh loads Vivado/xsim 2026.1 | 2026-11-09 |
| Phase 2: spec + official code downloaded into repo | Henry Su | Done | spec PDF identical to copy inside NIST zip | 2026-11-09 |
| Phase 2: reference model (official C + esch_tool) | Henry Su | Done | official code reproduces all 1025 official KATs | 2026-11-09 |
| Phase 2: custom KATs, unit vectors, debug trace | Henry Su | Done | `make check` in ref/: 5/5 PASS | 2026-11-09 |
| Phase 2: slides 1-3, 8, 11 | Henry Su | Done | deck builds, no shapes off-page | 2026-11-09 |
| P3 task 1: Alzette ARX-box (rtl/alzette.sv, combinational) + tb_alzette | Henry Su | Done | 64/64 vectors pass; mutated copy fails 64/64 | 2026-11-09 |
| Synthesis check script (scripts/check_synth.sh, syn/part.tcl) | Henry Su | Done | alzette: 254 LUTs, 0 latches; latch test module correctly FAILS | 2026-11-09 |
| P3 task 2: linear layer L8 (rtl/sparkle_linear.sv) + tb_sparkle_linear | Henry Su | Done | 64/64 pass; 2 mutated copies fail; synth OK, 320 LUTs | 2026-11-09 |
| P3 task 3: SPARKLE512 (rtl/sparkle_step.sv, rtl/sparkle512.sv) + tb_sparkle512 | Henry Su | Done | 71/71 (64 vectors + busy/reset/back-to-back); 2 mutations fail; synth 2023 LUTs, 521 FFs. Note: xsim crashes on string ternaries passed to tasks, use a variable | 2026-11-09 |
| P3 task 4 (own-attempt branch): datapath (rtl/esch_datapath.sv) + tb_esch_datapath | Henry Su | Done | 1113/1113 (27 msgs 0-48 B, every inj/step/squeeze); 3 mutations fail; synth 2158 LUTs, 512 FFs | 2026-11-10 |
| P3 task 5 (own-attempt branch): controller FSM (rtl/esch_ctrl.sv) + tb_esch_ctrl | Henry Su | Done | 3751/3751 (n=1,2,3,5, stalls, mid-message reset); 4 mutations fail; latency 9n+23 cycles; synth 18 LUTs, 10 FFs | 2026-11-10 |
| P3 task 6 (own-attempt branch): top level (rtl/esch384.sv) + full KAT tb_esch384 | Henry Su | Done | 3255/3255; official 1025/1025 + custom 34/34 KATs (also with stalls); cycles = 9n+23 checked; HW trace = ref trace; 3 mutations fail; synth 2180 LUTs, 522 FFs | 2026-11-10 |
