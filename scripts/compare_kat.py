#!/usr/bin/env python3
"""Compare two KAT files (NIST format: Count / Msg / MD blocks).

Usage:
  compare_kat.py EXPECTED ACTUAL     match entries by Msg, report pass/fail
  compare_kat.py --selftest          check this script on a tiny example

Exit code 0 only if every expected entry is present in ACTUAL and matches.
Hex is compared case-insensitively.
"""
import sys


def parse(path_or_text, is_text=False):
    text = path_or_text if is_text else open(path_or_text).read()
    entries, cur = [], {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, val = (s.strip() for s in line.split("=", 1))
        cur[key] = val.upper()
        if key == "MD":
            entries.append(cur)
            cur = {}
    return entries


def compare(expected, actual, quiet=False):
    got = {e.get("Msg", ""): e["MD"] for e in actual}
    fails = 0
    for e in expected:
        msg, md = e.get("Msg", ""), e["MD"]
        if msg not in got:
            quiet or print(f"MISSING Count={e.get('Count')} len={len(msg)//2}")
            fails += 1
        elif got[msg] != md:
            quiet or print(f"FAIL    Count={e.get('Count')} len={len(msg)//2}\n"
                  f"  expected {md}\n  got      {got[msg]}")
            fails += 1
    quiet or print(f"{len(expected) - fails}/{len(expected)} passed")
    return fails == 0


def selftest():
    a = "Count = 1\nMsg = \nMD = AB\n\nCount = 2\nMsg = 00\nMD = CD\n"
    b = "Count = 2\nMsg = 00\nMD = cd\n\nCount = 1\nMsg = \nMD = ab\n"
    c = "Count = 1\nMsg = \nMD = AA\n"
    ok = compare(parse(a, True), parse(b, True), quiet=True)
    bad = not compare(parse(a, True), parse(c, True), quiet=True)
    if ok and bad:
        print("PASS: compare_kat selftest")
        return True
    print("FAIL: compare_kat selftest")
    return False


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(0 if selftest() else 1)
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(0 if compare(parse(sys.argv[1]), parse(sys.argv[2])) else 1)
