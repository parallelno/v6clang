#!/usr/bin/env python3
"""O51 A/B measurement: compile every tests/features/*/v6clang.c at -O2 with
three LSR strategy settings, then report per-test asm sizes (proxy for
in-loop instruction count) and aggregate deltas.

Output is a markdown table appended to design/plan_O51_lsr_cost_tuning.md
manually after running this script.
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLANG = ROOT / "llvm-build" / "bin" / "clang.exe"
TESTS = ROOT / "tests" / "features"
OUT = ROOT / "temp" / "o51_ab"
OUT.mkdir(parents=True, exist_ok=True)

VARIANTS = {
    "auto":  [],
    "insns": ["-mllvm", "-v6clang-lsr-strategy=insns-first"],
    "regs":  ["-mllvm", "-v6clang-lsr-strategy=regs-first"],
}

def build(src: Path, dst: Path, extra):
    cmd = [str(CLANG), "-target", "i8080-unknown-v6clang", "-O2", "-S",
           str(src), "-o", str(dst), *extra]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return dst.stat().st_size

def main():
    rows = []
    for d in sorted(TESTS.iterdir()):
        if not d.is_dir():
            continue
        src = d / "v6clang.c"
        if not src.exists():
            continue
        sizes = {}
        for name, extra in VARIANTS.items():
            out = OUT / f"{d.name}_{name}.asm"
            sz = build(src, out, extra)
            sizes[name] = sz
        if None in sizes.values():
            rows.append((d.name, "n/a", "n/a", "n/a", "BUILD FAIL"))
            continue
        a, i, r = sizes["auto"], sizes["insns"], sizes["regs"]
        delta = i - r  # insns vs regs (negative = insns smaller)
        match = "auto=insns" if a == i else ("auto=regs" if a == r else "auto=other")
        rows.append((d.name, str(a), str(i), str(r), match, str(delta)))

    print(f"{'test':<6} {'auto':>8} {'insns':>8} {'regs':>8} {'match':<12} {'i-r':>6}")
    print("-" * 60)
    insns_better = insns_worse = same = 0
    for row in rows:
        if len(row) == 5:
            print(f"{row[0]:<6} {row[1]:>8} {row[2]:>8} {row[3]:>8} {row[4]:<12}")
            continue
        name, a, i, r, m, delta = row
        print(f"{name:<6} {a:>8} {i:>8} {r:>8} {m:<12} {delta:>6}")
        d = int(delta)
        if d < 0: insns_better += 1
        elif d > 0: insns_worse += 1
        else: same += 1
    print("-" * 60)
    print(f"insns smaller than regs: {insns_better}")
    print(f"insns larger than regs:  {insns_worse}")
    print(f"identical:               {same}")

if __name__ == "__main__":
    main()
