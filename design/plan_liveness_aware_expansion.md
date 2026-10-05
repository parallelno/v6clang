# Plan: Liveness-Aware Pseudo Expansion (Skip PUSH/POP When Dead) — O42

## 1. Problem

### Current behavior

Many pseudo expansions (SPILL8, RELOAD8, SPILL16, RELOAD16, LOAD16_P,
LOAD16_G, LOAD8_P, STORE8_P) need HL (or DE) as a scratch register. To
preserve the caller's value, they wrap the addressing in PUSH/POP:

```asm
; RELOAD16 BC (static stack, current):
PUSH HL           ; 1B 11cc  ← unnecessary if HL dead
LXI  HL, addr     ; 3B 10cc
MOV  C, M         ; 1B  7cc
INX  HL           ; 1B  5cc
MOV  B, M         ; 1B  7cc
POP  HL           ; 1B 10cc  ← unnecessary if HL dead
                  ; total: 8B 50cc
```

### Desired behavior

When the RA marks the source register as `killed` on the preceding SPILL
(or the pseudo's preserved register is dead at the expansion point), the
PUSH/POP wrapper is omitted. For some cases, alternative instruction
sequences (LHLD/SHLD) become available:

```asm
; RELOAD16 BC (static stack, HL dead):
LHLD addr         ; 3B 16cc
MOV  C, L         ; 1B  7cc
MOV  B, H         ; 1B  7cc  ← not needed: only 3 instructionss
                  ; total: 5B 26cc (saves 3B, 24cc)
```

### Root cause

The expansions unconditionally wrap with PUSH/POP because the original
implementation did not query post-RA register liveness at expansion time.
The `isRegDeadAtMI()` helper already exists in V6ClangInstrInfo.cpp (used by
LOAD8_P/STORE8_P priority-3 path) but is not applied to other pseudos.

---

## 2. Strategy

### Approach: Liveness check at expansion time

At each expansion point, call a liveness helper to check whether the
preserved register (HL or DE) is dead after the pseudo instruction. If
dead, emit the shorter sequence without PUSH/POP.

### Why this works

1. **Post-RA context** — physical register liveness is well-defined.
2. **Conservative fallback** — if uncertain, `isRegDeadAtMI()` returns
   false and the PUSH/POP is kept (original behavior preserved).
3. **Proven pattern** — LOAD8_P/STORE8_P already use `isRegDeadAtMI()`
   for priority-3 path selection (A-dead check).

### Summary of changes

| File | Change |
|------|--------|
| V6ClangRegisterInfo.cpp | Add `isRegDeadAfterMI()` static helper; modify 10 static stack + 8 dynamic stack expansion paths |
| V6ClangInstrInfo.cpp | Modify LOAD16_P (addr=BC), LOAD16_G (dst=BC), STORE16_P (addr=DE/BC), LOAD8_P (P4), STORE8_P (P4) |

---

## 3. Implementation Steps

### Step 3.1 — Add `isRegDeadAfterMI` helper to V6ClangRegisterInfo.cpp [ ]

Add a static helper function identical to `isRegDeadAtMI()` from
V6ClangInstrInfo.cpp. Both files need independent access to this check.

```cpp
/// Check if a physical register is dead after a given instruction.
/// Scans forward from MI (exclusive) to end of MBB.
/// Returns true if no read before redef, and Reg not in any successor livein.
static bool isRegDeadAfterMI(unsigned Reg, const MachineInstr &MI,
                             MachineBasicBlock &MBB,
                             const TargetRegisterInfo *TRI) {
  for (auto I = std::next(MI.getIterator()); I != MBB.end(); ++I) {
    bool usesReg = false, defsReg = false;
    for (const MachineOperand &MO : I->operands()) {
      if (!MO.isReg() || !TRI->regsOverlap(MO.getReg(), Reg))
        continue;
      if (MO.isUse())
        usesReg = true;
      if (MO.isDef())
        defsReg = true;
    }
    if (usesReg)
      return false;
    if (defsReg)
      return true;
  }
  for (MachineBasicBlock *Succ : MBB.successors()) {
    for (MCRegAliasIterator AI(Reg, TRI, /*IncludeSelf=*/true); AI.isValid();
         ++AI) {
      if (Succ->isLiveIn(*AI))
        return false;
    }
  }
  return true;
}
```

> **Design Notes**: Replicates `isRegDeadAtMI()` from V6ClangInstrInfo.cpp
> because both files need independent access (both are static helpers).
> An alternative is moving to a shared header, but that's unnecessary
> complexity for a 25-line function.

> **Implementation Notes**: (filled after completion)

### Step 3.2 — Static stack SPILL8/RELOAD8: skip PUSH/POP when preserved reg dead [ ]

**File**: `V6ClangRegisterInfo.cpp` — `eliminateFrameIndex`, static stack section.

**SPILL8 (B,C,D,E) — HL dead**: Skip PUSH HL / POP HL.
- Before: `PUSH HL; LXI HL, addr; MOV M, r; POP HL` (6B, 42cc)
- After: `LXI HL, addr; MOV M, r` (4B, 17cc)
- Savings: 2B, 25cc

**SPILL8 (H/L) — DE dead**: Skip PUSH DE / POP DE.
- Before: `PUSH DE; MOV D,src; MOV E,other; LXI; MOV M,D/E; restore; POP DE`
- After: `MOV D,src; MOV E,other; LXI; MOV M,D/E; restore` (skip 2B, 21cc)

**RELOAD8 (B,C,D,E) — HL dead**: Skip PUSH HL / POP HL.
- Before: `PUSH HL; LXI HL, addr; MOV r, M; POP HL` (6B, 42cc)
- After: `LXI HL, addr; MOV r, M` (4B, 17cc)
- Savings: 2B, 25cc

**RELOAD8 (H/L) — DE dead**: Skip PUSH DE / POP DE.
- Same pattern as SPILL8 H/L: skip outer PUSH DE / POP DE.

> **Implementation Notes**: (filled after completion)

### Step 3.3 — Static stack SPILL16/RELOAD16: optimized paths when preserved reg dead [ ]

**File**: `V6ClangRegisterInfo.cpp` — `eliminateFrameIndex`, static stack section.

**SPILL16 BC — HL dead**: Use MOV+SHLD instead of PUSH/LXI/MOV/INX/MOV/POP.
- Before: `PUSH HL; LXI HL, addr; MOV M, C; INX HL; MOV M, B; POP HL` (8B, 50cc)
- After: `MOV L, C; MOV H, B; SHLD addr` (5B, 32cc)
- Savings: 3B, 18cc

**RELOAD16 BC — HL dead**: Use LHLD+MOV instead of PUSH/LXI/MOV/INX/MOV/POP.
- Before: `PUSH HL; LXI HL, addr; MOV C, M; INX HL; MOV B, M; POP HL` (8B, 50cc)
- After: `LHLD addr; MOV C, L; MOV B, H` (5B, 30cc)
- Savings: 3B, 20cc

**RELOAD16 DE — HL dead**: Skip leading XCHG, use LHLD+XCHG.
- Before: `XCHG; LHLD addr; XCHG` (5B, 24cc)
- After: `LHLD addr; XCHG` (4B, 20cc)
- Savings: 1B, 4cc

> **Design Notes**: For SPILL16 DE, the XCHG approach swaps both HL and
> DE simultaneously. Skipping the trailing XCHG would leave DE=old_HL
> (corrupted) when DE is not killed. The only SPILL16 DE savings come
> from `IsKill` which is already handled. So SPILL16 DE is unchanged.

> **Implementation Notes**: (filled after completion)

### Step 3.4 — Dynamic stack SPILL8/RELOAD8: skip PUSH/POP + adjust offset [ ]

**File**: `V6ClangRegisterInfo.cpp` — `eliminateFrameIndex`, dynamic stack section.

Same patterns as static stack, but with DAD SP addressing. When PUSH is
skipped, the offset changes from `Offset + 2` to `Offset` (no PUSH on
stack to account for).

**SPILL8 (B,C,D,E) — HL dead**:
- Before: `PUSH HL; LXI HL, offset+2; DAD SP; MOV M, r; POP HL`
- After: `LXI HL, offset; DAD SP; MOV M, r`

**SPILL8 (H/L) — DE dead**:
- Before: `PUSH DE; MOV; MOV; LXI HL, offset+2; DAD SP; MOV M; restore; POP DE`
- After: `MOV; MOV; LXI HL, offset; DAD SP; MOV M; restore`

**RELOAD8 (B,C,D,E) — HL dead**:
- Before: `PUSH HL; LXI HL, offset+2; DAD SP; MOV r, M; POP HL`
- After: `LXI HL, offset; DAD SP; MOV r, M`

**RELOAD8 (H/L) — DE dead**:
- Before: `PUSH DE; MOV D, other; LXI HL, offset+2; DAD SP; MOV dst, M; restore; POP DE`
- After: `MOV D, other; LXI HL, offset; DAD SP; MOV dst, M; restore`

> **Design Notes**: The `+2` offset accounts for the PUSH pushing 2 bytes
> onto the stack before DAD SP computes the effective address. When PUSH
> is omitted, SP doesn't change, so the offset must NOT include `+2`.

> **Implementation Notes**: (filled after completion)

### Step 3.5 — Dynamic stack SPILL16/RELOAD16: skip PUSH/POP + adjust offset [ ]

**File**: `V6ClangRegisterInfo.cpp` — `eliminateFrameIndex`, dynamic stack section.

**SPILL16 HL — DE dead**:
- Before: `PUSH DE; MOV D,H; MOV E,L; LXI HL, offset+2; DAD SP; store; restore; POP DE`
- After: `MOV D,H; MOV E,L; LXI HL, offset; DAD SP; store; restore`

**SPILL16 DE/BC — HL dead**:
- Before: `PUSH HL; LXI HL, offset+2; DAD SP; store; POP HL`
- After: `LXI HL, offset; DAD SP; store`

**RELOAD16 HL — DE dead**:
- Before: `PUSH DE; LXI HL, offset+2; DAD SP; load; copy; POP DE`
- After: `LXI HL, offset; DAD SP; load; copy`

**RELOAD16 DE/BC — HL dead**:
- Before: `PUSH HL; LXI HL, offset+2; DAD SP; load; POP HL`
- After: `LXI HL, offset; DAD SP; load`

> **Implementation Notes**: (filled after completion)

### Step 3.6 — LOAD16_P (addr=BC) and LOAD16_G (dst=BC): skip PUSH/POP HL [ ]

**File**: `V6ClangInstrInfo.cpp` — `expandPostRAPseudo`.

**LOAD16_P (addr=BC) — HL dead**:
- Before: `PUSH HL; MOV H,B; MOV L,C; load; POP HL`
- After: `MOV H,B; MOV L,C; load`
- Savings: 2B, 21cc

**LOAD16_G (dst=BC) — HL dead**:
- Before: `PUSH HL; LHLD addr; MOV B,H; MOV C,L; POP HL`
- After: `LHLD addr; MOV B,H; MOV C,L`
- Savings: 2B, 21cc

> **Implementation Notes**: (filled after completion)

### Step 3.7 — STORE16_P (val=HL, addr=DE/BC): skip PUSH/POP when addr dead [ ]

**File**: `V6ClangInstrInfo.cpp` — `expandPostRAPseudo`.

**STORE16_P (val=HL, addr=DE) — DE dead**:
- Before: `PUSH DE; MOV A,L; STAX DE; INX DE; MOV A,H; STAX DE; POP DE`
- After: `MOV A,L; STAX DE; INX DE; MOV A,H; STAX DE`
- Savings: 2B, 21cc

**STORE16_P (val=HL, addr=BC) — BC dead**:
- Before: `PUSH BC; MOV A,L; STAX BC; INX BC; MOV A,H; STAX BC; POP BC`
- After: `MOV A,L; STAX BC; INX BC; MOV A,H; STAX BC`
- Savings: 2B, 21cc

> **Implementation Notes**: (filled after completion)

### Step 3.8 — LOAD8_P/STORE8_P (priority 4): skip PUSH/POP HL [ ]

**File**: `V6ClangInstrInfo.cpp` — `expandPostRAPseudo`.

**LOAD8_P (priority 4, addr=BC/DE, A alive) — HL dead**:
- Before: `PUSH HL; MOV H,hi; MOV L,lo; MOV dst,M; POP HL` (43cc)
- After: `MOV H,hi; MOV L,lo; MOV dst,M` (22cc)
- Savings: 2B, 21cc

**STORE8_P (priority 4, addr=BC/DE, A alive) — HL dead**:
- Before: `PUSH HL; MOV H,hi; MOV L,lo; MOV M,src; POP HL` (43cc)
- After: `MOV H,hi; MOV L,lo; MOV M,src` (22cc)
- Savings: 2B, 21cc

> **Implementation Notes**: (filled after completion)

### Step 3.9 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: (filled after completion)

### Step 3.10 — Lit test: liveness-aware-expansion.ll [ ]

**File**: `tests/lit/CodeGen/V6CLANG/liveness-aware-expansion.ll`

Test cases:
1. **reload16_bc_hl_dead**: RELOAD16 BC when HL is killed by preceding
   SPILL → verify LHLD+MOV pattern (no PUSH/POP)
2. **spill16_bc_hl_dead**: SPILL16 BC when HL is dead → verify MOV+SHLD
   pattern (no PUSH/POP)
3. **load16_p_bc_hl_dead**: LOAD16_P with addr=BC when HL dead → no PUSH/POP
4. **load16_g_bc_hl_dead**: LOAD16_G with dst=BC when HL dead → no PUSH/POP
5. **hl_live_preserves_push_pop**: When HL is live, verify PUSH/POP is kept

> **Implementation Notes**: (filled after completion)

### Step 3.11 — Run regression tests [ ]

```
python tests\run_all.py
```

> **Implementation Notes**: (filled after completion)

### Step 3.12 — Verification assembly steps from `tests\features\README.md` [ ]

Compile the feature test case, analyze assembly for PUSH/POP elimination.

> **Implementation Notes**: (filled after completion)

### Step 3.13 — Make sure result.txt is created. `tests\features\README.md` [ ]

> **Implementation Notes**: (filled after completion)

### Step 3.14 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: (filled after completion)

---

## 4. Expected Results

### Two-array summation loop improvement

Steps 5–8 (spill/reload cluster) shrink from **16B, 132cc** to **12B, 88cc**:

```asm
; BEFORE:
  SHLD  ss+2                ; spill partial (HL=partial, killed)
  PUSH  HL                  ; RELOAD16 BC: preserve dead HL
  LXI   HL, ss
  MOV   C, M
  INX   HL
  MOV   B, M
  POP   HL
  PUSH  HL                  ; LOAD16_P BC: preserve dead HL again
  MOV   H, B
  MOV   L, C
  MOV   E, M
  INX   HL
  MOV   D, M
  POP   HL
  LHLD  ss+2                ; RELOAD16 HL

; AFTER:
  SHLD  ss+2                ; spill partial (HL killed → dead)
  LHLD  ss                  ; RELOAD16 BC, HL dead → LHLD path
  MOV   C, L
  MOV   B, H
  MOV   H, B                ; LOAD16_P BC, HL dead → no PUSH/POP
  MOV   L, C
  MOV   E, M
  INX   HL
  MOV   D, M
  LHLD  ss+2                ; RELOAD16 HL
```

Saves **4B, 44cc per iteration**.

### General per-instance savings

| Expansion | Savings |
|-----------|---------|
| SPILL16/RELOAD16 BC (static, HL dead) | 3B, 18–20cc |
| SPILL8/RELOAD8 (B,C,D,E, static, HL dead) | 2B, 25cc |
| LOAD16_P/LOAD16_G BC (HL dead) | 2B, 21cc |
| LOAD8_P/STORE8_P P4 (HL dead) | 2B, 21cc |
| RELOAD16 DE (HL dead) | 1B, 4cc |

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Incorrect liveness → skip PUSH/POP when reg is live | `isRegDeadAfterMI()` is conservative: if uncertain, reports "live" → PUSH/POP preserved |
| Dynamic stack offset error (+2 → +0) | Existing offset+2 logic is well-tested; only change is conditional |
| SPILL16 DE trailing XCHG skip corrupts DE | Not implementing SPILL16 DE case (only RELOAD16 DE) |
| Regression in existing tests | Full lit + golden suite after each build |

---

## 6. Relationship to Other Improvements

- **O10** (done): Static stack enables LHLD/SHLD alternatives for BC
- **O16** (planned): Spill forwarding benefits from cleaner SHLD/LHLD sequences
- **O20** (done): Honest defs create more HL-dead situations at expansion time

---

## 7. Future Enhancements

- **SPILL16 DE with HL dead**: Requires careful analysis of XCHG-based
  preservation; deferred for now
- **Cross-BB liveness**: Current helper is intra-BB; a cross-BB analysis
  could catch more dead cases
- **STORE16_P non-HL value paths**: Additional PUSH/POP elimination targets

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O42 Design](design\future_plans\O42_liveness_aware_expansion.md)
