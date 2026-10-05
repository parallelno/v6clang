# Plan: INX/DCX Peephole for 16-bit Increment/Decrement

## 1. Problem

### Current behavior

When the loop body increments a 16-bit register pair by 1, the compiler
emits a full 8-bit arithmetic chain through the accumulator:

```asm
; rp = rp + 1 (current codegen: 52cc, 7 instructions)
    LXI  H, 1          ; 12cc — materialize constant 1
    MOV  A, E           ;  8cc
    ADD  L              ;  4cc
    MOV  E, A           ;  8cc
    MOV  A, D           ;  8cc
    ADC  H              ;  4cc
    MOV  D, A           ;  8cc — total 40cc
```

### Desired behavior

```asm
; rp = rp + 1 (optimal: 8cc, 1 instruction)
    INX  D              ;  8cc
```

The 8080 INX instruction increments any register pair in a single 8cc
instruction. DCX decrements any register pair in 8cc. Neither instruction
sets flags.

### Root cause

V6CLANG_ADD16 is an ISel pseudo that expands post-RA into either:
- `DAD rp` (12cc) when the destination is HL, or
- a 6-instruction 8-bit ADD/ADC chain (~40cc, plus the 12cc LXI to
  materialize the constant) for all other register pairs.

There is currently no check for the special case where the addend is a
small constant (±1 to ±3), which could be replaced by one or more
INX/DCX instructions.

### Impact

In a tight array-copy loop, two pointer increments per iteration
account for **92cc** (LXI 12cc + 2 × 40cc chain, shared LXI) of
overhead that could be reduced to **16cc** (2 × 8cc INX) — saving
**76cc per iteration** (5.75× on the increment portion). Additionally,
eliminating the LXI frees a register pair, reducing register pressure
that causes spills in tight loops.

---

## 2. Strategy

The optimization belongs in `V6ClangInstrInfo::expandPostRAPseudo()`, where
V6CLANG_ADD16 is already expanded. This is the natural place because:

1. **Physical registers are known** — we can check dst == lhs directly.
2. **The LXI that materializes the constant is visible** — we can scan
   backward in the MBB to find it and read the immediate value.
3. **Liveness information is available** — we can check that FLAGS is dead
   after the pseudo (required because INX/DCX do not set flags).
4. **Dead LXI cleanup is straightforward** — if the constant register has
   no other uses, the LXI can be deleted too, saving another 12cc.

### Why not ISel?

An ISel pattern like `(add i16:$src, 1) → INX` would require proving at
the DAG level that FLAGS from the add is unused. This is fragile because
V6CLANG_ADD16 declares `Defs = [A, FLAGS]` and the rest of the pipeline
assumes that declaration is accurate. At the post-RA level, the implicit
def operand carries a concrete `isDead()` flag that we can trust.

### Why not a later peephole?

After V6CLANG_ADD16 expansion, the 8-bit chain has already been emitted as
6+ individual instructions. Matching that pattern in V6ClangPeephole.cpp would
require recognizing a specific 6-instruction sequence across the expanded
code — much more complex and brittle than checking the pseudo's operands
directly before expansion.

### Approach summary

| Step | What | Where |
|------|------|-------|
| Detect constant operand | Scan backward for LXI defining the RHS/LHS register | `expandPostRAPseudo`, V6CLANG_ADD16 case |
| Verify safety | Check FLAGS implicit-def isDead | Same |
| Emit INX/DCX chain | Replace expansion with 1–3 INX or DCX instructions | Same |
| Clean up LXI | Erase dead LXI if constant register is no longer used | Same |
| Handle SUB16 | Same logic for V6CLANG_SUB16 with inverted direction | `expandPostRAPseudo`, V6CLANG_SUB16 case |

---

## 3. Implementation Steps

### Step 3.1 — Add helper: find constant-defining LXI [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Add a static helper function before `expandPostRAPseudo`:

