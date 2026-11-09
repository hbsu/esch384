# Builds the Esch384 reference tool into ../sim/ref_build/.
#   make         build esch_tool and genkat (official KAT generator)
#   make check   official KAT + custom KAT + debug self-check
OFF   = official/esch384v2_ref
OUT   = ../sim/ref_build
CFLAGS = -std=c99 -O2 -Wall -Wextra -Wshadow -Iinclude -I$(OFF)
SRC   = $(OFF)/hash.c $(OFF)/sparkle_ref.c

all: $(OUT)/esch_tool $(OUT)/genkat

$(OUT)/esch_tool: esch_tool.c $(SRC)
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) $^ -o $@

$(OUT)/genkat: $(OFF)/genkat_hash.c $(SRC)
	mkdir -p $(OUT)
	$(CC) $(CFLAGS) $^ -o $@

check: all
	cd $(OUT) && ./genkat && cmp LWC_HASH_KAT_384.txt $(CURDIR)/official/LWC_HASH_KAT_384.txt
	@echo "PASS: official code reproduces official KAT"
	$(OUT)/esch_tool kat | cmp - kat/esch384_custom_kat.txt
	@echo "PASS: custom KAT file is up to date"
	python3 ../scripts/compare_kat.py --selftest
	python3 check_vectors.py
	@for m in "" 00 000102030405060708090a0b0c0d0e 000102030405060708090a0b0c0d0e0f \
	          000102030405060708090a0b0c0d0e0f10 \
	          000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f; do \
	  $(OUT)/esch_tool debug "$$m" | tail -1 | grep -q OK || { echo "FAIL debug '$$m'"; exit 1; }; done
	@echo "PASS: debug trace matches official code"

.PHONY: all check
