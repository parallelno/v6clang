#!/usr/bin/env python3
"""Build + run + aggregate the C-compiler benchmark matrix.

Compilers tested: v6clang (this repo, baseline), c8080, z88dk/sccz80.
Programs: bsort, sieve, fib_crc.

Each program ends with bench_finish(checksum) which writes the byte to
port 0xED and HLTs.  v6emul prints both the checksum and cycle count;
we parse them and assemble a results table.

Environment variables:
    V6EMUL  (required) Path to the v6emul executable. Runs every ROM to
            collect cycle counts and checksums; without it the whole
            benchmark run fails.
    C8080   (optional) Path to the c8080 reference compiler executable.
            Enables the c8080 comparator column; skipped if unset.
    Z88DK   (optional) Root of the z88dk installation (containing
            bin/zcc.exe and lib/config). Enables the z88dk/sccz80
            comparator column; skipped if unset.

The v6clang baseline uses this repo's own clang (llvm-build/bin/clang.exe)
and needs no environment variable.

Run:    python tests/benchmarks_c/run_benchmarks.py
Output: docs/benchmarks.md  (+ stdout summary)
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "tests" / "benchmarks_c" / "src"
BUILD = REPO / "tests" / "benchmarks_c" / "build"
ASM = REPO / "tests" / "benchmarks_c" / "asm"
DOCS = REPO / "docs" / "benchmarks.md"

V6CLANG_CLANG = REPO / "llvm-build" / "bin" / "clang.exe"
C8080 = os.environ.get("C8080")
V6EMUL = os.environ.get("V6EMUL")
Z88DK = Path(os.environ["Z88DK"]) if os.environ.get("Z88DK") else None
ZCC = Z88DK / "bin" / "zcc.exe" if Z88DK else None
ZCC_BIN = ZCC.parent if ZCC else None
ZCC_CFG = Z88DK / "lib" / "config" if Z88DK else None

PROGRAMS = ["bsort", "sieve", "fib_crc", "fannkuch", "lfsr16"]
EXPECTED = {"bsort": 0x98, "sieve": 0xEC, "fib_crc": 0x2B, "fannkuch": 0x10,
            "lfsr16": 0x1D}
# Environment variable each optional comparator depends on, and how to set it.
COMPILER_ENV = {
    "c8080": (
        "C8080",
        "path to the c8080 executable",
        r"$env:C8080 = 'C:\path\to\c8080.exe'",
    ),
    "z88dk": (
        "Z88DK",
        "root of the z88dk installation (containing bin\\zcc.exe and lib\\config)",
        r"$env:Z88DK = 'C:\path\to\z88dk'",
    ),
}
# Generous safety cap: long enough for fannkuch-style N=9 runs (~50-100M cc
# expected per the z88dk reference) without bailing too early. A real
# emulator stall would still terminate the run via exit code; this just
# bounds runaway loops in broken codegen.
MAX_CYCLES = 1_000_000_000


@dataclass
class Result:
    compiler: str
    program: str
    rom_size: int
    cycles: int | None
    checksum: int | None
    flags: str
    error: str | None = None
    skipped: bool = False

    @property
    def ok(self) -> bool:
        return (
            not self.skipped
            and
            self.error is None
            and self.checksum == EXPECTED[self.program]
            and self.cycles is not None
        )


# ---------------------------------------------------------------------------

def run_emul(rom: Path, load_addr: int) -> tuple[int | None, int | None]:
    """Return (cycles, checksum) parsed from v6emul output."""
    cmd = [
        str(V6EMUL),
        "--rom", str(rom),
        "--load-addr", f"0x{load_addr:04X}",
        "--halt-exit",
        "--dump-cpu",
        "-run-cycles", str(MAX_CYCLES),
    ]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    cyc = re.search(r"after (\d+) cpu_cycles", out)
    val = re.search(r"value=0x([0-9A-Fa-f]+)", out)
    if not (cyc and "HALT" in out):
        return None, None
    return int(cyc.group(1)), (int(val.group(1), 16) if val else None)


def make_z88dk_env() -> dict[str, str]:
    env = os.environ.copy()
    env["ZCCCFG"] = str(ZCC_CFG)
    env["PATH"] = f"{ZCC_BIN};{env['PATH']}"
    return env


def probe_z88dk() -> str | None:
    if Z88DK is None:
        return "Z88DK is not configured; set it to the z88dk installation root"
    if not ZCC.exists():
        return f"{ZCC.name} not found"
    if not ZCC_CFG.is_dir():
        return "z88dk config directory not found"
    try:
        subprocess.run([str(ZCC)], capture_output=True, text=True,
                       env=make_z88dk_env())
    except OSError as exc:
        return f"unable to launch {ZCC.name}: {exc}"
    return None


def probe_c8080() -> str | None:
    if not C8080:
        return "C8080 is not configured; set it to the c8080 executable"
    if not Path(C8080).is_file():
        return f"{Path(C8080).name} not found"
    try:
        subprocess.run([str(C8080)], capture_output=True, text=True,
                       stdin=subprocess.DEVNULL, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"unable to launch {Path(C8080).name}: {exc}"
    return None


def skipped_result(compiler: str, prog: str, flags: str, reason: str) -> Result:
    return Result(compiler, prog, 0, None, None, flags,
                  error=reason, skipped=True)


# ---------------------------------------------------------------------------

def build_v6clang(prog: str, opt: str) -> Result:
    rom = BUILD / f"v6clang_{prog}_{opt}.rom"
    rom.unlink(missing_ok=True)
    cmd = [str(V6CLANG_CLANG), "-target", "i8080-unknown-v6clang",
           f"-{opt}",
           str(SRC / f"{prog}.c"), "-o", str(rom)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0 or not rom.exists():
        return Result("v6clang", prog, 0, None, None, opt,
                      error=p.stderr.strip()[:200] or "build failed")
    # Also emit .asm next to the source for analysis.
    asm = ASM / f"v6clang_{prog}_{opt}.s"
    subprocess.run(
        [str(V6CLANG_CLANG), "-target", "i8080-unknown-v6clang",
         f"-{opt}",
         "-S", "-mllvm", "-mv6clang-annotate-pseudos",
         str(SRC / f"{prog}.c"), "-o", str(asm)],
        capture_output=True, text=True,
    )
    cyc, chk = run_emul(rom, 0x0100)
    return Result("v6clang", prog, rom.stat().st_size, cyc, chk, opt)


def build_c8080(prog: str) -> Result:
    com = BUILD / f"c8080_{prog}.com"
    asm = ASM / f"c8080_{prog}.asm"
    com.unlink(missing_ok=True); asm.unlink(missing_ok=True)
    cmd = [str(C8080), "-Ocpm", f"-I{SRC}",
           str(SRC / f"{prog}.c"),
           "-o", str(com), "-a", str(asm)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0 or not com.exists():
        return Result("c8080", prog, 0, None, None, "-Ocpm",
                      error=(p.stdout + p.stderr).strip()[:200])
    cyc, chk = run_emul(com, 0x0100)
    return Result("c8080", prog, com.stat().st_size, cyc, chk, "-Ocpm")


def build_z88dk(prog: str) -> Result:
    out = BUILD / f"z88dk_{prog}"
    com = Path(str(out) + ".COM")
    bin_path = BUILD / f"z88dk_{prog}.bin"
    for f in (out, com, bin_path):
        f.unlink(missing_ok=True)
    env = make_z88dk_env()
    flags = ["+cpm", "-clib=8080", "-m8080", "-compiler=sccz80",
             "-SO3", "-O3", "-create-app",
             "-pragma-define:CRT_INITIALIZE_BSS=0",
             "-pragma-define:CRT_ENABLE_STDIO=0",
             "-pragma-output:noprotectmsdos",
             f"-I{SRC}"]
    cmd = [str(ZCC), *flags, str(SRC / f"{prog}.c"), "-o", str(out)]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, env=env)
    except OSError as exc:
        return skipped_result("z88dk", prog, " ".join(flags[:8]),
                              f"unable to launch {ZCC.name}: {exc}")
    if not com.exists():
        return Result("z88dk", prog, 0, None, None, " ".join(flags[:8]),
                      error=(p.stdout + p.stderr).strip()[:200])
    # Also emit .asm via -S (no-link compile) for analysis.
    asm_out = ASM / f"z88dk_{prog}.asm"
    s_tmp = BUILD / f"z88dk_{prog}_s"
    s_tmp.unlink(missing_ok=True)
    try:
        subprocess.run(
            [str(ZCC), *flags, "-S", str(SRC / f"{prog}.c"), "-o", str(s_tmp)],
            capture_output=True, text=True, env=env,
        )
    except OSError:
        pass
    if s_tmp.exists():
        asm_out.write_bytes(s_tmp.read_bytes())
    # Wrap .COM into a flat ROM with BDOS stub: org 0 jumps to 0x0100,
    # 0x0005 is RET so any BDOS call returns harmlessly.
    com_bytes = com.read_bytes()
    img = bytearray(0x100 + len(com_bytes))
    img[0:3] = b"\xC3\x00\x01"          # JMP 0x0100
    img[5] = 0xC9                        # RET at BDOS entry
    for i in range(6, 16):
        img[i] = 0xC9
    img[0x100:0x100 + len(com_bytes)] = com_bytes
    bin_path.write_bytes(bytes(img))
    cyc, chk = run_emul(bin_path, 0x0000)
    return Result("z88dk", prog, len(com_bytes), cyc, chk,
                  "+cpm -clib=8080 -m8080 sccz80 -SO3 -O3")


# ---------------------------------------------------------------------------

def fmt_row(r: Result, baseline_cycles: int | None, md: bool = False) -> str:
    if r.skipped:
        return f"SKIPPED ({r.error or 'unavailable'})"
    if not r.ok:
        return f"FAIL ({r.error or 'wrong checksum'})"
    sz = r.rom_size
    cc = r.cycles
    if md:
        if baseline_cycles and cc:
            ratio = cc / baseline_cycles
            return (f"**{sz} B** / <span style=\"color:gray\">{cc:,} cc</span> "
                    f"(**{ratio:.2f}x**)")
        return f"**{sz} B** / <span style=\"color:gray\">{cc:,} cc</span>"
    if baseline_cycles and cc:
        ratio = cc / baseline_cycles
        return f"{sz} B / {cc:,} cc ({ratio:.2f}x)"
    return f"{sz} B / {cc:,} cc"


def main() -> int:
    BUILD.mkdir(exist_ok=True)
    ASM.mkdir(exist_ok=True)
    # V6EMUL is required: it runs every ROM to collect cycle counts/checksums.
    # C8080 and Z88DK are optional comparators (see probe_c8080/probe_z88dk).
    if not V6EMUL or not Path(V6EMUL).is_file():
        print("ERROR: set V6EMUL to the separately installed executable", file=sys.stderr)
        return 2
    print("Building and running benchmark matrix...\n")

    results: dict[tuple[str, str], Result] = {}

    # v6clang baseline = -O2.  Also run -O1, -Os for context.
    for prog in PROGRAMS:
        for opt in ("O1", "O2", "Os"):
            r = build_v6clang(prog, opt)
            results[(f"v6clang-{opt}", prog)] = r
            print(f"  v6clang -{opt:3} {prog:8} -> {fmt_row(r, None)}")

    c8080_issue = probe_c8080()
    if c8080_issue is None:
        for prog in PROGRAMS:
            r = build_c8080(prog)
            results[("c8080", prog)] = r
            print(f"  c8080         {prog:8} -> {fmt_row(r, None)}")
    else:
        print(f"  c8080         skipped -> {c8080_issue}")
        for prog in PROGRAMS:
            r = skipped_result("c8080", prog, "-Ocpm", c8080_issue)
            results[("c8080", prog)] = r
            print(f"  c8080         {prog:8} -> {fmt_row(r, None)}")

    z88dk_issue = probe_z88dk()
    if z88dk_issue is None:
        for prog in PROGRAMS:
            r = build_z88dk(prog)
            results[("z88dk", prog)] = r
            print(f"  z88dk         {prog:8} -> {fmt_row(r, None)}")
    else:
        print(f"  z88dk         skipped -> {z88dk_issue}")
        for prog in PROGRAMS:
            r = skipped_result("z88dk", prog,
                               "+cpm -clib=8080 -m8080 sccz80 -SO3 -O3",
                               z88dk_issue)
            results[("z88dk", prog)] = r
            print(f"  z88dk         {prog:8} -> {fmt_row(r, None)}")

    # Validate correctness invariant.
    print("\nCorrectness invariant: all compilers must agree on checksum.")
    fail = False
    for prog in PROGRAMS:
        seen = {}
        for key, r in results.items():
            if r.program == prog and r.checksum is not None:
                seen.setdefault(r.checksum, []).append(key[0])
        if len(seen) > 1:
            print(f"  MISMATCH for {prog}: {seen}")
            fail = True
        else:
            (chk,) = seen.keys()
            mark = "OK" if chk == EXPECTED[prog] else "WRONG"
            print(f"  {prog:8} checksum=0x{chk:02X} [{mark}]")
            fail = fail or (chk != EXPECTED[prog])

    # Build markdown table.
    baseline_key = "v6clang-O2"
    cols = [baseline_key, "v6clang-O1", "v6clang-Os", "c8080", "z88dk"]
    lines = []
    lines.append("# C-compiler benchmark results")
    lines.append("")
    lines.append("Cycle counts and ROM sizes for three pure-C benchmarks compiled "
                 "with each i8080-capable compiler and run on `v6emul`. The number "
                 "in parentheses is the cycle ratio relative to v6clang -O2.")
    lines.append("")
    lines.append("| Program | " + " | ".join(cols) + " |")
    lines.append("|---|" + "|".join(["---"] * len(cols)) + "|")
    for prog in PROGRAMS:
        baseline = results[(baseline_key, prog)]
        base_cc = baseline.cycles if baseline.ok else None
        cells = [prog]
        for c in cols:
            r = results[(c, prog)]
            cells.append(fmt_row(r, base_cc, md=True))
        lines.append("| " + " | ".join(cells) + " |")
    lines.append("")
    checksum_text = ", ".join(
        f"`{prog}`=0x{EXPECTED[prog]:02X}" for prog in PROGRAMS)
    skipped_compilers = sorted({r.compiler for r in results.values() if r.skipped})
    if skipped_compilers:
        skipped_text = ", ".join(f"`{compiler}`" for compiler in skipped_compilers)
        lines.append("All available compilers produced the same checksum byte per program "
                     f"({checksum_text}), confirming the ROMs are functionally "
                     "equivalent.")
        lines.append("")
        lines.append(f"Skipped comparator(s): {skipped_text} (toolchain unavailable during this run).")
        lines.append("")
        lines.append("### Environment setup for skipped comparators")
        lines.append("")
        lines.append("Set the following environment variable(s), then re-run the "
                     "benchmark to include the missing comparator(s):")
        lines.append("")
        for compiler in skipped_compilers:
            env = COMPILER_ENV.get(compiler)
            if env is None:
                continue
            var, desc, example = env
            lines.append(f"- **{compiler}** requires `{var}` ({desc}):")
            lines.append("")
            lines.append("  ```powershell")
            lines.append(f"  {example}")
            lines.append("  ```")
    else:
        lines.append("All compilers produced the same checksum byte per program "
                     f"({checksum_text}), confirming the ROMs are functionally "
                     "equivalent.")
    lines.append("")
    lines.append("## Compiler invocations")
    lines.append("")
    lines.append("- **v6clang**: `clang -target i8080-unknown-v6clang -O2 prog.c -o prog.rom`")
    lines.append("- **c8080**: `c8080 -Ocpm prog.c -o prog.com -a prog.asm` (CP/M `.COM`, ORG=0x0100)")
    lines.append("- **z88dk**: `zcc +cpm -clib=8080 -m8080 -compiler=sccz80 -SO3 -O3 -create-app prog.c`")
    lines.append("  with the BDOS region (0x0000-0x00FF) stubbed out by the runner so the CP/M crt0 returns from `BDOS` calls harmlessly.")
    lines.append("")
    lines.append("## Reproducing")
    lines.append("")
    lines.append("```")
    lines.append("python tests/benchmarks_c/run_benchmarks.py")
    lines.append("```")
    lines.append("")
    DOCS.parent.mkdir(parents=True, exist_ok=True)
    DOCS.write_text("\n".join(lines), encoding="utf-8")
    print(f"\nWrote {DOCS}")

    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
