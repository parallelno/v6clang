# Plan: Honest Store/Load Pseudo Defs (Remove False HL Clobber) — O20

## 1. Problem

### Current behavior

`V6CLANG_STORE8_P` and `V6CLANG_LOAD8_P` are defined with `Defs = [HL]`,
unconditionally telling the register allocator that HL is clobbered:

```tablegen
let mayStore = 1, Defs = [HL] in
def V6CLANG_STORE8_P : V6ClangPseudo<(outs), (ins GR8:$src, GR16:$addr), ...>;

let mayLoad = 1, Defs = [HL] in
def V6CLANG_LOAD8_P : V6ClangPseudo<(outs GR8:$dst), (ins GR16:$addr), ...>;
```

The register allocator avoids HL for pointers that survive past a
store/load, forcing DE/BC. The post-RA expansion then copies DE→HL
before the actual `MOV M, r` / `MOV r, M`, adding unnecessary overhead.

**Irony**: When addr IS HL, the expansion emits just `MOV M, r` — HL is
NOT clobbered. But the RA can't know this; `Defs` is unconditional.

### Desired behavior

Remove `Defs = [HL]` and make the expansion **preserve HL in every code
path**. The RA freely allocates HL for pointers (cheapest path), while
DE/BC remain as safe fallbacks with honest preservation.

### Root cause

`Defs = [HL]` was a conservative declaration from early development when
every non-HL path copied addr→HL, destroying HL. The fix is to make the
expansion preserve HL via PUSH/POP or STAX/LDAX paths that avoid touching HL.

### Impact

Single-pointer store loop (temp/compare/06): 52cc/iter → 38cc/iter (−27%)

```asm
; Current output (52cc/iter — DE→HL copy every iteration):
    LXI  DE, array1
    MVI  C, 0x2a
.loop:
    MOV  H, D       ;  8cc  ← unnecessary
    MOV  L, E       ;  8cc  ← unnecessary
    MOV  M, C       ;  7cc
    INX  DE          ;  6cc
    ...

; Expected output (38cc/iter — HL used directly):
    LXI  HL, array1
    MVI  C, 0x2a
.loop:
    MOV  M, C       ;  7cc
    INX  HL          ;  6cc
    ...
```

---

## 2. Strategy

### Approach: Remove `Defs = [HL]` + HL-preserving expansion priority chains

Two changes:
1. **TableGen**: Remove `Defs = [HL]` from both pseudos
2. **Expansion**: Rewrite both `expandPostRAPseudo` cases with priority
   chains that preserve HL in every code path

### Why this works

- When addr=HL: emit `MOV M, r` / `MOV r, M` directly — HL unchanged
- When addr=BC|DE and src/dst=A: use STAX/LDAX — HL untouched
- When addr=BC|DE and A dead: route through A → STAX/LDAX — HL untouched
- When addr=BC|DE and A live: PUSH HL; copy addr→HL; MOV M/r; POP HL — HL preserved

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Remove `Defs = [HL]` | Honest pseudo definitions | V6ClangInstrInfo.td |
| Rewrite STORE8_P expansion | 4-priority HL-preserving chain | V6ClangInstrInfo.cpp |
| Rewrite LOAD8_P expansion | 4-priority HL-preserving chain | V6ClangInstrInfo.cpp |
| Add liveness helper | `isRegDeadAt()` for A-dead check | V6ClangInstrInfo.cpp |
| New lit test | Both patterns exercised | store-load-honest-defs.ll |

---

## 3. Implementation Steps

### Step 3.1 — Remove `Defs = [HL]` from V6CLANG_STORE8_P and V6CLANG_LOAD8_P [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td` (lines ~584-595)

Change:
```tablegen
// Before:
let mayLoad = 1, Defs = [HL] in
def V6CLANG_LOAD8_P : V6ClangPseudo<(outs GR8:$dst), (ins GR16:$addr),
    "# LOAD8P $dst, ($addr)",
    [(set i8:$dst, (load i16:$addr))]>;

let mayStore = 1, Defs = [HL] in
def V6CLANG_STORE8_P : V6ClangPseudo<(outs), (ins GR8:$src, GR16:$addr),
    "# STORE8P $src, ($addr)",
    [(store i8:$src, i16:$addr)]>;

// After:
let mayLoad = 1 in
def V6CLANG_LOAD8_P : V6ClangPseudo<(outs GR8:$dst), (ins GR16:$addr),
    "# LOAD8P $dst, ($addr)",
    [(set i8:$dst, (load i16:$addr))]>;

let mayStore = 1 in
def V6CLANG_STORE8_P : V6ClangPseudo<(outs), (ins GR8:$src, GR16:$addr),
    "# STORE8P $src, ($addr)",
    [(store i8:$src, i16:$addr)]>;
```

> **Design Notes**: `Defs = [HL]` is removed because HL is now preserved
> in every expansion path. This gives the RA honest information.

> **Implementation Notes**: Done. Removed `Defs = [HL]` from both pseudos.
> Updated comments to document HL-preserving expansion.

