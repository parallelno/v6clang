# O82 — MOV Chain Collapse and Dead High-Byte Elimination

**Source:** V6CLANG — observed in `samples/03_demo/main.s` (SRL16 + call-argument setup)
**Savings:** 2 instructions, 2B, 16cc per occurrence
**Frequency:** Every `lshr i16, 8` result whose high byte is unused at the call site (common after `rand() & 0x7f` / `rand() >> 8` patterns)
**Complexity:** Low — two independent peephole patterns, each ~20 lines
**Risk:** Low — both patterns remove provably dead or redundant copies
**Dependencies:** O62 done (SRL16 expansion is already optimal at 2 instructions); no further prerequisites
**Status:** [ ] not started

---

## Problem

After O62, the `V6CLANG_SRL16`-by-8 expansion emits the minimal 2-instruction
sequence:

```asm
MOV  DstLo, SrcHi     ; 8cc, 1B
MVI  DstHi, 0         ; 8cc, 2B  ← Pattern A: high byte may be dead
```

When the consumer only uses `DstLo` (common after a truncation to `i8` or a
call where the high byte is not a parameter), `DstHi` is never read.  The
`MVI DstHi, 0` is a dead store.

Additionally, the subsequent call-argument shuffle can produce a copy chain:

```asm
MOV  E, H        ; SRL16: DstLo <- SrcHi   ← Pattern B intermediate
MVI  D, 0        ; SRL16: DstHi <- 0       ← Pattern A dead store
MOV  A, L        ; argument x1
MOV  B, E        ; argument y1 — copies E that was just loaded from H
CALL draw_line2
```

`E` is an unnecessary intermediate: `H → E → B` can be shortened to `H → B`
directly.  After the chain is collapsed `MOV E, H` also becomes dead.

### Concrete instance (`samples/03_demo/main.s`)

```asm
; Current (O62 already applied, 4 instructions before call):
;--- V6CLANG_SRL16 ---
    MOV  E, H        ; 8cc, 1B  — SRL16 DstLo
    MVI  D, 0        ; 8cc, 2B  — SRL16 DstHi (D never read)  [Pattern A]
    MOV  A, L        ; 8cc, 1B  — x1 = rand_lo
    MOV  B, E        ; 8cc, 1B  — y1 = E (= H)                [Pattern B]
    CALL draw_line2  ; x1=A, y1=B

; Optimal (2 instructions, same result):
    MOV  A, L        ; 8cc, 1B
    MOV  B, H        ; 8cc, 1B  — chain collapsed: H→E→B ⟹ H→B
    CALL draw_line2
```

**Net savings: 16cc, 2B** (MVI D,0 deleted + MOV E,H deleted).

---

## Pattern A — Dead Immediate Store Elimination

### Trigger

`MVI r, imm` where `r` is dead at that point — i.e. every path from that
instruction to the next definition of `r` (or function exit) does not read `r`.

### Peephole rule

In `V6ClangPeephole`, scan each `MVI r, imm` (opcode `V6CLANG::MVIr` or `V6CLANG::MVI_A`).
Query liveness of `r` immediately after the instruction.  If `r` is dead, erase
the instruction.

```cpp
// In V6ClangPeephole::runOnMachineFunction (or a new helper):
if (MI.getOpcode() == V6CLANG::MVIr || MI.getOpcode() == V6CLANG::MVI_A) {
  Register Dst = MI.getOperand(0).getReg();
  if (isRegDeadAfterMI(Dst, MI, MBB, TRI)) {
    MI.eraseFromParent();
    Changed = true;
    continue;
  }
}
```

`isRegDeadAfterMI` is already used extensively in `V6ClangSpillExpand.cpp` and
`V6ClangRegisterInfo.cpp`.

### Safety

`MVIr` / `MVI_A` write only the destination register and do not set flags
(unlike `XRA`).  Erasing the instruction when `Dst` is dead is always safe.

### Benefit per occurrence

8cc, 2B.

---

## Pattern B — Copy Chain Collapse

### Trigger

```
MOV  X, Y    ; (instruction I1)
[zero or more instructions that neither read nor write X or Y]
MOV  Z, X    ; (instruction I2) where X is dead after I2
```