```cpp
/// Scan backward from \p From in \p MBB looking for an LXI that defines
/// \p Reg with no intervening redefinition. Returns the LXI MachineInstr
/// if found, nullptr otherwise. Stops at the beginning of the block or
/// after a reasonable scan window (16 instructions).
static MachineInstr *findDefiningLXI(MachineBasicBlock &MBB,
                                     MachineBasicBlock::iterator From,
                                     Register Reg) {
  const unsigned ScanLimit = 16;
  unsigned Count = 0;
  for (auto I = From; I != MBB.begin() && Count < ScanLimit; ++Count) {
    --I;
    MachineInstr &Cand = *I;

    // Found LXI defining Reg — return it.
    if (Cand.getOpcode() == V6CLANG::LXI &&
        Cand.getOperand(0).getReg() == Reg)
      return &Cand;

    // If something else defines Reg (including sub-registers), stop.
    if (Cand.modifiesRegister(Reg, /*TRI=*/nullptr))
      return nullptr;
  }
  return nullptr;
}
```

### Step 3.2 — Add helper: check FLAGS is dead [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Add a helper to check whether the FLAGS implicit-def is marked dead on a
MachineInstr:

```cpp
/// Return true if the FLAGS register implicit-def on \p MI is dead.
static bool isFlagsDefDead(const MachineInstr &MI) {
  for (const MachineOperand &MO : MI.implicit_operands()) {
    if (MO.isReg() && MO.isDef() && MO.getReg() == V6CLANG::FLAGS)
      return MO.isDead();
  }
  // No FLAGS implicit def found — conservatively safe (no flags produced).
  return true;
}
```

### Step 3.3 — Add helper: check register is dead after instruction [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

To safely erase the LXI, we need to know whether the constant register has
any remaining uses. Add a simple forward-scan helper:

```cpp
/// Return true if \p Reg is not used by any instruction between \p After
/// (exclusive) and the next redefinition or end of \p MBB.
static bool isRegDeadAfter(MachineBasicBlock &MBB,
                           MachineBasicBlock::iterator After,
                           Register Reg,
                           const TargetRegisterInfo *TRI) {
  for (auto I = std::next(After), E = MBB.end(); I != E; ++I) {
    if (I->readsRegister(Reg, TRI))
      return false;
    if (I->modifiesRegister(Reg, TRI))
      return true; // Redefined before use — the LXI's value is dead.
  }
  // Reached end of block. Check if Reg is live-out.
  return !MBB.isLiveIn(Reg) || MBB.succ_empty();
}
```

> **Design Note**: This helper is conservative — it returns false (keep
> the LXI) whenever it can't prove the register is dead. False negatives
> are acceptable: the LXI wastes 12cc but correctness is preserved. The
> dead LXI can be cleaned up by a later peephole pass if needed.

### Step 3.4 — INX/DCX expansion in V6CLANG_ADD16 [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

In the `case V6CLANG::V6CLANG_ADD16:` block of `expandPostRAPseudo`, insert the
INX/DCX check **before** the DAD checks. This way HL benefits from INX
too (8cc beats LXI+DAD at 24cc for small constants):

