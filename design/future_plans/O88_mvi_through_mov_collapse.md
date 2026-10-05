# O88 — MVI-through-MOV Collapse (V6CLANG_BUILD_PAIR zero-hi peephole)

**Source:** V6CLANG — observed in `samples/03_demo/main.s` (`sin8`, `draw_circle`)
**Savings:** 8cc, 1B per occurrence
**Frequency:** Every `zext i8 → i16` that ISel materialises as `MVI r, 0; V6CLANG_BUILD_PAIR`
**Complexity:** Low — extends the existing `collapseMovChain` peephole (~20 lines)
**Risk:** Low — only removes a provably dead immediate store
**Dependencies:** O82 done (infrastructure already in place)
**Status:** [ ] not started

---

## Problem

`V6CLANG_BUILD_PAIR dst, lo_reg, hi_reg` expands to two `MOVrr` copies:

```asm
MOV  DstHi, hi_reg    ; copy hi half
MOV  DstLo, lo_reg    ; copy lo half
```

When `hi_reg` holds a zero that was materialised by an immediately preceding
`MVI hi_reg, 0`, and `hi_reg` is dead after the `MOV DstHi, hi_reg` consumer,
the `MVI` is a dead store that can be folded directly into the destination:

```asm
; Before                                 ; After
MVI  L, 0         ; 8cc, 2B             MVI  H, 0         ; 8cc, 2B
;--- V6CLANG_BUILD_PAIR ---                  ;--- V6CLANG_BUILD_PAIR ---
MOV  H, L         ; 8cc, 1B  ← elim    MOV  L, A         ; 8cc, 1B
MOV  L, A         ; 8cc, 1B
```

Net savings: **8cc, 1B** — the `MOV H, L` round-trip is eliminated and the
`MVI L, 0` becomes `MVI H, 0` (writing directly to the destination).

### Concrete instance (`sin8`, line 585)

```asm
MVI   L, 0
;--- V6CLANG_BUILD_PAIR ---
MOV   H, L        ← redundant: L was only ever 0, copy to H is MVI H, 0
MOV   L, A
LXI   D, sin_lut
DAD   D
MOV   A, M
RET
```

The zero-extend of `angle` (in A) to i16 sets `hi = 0`. ISel assigns both
`hi_reg = L` (for the MVI materialisation) and `DstHi = H`, so it emits
`MVI L, 0; MOV H, L` instead of the direct `MVI H, 0`.  The extra `MOV H, L`
costs 8cc/1B and is never needed.

The same pattern appears in `draw_circle` (`MVI C, 0; MOV H, C; …`) and
wherever a zero-extended byte is placed into the high half of a pair.

---

## Root-cause analysis

`collapseMovChain` in `V6ClangPeephole.cpp` already collapses `MOV X, Y; …; MOV Z, X`
chains when X is dead.  It only handles `MOVrr` **producers** — the outer loop
begins:

```cpp
if (ProducerMI.getOpcode() != V6CLANG::MOVrr)
    continue;
```

The producer here is `MVIr L, 0`, not a `MOVrr`, so the scan never starts and
the dead intermediate `L` is never eliminated.

`eliminateDeadMVI` also cannot fire: it erases `MVI r, imm` only when `r` is
dead *immediately after* the MVI, but `r = L` is still live at the `MOV H, L`
consumer one instruction later.

---

## Proposed fix

Extend `collapseMovChain` to also enter its forward scan when the producer is
`MVIr` (including `MVI_A`).  When the consumer `MOV DstHi, r` is found and `r`
is dead after it, replace the consumer with `MVI DstHi, imm` and erase the
original `MVIr`.

### Pseudocode

