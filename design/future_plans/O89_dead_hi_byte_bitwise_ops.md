# O89 — Dead High-Byte Elision in V6CLANG_AND16 / V6CLANG_OR16 / V6CLANG_XOR16

**Source:** `temp/test_i16_i8_narrow.c`; confirmed in `tests/benchmarks_c/src/lfsr16.c`
**Savings:** 20cc, 3B per i16 bitwise op whose result is truncated to i8
**Frequency:** Every `(u8)(a ^ b)` / `(u8)(a | b)` / `(u8)(a & b)` where both values are i16
**Complexity:** Low — one `isRegDeadAfter` guard in `expandPostRAPseudo`
**Risk:** Low — guarded by existing liveness infrastructure
**Dependencies:** none (can run standalone; composed benefit with AccumulatorPlanning)
**Status:** [x] complete

---

## Problem

`V6CLANG_AND16` / `V6CLANG_OR16` / `V6CLANG_XOR16` always expand to the full 6-instruction
pair-wise sequence, even when only the low byte of the result is consumed.

### Current expansion (xor example, `xor16_to_i8(u16 a, u16 b) → u8`)

```asm
;--- V6CLANG_XOR16 ---
MOV  A, E          ; load LhsLo          8cc  1B
XRA  L             ; lo result → A       4cc  1B
MOV  L, A          ; DstLo = L           8cc  1B
MOV  A, D          ; load LhsHi  ← DEAD 8cc  1B
XRA  H             ; hi result → A ← DEAD 4cc 1B
                   ; hi result never stored (AccPlan elided MOV H,A)
MOV  A, L          ; restore DstLo        8cc  1B  ← required by hi clobber
RET
; Total: 40cc, 6B
```

`DstHi` is dead, so the two hi-byte instructions serve no purpose.  Because
they clobber A, however, a `MOV A, DstLo` reload is required at the end —
adding a third wasted instruction.

### Root cause — `V6ClangInstrInfo.cpp` (expandPostRAPseudo)

```cpp
case V6CLANG::V6CLANG_AND16:
case V6CLANG::V6CLANG_OR16:
case V6CLANG::V6CLANG_XOR16: {
    // lo byte
    BuildMI(…, MOVrr, A).addReg(LhsLo);
    BuildMI(…, OpOpc, A).addReg(A).addReg(RhsLo);
    BuildMI(…, MOVrr, DstLo).addReg(A);
    // hi byte — unconditional, no dead-hi guard
    BuildMI(…, MOVrr, A).addReg(LhsHi);
    BuildMI(…, OpOpc, A).addReg(A).addReg(RhsHi);
    BuildMI(…, MOVrr, DstHi).addReg(A);
```

---

## Affected patterns (confirmed in `test_i16_i8_narrow_O2.s`)

| C pattern | Expected | Actual |
|---|---|---|
| `(u8)(a ^ b)` | `MOV A,E; XRA L; RET` (3 insn) | 6 insn + extra `MOV A,L` |
| `(u8)(a \| b)` | `MOV A,E; ORA L; RET` | same issue |
| `(u8)(a & b)` | `MOV A,E; ANA L; RET` | same issue |
| `(u8)a ^ (u8)(a>>8)` (bench_finish checksum) | `MOV A,H; XRA L; RET` | 6 insn + reload |
| `(u8)(a^b)==0` before `V6CLANG_CMP8_ZERO` | lo XRA + ORA A | full 16-bit + XRA A + CMP |
| `(u8)(a&b)==0` before `V6CLANG_CMP8_ZERO` | lo ANA + ORA A | full 16-bit + XRA A + CMP |
| `(u8)(a\|b)==0` before `V6CLANG_CMP8_ZERO` | lo ORA (flags already set!) | full 16-bit + XRA A + CMP |

Note: `(u8)(lfsr & 1)` is already optimal — DAGCombiner narrows to an i8 AND
before ISel, so `V6CLANG_AND16` is never generated; the result is `ANI 1`.

