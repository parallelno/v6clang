# Plan: ADD16 DAD-Based Expansion (Post-RA Pseudo Lowering)

## 1. Problem

### Current behavior

`V6CLANG_ADD16` is a pseudo-instruction for 16-bit addition. Its
`expandPostRAPseudo()` expansion has two paths:

1. **INX/DCX chain** — when one operand is a small constant and
   `DstReg == BaseReg`, emits repeated INX/DCX (cost-model gated).
2. **DAD path** (12cc, 1B) — when `DstReg == HL` AND one operand is HL.
3. **Byte chain** (40cc, 6B) — everything else: 6 MOV/ADD/ADC
   instructions through the accumulator.

When the register allocator assigns a non-HL destination but one operand
IS HL, the byte chain is used even though a DAD-based sequence (28cc, 3B)
would be cheaper. Similarly, when `DstReg == HL` but neither operand is
HL, a MOV pair + DAD is cheaper than the byte chain.

### Desired behavior

Two new DAD-based paths should be inserted between the existing DAD check
and the general byte-chain fallback:

**Path A**: `rp = ADD16 HL, rp` or `rp = ADD16 rp, HL` (HL dead after):
```asm
DAD  rp          ; 12cc 1B  — HL = HL + rp
MOV  rp_hi, H   ;  8cc 1B  — copy result to dst
MOV  rp_lo, L   ;  8cc 1B
; total: 28cc, 3B  (saves 12cc, 3B vs byte chain)
```

**Path B**: `HL = ADD16 rp1, rp2` (neither operand is HL):
```asm
MOV  H, rp1_hi  ;  8cc 1B  — copy rp1 into HL
MOV  L, rp1_lo  ;  8cc 1B
DAD  rp2         ; 12cc 1B  — HL = HL + rp2
; total: 28cc, 3B  (saves 12cc, 3B vs byte chain)
```

### Root cause

The existing expansion only checks `DstReg == HL && (LhsReg == HL ||
RhsReg == HL)` for the DAD fast path. It does not consider:
- Using DAD when one operand is HL but destination is different (HL dead).
- Copying an operand into HL then using DAD when destination is HL but
  neither source is HL.

---

## 2. Strategy

### Approach: Two new code paths with XCHG sub-cases in expandPostRAPseudo

Insert two new DAD-based expansion paths in `V6ClangInstrInfo::expandPostRAPseudo()`,
case `V6CLANG::V6CLANG_ADD16`, between the existing DAD check and the general
byte-chain fallback. When dst=DE, use XCHG (4cc, 1B) instead of two
MOVs (16cc, 2B) for a further savings.

### Why this works

- **Path A** exploits DAD's implicit HL accumulator when HL is already an
  operand. Since DAD clobbers HL with the sum, we need HL to be dead after
  the instruction — checked via `isRegDeadAfter()`.
  - **A1-DE**: When dest=DE and HL dead, `DAD rp; XCHG` moves the sum
    from HL to DE in 4cc instead of 16cc.
  - **A2-DE**: When dest=DE and HL live (OtherReg must be DE),
    `XCHG; DAD DE; XCHG` computes the sum AND preserves HL. This handles
    a case that currently falls to byte chain.
- **Path B** copies one operand into HL (which is the destination, so old
  HL value is dead by definition), then DADs the other operand.
  - **B1-DE**: When one operand is DE and DE is dead after, `XCHG; DAD rp`
    brings DE into HL in 4cc instead of two MOVs.
- Both paths produce correct results in all register-pair combinations.

### Case matrix

All `$dst = V6CLANG_ADD16 $lhs, $rhs` register pair assignments:

| dst | lhs | rhs | Path | Expansion | Cost |
|-----|-----|-----|------|-----------|------|
| HL | HL | rp | existing | `DAD rp` | 12cc, 1B |
| HL | rp | HL | existing | `DAD rp` | 12cc, 1B |
| DE | HL | rp | **A1-DE** (HL dead) | `DAD rp; XCHG` | 16cc, 2B |
| DE | rp | HL | **A1-DE** (HL dead) | `DAD rp; XCHG` | 16cc, 2B |
| DE | HL | DE | **A2-DE** (HL live) | `XCHG; DAD DE; XCHG` | 20cc, 3B |
| DE | DE | HL | **A2-DE** (HL live) | `XCHG; DAD DE; XCHG` | 20cc, 3B |
| HL | DE | rp≠DE | **B1-DE** (DE dead) | `XCHG; DAD rp` | 16cc, 2B |
| HL | rp≠DE | DE | **B1-DE** (DE dead) | `XCHG; DAD rp` | 16cc, 2B |
| HL | rp1 | rp2 | **B-general** | `MOV H,rp1_hi; MOV L,rp1_lo; DAD rp2` | 28cc, 3B |
| rp≠DE | HL | rp | **A-general** (HL dead) | `DAD rp; MOV hi,H; MOV lo,L` | 28cc, 3B |
| rp≠DE | rp | HL | **A-general** (HL dead) | `DAD rp; MOV hi,H; MOV lo,L` | 28cc, 3B |
| any | any | any | byte chain (fallback) | 6 MOV/ADD/ADC through A | 40cc, 6B |

