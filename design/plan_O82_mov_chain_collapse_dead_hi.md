# Plan: O82 — MOV Chain Collapse and Dead High-Byte Elimination

## 1. Problem

### Current behavior

After O62, `V6CLANG_SRL16`-by-8 expansion emits a 2-instruction sequence:

```asm
MOV  DstLo, SrcHi     ; 8cc, 1B
MVI  DstHi, 0         ; 8cc, 2B  ← dead store when DstHi never read
```

When the only consumer is the low byte (e.g. an `i8` truncation or a
call argument), DstHi is set to zero but never read.  Furthermore, when
the low byte result is subsequently copied again into a call-argument
register, a two-hop copy chain forms:

```asm
MOV  E, H        ; SRL16: DstLo <- SrcHi         (I1)
MVI  D, 0        ; SRL16: DstHi <- 0             (dead)
MOV  A, L        ; argument x1
MOV  B, E        ; argument y1  (E was just set from H)  (I2)
CALL draw_line2
```

`E` is a dead intermediate: `H → E → B` can be shortened to `H → B`.
After the chain is collapsed, `MOV E, H` (I1) is also dead and can be
deleted.

Concrete instance: `samples/03_demo/main.s`, inner loop of `main`.

### Desired behavior

```asm
MOV  A, L        ; 8cc, 1B
MOV  B, H        ; 8cc, 1B  ← chain collapsed: H→E→B ⟹ H→B
CALL draw_line2
```

Both `MVI D, 0` and `MOV E, H` are eliminated; `MOV B, E` is rewritten
to `MOV B, H` in-place.  **Net savings: 16cc, 3B** per occurrence.

### Root cause

Two independent issues both rooted in `V6ClangPeephole.cpp`:

1. **No dead-MVI elimination**: `foldMviZeroToXraA` only replaces
   `MVI A, 0` → `XRA A`; it does not erase `MVI r, imm` when `r` is
   entirely dead.

2. **No copy-chain forwarding**: `eliminateRedundantMov` detects
   `MOV X, Y; MOV X, Y` (duplicate adjacent copy), but not the
   `MOV X, Y; ...; MOV Z, X` (dead-intermediate forwarding) pattern.

---

## 2. Strategy

### Approach: two new helpers in `V6ClangPeephole`

**Pattern A — `eliminateDeadMVI`**: scan every `MVI r, imm` in each
MBB.  If `isRegDeadAfter(MBB, MI.getIterator(), r, TRI)` returns true,
the write is dead and the instruction can be erased.  Guard against O61
patched MVIs (they carry a pre-instruction symbol and must not be removed).

**Pattern B — `collapseMovChain`**: scan every `MOVrr X, Y`.
Walk forward up to `kChainWindow` non-debug instructions.  If, along the
way, we find `MOVrr Z, X` where:
- no intervening instruction reads or writes X or Y,
- `isRegDeadAfter` confirms X is dead after the consumer MOV,

then rewrite the consumer to `MOVrr Z, Y`.  After the rewrite, check
whether X is now dead at I1 (`isRegDeadAfter` from I1); if so, erase I1
as well.

Both helpers are run at the end of the existing per-MBB loop in
`runOnMachineFunction`, after `eliminateRedundantMov`.  Pattern A fires
first (dead store removal is a prerequisite for clean chain forwarding),
then Pattern B.

### Why this works

- All peephole safety properties are preserved: both patterns only erase
  instructions whose output is provably dead, using the existing
  `isRegDeadAfter` utility which is already correct for physical
  registers, aliases, and successor live-ins.
- Pattern A and B are complementary: A eliminates the `MVI D, 0` dead
  store; B eliminates the `MOV E, H` intermediate and rewrites
  `MOV B, E` → `MOV B, H`.
- The local `isRegDeadAfter` already handles pair-register aliases via
  `TRI->regsOverlap`, so a query on `E` automatically detects reads of
  `DE`.
