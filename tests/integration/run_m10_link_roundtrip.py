#!/usr/bin/env python3
"""Emulator round-trip tests for M10 (multi-file linking).

Compiles multiple LLVM IR files with llc, links them with ld.lld
(to validate cross-object relocations), and runs the resulting binary in
v6emul to verify correct cross-file symbol resolution and execution.

Because V6CLANG has no MC AsmParser, the startup stub cannot be assembled to
ELF and prepended via the linker. We use a hybrid path: ld.lld validates
the .o files link cleanly, then the IR is recompiled to text asm, stripped
of directives, prepended with a startup wrapper, and assembled with v6asm
for execution in v6emul.

Pipeline: LLVM IR → llc (obj) → ld.lld (validate) → v6asm hybrid → v6emul

Usage:
    python run_m10_link_roundtrip.py [--llc PATH] [--v6asm PATH] [--v6emul PATH] [-v]
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
LD_LLD = ROOT / "llvm-build" / "bin" / "ld.lld.exe"
LLVM_OBJCOPY = ROOT / "llvm-build" / "bin" / "llvm-objcopy.exe"


def compile_ir_to_obj(llc, ir_text, out_path):
    """Compile LLVM IR string to .o via llc."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".ll", delete=False) as f:
        f.write(ir_text)
        f.flush()
        ir_path = f.name
    try:
        result = subprocess.run(
            [str(llc), "-mtriple=i8080-unknown-v6clang", "-O2",
             "-filetype=obj", ir_path, "-o", out_path],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            raise RuntimeError(f"llc failed:\n{result.stderr}")
    finally:
        os.unlink(ir_path)


def compile_ir_to_asm(llc, ir_text):
    """Compile LLVM IR string to asm text via llc."""
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


def link_objects(obj_paths, out_path, base_addr=0, entry="main"):
    """Link .o files with ld.lld and convert to flat binary via llvm-objcopy."""
    elf_path = str(out_path) + ".elf"
    cmd = [str(LD_LLD), "-m", "elf32v6clang",
           f"-Ttext=0x{base_addr:04X}", "-e", entry,
           "-o", elf_path] + [str(p) for p in obj_paths]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(
            f"ld.lld failed (rc={result.returncode}):\n"
            f"stderr: {result.stderr}\nstdout: {result.stdout}"
        )
    cmd = [str(LLVM_OBJCOPY), "-O", "binary", elf_path, str(out_path)]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(
            f"llvm-objcopy failed (rc={result.returncode}):\n"
            f"stderr: {result.stderr}\nstdout: {result.stdout}"
        )


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


def test(name, ir_files, startup_asm, expected_outputs):
    """Register a test case.

    name: test name
    ir_files: list of LLVM IR strings (each becomes one .o file)
    startup_asm: 8080 asm snippet prepended before the linked code;
                 must call the entry function and OUT results
    expected_outputs: list of expected OUT 0xED values
    """
    TESTS.append((name, ir_files, startup_asm, expected_outputs))


# ------ Test: Cross-file function call ------
test(
    "cross_file_call",
    [
        # File 0: main calls helper()
        """\
define i8 @main() {
  %r = call i8 @helper(i8 41)
  ret i8 %r
}
declare i8 @helper(i8)
""",
        # File 1: helper() adds 1 to its argument
        """\
define i8 @helper(i8 %x) {
  %r = add i8 %x, 1
  ret i8 %r
}
""",
    ],
    # Startup: call main, output result via OUT 0xED
    """\
    .org 0
    LXI SP, 0xFFFF
    CALL main
    OUT 0xED
    HLT
""",
    [42],  # helper(41) = 42
)

# ------ Test: Cross-file with i16 ------
test(
    "cross_file_i16",
    [
        # File 0: calls add16 defined in file 1
        """\
define i16 @main16() {
  %r = call i16 @add16(i16 256, i16 512)
  ret i16 %r
}
declare i16 @add16(i16, i16)
""",
        # File 1: add16
        """\
define i16 @add16(i16 %a, i16 %b) {
  %r = add i16 %a, %b
  ret i16 %r
}
""",
    ],
    # Startup: call main16, output HL (result) low then high
    """\
    .org 0
    LXI SP, 0xFFFF
    CALL main16
    MOV A, L
    OUT 0xED
    MOV A, H
    OUT 0xED
    HLT
""",
    [0x00, 0x03],  # 256 + 512 = 768 = 0x0300 → L=0x00, H=0x03
)


def run_tests(llc, v6asm, v6emul, verbose=False):
    """Run all registered tests."""
    passed = 0
    failed = 0
    errors = 0

    for name, ir_files, startup_asm, expected in TESTS:
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                # Compile each IR file to .o (at base 0 since we prepend startup)
                obj_paths = []

                # We need a different approach for emulator testing:
                # 1. Compile each IR to asm
                # 2. Link the asm outputs (strip directives) with startup
                # 3. Assemble with v6asm and run

                # Actually, let's use the linker approach:
                # 1. Compile each IR to .o
                # 2. Link with v6clang_link.py at base that accounts for startup
                # 3. Prepend startup stub as a separate .o? No, simpler approach:

                # Simplest: compile all IR to asm, combine, wrap with startup,
                # then assemble with v6asm. This tests the IR compilation
                # and relies on the already-tested M7 round-trip approach.

                # For a proper linker test, let's use llc -filetype=obj + v6clang_link:
                for i, ir_text in enumerate(ir_files):
                    full_ir = (
                        f'target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"\n'
                        f'target triple = "i8080-unknown-v6clang"\n\n'
                        f'{ir_text}'
                    )
                    obj_path = os.path.join(tmpdir, f"file{i}.o")
                    compile_ir_to_obj(llc, full_ir, obj_path)
                    obj_paths.append(obj_path)

                # Validate the .o files link cleanly via ld.lld at a
                # representative base address. The execution path below
                # uses the v6asm hybrid; this call exercises ld.lld
                # cross-object relocations.
                # Pick the entry symbol from the IR (first def is main/main16).
                first_ir = ir_files[0]
                if "@main16" in first_ir:
                    entry = "main16"
                elif "@main" in first_ir:
                    entry = "main"
                else:
                    entry = "main"
                linked_bin = os.path.join(tmpdir, "linked.bin")
                link_objects(obj_paths, linked_bin,
                             base_addr=0x0100, entry=entry)

                # Now we need to prepend startup asm. The startup calls into
                # the linked code, so we need the startup at address 0 and
                # the linked code after it.
                # Approach: assemble startup + linked code together using v6asm.
                # BUT v6asm doesn't take raw binary includes easily.

                # Better: compile everything to asm, strip, and combine.
                # This tests llc asm output (already validated) + the linker
                # indirectly via symbol resolution.

                # Let's use a hybrid: compile to asm, strip directives, combine
                # with startup, assemble, and run. This is the most reliable.
                all_asm = []
                for ir_text in ir_files:
                    full_ir = (
                        f'target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"\n'
                        f'target triple = "i8080-unknown-v6clang"\n\n'
                        f'{ir_text}'
                    )
                    asm_text = compile_ir_to_asm(llc, full_ir)
                    stripped = strip_asm(asm_text)
                    all_asm.append(stripped)

                combined_asm = startup_asm + "\n" + "\n".join(all_asm)

                # Assemble with v6asm
                asm_path = os.path.join(tmpdir, "test.asm")
                bin_path = os.path.join(tmpdir, "test.bin")
                with open(asm_path, "w") as f:
                    f.write(combined_asm)

                r = subprocess.run(
                    [v6asm, asm_path, "-o", bin_path],
                    capture_output=True, text=True, timeout=30,
                )
                if r.returncode != 0:
                    raise RuntimeError(
                        f"v6asm failed:\nstderr: {r.stderr}\n"
                        f"--- ASM ---\n{combined_asm}"
                    )

                # Run in emulator
                outputs = run_binary(v6emul, bin_path, load_addr=0)

                # Also test the linker separately: link the .o files and
                # verify it produces a binary without errors.
                # (The actual execution test uses the asm approach above.)

                if outputs == expected:
                    passed += 1
                    status = "PASS"
                else:
                    failed += 1
                    status = "FAIL"

                if verbose or status == "FAIL":
                    print(f"  [{status}] {name}: expected={expected}, got={outputs}")
                else:
                    print(f"  [{status}] {name}")

                if status == "FAIL" and verbose:
                    print(f"    ASM:\n{combined_asm[:500]}")

        except Exception as e:
            errors += 1
            print(f"  [ERROR] {name}: {e}")

    return passed, failed, errors


def strip_asm(asm_text):
    """Strip LLVM directives from llc output."""
    lines = asm_text.split("\n")
    result = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(".text") or stripped.startswith(".globl"):
            continue
        if stripped.startswith("; -- ") or stripped.startswith("; %bb"):
            continue
        if not stripped:
            continue
        if ":" in stripped and not stripped.startswith(";"):
            stripped = re.sub(r'\s*;.*$', '', stripped)
        result.append("    " + stripped if not stripped.endswith(":") else stripped)
    return "\n".join(result)


def main():
    parser = argparse.ArgumentParser(
        description="M10 multi-file linking round-trip tests")
    parser.add_argument("--llc", default=str(DEFAULT_LLC))
    parser.add_argument("--v6asm", default=DEFAULT_V6ASM,
                        help="Path to the separately installed v6asm executable")
    parser.add_argument("--v6emul", default=DEFAULT_V6EMUL,
                        help="Path to the separately installed v6emul executable")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    print(f"M10 Link Round-Trip Tests")
    print(f"  llc:    {args.llc}")
    print(f"  v6asm:  {args.v6asm}")
    print(f"  v6emul: {args.v6emul}")
    print(f"  linker: {LD_LLD}")
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