Notes:
- A1-DE requires `isRegDeadAfter(HL)` — HL dead after instruction
- A2-DE requires HL live AND OtherReg==DE — only for `DE = HL + DE`
- B1-DE requires exactly one operand is DE (not both) and `isRegDeadAfter(DE)`
- A-general requires `isRegDeadAfter(HL)` — for dest=BC
- B-general applies when B1-DE conditions not met (DE live or both operands same)
- Byte chain is the final fallback when no DAD path applies

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Path A (A1-DE, A2-DE, A-general) | DAD + XCHG or MOV-pair when HL is operand, dst≠HL | V6ClangInstrInfo.cpp |
| Path B (B1-DE, B-general) | XCHG+DAD or MOV-pair+DAD when dst=HL, neither source is HL | V6ClangInstrInfo.cpp |
| Lit test | Verify all sub-paths in assembly output | tests/lit/CodeGen/V6CLANG/ |

---

## 3. Implementation Steps

### Step 3.1 — Add Path A: dst≠HL, one operand is HL [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Insert after the existing `DstReg == HL` DAD checks (around line 536),
before the general byte-chain fallback. Contains three sub-cases ordered
by profitability.

```cpp
// --- Path A: one operand is HL, DstReg != HL ---
if (DstReg != V6CLANG::HL &&
    (LhsReg == V6CLANG::HL || RhsReg == V6CLANG::HL)) {
  Register OtherReg = (LhsReg == V6CLANG::HL) ? RhsReg : LhsReg;
  bool HLDead = isRegDeadAfter(MBB, MI.getIterator(), V6CLANG::HL, &RI);

  if (DstReg == V6CLANG::DE) {
    if (HLDead) {
      // A1-DE: DAD OtherReg; XCHG → 16cc, 2B
      BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(OtherReg);
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      MI.eraseFromParent();
      return true;
    }
    if (OtherReg == V6CLANG::DE) {
      // A2-DE: DE = HL + DE with HL live. XCHG; DAD DE; XCHG → 20cc, 3B
      // After: DE = old_HL + old_DE (sum), HL = old_HL (preserved).
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(V6CLANG::DE);
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      MI.eraseFromParent();
      return true;
    }
    // dest=DE, HL live, OtherReg!=DE → no XCHG trick, fall to byte chain.
  }

  if (HLDead) {
    // A-general (dest=BC): DAD + MOV pair → 28cc, 3B
    BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(OtherReg);
    MCRegister DstHi = RI.getSubReg(DstReg, V6CLANG::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6CLANG::sub_lo);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstHi).addReg(V6CLANG::H);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstLo).addReg(V6CLANG::L);
    MI.eraseFromParent();
    return true;
  }
  // HL live, not A2-DE → fall through to byte chain.
}
```

> **Design Notes**:
> - **A1-DE** (16cc, 2B): `DAD rp; XCHG`. XCHG (4cc) replaces two MOVs
>   (16cc). HL is dead so XCHG clobbering HL is safe. Works for any
>   OtherReg (BC, DE, or even HL for DAD HL case).
> - **A2-DE** (20cc, 3B): `XCHG; DAD DE; XCHG`. Only for `DE = HL + DE`.
>   Step 1: XCHG → HL=old_DE, DE=old_HL. Step 2: DAD DE → HL=old_DE+old_HL.
>   Step 3: XCHG → DE=sum, HL=old_HL (restored). This handles the case
>   where HL is live — currently falls to 40cc byte chain.
> - **A-general** (28cc, 3B): DAD + two MOVs for dest=BC with HL dead.
> - Order matters: A1-DE and A2-DE checked first (DE-specific), then
>   A-general (any non-HL dest).

> **Implementation Notes**: *(empty — filled after completion)*

### Step 3.2 — Add Path B: dst=HL, neither operand is HL [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Insert immediately after Path A, still before the byte-chain fallback.