- Pattern B's window cap (`kChainWindow = 8`) prevents O(N²) scan
  behaviour in large blocks.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add `eliminateDeadMVI` | Erase `MVI r, imm` when r dead | V6ClangPeephole.cpp |
| Add `collapseMovChain` | Forward `MOV X,Y;…;MOV Z,X` → `MOV Z,Y` | V6ClangPeephole.cpp |
| Declare both helpers | Add to private methods | V6ClangPeephole.cpp |
| Wire into `runOnMachineFunction` | Call after `eliminateRedundantMov` | V6ClangPeephole.cpp |
| Lit test | `tests/features/63/` | see Step 3.5 |

---

## 3. Implementation Steps

### Step 3.1 — Add `eliminateDeadMVI` helper [ ]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Add a new private method after `foldMviZeroToXraA`:

```cpp
/// O82 Pattern A: erase MVI r, imm when r is dead after the instruction.
/// MVI r, imm writes only r and does not set FLAGS, so erasing it when r
/// is dead is always safe. O61 patched MVIs are excluded because the label
/// on the MVI byte is referenced by STA spills.
bool V6ClangPeephole::eliminateDeadMVI(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (MachineInstr &MI : llvm::make_early_inc_range(MBB)) {
    if (MI.getOpcode() != V6CLANG::MVIr)
      continue;
    // Skip MVI A — handled separately by foldMviZeroToXraA / foldMviAluImm.
    Register Dst = MI.getOperand(0).getReg();
    if (Dst == V6CLANG::A)
      continue;
    // Skip O61 patched-immediate sites (pre-instr label or MO_PATCH_IMM flag).
    if (isO61PatchedImm(MI))
      continue;
    if (!isRegDeadAfter(MBB, MI.getIterator(), Dst, TRI))
      continue;
    MI.eraseFromParent();
    Changed = true;
  }
  return Changed;
}
```

Also add the declaration to the `V6ClangPeephole` class private section:

```cpp
  bool eliminateDeadMVI(MachineBasicBlock &MBB);
```

> **Design Notes**:
> - We skip `MVI A` because it is handled more precisely by the existing
>   `foldMviZeroToXraA` (which can additionally rewrite to `XRA A`) and
>   `foldMviAluImm`.  Deferring keeps the logic clean and avoids
>   double-elimination.
> - The O61 guard (`isO61PatchedImm`) is the same check used by
>   `foldMviZeroToXraA` and `foldIncDecMviM`; copy it verbatim.
> - `isRegDeadAfter` already inspects pair aliases, so querying `D`
>   correctly accounts for any read of the `DE` pair.

> **Implementation Notes**: <empty — filled after completion>

---

### Step 3.2 — Add `collapseMovChain` helper [ ]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Add after `eliminateDeadMVI`:

