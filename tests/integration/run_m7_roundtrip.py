#!/usr/bin/env python3
"""Emulator round-trip tests for M7 (i16 & i32 operations).

Compiles LLVM IR functions with llc, wraps them with a startup stub,
assembles with v6asm, executes in v6emul, and verifies OUT 0xED output.

Pipeline: LLVM IR → llc (asm) → strip directives + prepend startup → v6asm → v6emul → verify

Usage:
    python run_m7_roundtrip.py [--llc PATH] [--v6asm PATH] [--v6emul PATH] [-v]
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def find_project_root():
    p = Path(__file__).resolve()
    for parent in [p] + list(p.parents):
        if (parent / "design").is_dir():
            return parent
    return Path.cwd()


ROOT = find_project_root()
DEFAULT_LLC = ROOT / "llvm-build" / "bin" / "llc.exe"
DEFAULT_V6ASM = os.environ.get("V6ASM")
DEFAULT_V6EMUL = os.environ.get("V6EMUL")


def compile_ir_to_asm(llc, ir_text):
    """Compile LLVM IR string to 8080 assembly via llc. Returns asm text."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".ll", delete=False) as f:
        f.write(ir_text)
        f.flush()
        ir_path = f.name
    try:
        result = subprocess.run(
            [str(llc), "-mtriple=i8080-unknown-v6clang", "-O2", ir_path, "-o", "-"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(f"llc failed:\n{result.stderr}")
        return result.stdout
    finally:
        os.unlink(ir_path)


def strip_llc_directives(asm_text):
    """Strip LLVM directives from llc output, keeping labels and instructions.

    Removes: .text, .globl, ; -- Begin/End function, ; %bb.N:, ; @label comments
    Keeps: labels (e.g. add16:), instructions, blank lines between functions.
    """
    lines = asm_text.split("\n")
    result = []
    for line in lines:
        stripped = line.strip()
        # Skip assembler directives
        if stripped.startswith(".text") or stripped.startswith(".globl"):
            continue
        # Skip LLVM function boundary markers
        if stripped.startswith("; -- "):
            continue
        # Skip basic block comments
        if stripped.startswith("; %bb"):
            continue
        # Strip trailing comments like "; @add16" from label lines
        if ":" in stripped and stripped.startswith(";") is False:
            stripped = re.sub(r'\s*;.*$', '', stripped)
        # Skip empty lines
        if not stripped:
            continue
        result.append("    " + stripped if not stripped.endswith(":") else stripped)
    return "\n".join(result)


def build_test_program(func_asm, call_sequence):
    """Build a complete asm program with startup stub.

    func_asm: cleaned assembly text of all functions (labels + instructions)
    call_sequence: list of (func_name, setup_asm, output_regs)
        setup_asm: assembly to set up arguments before CALL
        output_regs: list of register names to OUT 0xED after CALL
    """
    parts = [
        "    .org 0",
        "    LXI SP, 0xFFFF",
    ]
    for func_name, setup_asm, output_regs in call_sequence:
        if setup_asm:
            parts.append(setup_asm)
        parts.append(f"    CALL {func_name}")
        for reg in output_regs:
            if reg != "A":
                parts.append(f"    MOV A, {reg}")
            parts.append("    OUT 0xED")
    parts.append("    HLT")
    parts.append("")
    parts.append(func_asm)
    return "\n".join(parts)


def assemble_and_run(v6asm, v6emul, asm_text):
    """Assemble and run, return list of output byte values."""
    with tempfile.TemporaryDirectory() as tmpdir:
        asm_path = os.path.join(tmpdir, "test.asm")
        bin_path = os.path.join(tmpdir, "test.bin")
        with open(asm_path, "w") as f:
            f.write(asm_text)

        # Assemble
        result = subprocess.run(
            [str(v6asm), asm_path, "-o", bin_path],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"v6asm failed (rc={result.returncode}):\n"
                f"stderr: {result.stderr}\nstdout: {result.stdout}\n"
                f"--- ASM ---\n{asm_text}"
            )

        # Run in emulator
        result = subprocess.run(
            [str(v6emul), "--rom", bin_path, "--load-addr", "0",
             "--halt-exit", "--dump-cpu"],
            capture_output=True, text=True, timeout=10,
        )
        # v6emul may return non-zero on HLT; check for output regardless
        output_text = result.stdout + "\n" + result.stderr

        # Parse output values: TEST_OUT port=0xED value=0xNN
        outputs = []
        for line in output_text.split("\n"):
            m = re.search(r"TEST_OUT port=0xED value=0x([0-9A-Fa-f]+)", line)
            if m:
                outputs.append(int(m.group(1), 16))
        return outputs


# ============================================================
# Test definitions
# ============================================================

TESTS = []


def test(name, ir, call_specs, expected):
    """Register a test case.

    name: descriptive test name
    ir: LLVM IR string (single function)
    call_specs: list of (func_name, setup_asm, output_regs)
    expected: list of expected byte values from OUT 0xED
    """
    TESTS.append((name, ir, call_specs, expected))


# --- i16 ALU: add, sub, and, or, xor ---

test(
    "add_i16",
    "define i16 @add16(i16 %a, i16 %b) {\n  %r = add i16 %a, %b\n  ret i16 %r\n}\n",
    [("add16", "    LXI H, 0x1234\n    LXI D, 0x0111", ["L", "H"])],
    [0x45, 0x13],  # 0x1234 + 0x0111 = 0x1345
)

test(
    "add_i16_carry",
    "define i16 @add16c(i16 %a, i16 %b) {\n  %r = add i16 %a, %b\n  ret i16 %r\n}\n",
    [("add16c", "    LXI H, 0x00FF\n    LXI D, 0x0001", ["L", "H"])],
    [0x00, 0x01],  # 0x00FF + 0x0001 = 0x0100
)

test(
    "sub_i16",
    "define i16 @sub16(i16 %a, i16 %b) {\n  %r = sub i16 %a, %b\n  ret i16 %r\n}\n",
    [("sub16", "    LXI H, 0x1345\n    LXI D, 0x0111", ["L", "H"])],
    [0x34, 0x12],  # 0x1345 - 0x0111 = 0x1234
)

test(
    "and_i16",
    "define i16 @and16(i16 %a, i16 %b) {\n  %r = and i16 %a, %b\n  ret i16 %r\n}\n",
    [("and16", "    LXI H, 0xFF0F\n    LXI D, 0x0FFF", ["L", "H"])],
    [0x0F, 0x0F],  # 0xFF0F & 0x0FFF = 0x0F0F
)

test(
    "or_i16",
    "define i16 @or16(i16 %a, i16 %b) {\n  %r = or i16 %a, %b\n  ret i16 %r\n}\n",
    [("or16", "    LXI H, 0xF000\n    LXI D, 0x000F", ["L", "H"])],
    [0x0F, 0xF0],  # 0xF000 | 0x000F = 0xF00F
)

test(
    "xor_i16",
    "define i16 @xor16(i16 %a, i16 %b) {\n  %r = xor i16 %a, %b\n  ret i16 %r\n}\n",
    [("xor16", "    LXI H, 0xFFFF\n    LXI D, 0x0F0F", ["L", "H"])],
    [0xF0, 0xF0],  # 0xFFFF ^ 0x0F0F = 0xF0F0
)

# --- i16 shifts: shl, lshr, ashr ---

test(
    "shl1_i16",
    "define i16 @shl1(i16 %a) {\n  %r = shl i16 %a, 1\n  ret i16 %r\n}\n",
    [("shl1", "    LXI H, 0x4080", ["L", "H"])],
    [0x00, 0x81],  # 0x4080 << 1 = 0x8100
)

test(
    "shl8_i16",
    "define i16 @shl8(i16 %a) {\n  %r = shl i16 %a, 8\n  ret i16 %r\n}\n",
    [("shl8", "    LXI H, 0x0042", ["L", "H"])],
    [0x00, 0x42],  # 0x0042 << 8 = 0x4200
)

test(
    "srl1_i16",
    "define i16 @srl1(i16 %a) {\n  %r = lshr i16 %a, 1\n  ret i16 %r\n}\n",
    [("srl1", "    LXI H, 0x8100", ["L", "H"])],
    [0x80, 0x40],  # 0x8100 >> 1 = 0x4080
)

test(
    "srl8_i16",
    "define i16 @srl8(i16 %a) {\n  %r = lshr i16 %a, 8\n  ret i16 %r\n}\n",
    [("srl8", "    LXI H, 0x4200", ["L", "H"])],
    [0x42, 0x00],  # 0x4200 >> 8 = 0x0042
)

test(
    "sra1_i16_positive",
    "define i16 @sra1p(i16 %a) {\n  %r = ashr i16 %a, 1\n  ret i16 %r\n}\n",
    [("sra1p", "    LXI H, 0x4080", ["L", "H"])],
    [0x40, 0x20],  # 0x4080 >>> 1 = 0x2040 (positive, sign=0)
)

test(
    "sra1_i16_negative",
    "define i16 @sra1n(i16 %a) {\n  %r = ashr i16 %a, 1\n  ret i16 %r\n}\n",
    [("sra1n", "    LXI H, 0x8100", ["L", "H"])],
    [0x80, 0xC0],  # 0x8100 >>> 1 = 0xC080 (negative, sign-extended)
)

test(
    "sra8_i16_negative",
    "define i16 @sra8n(i16 %a) {\n  %r = ashr i16 %a, 8\n  ret i16 %r\n}\n",
    [("sra8n", "    LXI H, 0x8042", ["L", "H"])],
    [0x80, 0xFF],  # 0x8042 >>> 8 = 0xFF80 (sign-extended)
)


def run_tests(llc, v6asm, v6emul, verbose=False):
    passed = 0
    failed = 0
    errors = []

    for name, ir, call_specs, expected in TESTS:
        try:
            # Compile LLVM IR to assembly
            asm_text = compile_ir_to_asm(llc, ir)

            # Strip LLVM directives, keep only labels and instructions
            func_asm = strip_llc_directives(asm_text)

            if not func_asm.strip():
                raise RuntimeError(f"Empty function body from llc:\n{asm_text}")

            # Build complete program with startup stub
            program = build_test_program(func_asm, call_specs)

            if verbose:
                print(f"\n--- {name} ---")
                print(program)
                print("---")

            # Assemble and run
            outputs = assemble_and_run(v6asm, v6emul, program)

            if outputs == expected:
                passed += 1
                print(f"  PASS: {name}")
            else:
                failed += 1
                msg = (
                    f"  FAIL: {name}\n"
                    f"    Expected: {[hex(v) for v in expected]}\n"
                    f"    Got:      {[hex(v) for v in outputs]}"
                )
                errors.append(msg)
                print(msg)

        except Exception as e:
            failed += 1
            msg = f"  ERROR: {name} -- {e}"
            errors.append(msg)
            print(msg)

    # Summary
    total = passed + failed
    print(f"\nM7 Round-Trip Tests: {passed}/{total} passed, {failed} failed")
    return failed == 0


def main():
    parser = argparse.ArgumentParser(description="M7 emulator round-trip tests")
    parser.add_argument("--llc", default=str(DEFAULT_LLC))
    parser.add_argument("--v6asm", default=DEFAULT_V6ASM,
                        help="Path to the separately installed v6asm executable")
    parser.add_argument("--v6emul", default=DEFAULT_V6EMUL,
                        help="Path to the separately installed v6emul executable")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    # Verify tools exist
    for tool_name, tool_path in [("llc", args.llc), ("v6asm", args.v6asm), ("v6emul", args.v6emul)]:
        if not tool_path or not Path(tool_path).is_file():
            if tool_name in ("v6asm", "v6emul") and not tool_path:
                print(f"ERROR: specify --{tool_name} or set {tool_name.upper()} to the separately installed {tool_name} executable")
            else:
                print(f"ERROR: {tool_name} not found at {tool_path}")
            sys.exit(1)

    ok = run_tests(args.llc, args.v6asm, args.v6emul, args.verbose)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