```cpp
// --- Path B: DstReg == HL, neither operand is HL ---
if (DstReg == V6CLANG::HL && LhsReg != V6CLANG::HL && RhsReg != V6CLANG::HL) {
  // B1-DE: one operand is DE (not both), DE dead → XCHG + DAD (16cc, 2B)
  // XCHG brings DE into HL; DAD adds the other operand.
  if (LhsReg != RhsReg) { // skip if both operands are the same pair
    Register DEOp = Register();
    Register NonDEOp = Register();
    if (LhsReg == V6CLANG::DE) {
      DEOp = LhsReg;
      NonDEOp = RhsReg;
    } else if (RhsReg == V6CLANG::DE) {
      DEOp = RhsReg;
      NonDEOp = LhsReg;
    }
    if (DEOp && isRegDeadAfter(MBB, MI.getIterator(), V6CLANG::DE, &RI)) {
      // XCHG: HL=old_DE, DE=old_HL(dead). DAD NonDEOp: HL = old_DE + NonDEOp.
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(NonDEOp);
      MI.eraseFromParent();
      return true;
    }
  }

  // B-general: MOV pair + DAD → 28cc, 3B
  // Copy LhsReg into HL, DAD RhsReg. HL is the destination so old HL is dead.
  MCRegister LhsHi = RI.getSubReg(LhsReg, V6CLANG::sub_hi);
  MCRegister LhsLo = RI.getSubReg(LhsReg, V6CLANG::sub_lo);
  BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::H).addReg(LhsHi);
  BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::L).addReg(LhsLo);
  BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(RhsReg);
  MI.eraseFromParent();
  return true;
}
```

> **Design Notes**:
> - **B1-DE** (16cc, 2B): `XCHG; DAD rp`. XCHG moves DE into HL (4cc
>   vs 16cc for two MOVs). DE gets old HL (dead — HL is the destination).
>   Requires DE dead after to avoid clobbering a live DE value.
>   Only valid when exactly one operand is DE (if both are DE, XCHG
>   would move DE into HL but DAD DE would add the wrong value).
> - **B-general** (28cc, 3B): Two MOVs + DAD. Always correct fallback.
>   Works for DE+DE, BC+BC, or when DE is live after.

> **Implementation Notes**: *(empty — filled after completion)*

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

### Step 3.4 — Lit test: add16-dad-expansion.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/add16-dad-expansion.ll`

Test cases:
1. **A1-DE** — `DE = HL + rp`, HL dead: expect `DAD; XCHG`
2. **A2-DE** — `DE = HL + DE`, HL live: expect `XCHG; DAD; XCHG`
3. **A-general** — `BC = HL + rp`, HL dead: expect `DAD` then MOV pair
4. **B1-DE** — `HL = DE + rp`, DE dead: expect `XCHG; DAD`
5. **B-general** — `HL = rp1 + rp2`, no DE or DE live: expect MOV pair then `DAD`
6. **Existing** — `HL = HL + rp`: expect single `DAD`

### Step 3.5 — Run regression tests [x]

```
python tests\run_all.py
```

### Step 3.6 — Verification assembly from `tests\features\README.md` [x]

Compile the feature test case and analyze the assembly for DAD-based
expansion improvements.

### Step 3.7 — Create result.txt per `tests\features\README.md` [x]

### Step 3.8 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Case 1: `$bc = ADD16 $hl, $bc` (HL dead after) — A-general

Before (40cc, 6B):
```asm
MOV  A, L       ; 8cc  1B
ADD  C           ; 4cc  1B
MOV  C, A        ; 8cc  1B
MOV  A, H        ; 8cc  1B
ADC  B           ; 4cc  1B
MOV  B, A        ; 8cc  1B
```

After (28cc, 3B — saves 12cc, 3B):
```asm
DAD  B           ; 12cc 1B
MOV  B, H        ;  8cc 1B
MOV  C, L        ;  8cc 1B
```

### Case 2: `$de = ADD16 $hl, $de` (HL dead after) — A1-DE

Before (40cc, 6B):
```asm
MOV  A, L       ; 8cc  1B
ADD  E           ; 4cc  1B
MOV  E, A        ; 8cc  1B
MOV  A, H        ; 8cc  1B
ADC  D           ; 4cc  1B
MOV  D, A        ; 8cc  1B
```

After (16cc, 2B — saves 24cc, 4B):
```asm
DAD  D           ; 12cc 1B
XCHG             ;  4cc 1B
```

### Case 3: `$de = ADD16 $hl, $de` (HL live after) — A2-DE