```cpp
/// O82 Pattern B: collapse MOV X, Y; ...; MOV Z, X → MOV Z, Y when X
/// is a dead intermediate (no read of X between the two MOVs, X dead
/// after the consumer MOV).
///
/// After rewriting the consumer, if X is also dead at the producer, the
/// producer is erased too. Scan window is bounded to avoid O(N²) cost.
bool V6ClangPeephole::collapseMovChain(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  static constexpr unsigned kChainWindow = 8;

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    MachineInstr &ProducerMI = *I;
    if (ProducerMI.getOpcode() != V6CLANG::MOVrr)
      continue;

    Register X = ProducerMI.getOperand(0).getReg(); // intermediate
    Register Y = ProducerMI.getOperand(1).getReg(); // original source

    if (X == Y) // self-copy — handled by eliminateSelfMov
      continue;

    // Walk forward looking for a consumer MOV Z, X.
    unsigned Steps = 0;
    bool Blocked = false;
    auto J = std::next(I);
    for (; J != E && Steps < kChainWindow; ++J) {
      if (J->isDebugInstr())
        continue;
      ++Steps;

      // Check whether J reads or clobbers X or Y (other than as the
      // expected consumer MOV Z, X).
      bool ReadsX = false, ClobbersX = false, ClobbersY = false;
      for (const MachineOperand &MO : J->operands()) {
        if (!MO.isReg() || !MO.getReg())
          continue;
        if (TRI->regsOverlap(MO.getReg(), X)) {
          if (MO.isUse() && !MO.isUndef()) ReadsX = true;
          if (MO.isDef())                  ClobbersX = true;
        }
        if (TRI->regsOverlap(MO.getReg(), Y) && MO.isDef())
          ClobbersY = true;
      }

      if (ClobbersX || ClobbersY) {
        Blocked = true;
        break;
      }

      // Is this a MOV Z, X consumer?
      if (J->getOpcode() == V6CLANG::MOVrr &&
          TRI->regsOverlap(J->getOperand(1).getReg(), X) &&
          !ReadsX) {
        // X used only as source of this copy and is dead after it.
        if (isRegDeadAfter(MBB, J, X, TRI)) {
          // Forward: rewrite MOV Z, X → MOV Z, Y.
          J->getOperand(1).setReg(Y);
          // If X is now dead at the producer, erase the producer.
          if (isRegDeadAfter(MBB, I, X, TRI)) {
            auto Next = std::next(I);
            ProducerMI.eraseFromParent();
            I = std::prev(Next);
          }
          Changed = true;
        }
        break; // stop scan regardless (X already consumed or still live)
      }

      // X is read by something other than our target MOV Z, X — abort.
      if (ReadsX) {
        Blocked = true;
        break;
      }
    }
    (void)Blocked; // scan ends — no further action on failure
  }
  return Changed;
}
```

Add declaration to class:

```cpp
  bool collapseMovChain(MachineBasicBlock &MBB);
```

> **Design Notes**:
> - The forward scan stops at the first instruction that clobbers X or Y
>   (the source of the chain would be stale), or the first non-copy read
>   of X (X is needed for something else — safe to skip but chain can't
>   be removed).
> - `isRegDeadAfter(MBB, J, X, TRI)` is called *after* the rewrite:
>   because the rewrite just changed `J`'s read of X to a read of Y, the
>   dead check now correctly reflects that X has no readers from J
>   onward.
> - `isRegDeadAfter(MBB, I, X, TRI)` is the second liveness check: it
>   confirms X has no readers between I and J inclusive (I's write of X
>   is the only def).  After the consumer rewrite this is guaranteed to
>   return true in the motivating case, but the explicit check is a
>   safety guard.

> **Implementation Notes**: <empty — filled after completion>

---

### Step 3.3 — Wire both helpers into `runOnMachineFunction` [ ]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

In `runOnMachineFunction`, add after `eliminateRedundantMov`:

```cpp
    Changed |= eliminateDeadMVI(MBB);
    Changed |= collapseMovChain(MBB);
```

Full block after patch:

```cpp
    Changed |= eliminateSelfMov(MBB);
    Changed |= eliminateRedundantMov(MBB);
    Changed |= eliminateDeadMVI(MBB);    // O82 Pattern A
    Changed |= collapseMovChain(MBB);    // O82 Pattern B
    Changed |= foldCounterBranch(MBB);
```

> **Design Notes**:
> - Pattern A (eliminateDeadMVI) runs before Pattern B so that any dead
>   MVI between I1 and the consumer is already removed before the chain
>   scan, keeping the scan window short and the intervening-instruction
>   check simple.
> - Both run after `eliminateSelfMov` (eliminates `MOV X, X` no-ops that
>   could confuse the chain walk) and `eliminateRedundantMov` (eliminates
>   duplicate adjacent copies which are a degenerate chain case already
>   handled).

> **Implementation Notes**: <empty — filled after completion>

---

### Step 3.4 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

---

### Step 3.5 — Verify feature test assembly [ ]

Compile the feature test with the new build and verify both patterns fire:

```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\63\v6clang.c -o tests\features\63\v6clang_new01.asm
```