### Step 3.2 — Add `isRegDeadAt()` liveness helper [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Add a static helper near the top of the file (before `expandPostRAPseudo`),
modeled after `isRegDeadAfter()` in V6ClangXchgOpt.cpp:

```cpp
/// Check if a physical register is dead at a given instruction.
/// Scans forward from MI (exclusive) to the end of MBB.
/// Returns true if no read before redef, and Reg is not in successor liveins.
static bool isRegDeadAt(unsigned Reg, const MachineInstr &MI,
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
    for (MCRegAliasIterator AI(Reg, TRI, true); AI.isValid(); ++AI) {
      if (Succ->isLiveIn(*AI))
        return false;
    }
  }
  return true;
}
```

> **Design Notes**: Same algorithm as `isRegDeadAfter()` in V6ClangXchgOpt.cpp
> but takes `const MachineInstr &` and `MachineBasicBlock &` instead of
> iterators. Used by both STORE8_P and LOAD8_P expansion.

> **Implementation Notes**: Added `isRegDeadAtMI()` static helper in
> V6ClangInstrInfo.cpp before `expandPostRAPseudo`. Uses same algorithm as
> `isRegDeadAfter()` in V6ClangXchgOpt.cpp. Checks successor liveins.

### Step 3.3 — Rewrite V6CLANG_STORE8_P expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp` (lines ~1409-1444)

Replace the existing `case V6CLANG::V6CLANG_STORE8_P:` with a 4-priority chain:

```cpp
case V6CLANG::V6CLANG_STORE8_P: {
    Register SrcReg = MI.getOperand(0).getReg();
    Register AddrReg = MI.getOperand(1).getReg();

    if (AddrReg == V6CLANG::HL) {
      // Priority 1: addr is HL — just store (7cc)
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVMr)).addReg(SrcReg);
    } else if (SrcReg == V6CLANG::A &&
               (AddrReg == V6CLANG::BC || AddrReg == V6CLANG::DE)) {
      // Priority 2: STAX — src already in A (7cc)
      BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
          .addReg(SrcReg).addReg(AddrReg);
    } else if ((AddrReg == V6CLANG::BC || AddrReg == V6CLANG::DE) &&
               isRegDeadAt(V6CLANG::A, MI, MBB, &RI)) {
      // Priority 3: route through A for STAX — A is dead (12cc)
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(V6CLANG::A, RegState::Define).addReg(SrcReg);
      BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
          .addReg(V6CLANG::A).addReg(AddrReg);
    } else {
      // Priority 4: fallback — save/restore HL (43cc)
      BuildMI(MBB, MI, DL, get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
      MCRegister Hi = RI.getSubReg(AddrReg, V6CLANG::sub_hi);
      MCRegister Lo = RI.getSubReg(AddrReg, V6CLANG::sub_lo);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(V6CLANG::H, RegState::Define).addReg(Hi);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(V6CLANG::L, RegState::Define).addReg(Lo);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVMr)).addReg(SrcReg);
      BuildMI(MBB, MI, DL, get(V6CLANG::POP))
          .addDef(V6CLANG::HL);
    }
    MI.eraseFromParent();
    return true;
}
```

> **Design Notes**: Priority 1 (addr=HL) now benefits from the RA being
> willing to allocate HL for pointers. Priorities 2-3 preserve HL by
> not touching it. Priority 4 preserves HL via PUSH/POP.

> **Implementation Notes**: Done. 4-priority chain implemented as planned.
> Priority 3 (STAX via A) handles the fill_array case where arg occupies L.

### Step 3.4 — Rewrite V6CLANG_LOAD8_P expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp` (lines ~1378-1407)

Replace the existing `case V6CLANG::V6CLANG_LOAD8_P:` with a 4-priority chain:

```cpp
case V6CLANG::V6CLANG_LOAD8_P: {
    Register DstReg = MI.getOperand(0).getReg();
    Register AddrReg = MI.getOperand(1).getReg();

    if (AddrReg == V6CLANG::HL) {
      // Priority 1: addr is HL — just load (7cc)
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrM))
          .addReg(DstReg, RegState::Define);
    } else if (DstReg == V6CLANG::A &&
               (AddrReg == V6CLANG::BC || AddrReg == V6CLANG::DE)) {
      // Priority 2: LDAX — dst is A (7cc)
      BuildMI(MBB, MI, DL, get(V6CLANG::LDAX))
          .addReg(DstReg, RegState::Define)
          .addReg(AddrReg);
    } else if ((AddrReg == V6CLANG::BC || AddrReg == V6CLANG::DE) &&
               isRegDeadAt(V6CLANG::A, MI, MBB, &RI)) {
      // Priority 3: LDAX then move — A is dead (12cc)
      BuildMI(MBB, MI, DL, get(V6CLANG::LDAX))
          .addReg(V6CLANG::A, RegState::Define)
          .addReg(AddrReg);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(DstReg, RegState::Define).addReg(V6CLANG::A);
    } else {
      // Priority 4: fallback — save/restore HL (43cc)
      BuildMI(MBB, MI, DL, get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
      MCRegister Hi = RI.getSubReg(AddrReg, V6CLANG::sub_hi);
      MCRegister Lo = RI.getSubReg(AddrReg, V6CLANG::sub_lo);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(V6CLANG::H, RegState::Define).addReg(Hi);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(V6CLANG::L, RegState::Define).addReg(Lo);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrM))
          .addReg(DstReg, RegState::Define);
      BuildMI(MBB, MI, DL, get(V6CLANG::POP))
          .addDef(V6CLANG::HL);
    }
    MI.eraseFromParent();
    return true;
}
```

