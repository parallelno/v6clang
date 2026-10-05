#!/usr/bin/env python3
"""
Golden test runner for the Vector 06c LLVM backend project.

Assembles .asm files with v6asm, executes in v6emul with --halt-exit,
and checks results against expected values declared in test file comments.

Test header format:
    ; TEST: <name>
    ; DESC: <description>
    ; EXPECT_HALT: yes
    ; EXPECT_OUTPUT: <val1>, <val2>, ...   (decimal, from OUT 0xED)
    ; EXPECT_REG: A=<hex> [B=<hex>] ...
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def find_project_root():
    """Find the project root by looking for the design/ directory."""
    p = Path(__file__).resolve()
    for parent in [p] + list(p.parents):
        if (parent / "design").is_dir():
            return parent
    return Path.cwd()


def parse_test_header(asm_path):
    """Parse expected values from test file comments."""
    header = {
        "name": Path(asm_path).stem,
        "desc": "",
        "expect_halt": False,
        "expect_output": [],
        "expect_regs": {},
    }
    with open(asm_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith(";"):
                if line and not line.startswith("//"):
                    break
                continue
            line = line.lstrip("; ").strip()
            if line.startswith("TEST:"):
                header["name"] = line.split(":", 1)[1].strip()
            elif line.startswith("DESC:"):
                header["desc"] = line.split(":", 1)[1].strip()
            elif line.startswith("EXPECT_HALT:"):
                header["expect_halt"] = line.split(":", 1)[1].strip().lower() == "yes"
            elif line.startswith("EXPECT_OUTPUT:"):
                vals = line.split(":", 1)[1].strip()
                header["expect_output"] = [int(v.strip()) for v in vals.split(",") if v.strip()]
            elif line.startswith("EXPECT_REG:"):
                regs_str = line.split(":", 1)[1].strip()
                for pair in regs_str.split():
                    if "=" in pair:
                        reg, val = pair.split("=", 1)
                        header["expect_regs"][reg.upper()] = int(val, 16)
    return header


def assemble(v6asm, asm_path, bin_path):
    """Assemble an .asm file to a flat binary."""
    result = subprocess.run(
        [str(v6asm), str(asm_path), "-o", str(bin_path)],
        capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0:
        return False, f"Assembly failed:\n{result.stdout}\n{result.stderr}"
    return True, ""


def run_emulator(v6emul, bin_path):
    """Run a binary in v6emul with --halt-exit and --dump-cpu."""
    result = subprocess.run(
        [str(v6emul), "--rom", str(bin_path), "--load-addr", "0",
         "--halt-exit", "--dump-cpu"],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout, result.stderr, result.returncode


def parse_emulator_output(stdout):
    """Parse v6emul output into structured data."""
    data = {
        "halted": False,
        "pc": 0,
        "cycles": 0,
        "test_outputs": [],
        "regs": {},
    }

    for line in stdout.splitlines():
        line = line.strip()

        # Parse test output: TEST_OUT port=0xED value=0xNN or value=NN
        m = re.match(r"TEST_OUT\s+port=0x[Ee][Dd]\s+value=(?:0x([0-9A-Fa-f]+)|(\d+))", line)
        if m:
            if m.group(1) is not None:
                data["test_outputs"].append(int(m.group(1), 16))
            else:
                data["test_outputs"].append(int(m.group(2)))
            continue

        # Parse halt line: HALT at PC=0xXXXX after N cpu_cycles M frames
        m = re.match(r"HALT\s+at\s+PC=0x([0-9A-Fa-f]+)\s+after\s+(\d+)\s+cpu_cycles", line)
        if m:
            data["halted"] = True
            data["pc"] = int(m.group(1), 16)
            data["cycles"] = int(m.group(2))
            continue

        # Parse CPU state: CPU: A=XX F=XX B=XX C=XX D=XX E=XX H=XX L=XX
        m = re.match(r"CPU:\s+A=([0-9A-Fa-f]+)\s+F=([0-9A-Fa-f]+)\s+"
                     r"B=([0-9A-Fa-f]+)\s+C=([0-9A-Fa-f]+)\s+"
                     r"D=([0-9A-Fa-f]+)\s+E=([0-9A-Fa-f]+)\s+"
                     r"H=([0-9A-Fa-f]+)\s+L=([0-9A-Fa-f]+)", line)
        if m:
            data["regs"]["A"] = int(m.group(1), 16)
            data["regs"]["F"] = int(m.group(2), 16)
            data["regs"]["B"] = int(m.group(3), 16)
            data["regs"]["C"] = int(m.group(4), 16)
            data["regs"]["D"] = int(m.group(5), 16)
            data["regs"]["E"] = int(m.group(6), 16)
            data["regs"]["H"] = int(m.group(7), 16)
            data["regs"]["L"] = int(m.group(8), 16)
            continue

        # Parse SP/CC line:      PC=XXXX SP=XXXX CC=N
        m = re.match(r"\s*PC=([0-9A-Fa-f]+)\s+SP=([0-9A-Fa-f]+)\s+CC=(\d+)", line)
        if m:
            data["regs"]["PC"] = int(m.group(1), 16)
            data["regs"]["SP"] = int(m.group(2), 16)
            data["cycles"] = int(m.group(3))
            continue

    return data


def check_expectations(header, emu_data):
    """Check emulator output against expected values. Returns (pass, errors)."""
    errors = []

    if header["expect_halt"] and not emu_data["halted"]:
        errors.append("Expected HALT but program did not halt")

    if header["expect_output"]:
        expected = header["expect_output"]
        actual = emu_data["test_outputs"]
        if len(expected) != len(actual):
            errors.append(
                f"Output count mismatch: expected {len(expected)}, got {len(actual)}\n"
                f"  Expected: {expected}\n"
                f"  Actual:   {actual}"
            )
        else:
            for i, (exp, act) in enumerate(zip(expected, actual)):
                if exp != act:
                    errors.append(f"Output [{i}]: expected {exp}, got {act}")

    if header["expect_regs"]:
        for reg, expected_val in header["expect_regs"].items():
            actual_val = emu_data["regs"].get(reg)
            if actual_val is None:
                errors.append(f"Register {reg}: not found in emulator output")
            elif expected_val != actual_val:
                errors.append(
                    f"Register {reg}: expected 0x{expected_val:02X}, got 0x{actual_val:02X}"
                )

    return len(errors) == 0, errors


def run_test(v6asm, v6emul, asm_path, tmp_dir, verbose=False):
    """Run a single golden test. Returns (pass, name, message)."""
    header = parse_test_header(asm_path)
    name = header["name"]

    # Assemble
    bin_path = os.path.join(tmp_dir, Path(asm_path).stem + ".bin")
    ok, err_msg = assemble(v6asm, asm_path, bin_path)
    if not ok:
        return False, name, f"ASSEMBLE FAIL: {err_msg}"

    # Run in emulator
    stdout, stderr, rc = run_emulator(v6emul, bin_path)
    if verbose:
        print(f"  [emulator stdout] {stdout.strip()}")

    # Parse output
    emu_data = parse_emulator_output(stdout)

    # Check expectations
    passed, errors = check_expectations(header, emu_data)
    if passed:
        return True, name, f"OK ({emu_data['cycles']}cc)"
    else:
        return False, name, "\n".join(f"  FAIL: {e}" for e in errors)


def main():
    parser = argparse.ArgumentParser(description="Run golden test suite")
    parser.add_argument("--v6asm", default=None, help="Path to v6asm executable")
    parser.add_argument("--v6emul", default=None, help="Path to v6emul executable")
    parser.add_argument("--test-dir", default=None, help="Path to golden test directory")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show emulator output")
    parser.add_argument("tests", nargs="*", help="Specific test files to run (default: all)")
    args = parser.parse_args()

    root = find_project_root()

    # Resolve tool paths
    v6asm = args.v6asm or os.environ.get("V6ASM")
    v6emul = args.v6emul or os.environ.get("V6EMUL")
    test_dir = args.test_dir or str(root / "tests" / "golden")

    # Check tools exist
    if not v6asm:
        print("ERROR: specify --v6asm or set V6ASM to the separately installed v6asm executable", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(v6asm):
        # Try without .exe on non-Windows
        v6asm_noext = v6asm.replace(".exe", "")
        if os.path.isfile(v6asm_noext):
            v6asm = v6asm_noext
        else:
            print(f"ERROR: v6asm not found at {v6asm}", file=sys.stderr)
            sys.exit(1)

    if not v6emul:
        print("ERROR: specify --v6emul or set V6EMUL to the separately installed v6emul executable", file=sys.stderr)
        sys.exit(1)
    if not os.path.isfile(v6emul):
        v6emul_noext = v6emul.replace(".exe", "")
        if os.path.isfile(v6emul_noext):
            v6emul = v6emul_noext
        else:
            print(f"ERROR: v6emul not found at {v6emul}", file=sys.stderr)
            sys.exit(1)

    # Collect test files
    if args.tests:
        test_files = [os.path.abspath(t) for t in args.tests]
    else:
        test_files = sorted(
            str(p) for p in Path(test_dir).glob("*.asm")
        )

    if not test_files:
        print("No test files found.", file=sys.stderr)
        sys.exit(1)

    print(f"Running {len(test_files)} golden tests...")
    print(f"  v6asm:  {v6asm}")
    print(f"  v6emul: {v6emul}")
    print()

    passed = 0
    failed = 0
    results = []

    with tempfile.TemporaryDirectory(prefix="v6clang_golden_") as tmp_dir:
        for asm_path in test_files:
            ok, name, message = run_test(v6asm, v6emul, asm_path, tmp_dir, args.verbose)
            if ok:
                passed += 1
                print(f"  PASS: {name} - {message}")
            else:
                failed += 1
                print(f"  FAIL: {name}")
                print(message)
            results.append((ok, name, message))

    print()
    print(f"Results: {passed} passed, {failed} failed, {passed + failed} total")

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