Replace I2 with `MOV Z, Y` and then re-check I1: if X is now dead at I1 (no
other intervening read), erase I1 as well.

### Peephole rule

Extend `V6ClangPeephole::eliminateRedundantMov()`:

```cpp
// After the existing duplicate-MOV check:
// Pattern B: MOV X, Y; ...; MOV Z, X  where X dead after second MOV.
if (MI.getOpcode() == V6CLANG::MOVrr) {
  Register X = MI.getOperand(0).getReg();
  Register Y = MI.getOperand(1).getReg();

  // Scan forward within a small window for a consumer MOV Z, X.
  for (auto J = std::next(I); J != E && windowOK(I, J); ++J) {
    MachineInstr &JMI = *J;
    if (clobbersReg(JMI, X) || clobbersReg(JMI, Y))
      break; // X or Y overwritten before consumer — can't forward
    if (readsReg(JMI, X) && JMI.getOpcode() != V6CLANG::MOVrr)
      break; // X used for something other than a copy — don't touch
    if (JMI.getOpcode() == V6CLANG::MOVrr &&
        JMI.getOperand(1).getReg() == X &&
        isRegDeadAfterMI(X, JMI, MBB, TRI)) {
      // X is a dead intermediate: forward Y directly into Z.
      JMI.getOperand(1).setReg(Y);
      // If X is now completely dead at I (no reads between I and J):
      if (isRegDeadAfterMI(X, MI, MBB, TRI))
        MI.eraseFromParent();
      Changed = true;
      break;
    }
  }
}
```

`windowOK` limits the scan to avoid O(N²) behaviour in large blocks — a
window of 8–16 non-debug instructions is sufficient in practice.

### Safety

- Forwarding is only performed when no instruction between I1 and I2 reads or
  writes X or Y; this is checked by `clobbersReg` / `readsReg`.
- I1 is erased only when a second liveness check confirms X has no other
  readers after I1 (the check on `isRegDeadAfterMI(X, MI, …)` after the
  forward-rewrite ensures this).
- The pattern does not change flags or memory.

### Benefit per occurrence

8cc, 1B (the erased I2 `MOV Z, X` is replaced in-place by `MOV Z, Y` of equal
cost; the deleted I1 `MOV X, Y` saves 8cc, 1B).

---

## Combined savings for the motivating instance

| Instruction removed | cc | B |
|---|---|---|
| `MVI D, 0` (Pattern A) | 8 | 2 |
| `MOV E, H` (Pattern B, I1 erased after chain collapse) | 8 | 1 |
| **Total** | **16** | **3** |

(The replacement `MOV B, E` → `MOV B, H` is in-place, no cost change.)

---

## Relationship to other plans

| Plan | Relation |
|---|---|
| O01 — Redundant MOV Elimination | O01 handles only `MOV X,A; MOV A,X` (A↔dst symmetric). Pattern B generalises to arbitrary GR8 pairs. |
| O62 — Efficient Shift Expansion | Prerequisite (done). O62 reduces SRL16-by-8 from 4 MOVs to 2; O82 eliminates the remaining waste. |
| llvm_mos_analysis §S3 — Global Copy Optimization | A future inter-BB copy-forwarding pass would subsume Pattern B. O82 is an intra-BB approximation that fires immediately. |
| O55 — Additional Peepholes | Precedent for extending the peephole pass with liveness-gated rewrites. |

---

## Implementation location

Both patterns live in
[`V6ClangPeephole.cpp`](../../llvm/lib/Target/V6Clang/V6ClangPeephole.cpp):

- Pattern A: new helper `eliminateDeadMVI()`, called from `runOnMachineFunction`.
- Pattern B: extension of the existing `eliminateRedundantMov()`.

No TableGen changes.  No new pseudo instructions.  No ISel changes.

---

## Test

Add a lit test (`tests/features/NN/v6clang.ll` or `.c`) that compiles:

```c
void draw_line2(char x1, char y1);
int rand(void);
void test(void) {
    int r = rand();
    draw_line2((char)r, (char)(r >> 8));
}
```

and `FileCheck`-asserts that the output contains `MOV B, H` and does **not**
contain `MVI D, 0` or `MOV E, H`.
