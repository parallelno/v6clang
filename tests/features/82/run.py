#!/usr/bin/env python3
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CLANG = ROOT / "llvm-build" / "bin" / "clang.exe"
DWARFDUMP = ROOT / "llvm-build" / "bin" / "llvm-dwarfdump.exe"
READELF = ROOT / "llvm-build" / "bin" / "llvm-readelf.exe"
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


rom = HERE / "inline.rom"
elf = HERE / "inline.elf"
run([
    str(CLANG), "-target", "i8080-unknown-v6clang", "-O2", "-g",
    str(HERE / "v6clang.c"), "-o", str(rom),
])
run([str(DWARFDUMP), "--verify", str(elf)])
dwarf = run([str(DWARFDUMP), "--debug-info", str(elf)])
symbols = run([str(READELF), "-s", str(elf)])
snapshot = run([
    str(V6EMUL), "--rom", str(rom), "--load-addr", "0x0100",
    "--halt-exit", "--dump-cpu", "--dump-memory",
])
(HERE / "dwarf.txt").write_text(dwarf, encoding="ascii")
(HERE / "stop.txt").write_text(snapshot, encoding="ascii")

layout = re.search(
    r'DW_TAG_structure_type\s+DW_AT_name\s+\("layout"\)', dwarf, re.S
)
if not layout:
    raise RuntimeError("missing layout DIE")
layout_block = dwarf[layout.start():layout.start() + 5000]
if not re.search(r"DW_AT_byte_size\s+\(0x0b\)", layout_block):
    raise RuntimeError("missing 11-byte layout DIE")
for name, offset in (("tag", "0x00"), ("value", "0x01"), ("values", "0x03"), ("current", "0x09")):
    member = re.search(
        rf'DW_TAG_member(?:(?!DW_TAG_member).)*?DW_AT_name\s+\("{name}"\)(?:(?!DW_TAG_member).)*?DW_AT_data_member_location\s+\({offset}\)',
        layout_block,
        re.S,
    )
    if not member:
        raise RuntimeError(f"missing {name} offset {offset}")

sample = re.search(r"([0-9a-fA-F]{8})\s+\d+\s+\S+\s+GLOBAL.*\bsample\b", symbols)
if not sample:
    raise RuntimeError("missing sample symbol")
address = int(sample.group(1), 16)
memory = memory_from(snapshot)
values = (memory[address], word(memory, address + 1), word(memory, address + 3), word(memory, address + 5), word(memory, address + 7), word(memory, address + 9))
if values != (0xA5, 0x1234, 0x0102, 0x3456, 0x789A, 7):
    raise RuntimeError(f"wrong layout at 0x{address:04X}: {values}")

pc_match = re.search(r"PC=([0-9A-Fa-f]{4})", snapshot)
if not pc_match:
    raise RuntimeError("missing halted PC")
hlt = (int(pc_match.group(1), 16) - 1) & 0xFFFF
inline_ranges = [
    (int(begin, 16), int(end, 16))
    for begin, end in re.findall(
        r'DW_TAG_inlined_subroutine.*?DW_AT_low_pc\s+\(0x([0-9a-f]+)\).*?DW_AT_high_pc\s+\(0x([0-9a-f]+)\)',
        dwarf,
        re.S,
    )
]
if not any(begin <= hlt < end for begin, end in inline_ranges):
    raise RuntimeError(f"HLT 0x{hlt:04X} is outside inline ranges {inline_ranges}")

print(f"PASS: layout=0x{address:04X} values={values}, HLT=0x{hlt:04X}, inline_ranges={inline_ranges}")