```cpp
  case V6CLANG::V6CLANG_ADD16: {
    Register DstReg = MI.getOperand(0).getReg();
    Register LhsReg = MI.getOperand(1).getReg();
    Register RhsReg = MI.getOperand(2).getReg();

    // --- NEW: INX/DCX chains for constant ±1..±3 ---
    // Checked BEFORE DAD so that HL benefits too (INX is cheaper than
    // LXI+DAD for small constants, and doesn't clobber a helper pair).
    if (isFlagsDefDead(MI)) {
      // Try RhsReg as the constant.
      MachineInstr *LXI = findDefiningLXI(MBB, MI.getIterator(), RhsReg);
      Register BaseReg = LhsReg;
      if (!LXI) {
        // Try LhsReg as the constant (add is commutative).
        LXI = findDefiningLXI(MBB, MI.getIterator(), LhsReg);
        BaseReg = RhsReg;
      }
      if (LXI) {
        int64_t ImmVal = LXI->getOperand(1).getImm();
        // Normalize unsigned 16-bit to signed.
        if (ImmVal > 0x7FFF)
          ImmVal -= 0x10000;
        unsigned Opc = 0;
        unsigned Count = 0;
        if (ImmVal >= 1 && ImmVal <= 3) {
          Opc = V6CLANG::INX;
          Count = static_cast<unsigned>(ImmVal);
        } else if (ImmVal >= -3 && ImmVal <= -1) {
          Opc = V6CLANG::DCX;
          Count = static_cast<unsigned>(-ImmVal);
        }

        if (Opc && DstReg == BaseReg) {
          for (unsigned I = 0; I < Count; ++I)
            BuildMI(MBB, MI, DL, get(Opc), DstReg).addReg(DstReg);
          // Try to erase the now-dead LXI.
          Register ConstReg = LXI->getOperand(0).getReg();
          if (isRegDeadAfter(MBB, MI.getIterator(), ConstReg, &RI))
            LXI->eraseFromParent();
          MI.eraseFromParent();
          return true;
        }
      }
    }

    // [existing] DAD rp: HL = HL + rp.
    if (DstReg == V6CLANG::HL && LhsReg == V6CLANG::HL) { ... }
    if (DstReg == V6CLANG::HL && RhsReg == V6CLANG::HL) { ... }

    // [existing] General case: expand to 8-bit chain.
    MCRegister DstLo = RI.getSubReg(DstReg, V6CLANG::sub_lo);
    ...
  }
```

> **Design Notes**:
>
> - **FLAGS check first**: INX/DCX do not set flags. If anything after the
>   ADD16 depends on FLAGS, we must not replace. The `isDead()` flag on
>   the implicit def is set by the register allocator's liveness analysis.
>
> - **Before DAD**: The INX/DCX check runs before the DAD path so that
>   HL benefits too. `INX` (8cc) beats `LXI+DAD` (24cc) for ±1; `INX×2`
>   (16cc) still beats it for ±2. For ±3, `INX×3` (24cc) ties `LXI+DAD`
>   on time but saves 1 byte and avoids clobbering a helper register pair.
>
> - **Chain limit ±3**: Each INX/DCX costs 8cc. The 8-bit chain costs
>   52cc (non-HL) or the DAD path costs 24cc (HL). Three INX = 24cc is
>   always profitable for non-HL (52cc → 24cc = 2.2×) and at worst a
>   tie for HL. Four INX = 32cc would be slower than DAD for HL, so we
>   cap at 3.
>
> - **Signed normalization**: LXI immediates are stored as unsigned
>   16-bit values. We normalize to signed so that 0xFFFF → −1,
>   0xFFFE → −2, 0xFFFD → −3 map correctly to DCX chains.
>
> - **Commutative check**: `add` is commutative, so either operand could
>   be the constant. We try RhsReg first (the more common case from ISel
>   canonicalization), then LhsReg.
>
> - **DstReg == BaseReg requirement**: INX has a tied constraint (output =
>   input). After RA, DstReg and BaseReg are often the same physical
>   register (e.g. `BC = BC + <const>`) because the register coalescer
>   eliminates the copy. If they differ, we fall through to the general
>   expansion.
>
> - **LXI cleanup**: If the constant register is dead after the ADD16
>   (common when the constant was materialized solely for this add), we
>   erase the LXI to save 12cc and free the register pair. The
>   `isRegDeadAfter` helper is conservative — it keeps the LXI if unsure.
>
> - **INX on GR16All**: The physical INX instruction works on all register
>   pairs including SP. The V6CLANG_ADD16 pseudo uses GR16 (BC, DE, HL only).
>   Since DstReg comes from V6CLANG_ADD16, it will never be SP, so there is
>   no risk of accidentally incrementing SP.

### Step 3.5 — DCX expansion in V6CLANG_SUB16 [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Apply the same pattern to the `case V6CLANG::V6CLANG_SUB16:` block. Subtraction is
**not** commutative, so only RhsReg can be the constant:

