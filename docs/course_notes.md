# Course Notes (ECE 545, from ../ lectures and assignments)

Source: files in the parent `ece545/` folder (read only, not copied here).

## Project requirements found
- **No project handout was found** in the course folder. No required
  format, page limit, or presentation rules for the project.
- **No AI-tool policy was found** in the slides or assignments.
  Ask the instructor (Prof. Aysu, aaysu@ncsu.edu) about both.
  We keep `docs/ai_log.md` anyway.

## Report rules from the homework (likely apply here too)
From HW2–HW4 handouts:
- Written in readable English, not raw log dumps.
- Typeset with **LaTeX** (Overleaf is fine). HW3: max 6 pages.
- Label all figures and tables.
- Submit on **Moodle**: report as `.pdf`, code as a separate `.zip`.

## Lecture topics that matter for this project
- **Hardware metrics** (lec 2-3-4): latency = time for one block;
  throughput = block_size x blocks_in_parallel / latency.
  Iterative (one round per cycle) vs. unrolled vs. pipelined designs.
- **Area optimization** (lec 13, Lightweight Crypto): "lightweight" =
  small area, power, energy. Main trick: serialize the datapath
  (e.g. AES 128-bit -> 32-bit -> 8-bit), trading cycles for area.
  Design space reference: Aysu et al., ESL'14 ("round serial").
  This maps directly onto our Phase 4 (fewer parallel Alzettes).
- **Hash functions / sponge** (lec 10-11): sponge structure from
  SHA-3/Keccak; rate r and capacity c; lightweight instances use
  small r. Esch384 is also a sponge.
- **Side-channel and fault attacks** (lec 4-6, 12, fault attacks):
  not required by the plan, but could be a "future work" slide.