Before (40cc, 6B — byte chain through A).

After (20cc, 3B — saves 20cc, 3B):
```asm
XCHG             ;  4cc 1B  — HL=old_DE, DE=old_HL
DAD  D           ; 12cc 1B  — HL = old_DE + old_HL
XCHG             ;  4cc 1B  — DE=sum, HL=old_HL (preserved)
```

### Case 4: `$hl = ADD16 $de, $bc` (DE dead after) — B1-DE

Before (40cc, 6B):
```asm
MOV  A, E        ; 8cc  1B
ADD  C           ; 4cc  1B
MOV  L, A        ; 8cc  1B
MOV  A, D        ; 8cc  1B
ADC  B           ; 4cc  1B
MOV  H, A        ; 8cc  1B
```

After (16cc, 2B — saves 24cc, 4B):
```asm
XCHG             ;  4cc 1B  — HL=old_DE, DE=old_HL(dead)
DAD  B           ; 12cc 1B  — HL = old_DE + BC
```

### Case 5: `$hl = ADD16 $bc, $de` — B-general

Before (40cc, 6B — byte chain through A).

After (28cc, 3B — saves 12cc, 3B):
```asm
MOV  H, B        ; 8cc  1B
MOV  L, C        ; 8cc  1B
DAD  D           ; 12cc 1B
```

### Cost comparison

| Sub-case | Old | New | Saving |
|----------|-----|-----|--------|
| A1-DE: `DE = HL + rp` (HL dead) | 40cc, 6B | 16cc, 2B | **24cc, 4B** |
| A2-DE: `DE = HL + DE` (HL live) | 40cc, 6B | 20cc, 3B | **20cc, 3B** |
| A-general: `BC = HL + rp` (HL dead) | 40cc, 6B | 28cc, 3B | **12cc, 3B** |
| B1-DE: `HL = DE + rp` (DE dead) | 40cc, 6B | 16cc, 2B | **24cc, 4B** |
| B-general: `HL = rp1 + rp2` | 40cc, 6B | 28cc, 3B | **12cc, 3B** |
| HL live, not A2-DE eligible | 40cc, 6B | 40cc, 6B | 0 (unchanged) |

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Path A: HL live-out not detected | `isRegDeadAfter()` is battle-tested in XchgOpt, Peephole, and other ADD16/SUB16/CMP16 expansions. Conservative: checks successor live-ins. |
| Path B B1-DE: DE live-out not detected | Same `isRegDeadAfter()` used for DE. If DE is live, falls to B-general (correct, just slower). |
| A2-DE correctness: XCHG;DAD DE;XCHG preserving HL | Verified algebraically: start HL=X,DE=Y → XCHG → HL=Y,DE=X → DAD DE → HL=Y+X,DE=X → XCHG → DE=Y+X,HL=X. Sum correct, HL preserved. |
| B1-DE: both operands are DE | Guarded by `LhsReg != RhsReg` check. If both are DE, XCHG+DAD would compute wrong result. Falls to B-general. |
| XCHG clobbers both DE and HL | Properly modeled: `Defs = [DE, HL], Uses = [DE, HL]`. All XCHG sub-cases verified for liveness: dead register checked before clobbering. |
| Path B: LhsReg or RhsReg sub-regs overlap with HL | Impossible: precondition requires `LhsReg != HL && RhsReg != HL`, and register pairs don't share sub-registers across BC/DE/HL. |
| DAD only sets Carry flag, not Z/S/P | The pseudo doesn't guarantee specific flag semantics beyond carry. Any consumer expecting Z/S/P from ADD16 would be incorrect. |

---

## 6. Relationship to Other Improvements

- **O11 (Dual Cost Model)**: The INX/DCX path already uses the cost model.
  The new DAD paths have fixed cost (28cc, 3B) and are always cheaper than
  the byte chain (40cc, 6B), so no cost-model gating needed.
- **O13 (Load-Immediate Combining)**: May eliminate LXI instructions that
  set up ADD16 operands, but doesn't affect the expansion itself.
- **O39 (IPRA)**: Reduces call-spill pressure, potentially keeping more
  values in registers and creating more opportunities for these paths.

---

## 7. Future Enhancements

- **SUB16 DAD-based path**: Similar optimization for SUB16 when one operand
  is HL (negate + DAD), though the negate cost may not always win.
- **Three-operand form**: If all three operands are different pairs and none
  is HL, consider LhsReg→HL copy + DAD (only helps if DstReg == HL, which
  is already Path B).

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [Feature Description](design\future_plans\O40_add16_dad_expansion.md)
