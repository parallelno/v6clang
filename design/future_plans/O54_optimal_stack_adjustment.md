# O54. Optimal Stack Adjustment Strategy

*Inspired by jacobly0 `Z80FrameLowering::getOptimalStackAdjustmentMethod()`.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S4.*

## Problem

V6CLANG currently uses a fixed approach for stack pointer adjustment in function
prologues/epilogues: `LXI HL, -N; DAD SP; SPHL` (5 bytes, 32cc). For small
adjustments this is wasteful — there are cheaper alternatives.

Per [docs/V6ClangInstructionTimings.md](../../docs/V6ClangInstructionTimings.md):
`PUSH rp` = 1B / **16cc**, `POP rp` = 1B / 12cc, `LXI rp,d16` = 3B / 12cc,
`DAD rp` = 1B / 12cc, `SPHL` = 1B / 8cc. POP and PUSH have **different**
cycle costs, so the tradeoff differs between prologue (PUSH) and epilogue
(POP).

## Strategy Table

Reference cost: `LXI+DAD+SPHL` = **5B, 32cc**.

### Epilogue — increment SP (deallocate) via `POP rp`

| SP +N | `POP×n` (1B/12cc each) | vs LXI+DAD+SPHL | Verdict |
|-------|------------------------|-----------------|---------|
| +2    | 1B, 12cc               | 5B, 32cc        | POP wins (-4B, -20cc) |
| +4    | 2B, 24cc               | 5B, 32cc        | POP wins (-3B, -8cc)  |
| +6    | 3B, 36cc               | 5B, 32cc        | mixed: -2B but +4cc → **size-only** |
| ≥8    | ≥4B, ≥48cc             | 5B, 32cc        | LXI+DAD+SPHL wins on cc |

### Prologue — decrement SP (allocate) via `PUSH rp`