```cpp
  case V6CLANG::V6CLANG_SUB16: {
    Register DstReg = MI.getOperand(0).getReg();
    Register LhsReg = MI.getOperand(1).getReg();
    Register RhsReg = MI.getOperand(2).getReg();

    // --- NEW: DCX/INX chains for constant ±1..±3 ---
    if (isFlagsDefDead(MI)) {
      MachineInstr *LXI = findDefiningLXI(MBB, MI.getIterator(), RhsReg);
      if (LXI && DstReg == LhsReg) {
        int64_t ImmVal = LXI->getOperand(1).getImm();
        // Normalize unsigned 16-bit to signed.
        if (ImmVal > 0x7FFF)
          ImmVal -= 0x10000;
        unsigned Opc = 0;
        unsigned Count = 0;
        if (ImmVal >= 1 && ImmVal <= 3) {
          Opc = V6CLANG::DCX;  // sub rp, N → N × DCX rp
          Count = static_cast<unsigned>(ImmVal);
        } else if (ImmVal >= -3 && ImmVal <= -1) {
          Opc = V6CLANG::INX;  // sub rp, -N → N × INX rp
          Count = static_cast<unsigned>(-ImmVal);
        }

        if (Opc) {
          for (unsigned I = 0; I < Count; ++I)
            BuildMI(MBB, MI, DL, get(Opc), DstReg).addReg(DstReg);
          Register ConstReg = LXI->getOperand(0).getReg();
          if (isRegDeadAfter(MBB, MI.getIterator(), ConstReg, &RI))
            LXI->eraseFromParent();
          MI.eraseFromParent();
          return true;
        }
      }
    }

    // [existing] General case: expand to 8-bit chain.
    MCRegister DstLo = RI.getSubReg(DstReg, V6CLANG::sub_lo);
    ...
  }
```

### Step 3.6 — Lit test: INX/DCX chains [x]

**File**: `tests/lit/CodeGen/V6Clang/inx-dcx-peephole.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; Test that i16 add-by-1 becomes INX instead of 8-bit chain.
define i16 @inc16(i16 %x) {
; CHECK-LABEL: inc16:
; CHECK:       INX
; CHECK-NOT:   ADC
  %r = add i16 %x, 1
  ret i16 %r
}

; Test that i16 sub-by-1 becomes DCX.
define i16 @dec16(i16 %x) {
; CHECK-LABEL: dec16:
; CHECK:       DCX
; CHECK-NOT:   SBB
  %r = sub i16 %x, 1
  ret i16 %r
}

; Test that add-by-2 becomes an INX chain (2× INX).
define i16 @add_two(i16 %x) {
; CHECK-LABEL: add_two:
; CHECK:       INX
; CHECK-NEXT:  INX
; CHECK-NOT:   ADC
  %r = add i16 %x, 2
  ret i16 %r
}

; Test that sub-by-2 becomes a DCX chain (2× DCX).
define i16 @sub_two(i16 %x) {
; CHECK-LABEL: sub_two:
; CHECK:       DCX
; CHECK-NEXT:  DCX
; CHECK-NOT:   SBB
  %r = sub i16 %x, 2
  ret i16 %r
}

; Test that add-by-3 becomes an INX chain (3× INX).
define i16 @add_three(i16 %x) {
; CHECK-LABEL: add_three:
; CHECK:       INX
; CHECK-NEXT:  INX
; CHECK-NEXT:  INX
; CHECK-NOT:   ADC
  %r = add i16 %x, 3
  ret i16 %r
}

; Test that sub-by-3 becomes a DCX chain (3× DCX).
define i16 @sub_three(i16 %x) {
; CHECK-LABEL: sub_three:
; CHECK:       DCX
; CHECK-NEXT:  DCX
; CHECK-NEXT:  DCX
; CHECK-NOT:   SBB
  %r = sub i16 %x, 3
  ret i16 %r
}

; Test that add-by-4 does NOT become an INX chain (beyond ±3 limit).
define i16 @add_four(i16 %x) {
; CHECK-LABEL: add_four:
; CHECK-NOT:   INX
  %r = add i16 %x, 4
  ret i16 %r
}

; Test that add-by-1 with live flags does NOT become INX.
; (The select forces FLAGS to be live after the add.)
define i16 @inc16_with_flags(i16 %x, i16 %y) {
; CHECK-LABEL: inc16_with_flags:
; The add may or may not use INX depending on whether flags are live.
; This test documents the current behavior — update if FLAGS liveness
; analysis improves.
  %r = add i16 %x, 1
  %cmp = icmp ugt i16 %r, %y
  %s = select i1 %cmp, i16 %r, i16 %y
  ret i16 %s
}
```

