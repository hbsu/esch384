# Reference model

## Files
| Path | What |
|------|------|
| `official/sparkle_nist_submission.zip` | Full SPARKLE submission from NIST (final round) |
| `official/esch384v2_ref/` | Official Esch384 reference C code, unmodified (GPLv3) |
| `official/LWC_HASH_KAT_384.txt` | Official KATs: messages of 0..1024 bytes |
| `include/crypto_hash.h` | One-line header the official code expects |
| `esch_tool.c` | Our wrapper: hash, debug trace, vector generators |
| `kat/esch384_custom_kat.txt` | Our KATs: 0, 1, 15, 16, 17, 31, 32, 33, 48, 64, 100, 255 bytes, three data patterns |
| `vectors/` | Unit-test vectors for Alzette, linear layer, SPARKLE512 (8 and 12 steps) |
| `check_vectors.py` | Re-checks the vectors with Python written from the spec pseudocode |

## Build and check
    cd ref
    make            # builds ../sim/ref_build/esch_tool and genkat
    make check      # all checks below must say PASS

`make check` verifies:
1. Official code reproduces the official KAT file exactly.
2. Custom KAT file is up to date.
3. `compare_kat.py` self-test.
4. Unit vectors match an independent Python model from the spec.
5. Debug trace gives the same digest as the official code.

## Use
    T=../sim/ref_build/esch_tool
    $T hash 000102                  # digest
    $T debug 000102 > trace.txt     # state after every step
    $T alzette 64 1                 # vectors: c x y u v
    $T linear 64 2                  # vectors: 16 words in | 16 words out
    $T sparkle 8 32 3               # 8-step SPARKLE512 vectors

## Debug trace format
One line per state: `TRACE <tag> x0 y0 x1 y1 ... x7 y7` (hex words).

Tags: `init`, `b<k>.inj` (after injecting block k), `b<k>.s<i>`
(after step i of block k's permutation), `sq<j>.s<i>` (squeeze j).
The hardware testbench should print the same format, so the first
different line shows where the bug is.
