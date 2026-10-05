"""Build, run, and verify the inline-asm clobber feature test.

Verifies three things end-to-end:

1.  ROM produced by the V6CLANG clang driver, when executed in v6emul, emits
    exactly the expected TEST_OUT byte stream (`expected.txt`).
2.  After --gc-sections, the unreachable asm helpers `func3` and `func4`
    are absent from the linked ELF (verified via `llvm-nm`).
3.  The Style-B inline-asm CALL site does NOT save/restore BC/DE around
    the asm block (verified by FileCheck on the `.s` listing).

Run from the repo root:

    python tests/features/inline_asm_clobber/run.py
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BIN = ROOT / "llvm-build" / "bin"

CLANG = BIN / "clang.exe"
NM = BIN / "llvm-nm.exe"
FILECHECK = BIN / "FileCheck.exe"
V6EMUL = os.environ.get("V6EMUL")

ROM = HERE / "out.rom"
ELF = HERE / "out.elf"
ASM = HERE / "main.s"
CRT0_S = ROOT / "compiler-rt" / "lib" / "builtins" / "v6clang" / "crt0.s"
CRT0_O = HERE / "crt0.o"


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    print("$", " ".join(str(c) for c in cmd))
    return subprocess.run([str(c) for c in cmd], check=True, text=True,
                          capture_output=True, **kwargs)


def step0_assemble_crt0() -> None:
    run([CLANG, "-target", "i8080-unknown-v6clang", "-c", CRT0_S, "-o", CRT0_O])


def step1_compile_rom() -> None:
    run([
        CLANG, "-target", "i8080-unknown-v6clang", "-O2",
        "-ffunction-sections", "-nostartfiles",
        CRT0_O, HERE / "main.c", HERE / "external.s",
        "-Wl,--gc-sections",
        "-o", ROM,
    ])


def step1b_keep_elf() -> None:
    # Re-link, but produce ELF (extension .elf -> driver skips objcopy).
    run([
        CLANG, "-target", "i8080-unknown-v6clang", "-O2",
        "-ffunction-sections", "-nostartfiles",
        CRT0_O, HERE / "main.c", HERE / "external.s",
        "-Wl,--gc-sections",
        "-o", ELF,
    ])


def step2_run_rom() -> str:
    proc = subprocess.run(
        [str(V6EMUL), "--rom", str(ROM), "--load-addr", "0x0100",
         "--halt-exit", "--dump-cpu"],
        check=True, text=True, capture_output=True,
    )
    out_bytes: list[int] = []
    for line in proc.stdout.splitlines():
        # "TEST_OUT port=0xED value=0xNN"
        if line.startswith("TEST_OUT") and "port=0xED" in line:
            value = line.rsplit("=", 1)[-1]
            out_bytes.append(int(value, 16))
    return "".join(chr(b) for b in out_bytes)


def step3_check_gc() -> None:
    proc = run([NM, ELF])
    syms = {ln.split()[-1] for ln in proc.stdout.splitlines() if ln.strip()}
    assert "func1" in syms, "func1 should be present (reachable)"
    assert "func2" in syms, "func2 should be present (reachable from func1)"
    assert "func3" not in syms, f"func3 should be GC'd, found in: {syms}"
    assert "func4" not in syms, f"func4 should be GC'd, found in: {syms}"


def step4_check_no_overspill() -> None:
    # Emit .s for main.c only (not the bodies in external.s) to inspect
    # the inline-asm CALL site.
    run([
        CLANG, "-target", "i8080-unknown-v6clang", "-O2",
        "-ffunction-sections", "-S",
        HERE / "main.c",
        "-o", ASM,
    ])
    # FileCheck pattern: between APP/NO_APP markers there should be no
    # PUSH B / PUSH D / POP B / POP D bracketing the CALL func1 site.
    text = ASM.read_text()
    # Quick assertion: no PUSH/POP of pair regs anywhere in main (it has
    # no live i16 in pairs to spill, but this codifies the expectation).
    bad = [ln for ln in text.splitlines()
           if ln.strip().startswith(("PUSH", "POP")) and any(
               p in ln for p in (" B", " D", " H"))]
    assert not bad, f"Unexpected pair PUSH/POP in main.s: {bad}"


def main() -> int:
    if not V6EMUL or not Path(V6EMUL).is_file():
        raise RuntimeError("Set V6EMUL to the separately installed v6emul executable.")
    expected = (HERE / "expected.txt").read_text().strip()

    step0_assemble_crt0()
    step1_compile_rom()
    step1b_keep_elf()
    actual = step2_run_rom().strip()
    if actual != expected:
        print(f"FAIL: stdout mismatch. expected={expected!r} actual={actual!r}")
        return 1
    step3_check_gc()
    step4_check_no_overspill()
    print("OK: stdout matches; func3/func4 GC'd; no over-spill around inline asm.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