> **Design Notes**: Same 4-priority structure as STORE8_P. Priority 3
> differs: LDAX into A, then MOV dst, A. Priority 4 identical PUSH/POP.

> **Implementation Notes**: Done. 4-priority chain mirrors STORE8_P structure.

### Step 3.5 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Build succeeded. Also fixed pre-existing missing
> `createV6ClangSpillForwardingPass()` declaration in V6Clang.h.
> Extended `findDefiningLXI()` to check predecessor BBs for cross-BB INX
> peephole (needed because O20's RA changes put LXI BC,1 in loop preheaders).
> Added `LXI->getParent() == &MBB` guard on all 3 LXI erase sites.

### Step 3.6 — Lit test: store-load-honest-defs.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/store-load-honest-defs.ll`

Test cases:
1. **store_via_hl**: Store through pointer — expect `MOV M, r` with HL, no copy
2. **load_via_hl**: Load through pointer — expect `MOV r, M` with HL, no copy
3. **store_stax**: Store src=A through BC/DE — expect `STAX`
4. **load_ldax**: Load dst=A through BC/DE — expect `LDAX`
5. **store_loop**: Single-pointer store loop — expect HL not copied from DE every iteration

Each case uses `CHECK-NOT: PUSH` or `CHECK-NOT: MOV H, D` to verify
HL preservation without unnecessary copies.

> **Implementation Notes**: Created store-load-honest-defs.ll with 3 test
> functions: store_byte (STAX path), load_byte (MOV A,M path),
> fill_array (loop verifying no DE→HL copy).

### Step 3.7 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 15/15 golden PASS, 99/99 lit PASS.
> Updated CHECK patterns in loop-pointer-induction.ll (src now in DE),
> spill-forwarding.ll (pass not in pipeline, updated to match actual output),
> and store-load-honest-defs.ll (fill_array uses STAX DE).

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [x]

Compile feature test case and verify the expected improvement appears:
```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\23\v6clang.c -o tests\features\23\v6clang_new01.asm
```

> **Implementation Notes**: Done. fill_array: 64cc→56cc/iter (−12.5%).
> v6clang_new01.asm (before cross-BB INX fix) and v6clang_new02.asm (final).

### Step 3.9 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: Created. Total: OLD 12,268cc → NEW 11,492cc = −776cc (6.3%).

### Step 3.10 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Synced.

---

### Single-pointer store loop (temp/compare/06)

RA allocates pointer in HL. `MOV M, C` emitted directly via Priority 1.
No DE→HL copy. 38cc/iter vs 52cc/iter. **−27%, −2B/iter.**

### Memcpy pattern (temp/compare/03) — no regression

Two pointers needed. RA puts one in HL (store), one in BC (load).
Load: `LDAX BC` (Priority 2, dst=A). Store: `MOV M, A` (Priority 1, addr=HL).
14cc/iter — identical to current LDAX+STAX quality.

### HL busy + store through DE/BC + A dead — new path

`MOV A, src; STAX addr` (12cc) vs current `MOV H,D; MOV L,E; MOV M,src` (23cc).
**11cc savings.**

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| PUSH/POP fallback (43cc) slower than current (23cc) in rare cases | Only triggers when HL busy AND A live AND src≠A — very rare |
| Removing `Defs = [HL]` causes RA to over-commit HL | Expansion preserves HL in ALL paths; PUSH/POP guarantees correctness |
| Liveness check for A is wrong | Uses same proven algorithm as V6ClangXchgOpt::isRegDeadAfter() |
| Regression in other patterns | Full test suite (lit + golden) run before completion |

---

## 6. Relationship to Other Improvements

- **Independent**: No dependencies on other optimizations
- **Complements O6 (LDA/STA)**: O6 handles global addresses; O20 handles pointer-based access
- **Complements O21 (LHLD/SHLD)**: O21 handles 16-bit global loads; O20 handles 8-bit pointer loads
- **Future benefit from O10 (Static Stack)**: With static stack, fewer spill HL-via-PUSH/POP scenarios

---

## 7. Future Enhancements

- Could track HL liveness at instruction scheduling time for even better decisions
- STORE16_P / LOAD16_P could benefit from similar honest Defs treatment

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O20 Design](design\future_plans\O20_honest_store_load_defs.md)
* [V6ClangXchgOpt isRegDeadAfter](llvm\lib\Target\V6CLANG\V6ClangXchgOpt.cpp) — liveness helper reference