---

## Fix

In `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`,
`expandPostRAPseudo` case `V6CLANG_AND16` / `V6CLANG_OR16` / `V6CLANG_XOR16`:

```cpp
bool HiDead = isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI);

// lo byte (always needed)
BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(LhsLo);
BuildMI(MBB, MI, DL, get(OpOpc), V6CLANG::A).addReg(V6CLANG::A).addReg(RhsLo);
BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstLo).addReg(V6CLANG::A);

// hi byte — skip entirely when DstHi is dead
if (!HiDead) {
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(LhsHi);
    BuildMI(MBB, MI, DL, get(OpOpc), V6CLANG::A).addReg(V6CLANG::A).addReg(RhsHi);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstHi).addReg(V6CLANG::A);
}
```

`isRegDeadAfter` is the same helper used at lines 896, 928, 1062, 1215, 2720,
etc.  No new infrastructure required.

### Secondary benefit — AccumulatorPlanning interaction

When `HiDead=true`, the expansion leaves A = lo result after the `OpOpc`.
The `MOV DstLo, A` is still emitted for correctness (another instruction may
read DstLo as a named register), but AccumulatorPlanning already tracks that
`A == DstLo` and will eliminate a subsequent `MOV A, DstLo` reload if the
caller needs A.  For the common `(u8)(a^b)` return pattern this means
AccumulatorPlanning removes the `MOV DstLo, A; MOV A, DstLo` round-trip and
the final sequence shrinks from 6 insn to 2 insn:

```asm
; After O89 + AccumulatorPlanning
MOV  A, E          ; 8cc  1B
XRA  L             ; 4cc  1B   ← A = return value, no further stores needed
RET
```

### OR16 special case — flags already set

For `V6CLANG_OR16` with `HiDead=true`, the lo-byte `ORA RhsLo` already sets the
Z flag correctly for the truncated result.  If the immediate consumer is
`V6CLANG_CMP8_ZERO` (which needs ORA A / XRA A+CMP to re-establish the flag),
that CMP8_ZERO becomes redundant.  This is a secondary optimisation for a
follow-on patch — the simple `HiDead` guard alone eliminates the bulk of
the waste.

---

## Expected savings per occurrence

| Pattern | Before | After + AccPlan | Saved |
|---|---|---|---|
| `(u8)(a OP b)` return | 6 insn, 40cc, 6B | 2 insn, 12cc, 2B | **28cc, 4B** |
| `(u8)(a OP b)` store to reg | 6 insn, 40cc, 6B | 3 insn, 20cc, 3B | **20cc, 3B** |
| bench_finish checksum `xor_bytes` | 6 insn, 36cc | 2 insn, 12cc | **24cc, 4B** |
| `(u8)(a^b)==0` branch | 7 insn (incl. XRA A+CMP) | 4 insn | **~16cc, 3B** |

*Cycle counts use V6CLANG costs: MOVrr=8cc, ALU reg=4cc.*

---

## Benchmarks likely to benefit

- **lfsr16**: bench_finish line `(u8)((u8)acc ^ (u8)(acc >> 8))` — 1× `xor_bytes`
  pattern, saves ~28cc outside the hot loop.
- Any benchmark using CRC, hash, or LFSR primitives that fold a 16-bit
  intermediate to u8 at a call boundary.

---

## Implementation checklist

- [ ] Edit `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp` — add
      `HiDead` guard in the `V6CLANG_AND16`/`V6CLANG_OR16`/`V6CLANG_XOR16` case.
- [ ] Add lit test `llvm-project/llvm/test/CodeGen/V6CLANG/bitwise16-dead-hi.ll`
      covering XOR/OR/AND with i8-truncated result, with and without dead-hi.
- [ ] Run `tests/run_all.py` — all golden + lit must pass.
- [ ] Sync mirror: `pwsh scripts/sync_llvm_mirror.ps1`.
