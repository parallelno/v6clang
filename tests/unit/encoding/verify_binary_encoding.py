#!/usr/bin/env python3
"""Verify V6CLANG binary encoding against v6asm reference.

For each test case, compiles LLVM IR → ELF .o → flat binary and compares
the .text section bytes against v6asm-assembled reference.

Usage:
    python verify_binary_encoding.py [--llc PATH] [--v6asm PATH]
"""

import argparse
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

# Test cases: (description, llvm_ir, expected_asm, expected_bytes)
# expected_bytes is the hex string of expected .text section contents
TEST_CASES = [
    (
        "RET (1-byte implied)",
        "define void @f() { ret void }",
        "RET",
        "C9",
    ),
    (
        "MVI A, 42 + RET (2-byte imm8)",
        "define i8 @f() { ret i8 42 }",
        "MVI A, 0x2a\nRET",
        "3E 2A C9",
    ),
    (
        "ADD E + RET (1-byte reg ALU)",
        "define i8 @f(i8 %a, i8 %b) { %c = add i8 %a, %b\n ret i8 %c }",
        "ADD E\nRET",
        "83 C9",
    ),
    (
        "SUB E + RET",
        "define i8 @f(i8 %a, i8 %b) { %c = sub i8 %a, %b\n ret i8 %c }",
        "SUB E\nRET",
        "93 C9",
    ),
    (
        "ANA E + RET",
        "define i8 @f(i8 %a, i8 %b) { %c = and i8 %a, %b\n ret i8 %c }",
        "ANA E\nRET",
        "A3 C9",
    ),
    (
        "ORA E + RET",
        "define i8 @f(i8 %a, i8 %b) { %c = or i8 %a, %b\n ret i8 %c }",
        "ORA E\nRET",
        "B3 C9",
    ),
    (
        "XRA E + RET",
        "define i8 @f(i8 %a, i8 %b) { %c = xor i8 %a, %b\n ret i8 %c }",
        "XRA E\nRET",
        "AB C9",
    ),
    (
        "ADI 10 + RET (2-byte imm ALU)",
        "define i8 @f(i8 %a) { %c = add i8 %a, 10\n ret i8 %c }",
        "ADI 0x0a\nRET",
        "C6 0A C9",
    ),
    (
        "NOP (1-byte implied, 0x00)",
        None,  # skip IR, test asm only
        "NOP",
        "00",
    ),
    (
        "HLT (1-byte implied, 0x76)",
        None,
        "HLT",
        "76",
    ),
    (
        "INR A (1-byte reg, 0x3C)",
        None,
        "INR A",
        "3C",
    ),
    (
        "DCR B (1-byte reg, 0x05)",
        None,
        "DCR B",
        "05",
    ),
    (
        "MOV B, A (1-byte reg-reg, 0x47)",
        None,
        "MOV B, A",
        "47",
    ),
    (
        "LXI HL, 0x1234 (3-byte imm16, 21 34 12)",
        None,
        "LXI H, 0x1234",
        "21 34 12",
    ),
    (
        "JMP 0x0100 (3-byte, C3 00 01)",
        None,
        "JMP 0x0100",
        "C3 00 01",
    ),
    (
        "CALL 0x0200 (3-byte, CD 00 02)",
        None,
        "CALL 0x0200",
        "CD 00 02",
    ),
    (
        "LDA 0x8000 (3-byte direct, 3A 00 80)",
        None,
        "LDA 0x8000",
        "3A 00 80",
    ),
    (
        "STA 0x4000 (3-byte direct, 32 00 40)",
        None,
        "STA 0x4000",
        "32 00 40",
    ),
    (
        "CPI 0xFF (2-byte imm, FE FF)",
        None,
        "CPI 0xFF",
        "FE FF",
    ),
    (
        "PUSH BC (1-byte pair, C5)",
        None,
        "PUSH B",
        "C5",
    ),
    (
        "POP DE (1-byte pair, D1)",
        None,
        "POP D",
        "D1",
    ),
    (
        "XCHG (1-byte implied, EB)",
        None,
        "XCHG",
        "EB",
    ),
]


def find_project_root():
    p = Path(__file__).resolve()
    for parent in [p] + list(p.parents):
        if (parent / "design").is_dir():
            return parent
    return Path.cwd()


