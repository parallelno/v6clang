#!/usr/bin/env python3
"""Emulator round-trip tests for M11 (runtime library integration).

Compiles LLVM IR with llc, combines the output with runtime library
functions, assembles with v6asm, and runs in v6emul to verify that
compiler-emitted libcalls produce correct results.

Pipeline: LLVM IR -> llc (asm) -> combine with runtime -> v6asm -> v6emul -> verify

Usage:
    python run_m11_integration.py [--llc PATH] [--v6emul PATH] [-v]
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
RUNTIME_DIR = ROOT / "compiler-rt" / "lib" / "builtins" / "v6clang"


def compile_ir_to_asm(llc, ir_text):
    """Compile LLVM IR string to assembly via llc."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".ll", delete=False) as f:
        f.write(ir_text)
        f.flush()
        ir_path = f.name
    try:
        result = subprocess.run(
            [str(llc), "-mtriple=i8080-unknown-v6clang", "-O2",
             ir_path, "-o", "-"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(f"llc failed:\n{result.stderr}")
        return result.stdout
    finally:
        os.unlink(ir_path)


def strip_asm(asm_text):
    """Strip LLVM directives from llc output, keep only instructions/labels."""
    lines = asm_text.split("\n")
    result = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith(".text") or stripped.startswith(".globl"):
            continue
        if stripped.startswith("; -- ") or stripped.startswith("; %bb"):
            continue
        if ":" in stripped and not stripped.startswith(";"):
            stripped = re.sub(r'\s*;.*$', '', stripped)
        result.append("    " + stripped if not stripped.endswith(":") else stripped)
    return "\n".join(result)


def read_runtime_file(name):
    """Read a runtime library source file, stripping .globl directives."""
    path = RUNTIME_DIR / name
    with open(path, "r") as f:
        text = f.read()
    lines = text.split("\n")
    result = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(".globl"):
            continue
        if stripped.startswith(";") and not stripped.startswith("; ---"):
            continue
        result.append(line)
    return "\n".join(result)


def run_binary(v6emul, bin_path, load_addr=0):
    """Run binary in v6emul, return list of output values."""
    result = subprocess.run(
        [str(v6emul), "--rom", str(bin_path), "--load-addr", str(load_addr),
         "--halt-exit", "--dump-cpu"],
        capture_output=True, text=True, timeout=10,
    )
    output_text = result.stdout + "\n" + result.stderr
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

IR_HEADER = (
    'target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"\n'
    'target triple = "i8080-unknown-v6clang"\n\n'
)


def test(name, ir_text, startup_asm, runtime_files, expected_outputs):
    """Register a test case."""
    TESTS.append((name, ir_text, startup_asm, runtime_files, expected_outputs))


# ------ Test: i8 and i16 multiplication ------
test(
    "multiply",
    IR_HEADER + """\
define i16 @mul16(i16 %a, i16 %b) {
  %r = mul i16 %a, %b
  ret i16 %r
}

define i8 @mul8(i8 %a, i8 %b) {
  %r = mul i8 %a, %b
  ret i8 %r
}
""",
    """\
    .org 0
    LXI SP, 0xFFFF

    ; mul16(10, 20) = 200
    LXI H, 10
    LXI D, 20
    CALL mul16
    MOV A, L
    OUT 0xED            ; expect 200

    ; mul16(100, 100) = 10000 = 0x2710
    LXI H, 100
    LXI D, 100
    CALL mul16
    MOV A, L
    OUT 0xED            ; expect 0x10 = 16 (low byte)
    MOV A, H
    OUT 0xED            ; expect 0x27 = 39 (high byte)

    ; mul8(7, 6) = 42
    MVI A, 7
    MVI E, 6
    CALL mul8
    OUT 0xED            ; expect 42

    HLT
""",
    ["mulhi3.s"],
    [200, 16, 39, 42],
)


# ------ Test: signed and unsigned division/modulo ------
test(
    "divide",
    IR_HEADER + """\
define i16 @sdiv16(i16 %a, i16 %b) {
  %r = sdiv i16 %a, %b
  ret i16 %r
}

define i16 @udiv16(i16 %a, i16 %b) {
  %r = udiv i16 %a, %b
  ret i16 %r
}

define i16 @srem16(i16 %a, i16 %b) {
  %r = srem i16 %a, %b
  ret i16 %r
}

define i16 @urem16(i16 %a, i16 %b) {
  %r = urem i16 %a, %b
  ret i16 %r
}
""",
    """\
    .org 0
    LXI SP, 0xFFFF

    ; sdiv16(10, 3) = 3
    LXI H, 10
    LXI D, 3
    CALL sdiv16
    MOV A, L
    OUT 0xED            ; expect 3

    ; sdiv16(-10, 3) = -3, low byte = 0xFD = 253
    LXI H, 0xFFF6      ; -10
    LXI D, 3
    CALL sdiv16
    MOV A, L
    OUT 0xED            ; expect 253

    ; udiv16(100, 7) = 14
    LXI H, 100
    LXI D, 7
    CALL udiv16
    MOV A, L
    OUT 0xED            ; expect 14

    ; srem16(10, 3) = 1
    LXI H, 10
    LXI D, 3
    CALL srem16
    MOV A, L
    OUT 0xED            ; expect 1

    ; urem16(100, 7) = 2
    LXI H, 100
    LXI D, 7
    CALL urem16
    MOV A, L
    OUT 0xED            ; expect 2

    HLT
""",
    ["udivhi3.s", "divhi3.s"],
    [3, 253, 14, 1, 2],
)


# ------ Test: variable-count shifts ------
test(
    "shift_var",
    IR_HEADER + """\
define i16 @shl16(i16 %a, i16 %n) {
  %r = shl i16 %a, %n
  ret i16 %r
}

define i16 @lshr16(i16 %a, i16 %n) {
  %r = lshr i16 %a, %n
  ret i16 %r
}

define i16 @ashr16(i16 %a, i16 %n) {
  %r = ashr i16 %a, %n
  ret i16 %r
}
""",
    """\
    .org 0
    LXI SP, 0xFFFF

    ; shl16(1, 8) = 256 = 0x0100
    LXI H, 1
    LXI D, 8
    CALL shl16
    MOV A, L
    OUT 0xED            ; expect 0
    MOV A, H
    OUT 0xED            ; expect 1

    ; lshr16(0x8000, 15) = 1
    LXI H, 0x8000
    LXI D, 15
    CALL lshr16
    MOV A, L
    OUT 0xED            ; expect 1

    ; ashr16(-256, 4) = -16 = 0xFFF0
    LXI H, 0xFF00      ; -256
    LXI D, 4
    CALL ashr16
    MOV A, L
    OUT 0xED            ; expect 0xF0 = 240
    MOV A, H
    OUT 0xED            ; expect 0xFF = 255

    HLT
""",
    ["shift.s"],
    [0, 1, 1, 240, 255],
)


# ------ Test: memcpy from C ------
test(
    "memcpy_c",
    IR_HEADER + """\
define void @do_copy(ptr %dst, ptr %src, i16 %n) {
  call void @llvm.memcpy.p0.p0.i16(ptr %dst, ptr %src, i16 %n, i1 false)
  ret void
}

declare void @llvm.memcpy.p0.p0.i16(ptr, ptr, i16, i1)
""",
    """\
    .org 0
    LXI SP, 0xFFFF

    ; do_copy(_dst, _src, 4)
    LXI H, _dst
    LXI D, _src
    LXI B, 4
    CALL do_copy

    ; Verify copied bytes
    LXI H, _dst
    MOV A, M
    OUT 0xED            ; expect 10
    INX H
    MOV A, M
    OUT 0xED            ; expect 20
    INX H
    MOV A, M
    OUT 0xED            ; expect 30
    INX H
    MOV A, M
    OUT 0xED            ; expect 40

    HLT

_src:
    .db 10, 20, 30, 40
_dst:
    .db 0, 0, 0, 0
""",
    ["memory.s"],
    [10, 20, 30, 40],
)


def run_tests(llc, v6asm, v6emul, verbose=False):
    """Run all registered tests."""
    passed = 0
    failed = 0
    errors = 0

    for name, ir_text, startup_asm, runtime_files, expected in TESTS:
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                # 1. Compile IR to assembly
                asm_text = compile_ir_to_asm(llc, ir_text)
                stripped = strip_asm(asm_text)

                if verbose:
                    print(f"\n  --- {name} llc output ---")
                    print(asm_text[:500])

                # 2. Read runtime library functions
                runtime_asm = ""
                for rt_file in runtime_files:
                    runtime_asm += "\n" + read_runtime_file(rt_file)

                # 3. Combine: startup + compiled code + runtime library
                combined = startup_asm + "\n" + stripped + "\n" + runtime_asm

                # 4. Assemble with v6asm
                asm_path = os.path.join(tmpdir, "test.asm")
                bin_path = os.path.join(tmpdir, "test.bin")
                with open(asm_path, "w") as f:
                    f.write(combined)

                r = subprocess.run(
                    [str(v6asm), asm_path, "-o", bin_path],
                    capture_output=True, text=True, timeout=30,
                )
                if r.returncode != 0:
                    raise RuntimeError(
                        f"v6asm failed:\nstderr: {r.stderr}\n"
                        f"--- Combined ASM ---\n{combined}"
                    )

                # 5. Run in emulator
                outputs = run_binary(v6emul, bin_path, load_addr=0)

                if outputs == expected:
                    passed += 1
                    print(f"  PASS: {name}")
                else:
                    failed += 1
                    print(f"  FAIL: {name} - expected={expected}, got={outputs}")
                    if verbose:
                        print(f"    --- Combined ASM ---\n{combined[:1000]}")

        except Exception as e:
            errors += 1
            print(f"  ERROR: {name}: {e}")

    return passed, failed, errors


def main():
    parser = argparse.ArgumentParser(
        description="M11 runtime library integration tests")
    parser.add_argument("--llc", default=str(DEFAULT_LLC))
    parser.add_argument("--v6asm", default=DEFAULT_V6ASM,
                        help="Path to the separately installed v6asm executable")
    parser.add_argument("--v6emul", default=DEFAULT_V6EMUL,
                        help="Path to the separately installed v6emul executable")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    print("M11 Runtime Integration Tests")
    print(f"  llc:    {args.llc}")
    print(f"  v6asm:  {args.v6asm}")
    print(f"  v6emul: {args.v6emul}")
    print()

    for tool_name, tool_path in [("llc", args.llc), ("v6asm", args.v6asm),
                                 ("v6emul", args.v6emul)]:
        if not tool_path or not Path(tool_path).is_file():
            if tool_name in ("v6asm", "v6emul") and not tool_path:
                print(f"ERROR: specify --{tool_name} or set {tool_name.upper()} to the separately installed {tool_name} executable")
            else:
                print(f"ERROR: {tool_name} not found at {tool_path}")
            sys.exit(1)

    passed, failed, errors = run_tests(args.llc, args.v6asm, args.v6emul,
                                       args.verbose)

    print(f"\nResults: {passed} passed, {failed} failed, {errors} errors "
          f"/ {len(TESTS)} total")

    if failed > 0 or errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