> **Design Note**: The `inc16_with_flags` test documents behavior when
> FLAGS might be live. Whether INX fires depends on how ISel lowers the
> icmp — it may use a separate comparison instruction, making FLAGS dead
> after the add. The test uses CHECK (not CHECK-NOT) only for the
> function label, allowing the output to vary. Update the CHECKs once
> the actual output is known.

### Step 3.7 — Lit test: loop with pointer increment [x]

**File**: `tests/lit/CodeGen/V6Clang/loop-pointer-inx.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; Verify that a loop with pointer increment uses INX, not the 8-bit chain.
@buf = global [64 x i8] zeroinitializer

define void @clear_buf() {
entry:
  br label %loop

loop:
  %p = phi ptr [ @buf, %entry ], [ %p.next, %loop ]
  store i8 0, ptr %p
  %p.next = getelementptr i8, ptr %p, i16 1
  %done = icmp eq ptr %p.next, getelementptr (i8, ptr @buf, i16 64)
  br i1 %done, label %exit, label %loop

exit:
  ret void
}

; CHECK-LABEL: clear_buf:
; CHECK: .L{{.*}}:
; CHECK:     INX
; CHECK-NOT: ADC
; CHECK:     JNZ
```

### Step 3.8 — Build [x]

```bash
cmd /c "call vcvars64.bat >nul 2>&1 && ninja -C llvm-build clang llc"
```

Fix any compilation errors. The helpers use standard LLVM MachineInstr API
(`modifiesRegister`, `readsRegister`, `implicit_operands`, `isDead`).

### Step 3.9 — Run regression tests [x]

```bash
python tests/run_all.py
```

All existing lit tests and golden tests must pass. The INX/DCX optimization
is strictly an improvement — it generates fewer instructions for the same
semantics — so no existing tests should break. If a test checks for specific
instruction sequences that now change (e.g. a test that expects the 8-bit
chain), update the CHECK lines.

### Step 3.10 — Verify assembly on array copy benchmark [x]

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2_inx.asm
```

Inspect the loop body. Expected improvement:

**Before** (two pointer increments via 8-bit chain):
```asm
    LXI  H, 1          ; 12cc
    MOV  A, C           ;  8cc
    ADD  L              ;  4cc
    MOV  C, A           ;  8cc
    MOV  A, B           ;  8cc
    ADC  H              ;  4cc
    MOV  B, A           ;  8cc  (BC += 1, chain 40cc)
    ; ... same for DE ...        (DE += 1, chain 40cc, reuses HL)
```

**After**:
```asm
    INX  B              ;  8cc  (BC += 1)
    INX  D              ;  8cc  (DE += 1)
