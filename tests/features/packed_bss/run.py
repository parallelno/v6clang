"""Build, execute, and inspect the native packed-BSS linker feature."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BIN = ROOT / "llvm-build" / "bin"
CLANG = BIN / "clang.exe"
NM = BIN / "llvm-nm.exe"
READELF = BIN / "llvm-readelf.exe"
V6EMUL = os.environ.get("V6EMUL")


def run(command: list[Path | str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(arg) for arg in command],
        check=True,
        text=True,
        capture_output=True,
        timeout=60,
    )


def symbols(elf: Path) -> dict[str, int]:
    result: dict[str, int] = {}
    for line in run([NM, "--numeric-sort", elf]).stdout.splitlines():
        fields = line.split()
        if len(fields) >= 3:
            result[fields[-1]] = int(fields[0], 16)
    return result


def main() -> int:
    if not V6EMUL or not Path(V6EMUL).is_file():
        raise RuntimeError("Set V6EMUL to the separately installed v6emul executable.")
    with tempfile.TemporaryDirectory(prefix="v6clang-packed-bss-") as temp:
        output_dir = Path(temp)
        rom = output_dir / "packed.rom"
        elf = output_dir / "packed.elf"
        common = [
            CLANG,
            "-target",
            "i8080-unknown-v6clang",
            "-O2",
            HERE / "main.c",
            HERE / "blocks.s",
        ]
        run(common + ["-o", rom])
        run(common + ["-o", elf])

        emulator = run([
            V6EMUL,
            "--rom",
            rom,
            "--load-addr",
            "0x0100",
            "--halt-exit",
            "--dump-cpu",
        ])
        outputs = [
            int(match.group(1), 16)
            for match in re.finditer(
                r"TEST_OUT port=0xED value=0x([0-9A-Fa-f]+)",
                emulator.stdout,
            )
        ]
        if outputs != [0x5A]:
            raise AssertionError(f"expected success byte 0x5A, got {outputs}")

        linked_symbols = symbols(elf)
        for name in ("filler_block", "anchor_block", "window_block"):
            if name not in linked_symbols:
                raise AssertionError(f"live packed symbol missing: {name}")
        if "dead_block" in linked_symbols:
            raise AssertionError("unreferenced packed block was not garbage-collected")

        anchor = linked_symbols["anchor_block"]
        window = linked_symbols["window_block"]
        if anchor % 256 != 0:
            raise AssertionError(f"anchor is not page-aligned: 0x{anchor:04x}")
        if window // 256 != (window + 199) // 256:
            raise AssertionError(f"window crosses a page: 0x{window:04x}")

        sections = run([READELF, "--wide", "--sections", elf]).stdout
        if not re.search(r"\.bss\.pack\s+NOBITS", sections):
            raise AssertionError("packed output section is not SHT_NOBITS")

        bss_end = linked_symbols["__bss_end"]
        if len(rom.read_bytes()) >= bss_end - 0x0100:
            raise AssertionError("flat ROM unexpectedly contains the NOBITS arena")

    print("PASS: packed BSS runtime, GC, constraints, and ROM size")
    return 0


if __name__ == "__main__":
    sys.exit(main())