Expected in `test_chain_and_dead_hi`:
- `MOV B, H` present (chain collapsed)
- `MVI D, 0` absent  (dead store removed)
- `MOV E, H` absent  (producer removed after chain collapse)

Expected in `test_dead_hi`:
- `MVI D, 0` absent (dead store removed)

---

### Step 3.6 — Run regression tests [ ]

```
python tests\run_all.py
```

Fix any failures before proceeding.

---

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [ ]

Compile, analyze, present improvements to user.

---

### Step 3.8 — Make sure result.txt is created [ ]

See `tests\features\result.md` for format.

---

### Step 3.9 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Example 1 — `test_chain_and_dead_hi` (motivating case)

```asm
; Before (5 instructions, 5B, 40cc before CALL):
    MOV  E, H        ; 8cc, 1B  SRL16 DstLo
    MVI  D, 0        ; 8cc, 2B  SRL16 DstHi — DEAD (Pattern A)
    MOV  A, L        ; 8cc, 1B  x1 argument
    MOV  B, E        ; 8cc, 1B  y1 argument via intermediate E (Pattern B)
    CALL draw_stub

; After (2 instructions, 2B, 16cc before CALL):
    MOV  A, L        ; 8cc, 1B  x1 argument
    MOV  B, H        ; 8cc, 1B  y1 argument direct from H
    CALL draw_stub
```

**Savings: 16cc, 3B** per call site.

### Example 2 — `test_dead_hi` (isolated Pattern A)

```asm
; Before:
    MOV  E, H        ; SRL16 DstLo
    MVI  D, 0        ; SRL16 DstHi — DEAD
    MOV  A, E        ; truncate to i8
    CALL use_byte

; After:
    MOV  A, H        ; SRL16 DstLo, chain B may also fire here
    CALL use_byte
```

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Pattern B rewrites wrong instruction if X is aliased by a pair | `TRI->regsOverlap` handles aliasing; the `ClobbersX` and `ReadsX` checks cover all sub-/super-registers |
| O61 patched MVIs silently removed | `isO61PatchedImm` guard inherited from `foldMviZeroToXraA` |
| Iterator invalidation after erase in `collapseMovChain` | Producer is erased only after saving `Next = std::next(I)` and resetting `I = std::prev(Next)` |
| Chain window too small, pattern missed | kChainWindow=8 covers the motivating case (gap is 2 instructions); enlarging it is a future tuning knob |
| Regression in blocks with complex liveness | Full regression suite (`tests/run_all.py`) covers all existing feature tests |

---

## 6. Relationship to Other Improvements

| Plan | Relation |
|------|----------|
| O62 — Efficient Shift Expansion | Prerequisite (✅). O62 reduced SRL16-by-8 from 4 MOVs to 2; O82 eliminates the remaining waste. |
| O01 — Redundant MOV Elimination | O01 covers `MOV X, A; MOV A, X` only. Pattern B generalises to arbitrary GR8 pairs. |
| O55 — Additional Peepholes | Precedent for FLAGS-gated MVI rewrite in `V6ClangPeephole`; Pattern A is simpler (no FLAGS involvement). |
| O79 — MVI+ALU Fold | Both use `isRegDeadAfter` to decide safety; no interaction. |

---

## 7. Future Enhancements

- Extend Pattern B to handle chains longer than 2 hops (`MOV X,Y; MOV Z,X; MOV W,Z`).
- Generalise Pattern A to `MOV r, r'` (not just `MVI`) when r is dead — subsumed by a general dead-copy elimination pass (llvm_mos_analysis §S3).
- Increase `kChainWindow` from 8 to 16 after measuring compile-time impact on large functions.

---

## 8. References

- [V6CLANG Build Guide](docs/V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](docs/Vector_06c_instruction_timings.md)
- [Future Improvements](design/future_plans/README.md)
- [O82 Design](design/future_plans/O82_mov_chain_collapse_dead_hi.md)
- [V6ClangPeephole.cpp](llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp)
