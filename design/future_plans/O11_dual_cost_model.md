# O11. Dual Cost Model (Bytes + Cycles)

*Inspired by llvm-mos `MOSInstrCost`.*
*Detailed analysis: [llvm_mos_analysis.md](llvm_mos_analysis.md) §S8.*

## Problem

V6CLANG optimization decisions (peephole replacements, pseudo expansion choices,
copy elimination) are currently ad-hoc — each pass uses hardcoded heuristics.
There is no unified way to express "prefer speed" vs "prefer size" vs
"balanced". This leads to inconsistent decisions and makes it hard to add
`-Os`/`-Oz` support.

## How llvm-mos Does It

A simple `MOSInstrCost` class with two `int32_t` fields (Bytes, Cycles).
The `value()` method composes them based on optimization mode:
- `-Oz`: `(Bytes << 32) + Cycles` — bytes dominate
- `-O2`: `(Cycles << 32) + Bytes` — cycles dominate
- Default: `Bytes + Cycles` — balanced

Used in `copyCost()` for register-to-register copy decisions, and throughout
the backend wherever optimization tradeoffs exist.

## V6CLANG Adaptation

Create `V6ClangInstrCost` with identical interface. Populate from the existing
instruction timing tables in [V6ClangInstructionTimings.md](../../docs/V6ClangInstructionTimings.md).
Use in:
- `V6ClangPeephole` decisions (is INX cheaper than LXI in this context?)
- `expandPostRAPseudo` choices (shorter ADD16 sequence selection)
- Future copy optimization pass (O12)
- Any new optimization pass

## Benefit

- **Prevents regressions** when adding new optimizations
- **Enables `-Os`/`-Oz`** support for size-constrained targets
- **Foundation** for cost-aware passes (O12, O13)

## Complexity

Low. ~40 lines: header with struct + 3 methods, one `.cpp` with `getModeFor()`.

## Risk

Very Low. Informational infrastructure — no code transformation by itself.
