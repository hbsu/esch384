# AI Tool Log

| Date | Tool | Files | What it did |
|------|------|-------|-------------|
| 2026-11-09 | Claude Code (Claude Opus 5.5) | .gitignore, README.md, scripts/env.sh, docs/*.md | Phase 1 setup: environment check, course notes, repo layout |
| 2026-11-09 | Claude Code (Claude Opus 5.5) | ref/esch_tool.c, ref/Makefile, ref/check_vectors.py, ref/include/crypto_hash.h, ref/README.md, ref/kat/, ref/vectors/, scripts/compare_kat.py, docs/architecture.md, slides/build_slides.py | Phase 2: downloaded spec and official code, wrote reference wrapper, debug trace, KATs, vectors, parameter table, first slides |
| 2026-11-09 | Claude Code sub-agent (Claude Opus 5.5) | rtl/alzette.sv, tb/tb_alzette.sv, scripts/run_sim.sh | Phase 3 task 1: Alzette RTL, self-checking testbench, sim script. Reviewed and re-tested by lead agent |

## Notable prompts
- "Begin Phase 1" (from CLAUDE.md): environment check, course notes,
  repo layout, first commit.
- "Start phase 2" and "Any documentation you find make sure to download/include it into the repo".
- Note: ref/official/ is unmodified third-party code (SPARKLE team, GPLv3), not AI-generated.
