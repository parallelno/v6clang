# O53. Enhanced Value Tracking (Full RegVal)

*Inspired by jacobly0 `Z80MachineLateOptimization` RegVal tracking.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S1.*

## Rejected
O53 verification: largely obsolete
The plan was inspired by jacobly0's RegVal struct. Walking through each proposed pattern against actual -O3 and -Os output (o53_test.c, o53_test.asm, o53_test_os.asm):

Plan pattern	Status	Where
MVI A,0 → XRA A (flags dead)	✅ Done	O55 in V6ClangPeephole.cpp:918 — test_mvi_zero emits XRA A
XRI 0FFH → CMA	✅ Done	Direct ISel/tablegen — test_not_u8 (~x) emits a single CMA
ORA A redundant after ALU	✅ Done	O17 V6ClangRedundantFlagElim.cpp
CPI imm redundant	✅ Done	O17 + O36 branch-implied propagation; test_redundant_cpi collapses to one ORA A; RNZ
ANI n; ANI n → ANI n	✅ Done	InstCombine at IR — test_double_and emits one ANI 0xf
Sub-reg composition (H,L known → HL known)	✅ Done	DAGCombine merges to single LXI — test_subreg_compose emits LXI H,0x3412; SHLD buf
Immediate ±1, same-value	✅ Done	O13 V6ClangLoadImmCombine.cpp
GlobalAddress + offset tracking	⚠️ Partial	O02 V6ClangLoadStoreOpt.cpp does this, but cost-gated by MaxDelta
The one observable gap is in test_ga_offset (sum of arr[0..2]):

-Os (MaxDelta=3): LXI H,arr; LDA arr+1; ADD M; INX H; INX H; ADD M ✅
-O3 (MaxDelta=1): LXI H,arr; LDA arr+1; ADD M; LXI H,arr+2; ADD M — second LXI not folded (Δ=2 > 1)
This is a 1-byte regression at speed mode and is a tuning issue in O02, not a missing pass. The full RegVal rewrite (200–300 LOC, flag bitmap, etc.) the plan proposes would yield essentially zero additional savings beyond what's already in tree.

## Problem

O13 (Load-Immediate Combining) tracks only **immediate constants** per
register. The jacobly0 Z80 backend maintains a much richer `RegVal` state
that enables substantially more optimizations.

O13 catches:
- `MVI r, imm` → `MOV r, r'` when r' holds imm
- `MVI r, imm` → `INR r` / `DCR r` when r holds imm±1

O13 misses:
- Flag state tracking (which flags are known set/clear)
- Sub-register composition (knowing H and L values implies HL value)
- Global address tracking (knowing a register holds `&global + offset`)
- Dependent optimizations enabled by flag state awareness

## How jacobly0 Does It

A `RegVal` per physical register tracking:
- **Immediate constant** (8-bit or 16-bit known value)
- **GlobalAddress + offset** (for relocatable pointers)
- **Sub-register composition** (H=5, L=3 → HL = 0x0503)
- **Flag state bitmap**: 8 bits for known mask + known value of each flag

This enables:
- `MVI A, 0` → `XRA A` when flags are dead (saves 1B)
- `ADD A, A` instead of `RLC` when only doubling (saves prefix byte — Z80-specific)
- `SBB A` (A = 0 - carry) when carry is known clear → `XRA A` (same but clearer intent)
- `CPI 0` → skip when Z flag already reflects A's value
- `MOV A, H; ORA L` → skip when HL's zero-ness is already in flags
- Immediate ± 1 folding (already in O13)
- Same-value elimination (already in O13)

## V6CLANG Adaptation

Extend the existing O13 `RegVal` tracking in `V6ClangPeephole.cpp`:

```cpp
struct RegVal {
  enum Kind { Unknown, Immediate, GlobalAddr };
  Kind K = Unknown;
  int64_t Value = 0;             // Immediate value or GlobalAddr offset
  const GlobalValue *GV = nullptr; // For GlobalAddr kind
};

struct FlagState {
  uint8_t KnownMask = 0;   // Which flags have known values (S,Z,AC,P,CY)
  uint8_t KnownValue = 0;  // The known values of those flags
};

// Per-BB forward scan:
RegVal Regs[7];     // A, B, C, D, E, H, L
FlagState Flags;
```

### New patterns enabled

| Pattern | When | Saving |
|---------|------|--------|
| `MVI A, 0` → `XRA A` | Flags dead after | 1B |
| `XRI 0FFH` → `CMA` | Always (CMA doesn't affect flags) | 1B |
| `ORA A` → delete | Z flag already valid for A | 4cc, 1B |
| `CPI imm` → delete | Flags already reflect comparison | 4cc, 2B |
| `ANI n; ANI n` → `ANI n` | Consecutive identical ALU | 4cc, 2B |
| Sub-reg composition | H=known, L=known → HL=known | Enables more LXI elimination |

## Before → After

```asm
; Before                        ; After
MVI  A, 0       ;  8cc, 2B     XRA  A       ;  4cc, 1B  (flags dead)
...
XRI  0FFH       ;  8cc, 2B     CMA          ;  4cc, 1B
...
ADD  B          ;  4cc          ADD  B       ;  4cc      (sets Z flag)
ORA  A          ;  4cc, 1B     JZ   label   ; 12cc      (ORA A deleted)
JZ   label      ; 12cc
```

## Benefit

- **Savings per instance**: 1-2B and 4-8cc per pattern
- **Frequency**: Very high when combined — XRA A pattern alone is common
- **Cumulative**: jacobly0 reports this as their highest-impact optimization

## Complexity

Medium. ~200-300 lines extending existing O13 infrastructure. The core
tracking is straightforward; the complexity is in correctly modeling flag
effects of every instruction.

## Risk

Low-Medium. Must accurately model which instructions affect which flags.
The 8080's flag behavior is well-documented and deterministic.

## Dependencies

O13 (done) — extends the existing value tracking infrastructure.
Enhances O17 (redundant flag elimination) by providing richer flag state.