```cpp
bool V6ClangPeephole::collapseMovChain(MachineBasicBlock &MBB) {
  // ... existing MOVrr producer loop unchanged ...

  // NEW: MVIr producer variant
  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    MachineInstr &ProducerMI = *I;
    if (ProducerMI.getOpcode() != V6CLANG::MVIr)  // (also handle MVI_A if needed)
      continue;
    if (isO61PatchedImm(ProducerMI))
      continue;

    Register X   = ProducerMI.getOperand(0).getReg(); // intermediate reg
    int64_t  Imm = ProducerMI.getOperand(1).getImm();

    unsigned Steps = 0;
    for (auto J = std::next(I); J != E && Steps < kChainWindow; ++J) {
      if (J->isDebugInstr()) continue;
      ++Steps;

      // Bail if anything reads or redefines X before the consumer.
      bool ReadsX = false, ClobbersX = false;
      for (const MachineOperand &MO : J->operands()) {
        if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), X)) continue;
        if (MO.isUse() && !MO.isUndef()) ReadsX = true;
        if (MO.isDef())                  ClobbersX = true;
      }

      bool IsConsumer = J->getOpcode() == V6CLANG::MOVrr &&
                        TRI->regsOverlap(J->getOperand(1).getReg(), X);

      if (IsConsumer) {
        if (ClobbersX) break;
        if (isRegDeadAfter(MBB, J, X, TRI)) {
          // Replace MOV DstHi, X  →  MVI DstHi, Imm
          Register Z = J->getOperand(0).getReg();
          const TargetInstrInfo &TII =
              *MBB.getParent()->getSubtarget().getInstrInfo();
          BuildMI(MBB, J, J->getDebugLoc(), TII.get(V6CLANG::MVIr), Z)
              .addImm(Imm);
          J->eraseFromParent();
          ProducerMI.eraseFromParent();
          Changed = true;
        }
        break;
      }

      if (ReadsX || ClobbersX) break;
    }
  }
  return Changed;
}
```

### Safety conditions

| Condition | Why |
|-----------|-----|
| Producer is `MVIr` and not O61-patched | Patched MVIs carry a label; erasing them orphans the spill site |
| No instruction between producer and consumer reads or redefines X | Ensures the intermediate value is only consumed by the `MOV DstHi, X` |
| X is dead after the consumer `MOV DstHi, X` | Ensures the producer → consumer chain is the sole use |
| Replacement is `MVIr DstHi, Imm` | MVIr can target any GR8 register |

Note: this transform is **not** gated on `hi_reg` being zero specifically — it
fires for any immediate value, though zero is by far the most common case (zext).

---

## Affected patterns in `main.s`

| Site | Before | After | Saving |
|------|--------|-------|--------|
| `sin8` | `MVI L, 0; MOV H, L` | `MVI H, 0` | 8cc, 1B |
| `draw_circle` `.LLo61_0` | `MVI C, 0; MOV H, C; … MOV B, C` | more complex (two consumers of C) | see below |

The `draw_circle` occurrence has **two** consumers of `C` after `MVI C, 0`:
`MOV H, C` (BUILD_PAIR hi) and `MOV B, C` (another BUILD_PAIR hi). The
kChainWindow scan will only match the *first* consumer; the second will be
handled by a subsequent `eliminateDeadMVI` pass (once both consumers redirect
to `MVI`, the original `MVI C, 0` becomes truly dead).  Iterating the peephole
pass (as `runOnMachineFunction` already does for each BB) handles this.

---

## Benefit summary

- **Per-instance saving**: 8cc, 1B
- **`sin8` function**: −8cc, −1B (a tight inner helper; every cycle matters)
- **`draw_circle` loop body**: potentially −16cc, −2B once both consumers fold
- **General impact**: fires on every `zext i8 → i16` that RA assigns via an
  intermediate register rather than directly into the destination half

---

## Implementation notes

1. The new loop is structurally identical to the existing `collapseMovChain`
   `MOVrr`-producer loop. Consider refactoring into a shared helper or simply
   add the `MVIr`-producer case as a second loop in the same function.
2. `MVI_A` (opcode for `MVI A, imm`) should be handled separately only if RA
   ever places A as the zero-extend intermediate; in practice RA prefers B/C/D/E
   for this role because A is pinned to the accumulator, so `MVIr` alone covers
   all observed cases.
3. The `isO61PatchedImm` guard is **required** — O61 patched sites have a
   pre-instruction symbol that assembler spill sites reference via `Sym+1`; an
   erased MVI would orphan those references.
4. Run `eliminateDeadMVI` **after** `collapseMovChain` (already the case in
   `runOnMachineFunction`) so that any remaining dead `MVIr X` left by a
   multi-consumer collapse gets cleaned up in the same pass invocation.
