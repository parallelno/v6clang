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


def build_and_stop(name, defines=()):
    rom = HERE / f"{name}.rom"
    elf = HERE / f"{name}.elf"
    run([
        str(CLANG), "-target", "i8080-unknown-v6clang", "-O0", "-g",
        *defines, str(HERE / "v6clang.c"), "-o", str(rom),
    ])
    run([str(DWARFDUMP), "--verify", str(elf)])
    dwarf = run([str(DWARFDUMP), "--debug-info", str(elf)])
    cfi = run([str(DWARFDUMP), "--debug-frame", str(elf)])
    snapshot = run([
        str(V6EMUL), "--rom", str(rom), "--load-addr", "0x0100",
        "--halt-exit", "--dump-cpu", "--dump-memory",
    ])
    (HERE / f"{name}-dwarf.txt").write_text(dwarf, encoding="ascii")
    (HERE / f"{name}-stop.txt").write_text(snapshot, encoding="ascii")
    return elf, dwarf, cfi, snapshot


def memory_from(snapshot):
    memory = bytearray(65536)
    for match in re.finditer(
        r"^([0-9A-Fa-f]{4}):((?: [0-9A-Fa-f]{2}){16})$", snapshot, re.M
    ):
        base = int(match.group(1), 16)
        memory[base:base + 16] = bytes.fromhex(match.group(2))
    return memory


def cpu_from(snapshot):
    match = re.search(r"PC=([0-9A-Fa-f]{4}) SP=([0-9A-Fa-f]{4})", snapshot)
    if not match:
        raise RuntimeError("missing CPU state")
    return int(match.group(1), 16), int(match.group(2), 16)


def word(memory, address):
    return memory[address] | (memory[(address + 1) & 0xFFFF] << 8)


def subprogram_block(dwarf, name):
    match = re.search(
        rf"DW_TAG_subprogram(?:(?!DW_TAG_subprogram).)*?DW_AT_name\s+\(\"{name}\"\)(?:(?!DW_TAG_subprogram).)*?(?=\n0x[0-9a-f]+:\s+DW_TAG_subprogram|\Z)",
        dwarf,
        re.S,
    )
    if not match:
        raise RuntimeError(f"missing subprogram {name}")
    return match.group(0)


def variable_location(block, name):
    matches = re.findall(
        r"DW_TAG_(?:formal_parameter|variable)(.*?)(?=\n0x[0-9a-f]+:|\Z)",
        block,
        re.S,
    )
    for item in matches:
        if re.search(rf'DW_AT_name\s+\(\"{name}\"\)', item):
            location = re.search(r"DW_AT_location\s+\((.*?)\)", item, re.S)
            if not location:
                raise RuntimeError(f"missing location for {name}")
            return " ".join(location.group(1).split())
    raise RuntimeError(f"missing variable {name}")


# Static alloca-promotion scenario.
static_elf, static_dwarf, _, static_snapshot = build_and_stop("static")
static_block = subprogram_block(static_dwarf, "static_probe")
static_locations = {
    name: variable_location(static_block, name)
    for name in ("parameter", "local", "addressable")
}
if "DW_OP_addrx" not in static_locations["parameter"]:
    raise RuntimeError(f"parameter is not static: {static_locations}")
if "DW_OP_plus_uconst 0x2" not in static_locations["local"]:
    raise RuntimeError(f"local offset is wrong: {static_locations}")
if "DW_OP_plus_uconst 0x4" not in static_locations["addressable"]:
    raise RuntimeError(f"addressable offset is wrong: {static_locations}")

symbols = run([str(READELF), "-s", str(static_elf)])
match = re.search(r"([0-9a-fA-F]{8})\s+\d+\s+OBJECT\s+LOCAL.*__v6clang_a\.static_probe", symbols)
if not match:
    raise RuntimeError("missing __v6clang_a.static_probe symbol")
base = int(match.group(1), 16)
static_memory = memory_from(static_snapshot)
static_values = [word(static_memory, base + offset) for offset in (0, 2, 4)]
if static_values != [0x1122, 0x1245, 0x1246]:
    raise RuntimeError(f"wrong static values: {static_values}")

# Dynamic stack-frame scenario.
dynamic_elf, dynamic_dwarf, dynamic_cfi, dynamic_snapshot = build_and_stop(
    "dynamic", ("-DDYNAMIC_PROBE",)
)
dynamic_block = subprogram_block(dynamic_dwarf, "dynamic_probe")
frame_base = re.search(
    r"DW_AT_frame_base\s+\(DW_OP_call_frame_cfa, DW_OP_consts (-\d+), DW_OP_plus\)",
    dynamic_block,
)
if not frame_base:
    raise RuntimeError("missing CFA-based frame base")
frame_adjust = int(frame_base.group(1))
offsets = {}
for name in ("parameter", "local", "addressable"):
    location = variable_location(dynamic_block, name)
    match = re.search(r"DW_OP_fbreg \+(\d+)", location)
    if not match:
        raise RuntimeError(f"{name} is not frame-relative: {location}")
    offsets[name] = int(match.group(1))

pc, sp = cpu_from(dynamic_snapshot)
fde_match = None
for match in re.finditer(
    r"FDE cie=.*?pc=([0-9a-f]+)\.\.\.([0-9a-f]+)(.*?)(?=\n\n0|\n\n\.eh_frame)",
    dynamic_cfi,
    re.S,
):
    if int(match.group(1), 16) <= pc < int(match.group(2), 16):
        fde_match = match
        break
if not fde_match:
    raise RuntimeError(f"no FDE for stopped PC 0x{pc:04X}")

cfa_offset = None
for address, offset in re.findall(r"0x([0-9a-f]+): CFA=SP\+(\d+)", fde_match.group(3)):
    if int(address, 16) <= pc:
        cfa_offset = int(offset)
if cfa_offset is None:
    raise RuntimeError("no active CFA row")

cfa = (sp + cfa_offset) & 0xFFFF
frame = (cfa + frame_adjust) & 0xFFFF
dynamic_memory = memory_from(dynamic_snapshot)
dynamic_values = [
    word(dynamic_memory, (frame + offsets[name]) & 0xFFFF)
    for name in ("parameter", "local", "addressable")
]
if dynamic_values != [0x3344, 0x3578, 0x3579]:
    raise RuntimeError(
        f"wrong dynamic values: {dynamic_values}, PC=0x{pc:04X}, SP=0x{sp:04X}, frame=0x{frame:04X}"
    )

print("PASS: static locations", static_locations)
print(f"  base=0x{base:04X} values={[hex(v) for v in static_values]}")
print("PASS: dynamic locations", offsets)
print(
    f"  PC=0x{pc:04X} SP=0x{sp:04X} CFA=0x{cfa:04X} frame=0x{frame:04X} "
    f"values={[hex(v) for v in dynamic_values]}"
)
