#!/usr/bin/env python3
import hashlib
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
CLANG = ROOT / "llvm-build" / "bin" / "clang.exe"
OBJCOPY = ROOT / "llvm-build" / "bin" / "llvm-objcopy.exe"
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


def memory_from(snapshot):
    memory = bytearray(65536)
    for match in re.finditer(
        r"^([0-9A-Fa-f]{4}):((?: [0-9A-Fa-f]{2}){16})$", snapshot, re.M
    ):
        base = int(match.group(1), 16)
        memory[base:base + 16] = bytes.fromhex(match.group(2))
    return memory


def symbols_from(text):
    symbols = {}
    for line in text.splitlines():
        match = re.search(r"\b([0-9a-fA-F]{8})\s+\d+\s+\w+\s+\w+\s+\w+\s+\S+\s+(\S+)$", line)
        if match and match.group(2) in {"leaf", "middle", "main"}:
            symbols[match.group(2)] = int(match.group(1), 16)
    return symbols


results = []
for level in ("O0", "O1", "O2", "Os"):
    rom = HERE / f"contract-{level}.rom"
    elf = HERE / f"contract-{level}.elf"
    image = HERE / f"contract-{level}.bin"
    run([
        str(CLANG), "-target", "i8080-unknown-v6clang", f"-{level}", "-g",
        str(HERE / "v6clang.c"), "-o", str(rom),
    ])
    run([str(DWARFDUMP), "--verify", str(elf)])
    run([str(OBJCOPY), "-O", "binary", str(elf), str(image)])
    if image.read_bytes() != rom.read_bytes():
        raise RuntimeError(f"{level}: ROM differs from final ELF projection")

    sections = run([str(READELF), "-S", str(elf)])
    for section in (".debug_info", ".debug_abbrev", ".debug_line", ".debug_addr", ".debug_frame"):
        if section not in sections:
            raise RuntimeError(f"{level}: missing {section}")
    dwarf = run([str(DWARFDUMP), "--debug-info", "--debug-rnglists", "--debug-loclists", str(elf)])
    cfi = run([str(DWARFDUMP), "--debug-frame", str(elf)])
    if "DW_TAG_inlined_subroutine" not in dwarf:
        raise RuntimeError(f"{level}: missing nested inline metadata")
    if "DW_TAG_formal_parameter" not in dwarf or "DW_TAG_variable" not in dwarf:
        raise RuntimeError(f"{level}: missing variable metadata")

    symbols = symbols_from(run([str(READELF), "-s", str(elf)]))
    if set(symbols) != {"leaf", "middle", "main"}:
        raise RuntimeError(f"{level}: missing physical symbols {symbols}")
    for name, address in symbols.items():
        if not re.search(rf"FDE cie=.*pc=0*{address:x}\.\.\..*?CFA=SP\+2: PC=\[CFA-2\]", cfi, re.S):
            raise RuntimeError(f"{level}: missing entry CFI for {name}")

    snapshot = run([
        str(V6EMUL), "--rom", str(rom), "--load-addr", "0x0100",
        "--halt-exit", "--dump-cpu", "--dump-memory",
    ])
    (HERE / f"contract-{level}-dwarf.txt").write_text(dwarf, encoding="ascii")
    (HERE / f"contract-{level}-cfi.txt").write_text(cfi, encoding="ascii")
    (HERE / f"contract-{level}-stop.txt").write_text(snapshot, encoding="ascii")
    pc_match = re.search(r"PC=([0-9A-Fa-f]{4}) SP=([0-9A-Fa-f]{4})", snapshot)
    if not pc_match:
        raise RuntimeError(f"{level}: missing emulator CPU state")
    hlt = (int(pc_match.group(1), 16) - 1) & 0xFFFF
    inline_ranges = [
        (int(begin, 16), int(end, 16))
        for begin, end in re.findall(
            r"DW_TAG_inlined_subroutine.*?DW_AT_low_pc\s+\(0x([0-9a-f]+)\).*?DW_AT_high_pc\s+\(0x([0-9a-f]+)\)",
            dwarf,
            re.S,
        )
    ]
    if not any(begin <= hlt < end for begin, end in inline_ranges):
        raise RuntimeError(f"{level}: HLT 0x{hlt:04X} is outside inline ranges")
    results.append(f"{level}: elf-rom={hashlib.sha256(rom.read_bytes()).hexdigest()} HLT=0x{hlt:04X} inline-ranges={inline_ranges}")

(HERE / "result.txt").write_text(
    "Feature 83 - C Debug Metadata Milestone 6 Producer Contract\n"
    "===========================================================\n\n"
    "Each optimization level builds a final ELF/ROM pair, verifies DWARF and "
    "CFI, proves the ROM is the ELF binary projection, and stops inside nested "
    "inline metadata.\n\n" + "\n".join(results) + "\n",
    encoding="ascii",
)
print("PASS: final-link producer contract")
for result in results:
    print("  " + result)