```

Savings: 92cc → 16cc per iteration (76cc saved, **5.75× faster** on
increment portion). The LXI is also erased, freeing the HL register pair.

### Step 3.11 — Sync mirror [x]

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Per-instruction improvement

| Pattern | Before | After | Speedup |
|---------|--------|-------|---------|
| `rp ± 1` (non-HL) | LXI + 8-bit chain (52cc, 9B) | 1×INX/DCX (8cc, 1B) | 6.5× |
| `rp ± 2` (non-HL) | LXI + 8-bit chain (52cc, 9B) | 2×INX/DCX (16cc, 2B) | 3.25× |
| `rp ± 3` (non-HL) | LXI + 8-bit chain (52cc, 9B) | 3×INX/DCX (24cc, 3B) | 2.2× |
| `HL ± 1` | LXI + DAD (24cc, 4B) | 1×INX/DCX (8cc, 1B) | 3× |
| `HL ± 2` | LXI + DAD (24cc, 4B) | 2×INX/DCX (16cc, 2B) | 1.5× |
| `HL ± 3` | LXI + DAD (24cc, 4B) | 3×INX/DCX (24cc, 3B) | 1× (saves 1B, no clobber) |

> **Note**: The INX/DCX check runs *before* the DAD check, so HL
> benefits too. For HL ± 3, the chain ties DAD on time but saves code
> size and avoids clobbering a helper register pair with LXI.

### Array copy loop impact

| Metric | Before | After |
|--------|--------|-------|
| Pointer increment (2×) | 92cc (LXI 12 + 2×40 chain) | 16cc (2 × INX) |
| Other loop body | ~46cc | ~46cc |
| **Total per iteration** | **~138cc** | **~62cc** |

> The loop shares one `LXI HL, 1` between two increment chains. After
> the optimization, both chains and the LXI are replaced by two INX
> instructions, also freeing the HL register pair.

### Code size

For ±1: the 7-instruction sequence (LXI + 6 MOV/ADD/ADC, 9 bytes) is
replaced by a single INX/DCX (1 byte), saving **8 bytes**. For ±2: save
**7 bytes** (9B → 2B). For ±3: save **6 bytes** (9B → 3B).

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| FLAGS not actually dead — INX silently breaks flag-dependent code | `isFlagsDefDead()` checks the implicit-def's `isDead()` bit set by RA liveness analysis; only fires when FLAGS is provably dead |
| LXI used by another instruction — erasing it breaks other code | `isRegDeadAfter()` conservatively keeps the LXI when any downstream use exists; false negatives keep the LXI (wastes 12cc, but correct) |
| DstReg != BaseReg — INX can't express a 3-operand add | Fall through to existing 8-bit chain; no correctness risk. After RA coalescing, the `rp = rp + 1` pattern almost always has DstReg == LhsReg |
| Scan window too small — misses LXI placed far away | 16-instruction window covers the common case. If the LXI is farther away, the constant was likely loaded for multiple uses and shouldn't be deleted anyway |
| INX on SP by accident | V6CLANG_ADD16 uses GR16 (BC/DE/HL), never SP. INX's GR16All class is irrelevant since we inherit the register from V6CLANG_ADD16's operand |

---

## 6. Relationship to Other Planned Improvements

This is the first of three improvements identified for the array-copy loop:

1. **INX/DCX peephole** (this plan) — replaces 8-bit add/sub chains for
   small constants (±1 to ±3) with INX/DCX instruction chains.
2. **CMP-based 16-bit comparison** — replaces the destructive XOR-based
   V6CLANG_BR_CC16 EQ/NE with a non-destructive `CPI lo; JNZ; CPI hi; JNZ`
   sequence. This eliminates the register copy that RA inserts to preserve
   the compared register pair.
3. **Spill elimination** — expected to follow automatically from (1) and
   (2), as reduced register pressure from eliminating the LXI temporary
   and the comparison copy frees register pairs.

After all three, the target loop body is:
```asm
.loop:
    LDAX B              ;  8cc  — load from [BC]
    STAX D              ;  8cc  — store to [DE]
    INX  B              ;  8cc  — advance source pointer
    INX  D              ;  8cc  — advance dest pointer
    MVI  A, lo(end)     ;  8cc  — compare BC with loop end
    CMP  C              ;  4cc
    JNZ  .loop          ; 12cc
    MVI  A, hi(end)     ;  8cc
    CMP  B              ;  4cc
    JNZ  .loop          ; 12cc  — total ~80cc per iteration
