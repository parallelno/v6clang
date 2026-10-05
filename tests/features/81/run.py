#!/usr/bin/env python3
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CLANG = ROOT / "llvm-build" / "bin" / "clang.exe"
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


def memory_from(snapshot):
    memory = bytearray(65536)
    for match in re.finditer(
        r"^([0-9A-Fa-f]{4}):((?: [0-9A-Fa-f]{2}){16})$", snapshot, re.M
    ):
        base = int(match.group(1), 16)
        memory[base:base + 16] = bytes.fromhex(match.group(2))
    return memory


def word(memory, address):
    return memory[address] | (memory[(address + 1) & 0xFFFF] << 8)


rom = HERE / "optimized.rom"
elf = HERE / "optimized.elf"
run([
    str(CLANG), "-target", "i8080-unknown-v6clang", "-O2", "-g",
    str(HERE / "v6clang.c"), "-o", str(rom),
])
run([str(DWARFDUMP), "--verify", str(elf)])
dwarf = run([str(DWARFDUMP), "--debug-info", "--debug-loclists", "--debug-addr", str(elf)])
snapshot = run([
    str(V6EMUL), "--rom", str(rom), "--load-addr", "0x0100",
    "--halt-exit", "--dump-cpu", "--dump-memory",
])
(HERE / "dwarf.txt").write_text(dwarf, encoding="ascii")
(HERE / "stop.txt").write_text(snapshot, encoding="ascii")

function = re.search(
    r'DW_TAG_subprogram(?:(?!DW_TAG_subprogram).)*?DW_AT_name\s+\("optimized_locations"\)(?:(?!DW_TAG_subprogram).)*?(?=\n0x[0-9a-f]+:\s+DW_TAG_subprogram|\Z)',
    dwarf,
    re.S,
)
if not function:
    raise RuntimeError("missing optimized_locations")
first = re.search(
    r'DW_TAG_variable(?:(?!\n0x[0-9a-f]+:\s+DW_TAG).)*?DW_AT_location\s+\((.*?)\)\s+DW_AT_name\s+\("first"\)',
    function.group(0),
    re.S,
)
if not first:
    raise RuntimeError("missing first location")
location = " ".join(first.group(1).split())
match = re.search(r'DW_OP_addrx 0x([0-9a-f]+), DW_OP_plus_uconst 0x1', location)
if not match:
    raise RuntimeError(f"first is not O61-backed: {location}")
index = int(match.group(1), 16)

range_match = re.search(
    r'\[0x([0-9a-f]+), 0x([0-9a-f]+)\): DW_OP_addrx 0x'
    + match.group(1) + r', DW_OP_plus_uconst 0x1',
    location,
)
pc_match = re.search(r"PC=([0-9A-Fa-f]{4})", snapshot)
if not range_match or not pc_match:
    raise RuntimeError("missing O61 location range or halted PC")
start, end = (int(range_match.group(1), 16), int(range_match.group(2), 16))
resume_pc = int(pc_match.group(1), 16)
pc = (resume_pc - 1) & 0xFFFF
if not start <= pc < end:
    raise RuntimeError(f"HLT at 0x{pc:04X} is outside O61 range 0x{start:04X}..0x{end:04X}")

addresses = re.search(r"\.debug_addr contents:.*?Addrs:\s+\[(.*?)\]", dwarf, re.S)
if not addresses:
    raise RuntimeError("missing debug address table")
entries = re.findall(r"0x([0-9a-f]+)", addresses.group(1))
if index >= len(entries):
    raise RuntimeError(f"missing debug address index {index}")
address = (int(entries[index], 16) + 1) & 0xFFFF
value = word(memory_from(snapshot), address)
if value != 0x1235:
    raise RuntimeError(f"wrong O61 value at 0x{address:04X}: 0x{value:04X}")

print(
    f"PASS: first={location}, HLT=0x{pc:04X}, patch=0x{address:04X}, "
    f"value=0x{value:04X}"
)