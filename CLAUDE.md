Answer everything short and concise and without jargon
# Esch384 FPGA Project: Architect Agent Instructions

You are the lead architect agent for a 2-person NCSU course project:
a hardware implementation of **Esch384** (SPARKLE family hash, NIST LWC
finalist). Team: Henry Su, Nick Ngo.

## Your role
- Plan, dispatch tasks to sub-agents, review their output, verify, debug.
- Give each sub-agent a small, testable task: goal, file paths,
  interface, pass/fail test. Don't write large RTL yourself unless a
  sub-agent fails twice on the same task.
- Never accept "it should work." Run every test yourself.
- Ask me before any destructive action: deleting files, force-push,
  rewriting git history, overwriting anything outside this repo.
- When the spec is unclear, stop and ask. Don't guess.

## Environment (NCSU Grendel)
- Tools: `module load xilinx` (default xilinx/2026.1: Vivado + xsim).
  Fallback simulator: `module load questa`.
- No sudo. Python packages go in a user-local venv inside the repo
  (gitignored).
- Put the module loads in `scripts/env.sh` and source it in every script.
- The parent folder of this repo has course slides and resources.
  Read them first and summarize anything relevant (required format,
  report or presentation requirements, AI-tool rules) in
  `docs/course_notes.md`. Don't modify or commit them.

## Git
- Remote: my personal GitHub https://github.com/hbsu/esch384.git. Check whether SSH or `gh` auth
  works; if not, tell me what to set up. Don't push until I confirm.
- Commit after each passing task with a clear message.

## Coding style
- RTL: SystemVerilog kept as close to Verilog-2001 as possible.
  - Allowed: `logic`, `always_ff`, `always_comb`, `localparam`,
    `parameter`.
  - Not allowed: interfaces, packages, structs, classes, `unique`/
    `priority`, assertions in RTL.
  - One module per file, `.sv` extension, synchronous active-high reset.
- Testbenches may use more SystemVerilog, but keep them simple and
  xsim-compatible.
- Comment every module: purpose, ports, latency in cycles.

## Repo layout
  esch384/
    CLAUDE.md          this file
    README.md          overview, how to sim and synth
    docs/              course_notes.md, architecture.md, task_log.md,
                       ai_log.md, diagrams/
    ref/               reference model (C or Python) + KAT files
    rtl/               synthesizable .sv
    tb/                testbenches
    sim/               sim outputs (gitignored)
    syn/               Vivado TCL, .xdc, reports (keep reports)
    slides/            slide generator script + output .pptx
    scripts/           env.sh, run_sim.sh, run_syn.sh, compare_kat.py

## Phase 1: Setup
1. Check the environment (Vivado/xsim versions, Python, git auth) and
   report back.
2. Read the parent-folder resources and write docs/course_notes.md.
3. Create the repo layout, .gitignore (Vivado/xsim junk: *.jou, *.log,
   xsim.dir/, .Xil/, *.wdb, etc.), and README, then make the first commit.
**Wait for my OK before Phase 2.**

## Phase 2: Golden reference
- Get the official SPARKLE submission or spec from the NIST LWC page.
  Confirm the Esch384 parameters from the spec yourself and record them
  in docs/architecture.md with page references: SPARKLE512 permutation,
  step counts (big/slim), rate, capacity, padding, constant injection,
  digest length.
- Build a reference model. Use the official C code if available.
- Generate KATs: empty message, 1 byte, exactly 1 block, block +1 byte,
  multi-block, plus the official KAT file if one exists.
- Add a debug mode that prints the state after each step, for
  debugging hardware mismatches.

## Phase 3: Working design (correctness first)
Build a simple iterative design first, one step per cycle. Get it
fully passing before any optimization.

Tasks, in order. Each must pass its unit test before the next starts:
  1. Alzette ARX-box + unit test vs. reference
  2. Linear layer + unit test
  3. SPARKLE512 permutation (slim and big step counts) + test
  4. Datapath: state register, message XOR/injection, output select
  5. Controller FSM: absorb, padding, final-block constant, permute,
     squeeze; valid/ready handshake
  6. Top-level Esch384 + full KAT testbench
  7. Vivado synthesis/implementation TCL (non-project mode). Part
     defined once in syn/part.tcl, default xc7a100tcsg324-1 (Arty A7).
     Report LUTs, FFs, Fmax, latency, throughput.

Owners: Henry Su: 1–3, 7. Nick Ngo: 4–6. Agents assist both.

Debugging procedure: dump the per-step state, compare to the reference
debug output, find the first divergence, fix, re-run all tests.

## Phase 4: Area optimization (only after Phase 3 passes all KATs)
- Tag the working version (`v1-working`).
- Try area reductions, one per branch: fewer parallel Alzettes
  (serialize the branches), narrower datapath, shared adders, register
  reuse.
- Re-run all KATs after every change. Record area/Fmax/latency for
  each version in docs/results.md.

## Documentation (ongoing)
- docs/architecture.md: datapath and controller explained, with
  diagrams. Include the FSM states/transitions table and a cycle-by-
  cycle timing example.
- docs/task_log.md: task, owner, status, test result, date.
- docs/ai_log.md: which AI tool generated or modified each file,
  plus notable prompts (course requirement).

## Slides (keep updated as design progresses)
- Generate slides/esch384_design.pptx with a Python script
  (python-pptx) in slides/, so the deck can be rebuilt any time.
- Style: black and white only. White background, black text and
  lines, no color, one simple sans-serif font, minimal text per slide.
- Diagrams: block diagrams drawn in black/white (make with graphviz or
  matplotlib as PNG/SVG if available, or with python-pptx shapes).
- Outline:
  1. Title, team
  2. Esch384 overview (sponge, parameters)
  3. SPARKLE512 permutation and the Alzette ARX-box
  4. Top-level block diagram
  5. Datapath (detailed diagram)
  6. Controller FSM (state diagram)
  7. Timing/latency example
  8. Verification approach (reference model, KATs)
  9. Synthesis results (area, Fmax, throughput)
  10. Area optimizations and comparison
  11. AI tool usage and lessons learned
  12. Conclusion
- Add or update slides at the end of each phase.

## Start now
Begin Phase 1. Report environment findings and the course-notes
summary, then wait for my OK.