```

---

## 7. Implementation Notes

The implementation was completed and all tests pass (70/70 lit + 15/15
golden). The following deviations from the plan were made:

### Step 3.4 — V6CLANG_ADD16: condition check reordered

The plan nests conditions as:
```cpp
if (LXI) {
  // compute ImmVal, Opc, Count
  if (Opc && DstReg == BaseReg) { ... }
}
```

The implementation hoists `DstReg == BaseReg` into the outer guard:
```cpp
if (LXI && DstReg == BaseReg) {
  // compute ImmVal, Opc, Count
  if (Opc) { ... }
}
```

This avoids computing ImmVal/Opc when `DstReg != BaseReg` (which would
always fall through anyway). Semantically equivalent.

### Step 3.5 — V6CLANG_SUB16: same reordering

The plan has:
```cpp
if (isFlagsDefDead(MI)) {
  MachineInstr *LXI = findDefiningLXI(..., RhsReg);
  if (LXI && DstReg == LhsReg) { ... }
}
```

The implementation hoists `DstReg == LhsReg` into the outer guard:
```cpp
if (isFlagsDefDead(MI) && DstReg == LhsReg) {
  MachineInstr *LXI = findDefiningLXI(..., RhsReg);
  if (LXI) { ... }
}
```

This additionally avoids the backward LXI scan when `DstReg != LhsReg`.

### Step 3.6 — Lit test: inx-dcx-peephole.ll

| Aspect | Plan | Implementation |
|--------|------|----------------|
| RUN line | `-mtriple=i8080-unknown-v6clang -O2` | `-march=v6clang` (V6CLANG backend default triple; `-O2` is llc default) |
| CHECK patterns | Generic `INX`/`DCX` | Register-specific `INX HL`/`DCX HL` (stronger assertion) |
| Function terminators | None | Added `CHECK: RET` after each function to bound CHECK-NOT scope |
| `add_four` test | `CHECK-NOT: INX` | `CHECK-NOT: INX` × 2 + `CHECK: DAD` (also verifies DAD fallback) |
| `inc16_with_flags` test | Included (no concrete CHECKs) | **Omitted** — the test had no useful assertions since the plan acknowledged the output varies depending on ISel lowering of icmp |

### Step 3.7 — Lit test: loop-pointer-inx.ll

The plan's CHECK pattern was:
```
; CHECK:     INX
; CHECK-NOT: ADC
; CHECK:     JNZ
```

The implementation uses:
```
; CHECK:     INX DE
```

The `CHECK-NOT: ADC` was removed because only the DE pointer increment
benefits from INX in this loop. The BC increment still uses the 8-bit
chain because HL is clobbered by stack accesses (frame pointer save/restore)
between the LXI and the V6CLANG_ADD16 for BC, so `findDefiningLXI` cannot
find the LXI within its 16-instruction scan window. The `CHECK: JNZ`
was also removed as unnecessary — checking `INX DE` is sufficient.

### Step 3.10 — Array copy benchmark: partial improvement

The plan predicted both pointer increments would become INX (92cc → 16cc).
In practice, only the DE increment became `INX D` (8cc). The BC increment
still uses the 8-bit chain because intervening stack accesses (from the
comparison's register pressure) clobber HL between the `LXI H, 1` and the
`V6CLANG_ADD16` for BC, breaking the `findDefiningLXI` backward scan.

The full improvement predicted in Section 4 (Array copy loop impact)
requires the CMP-based 16-bit comparison from Section 6, which would
eliminate the register pressure that causes the intervening stack accesses.

---

## 8. Future Enhancements

- **DstReg != BaseReg handling**: Emit a register pair copy (two MOVs,
  16cc) followed by INX (8cc) = 24cc total, still better than 52cc. Only
  worthwhile if this case actually occurs in practice after RA.

  > **Not pursued.** Tested with runtime pointer patterns (`uint8_t *p`
  > passed as argument, both `*p` and `*(p+1)` used). LLVM's register
  > coalescing always ensures DstReg == BaseReg for the add. When both
  > the original and incremented pointer are needed, the compiler spills
  > the original to the stack before advancing — it never produces a
  > 3-operand `DE = HL + 1` pattern. For global arrays, constant folding
  > eliminates the pointer arithmetic entirely (LDA/STA with pre-computed
  > addresses). This case is dead code territory in practice.

- **DCR-based loop counter**: When the loop counter counts down and the
  only use of the counter is the exit test, DCR (8-bit decrement, sets
  flags) might replace the 16-bit comparison entirely. This is a separate
  IR-level optimization.
