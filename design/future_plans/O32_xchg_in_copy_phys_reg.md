# O32. XCHG in copyPhysReg (RA-Time DE↔HL Swap)

*Identified from investigation of missed XCHG in test_null_guard (O30 feature test).*
*The register allocator already knows source liveness — use it.*

## Problem

When the register allocator needs to copy between DE and HL, it calls
`V6ClangInstrInfo::copyPhysReg()` which unconditionally emits two MOV
instructions (2 bytes, 16cc). The 8080 has `XCHG` (1 byte, 4cc) which
swaps DE↔HL.

The RA passes a `KillSrc` flag: when `true`, the source register pair is
dead after the copy. In that case XCHG is semantically safe — the
"reverse swap" into the source pair doesn't matter since nobody reads it.

This is a strictly better approach than relying on the post-RA peephole
(V6ClangXchgOpt), because:
- The RA has **authoritative liveness** — `KillSrc` is always correct
- No pattern-matching heuristics needed
- Runs earlier, giving downstream passes better code to work with
- No false negatives from conservative liveness checks

### Example: `test_null_guard`

The RA inserts a copy `DE → HL` at the function epilogue with `KillSrc=true`
(DE is dead after the copy). Current output:

```asm
.LBB3_2:
    MOV  H, D           ; 1B  8cc
    MOV  L, E           ; 1B  8cc
    RET                 ; 1B 12cc
```

With XCHG in copyPhysReg:

```asm
.LBB3_2:
    XCHG                ; 1B  4cc
    RET                 ; 1B 12cc
```

Savings: **1 byte, 12cc** per DE↔HL copy where source is killed.

### Example: `test_multi_cond` (.LBB2_3)

```asm
.LBB2_3:
    MOV  H, D           ; 1B  8cc   ← RA copy DE→HL, KillSrc=true
    MOV  L, E           ; 1B  8cc
    JMP  bar            ; 3B 12cc
```

With XCHG:
```asm
.LBB2_3:
    XCHG                ; 1B  4cc
    JMP  bar            ; 3B 12cc
```

Savings: **1 byte, 12cc**.

### Frequency

Every DE↔HL copy inserted by the register allocator where the source is
killed. This is the majority of 16-bit register copies — the RA typically
copies a value to the return register (HL) at function exits, or moves
a value into HL for memory addressing. Estimated frequency: Medium-High
(1-3 instances per function with register pressure).

### What this does NOT cover

- MOV pairs emitted by `expandPostRAPseudos()` (e.g., V6CLANG_LOAD16_P address
  setup) — these bypass `copyPhysReg`
- RA copies where `KillSrc=false` but the source becomes dead later due to
  other post-RA optimizations
- MOV pairs introduced by other post-RA passes

These remaining cases are handled by O33 (V6ClangXchgOpt relaxation).

## Implementation

### Location

`V6ClangInstrInfo::copyPhysReg()` in `V6ClangInstrInfo.cpp` (lines 23-55).

### Change

Add a check before the existing 16-bit copy code: if both registers are
in {DE, HL} and `KillSrc` is true, emit XCHG instead of two MOVs.

```cpp
// 16-bit pair copy: two MOV instructions (hi byte, then lo byte)
if (V6CLANG::GR16RegClass.contains(DestReg) &&
    V6CLANG::GR16RegClass.contains(SrcReg)) {

  // DE↔HL with source killed: use XCHG (1B/4cc vs 2B/16cc).
  // Safe because source is dead — the reverse swap side-effect is harmless.
  if (KillSrc &&
      ((DestReg == V6CLANG::HL && SrcReg == V6CLANG::DE) ||
       (DestReg == V6CLANG::DE && SrcReg == V6CLANG::HL))) {
    BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    return;
  }

  // General case: two MOV instructions
  ...
}
```

### Testing

- Compile `test_null_guard` and verify XCHG appears instead of MOV H,D; MOV L,E
- Compile `test_multi_cond` and verify .LBB2_3 uses XCHG
- Run full lit + golden regression suite
- Create lit test with `; CHECK: XCHG` for DE→HL copy with dead source

### Risks

- **Very Low**: `KillSrc` is set by the register allocator and is always
  accurate for physical register copies
- XCHG clobbers both DE and HL — but `KillSrc=true` guarantees the source
  is dead, and the destination gets the correct value
- No interaction with FLAGS (XCHG does not affect flags on 8080)

### Dependencies

- None. Standalone change to `copyPhysReg()`.
- Supersedes most cases that V6ClangXchgOpt (existing peephole) catches.
- O33 handles remaining edge cases.
