#!/usr/bin/env python3
"""
Master test runner for the Vector 06c LLVM backend project.

Runs all available test suites and reports aggregate results.
"""

import argparse
import subprocess
import sys
from pathlib import Path


def find_project_root():
    p = Path(__file__).resolve()
    for parent in [p] + list(p.parents):
        if (parent / "design").is_dir():
            return parent
    return Path.cwd()


def run_suite(name, cmd, cwd, timeout=300):
    """Run a test suite and return (passed, output)."""
    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"{'='*60}\n")
    try:
        result = subprocess.run(
            cmd, cwd=str(cwd), timeout=timeout,
            capture_output=False  # let output flow through
        )
        return result.returncode == 0
    except FileNotFoundError:
        print(f"  SKIPPED: command not found ({cmd[0]})")
        return None
    except subprocess.TimeoutExpired:
        print(f"  TIMEOUT: suite exceeded {timeout//60} minute limit")
        return False


def main():
    parser = argparse.ArgumentParser(description="Run all V6CLANG test suites")
    parser.add_argument("--golden-only", action="store_true", help="Run only golden tests")
    parser.add_argument("--no-benchmarks", action="store_true",
                        help="Skip benchmark suite (fast mode; benchmarks can take 20+ min)")
    args = parser.parse_args()

    root = find_project_root()
    results = {}

    # Golden tests (always available)
    ok = run_suite(
        "Golden Tests (Emulator Trust Baseline)",
        [sys.executable, str(root / "tests" / "run_golden_tests.py")],
        root
    )
    results["golden"] = ok

    if not args.golden_only:
        # Lit tests — run against the project mirrors under tests/lit/, which
        # have self-contained lit.cfg.py files (no LLVM CMake config required).
        lit_root = root / "tests" / "lit"
        if lit_root.exists():
            ok = run_suite(
                "Lit Tests (FileCheck)",
                [sys.executable,
                 str(root / "llvm-build" / "bin" / "llvm-lit.py"),
                 str(lit_root), "-v"],
                root
            )
            results["lit"] = ok

        # Emulator round-trip tests (available from M4+)
        emu_test_script = root / "tests" / "run_emulator_tests.py"
        if emu_test_script.exists():
            ok = run_suite(
                "Emulator Round-Trip Tests",
                [sys.executable, str(emu_test_script)],
                root
            )
            results["emulator"] = ok

        packed_bss_test = root / "tests" / "features" / "packed_bss" / "run.py"
        if packed_bss_test.exists():
            ok = run_suite(
                "Packed BSS End-to-End",
                [sys.executable, str(packed_bss_test)],
                root
            )
            results["packed_bss"] = ok

        # Benchmark correctness suite — checks checksums only (cycles are informational).
        # Skipped with --no-benchmarks because each run can take 2+ minutes.
        bench_script = root / "tests" / "benchmarks_c" / "run_benchmarks.py"
        if bench_script.exists() and not args.no_benchmarks:
            ok = run_suite(
                "Benchmark Correctness (v6clang + others)",
                [sys.executable, str(bench_script)],
                root,
                timeout=1800,  # 30 min — worst case: all programs hit MAX_CYCLES
            )
            results["benchmarks"] = ok

    # Summary
    print(f"\n{'='*60}")
    print(f"  SUMMARY")
    print(f"{'='*60}\n")

    total = 0
    passed = 0
    skipped = 0
    for name, result in results.items():
        if result is None:
            status = "SKIPPED"
            skipped += 1
        elif result:
            status = "PASS"
            passed += 1
        else:
            status = "FAIL"
        total += 1
        print(f"  {name:30s} {status}")

    print(f"\n  {passed}/{total - skipped} suites passed", end="")
    if skipped:
        print(f" ({skipped} skipped)", end="")
    print()

    failed = total - skipped - passed
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