| SP −N | `PUSH×n` (1B/**16cc** each) | vs LXI+DAD+SPHL | Verdict |
|-------|-----------------------------|-----------------|---------|
| −2    | 1B, 16cc                    | 5B, 32cc        | PUSH wins (-4B, -16cc) |
| −4    | 2B, 32cc                    | 5B, 32cc        | PUSH wins (-3B, =cc)   |
| −6    | 3B, 48cc                    | 5B, 32cc        | mixed: -2B but +16cc → **size-only** |
| ≥8    | ≥4B, ≥64cc                  | 5B, 32cc        | LXI+DAD+SPHL wins on cc |

For SP **increment** (deallocating stack space), `POP rr` increments SP by 2
using only 1 byte and 12cc. The register it pops into doesn't matter if that
register is dead. `POP PSW` (A + flags) is the safest choice assuming A and
flags are dead at the epilogue (they usually are before RET).

For SP **decrement**, `PUSH rr` decrements SP by 2 using 1 byte and 16cc.
Any dead register pair can be pushed — the value stored is garbage.

### Decision summary (uses dual cost model O11)

- `±2`, `±4`: always use POP/PUSH (wins or ties on both axes).
- `±6`: POP/PUSH only when optimising for **size** (`-Os`/`-Oz`); under
  `-O2`/speed prefer LXI+DAD+SPHL (saves 4cc on epilogue, 16cc on prologue).
- `≥8` or odd: always LXI+DAD+SPHL.

## Implementation

In `V6ClangFrameLowering::emitPrologue()` and `emitEpilogue()`:

```cpp
void adjustSP(MachineBasicBlock &MBB, MachineBasicBlock::iterator MBBI,
              int Amount, const DebugLoc &DL, V6ClangOptMode Mode) {
  // Amount > 0 = increment SP (deallocate, POP), Amount < 0 = decrement (PUSH)
  unsigned AbsAmount = std::abs(Amount);
  bool IsInc = Amount > 0;

  // POP/PUSH usable only for even adjustments.
  // ±2, ±4: always cheaper than LXI+DAD+SPHL.
  // ±6: cheaper on bytes but worse on cycles → only under size-opt.
  //     POP×3  = 3B, 36cc (vs 5B, 32cc) → +4cc
  //     PUSH×3 = 3B, 48cc (vs 5B, 32cc) → +16cc
  bool UsePopPush = false;
  if (AbsAmount > 0 && (AbsAmount % 2) == 0) {
    if (AbsAmount <= 4) {
      UsePopPush = true;                   // wins or ties on both axes
    } else if (AbsAmount == 6 && Mode == V6ClangOptMode::Size) {
      UsePopPush = true;                   // size-only
    }
  }

  if (UsePopPush) {
    unsigned Opc = IsInc ? V6CLANG::POP : V6CLANG::PUSH;
    for (unsigned i = 0; i < AbsAmount / 2; i++) {
      auto MIB = BuildMI(MBB, MBBI, DL, TII->get(Opc));
      if (IsInc)
        MIB.addReg(V6CLANG::PSW, RegState::Define);    // POP PSW
      else
        MIB.addReg(V6CLANG::PSW);                      // PUSH PSW
    }
  } else {
    // LXI+DAD+SPHL for large, odd, or speed-mode +6 adjustments
    BuildMI(MBB, MBBI, DL, TII->get(V6CLANG::LXI), V6CLANG::HL).addImm(Amount);
    BuildMI(MBB, MBBI, DL, TII->get(V6CLANG::DAD), V6CLANG::HL).addReg(V6CLANG::SP);
    BuildMI(MBB, MBBI, DL, TII->get(V6CLANG::SPHL));
  }
}
```

Mode is obtained via `getV6ClangOptMode(MF)` (see O11 dual cost model).

## Before → After

```asm
; Before: deallocate 4 bytes        ; After: deallocate 4 bytes
LXI  HL, 4      ; 12cc, 3B          POP  PSW    ; 12cc, 1B
DAD  SP         ; 12cc, 1B          POP  PSW    ; 12cc, 1B
SPHL            ;  8cc, 1B
; Total: 32cc, 5B                   ; Total: 24cc, 2B
```

## Benefit

- **Savings per instance**:
  - epilogue ±2: -4B, -20cc; ±4: -3B, -8cc; ±6 (`-Os`): -2B, +4cc
  - prologue ±2: -4B, -16cc; ±4: -3B, ±0cc; ±6 (`-Os`): -2B, +16cc
- **Frequency**: Low in current pipeline. Most bsort/sieve/fib_crc functions are
  promoted to static globals by `V6ClangAllocaPromote` + `V6ClangStaticStackAlloc`
  (O10) and never touch the hardware stack. Only functions that fall outside
  those passes (recursive, callback-taking, or with var-sized objects) still
  hit `LXI+DAD+SPHL`. Verified 2026-04-30: 0 hits in C benchmarks, 8 hits
  across 4 lit tests (all ≤4 bytes — would all be POP/PUSH wins).
- **Breakeven**: see strategy tables above.

## Complexity

Low. ~30 lines in frame lowering. Decision logic is simple size comparison.

## Risk

Low. `POP PSW` clobbers A and flags, but both are dead at function epilogue
(before RET). For prologue (`PUSH PSW`), the pushed garbage value is
irrelevant — only the SP decrement matters. Must verify A/flags liveness
at adjustment points.

## Dependencies

None. Independent of all other optimizations. But interacts with O10 (static
stack) — functions using static stack don't have dynamic SP adjustments, so
this only benefits functions that still use the hardware stack.

## Related sub-plans

The same `POP rp` / `PUSH rp` substitution applies to other SP-adjustment
sites in the function body. Each is filed as a sibling plan with its own
liveness analysis and cost table:

- [O54b](O54b_per_call_frame_cleanup.md) — Per-call frame cleanup at
  `ADJCALLSTACKUP` (gated on flipping `hasReservedCallFrame()` to false).
- [O54c](O54c_stack_arg_passing_push.md) — Caller-side stack-arg passing
  via `PUSH rp` instead of LXI/DAD/MOV M (highest practical impact).
- [O54d](O54d_alloca_constant_size_push.md) — Constant-size dynamic alloca
  via `PUSH rp × n/2` (niche).

This plan (O54, baseline) provides the shared infrastructure those siblings
depend on:

- `chooseDeadPair(MBB, MBBI)` — pick the cheapest dead GR16All pair
  (`PSW`/`BC`/`DE`/`HL`) at a given point.
- `emitSPAdjustment(MBB, MBBI, amount, mode, allowPSW, deadPair)` — emit
  either `PUSH/POP × n/2` or `LXI/DAD/SPHL` per the cost table above.

### Suggested ordering

1. **O54** (this plan) — small, mechanical, unblocks the others.
2. **O54c** — biggest practical win; reuses the helpers.
3. **O54b** — only if/when reserved-call-frame mode is revisited.
4. **O54d** — niche; revisit after surveying alloca usage in real code.