def extract_text_section(elf_data):
    """Extract .text section bytes from ELF32 data."""
    shoff = struct.unpack_from('<I', elf_data, 32)[0]
    shentsize = struct.unpack_from('<H', elf_data, 46)[0]
    shnum = struct.unpack_from('<H', elf_data, 48)[0]
    shstrndx = struct.unpack_from('<H', elf_data, 50)[0]

    strtab_base = shoff + shstrndx * shentsize
    strtab_off = struct.unpack_from('<I', elf_data, strtab_base + 16)[0]

    for i in range(shnum):
        base = shoff + i * shentsize
        name_idx = struct.unpack_from('<I', elf_data, base)[0]
        sh_type = struct.unpack_from('<I', elf_data, base + 4)[0]
        sh_offset = struct.unpack_from('<I', elf_data, base + 16)[0]
        sh_size = struct.unpack_from('<I', elf_data, base + 20)[0]

        name_end = elf_data.index(b'\x00', strtab_off + name_idx)
        name = elf_data[strtab_off + name_idx:name_end].decode('ascii')

        if name == '.text' and sh_type == 1:  # SHT_PROGBITS
            return elf_data[sh_offset:sh_offset + sh_size]

    return None


def assemble_reference(v6asm, asm_text, tmpdir):
    """Assemble reference code with v6asm and return bytes."""
    asm_path = os.path.join(tmpdir, "ref.s")
    bin_path = os.path.join(tmpdir, "ref.bin")
    with open(asm_path, 'w') as f:
        f.write(asm_text + "\n")
    result = subprocess.run(
        [str(v6asm), asm_path, "-o", bin_path],
        capture_output=True, text=True, timeout=10
    )
    if result.returncode != 0:
        return None, f"v6asm failed: {result.stderr}"
    with open(bin_path, 'rb') as f:
        return f.read(), ""


def compile_ir(llc, ir_text, tmpdir):
    """Compile LLVM IR with llc and return .text section bytes."""
    ir_path = os.path.join(tmpdir, "test.ll")
    obj_path = os.path.join(tmpdir, "test.o")
    with open(ir_path, 'w') as f:
        f.write(ir_text + "\n")
    result = subprocess.run(
        [str(llc), "-march=v6clang", "-mtriple=i8080-unknown-v6clang",
         "-filetype=obj", ir_path, "-o", obj_path],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        return None, f"llc failed: {result.stderr}"
    with open(obj_path, 'rb') as f:
        elf_data = f.read()
    text = extract_text_section(elf_data)
    if text is None:
        return None, "No .text section found"
    return text, ""


def main():
    root = find_project_root()
    parser = argparse.ArgumentParser(description='Verify V6CLANG binary encoding')
    parser.add_argument('--llc', default=str(root / "llvm-build" / "bin" / "llc.exe"))
    parser.add_argument('--v6asm', default=os.environ.get("V6ASM"),
                        help="Path to the separately installed v6asm executable")
    args = parser.parse_args()

    if not args.v6asm:
        parser.error("specify --v6asm or set V6ASM to the separately installed v6asm executable")

    passed = 0
    failed = 0
    skipped = 0

    with tempfile.TemporaryDirectory() as tmpdir:
        for desc, ir_text, asm_text, expected_hex in TEST_CASES:
            expected_bytes = bytes.fromhex(expected_hex.replace(' ', ''))

            # Test v6asm reference
            ref_bytes, err = assemble_reference(args.v6asm, asm_text, tmpdir)
            if ref_bytes is None:
                print(f"  SKIP (v6asm): {desc} — {err}")
                skipped += 1
                continue
            if ref_bytes != expected_bytes:
                print(f"  FAIL (v6asm mismatch): {desc}")
                print(f"    expected: {expected_hex}")
                print(f"    got:      {' '.join(f'{b:02X}' for b in ref_bytes)}")
                failed += 1
                continue

            # If we have IR, also test llc
            if ir_text is not None:
                llc_bytes, err = compile_ir(args.llc, ir_text, tmpdir)
                if llc_bytes is None:
                    print(f"  FAIL (llc): {desc} — {err}")
                    failed += 1
                    continue
                if llc_bytes != expected_bytes:
                    print(f"  FAIL (llc mismatch): {desc}")
                    print(f"    expected: {expected_hex}")
                    print(f"    got:      {' '.join(f'{b:02X}' for b in llc_bytes)}")
                    failed += 1
                    continue
                print(f"  PASS (llc+v6asm): {desc}")
            else:
                print(f"  PASS (v6asm only): {desc}")
            passed += 1

    print(f"\n{passed} passed, {failed} failed, {skipped} skipped")
    return 0 if failed == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
