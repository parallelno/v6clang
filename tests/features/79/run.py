#!/usr/bin/env python3
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CLANG = ROOT / "llvm-build" / "bin" / "clang.exe"
READELF = ROOT / "llvm-build" / "bin" / "llvm-readelf.exe"
DWARFDUMP = ROOT / "llvm-build" / "bin" / "llvm-dwarfdump.exe"
V6EMUL = Path(os.environ.get(
    "V6EMUL",
    r"C:\Work\Programming\v6emul\build\release\app\Release\v6emul.exe",
))


def run(args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


elf = HERE / "cfi.elf"
rom = HERE / "cfi.rom"
run([
    str(CLANG), "-target", "i8080-unknown-v6clang", "-O1", "-g",
    str(HERE / "v6clang.c"), "-o", str(rom),
])
if not elf.exists():
    raise RuntimeError("clang did not retain cfi.elf")

run([str(DWARFDUMP), "--verify", str(elf)])
cfi = run([str(DWARFDUMP), "--debug-frame", str(elf)])
if "Return address column: 11" not in cfi:
    raise RuntimeError("missing V6CLANG return-address column")

symbols = {}
for line in run([str(READELF), "-s", str(elf)]).splitlines():
    match = re.search(r"\b([0-9a-fA-F]{8})\s+\d+\s+\w+\s+\w+\s+\w+\s+\S+\s+(\S+)$", line)
    if match and match.group(2) in {"_start", "leaf", "middle", "main"}:
        symbols[match.group(2)] = int(match.group(1), 16)
if set(symbols) != {"_start", "leaf", "middle", "main"}:
    raise RuntimeError(f"missing symbols: {symbols}")

ordered = sorted((address, name) for name, address in symbols.items())

def function_at(pc):
    result = None
    for address, name in ordered:
        if address <= pc:
            result = name
    return result

for name in ("leaf", "middle", "main"):
    address = symbols[name]
    fde = re.search(
        rf"FDE cie=.*pc=0*{address:x}\.\.\..*?(?=\n\n0|\n\n\.eh_frame)",
        cfi,
        re.S,
    )
    if not fde or "CFA=SP+2: PC=[CFA-2]" not in fde.group(0):
        raise RuntimeError(f"missing SP+2 unwind rule for {name}")

snapshot = run([
    str(V6EMUL), "--rom", str(rom), "--load-addr", "0x0100",
    "--run-cycles", "1400", "--dump-cpu", "--dump-memory",
])
(HERE / "emulator-stop.txt").write_text(snapshot, encoding="ascii")

pc_match = re.search(r"PC=([0-9A-Fa-f]{4}) SP=([0-9A-Fa-f]{4})", snapshot)
if not pc_match:
    raise RuntimeError("missing CPU snapshot")
pc = int(pc_match.group(1), 16)
sp = int(pc_match.group(2), 16)

memory = bytearray(65536)
for match in re.finditer(r"^([0-9A-Fa-f]{4}):((?: [0-9A-Fa-f]{2}){16})$", snapshot, re.M):
    base = int(match.group(1), 16)
    memory[base:base + 16] = bytes.fromhex(match.group(2))

frames = []
for _ in range(3):
    frames.append((function_at(pc), pc, sp))
    return_pc = memory[sp] | (memory[(sp + 1) & 0xFFFF] << 8)
    sp = (sp + 2) & 0xFFFF
    pc = return_pc

names = [frame[0] for frame in frames]
if names != ["leaf", "middle", "main"]:
    raise RuntimeError(f"unexpected unwind chain: {frames}")

print("PASS: .debug_frame verified")
for name, frame_pc, frame_sp in frames:
    print(f"  {name}: PC=0x{frame_pc:04X} SP=0x{frame_sp:04X}")
print(f"  caller after main: PC=0x{pc:04X} SP=0x{sp:04X}")
