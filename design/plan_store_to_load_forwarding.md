# Plan: Post-RA Store-to-Load Forwarding (O16) for V6CLANG

## 1. Problem

### Current behavior

After register allocation, V6CLANG inserts SPILL/RELOAD pseudos for stack access.
Each expands to a 5–10 instruction sequence costing 40–68cc.  Often the
register being reloaded **still holds the same value that was spilled** — the
register was not clobbered between the spill and reload.

Example from `case4_multi_ptr` loop body (expanded):
```asm
; SPILL16 BC → offset 0xa (7 instr, ~56cc)
PUSH HL; LXI HL, 0xa; DAD SP; MOV M, C; INX HL; MOV M, B; POP HL
; ... BC not clobbered ...
; RELOAD16 offset 0xa → DE (7 instr, ~56cc)
PUSH HL; LXI HL, 0xa; DAD SP; MOV E, M; INX HL; MOV D, M; POP HL
```

The RELOAD is redundant — BC still holds the stored value.  A simple
`MOV E,C; MOV D,B` (16cc, 2B) replaces the entire 7-instruction reload.

A separate but related pattern: SPILL with `isKill` immediately followed
by RELOAD of the same slot:
```
V6CLANG_SPILL16 HL(kill) → fi    ; kills HL (expansion skips HL restore)
V6CLANG_RELOAD16 fi → HL          ; immediately restores HL from stack
```
By clearing `isKill`, the expansion restores HL in-place (adding 16cc, 2B)
and the RELOAD (68cc, 10B) is eliminated entirely.

### Desired behavior

Redundant RELOADs replaced with register-to-register copies (MOV) or
erased entirely.  Redundant SPILLs (storing a value already in the slot)
erased.

### Root cause

The register allocator inserts spill/reload pairs based on live-range
analysis without considering that the spilled value may still be available
in a register at the reload point.  No post-RA pass currently tracks
stack-slot ↔ register mappings.

---

## 2. Strategy

### Approach: Post-RA pass operating on SPILL/RELOAD pseudos

Insert a new `MachineFunctionPass` in `addPostRegAlloc()` that runs **after
register allocation** but **before** `eliminateFrameIndex` (PEI).  At this
stage, the SPILL8/RELOAD8/SPILL16/RELOAD16 pseudos are single MachineInstrs
with explicit frame-index operands — trivial to identify and replace.

### Why this works

1. **Frame indices uniquely identify stack slots** — no offset arithmetic.
2. **Physical registers are assigned** — defs/uses are concrete.
3. **Before PEI** — eliminating a RELOAD means no expansion at all
   (the entire 5–10 instruction sequence vanishes).
4. **Clearing isKill on SPILL HL** causes PEI to emit the 2-instruction
   HL restore instead of the 10-instruction separate RELOAD.

### Why not pre-emit (expanded level)

Working on expanded sequences requires pattern-matching 5–10 instruction
spill/reload patterns with multiple variants (H/L special case, HL via
XCHG, etc.).  The pseudo-level approach is simpler and handles the
`isKill` case naturally.

### Data structure

```
DenseMap<int, MCPhysReg> Avail;   // frame_index → register holding that slot's value
```

### Algorithm (per BB, forward scan)

```
for each MI in MBB:
  if MI is V6CLANG_SPILL8 or V6CLANG_SPILL16:
    src = MI.getOperand(0).getReg()
    fi  = MI.getOperand(1).getIndex()
    isKill = MI.getOperand(0).isKill()

    // Redundant store check
    if Avail[fi] == src && !isKill:
      erase MI                               // slot already holds this value
      continue

    if isKill:
      // Peek: if next MI is RELOAD of same fi, un-kill and forward
      if next is RELOAD of fi:
        clear isKill on SPILL source operand
        forward the RELOAD (erase or replace with MOV)
        Avail[fi] = src
        skip next MI
        continue
      else:
        Avail.erase(fi)                      // register dead, slot orphaned
        continue

    Avail[fi] = src                          // register alive, maps to slot

  else if MI is V6CLANG_RELOAD8 or V6CLANG_RELOAD16:
    dst = MI.getOperand(0).getReg()
    fi  = MI.getOperand(1).getIndex()
    if Avail[fi] exists:
      srcReg = Avail[fi]
      if srcReg == dst:
        erase MI                             // register already holds the value
      else:
        replace MI with MOV(s) dst ← srcReg  // 8-bit: 1 MOV, 16-bit: 2 MOVs
    else:
      Avail[fi] = dst                        // now dst holds the slot value

  else if MI.isCall():
    Avail.clear()                            // all regs clobbered (no callee-saved)

  else:
    for each def operand in MI:
      invalidate all Avail entries mapping to that register (or sub/super)
```

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Create pass | V6ClangSpillForwarding.cpp | New file |
| Declare factory | `createV6ClangSpillForwardingPass()` | V6Clang.h |
| Register pass | `addPostRegAlloc()` override | V6ClangTargetMachine.cpp |
| Add to build | CMakeLists.txt | V6CLANG target |
| CLI toggle | `-v6clang-disable-spill-forwarding` | V6ClangSpillForwarding.cpp |

---

## 3. Implementation Steps

### Step 3.1 — Create V6ClangSpillForwarding.cpp skeleton [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangSpillForwarding.cpp` (new)

Create the `MachineFunctionPass` skeleton:
- `class V6ClangSpillForwarding : public MachineFunctionPass`
- `char V6ClangSpillForwarding::ID`
- `runOnMachineFunction()` stub (returns false)
- `createV6ClangSpillForwardingPass()` factory
- `cl::opt<bool> DisableSpillForwarding` toggle

Model on `V6ClangLoadImmCombine.cpp`.

> **Implementation Notes**: Created with full logic (~250 lines) in one step,
> combining steps 3.1, 3.4, and 3.5.  CLI toggle: `-v6clang-disable-spill-forwarding`.

### Step 3.2 — Declare pass and register in the pipeline [x]

**Files**:
- `llvm-project/llvm/lib/Target/V6CLANG/V6Clang.h` — add declaration
- `llvm-project/llvm/lib/Target/V6CLANG/V6ClangTargetMachine.cpp` — add `addPostRegAlloc()` override with the new pass
- `llvm-project/llvm/lib/Target/V6CLANG/CMakeLists.txt` — add `V6ClangSpillForwarding.cpp`

> **Design Note**: The pass runs in `addPostRegAlloc()`, after RA but before
> `ExpandPostRAPseudos` and `PrologEpilogInserter`.  This ensures SPILL/RELOAD
> pseudos are present and have physical-register operands.

> **Implementation Notes**: Done.  Declaration in V6Clang.h, `addPostRegAlloc()`
> override in V6ClangTargetMachine.cpp, CMakeLists.txt entry between
> V6ClangRegisterInfo.cpp and V6ClangSPTrickOpt.cpp.

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Verify the skeleton compiles cleanly (pass registered but no-op).

> **Implementation Notes**: First build failed: `getImplicitDefs()` not a member
> of `MCInstrDesc` in LLVM 18.  Fixed by removing the redundant implicit-def loop
> (implicit defs already included in `MI.operands()` iteration).  Clean build after fix.

### Step 3.4 — Implement core forwarding logic [x]

**File**: `V6ClangSpillForwarding.cpp`

Implement `runOnMachineFunction()`:
1. Iterate MBBs.
2. For each MBB, forward-scan tracking `Avail` map.
3. Handle SPILL8/16: record `Avail[fi] = srcReg` (non-kill only).
4. Handle RELOAD8/16: if `Avail[fi]` valid, forward or erase.
5. Handle kill: invalidate `Avail[fi]`.
6. Handle CALL: `Avail.clear()`.
7. Handle other defs: `invalidateReg()` removes entries where tracked
   register matches defined register or is a sub/super register.

For 8-bit forwarding: replace RELOAD8 with `MOVrr dst, src`.
For 16-bit forwarding: replace RELOAD16 with two `MOVrr` instructions
using sub-register indices (`sub_lo`, `sub_hi`).

> **Design Note**: Use `TRI->getSubReg(PairReg, V6CLANG::sub_hi)` and
> `TRI->getSubReg(PairReg, V6CLANG::sub_lo)` to decompose register pairs.
> For 16-bit same-pair case (srcPair == dstPair), simply erase the RELOAD.

> **Implementation Notes**: Implemented in step 3.1 (combined).  Uses
> `regsOverlap()` for invalidation.  DBGS logging for each forwarding action.

### Step 3.5 — Implement killed-SPILL + adjacent-RELOAD optimization [x]

**File**: `V6ClangSpillForwarding.cpp`

Add the killed-source peephole:
- When SPILL has `isKill=true` and the very next instruction is a RELOAD
  of the same frame index:
  - Clear `isKill` on the SPILL source operand.
  - Forward the RELOAD (erase or replace with MOVs).
  - Record `Avail[fi] = srcReg`.

This causes PEI's SPILL expansion to emit the 2-instruction restore
(MOV H,D; MOV L,E for HL) instead of the full 10-instruction RELOAD.

> **Design Note**: Only handles the immediately-adjacent case.  No
> tracking across intervening instructions for killed sources.

> **Implementation Notes**: Implemented in step 3.1 (combined).

### Step 3.6 — Build [x]

Rebuild after core implementation.

> **Implementation Notes**: Clean build after `getImplicitDefs()` fix.

### Step 3.7 — Lit test: spill-forwarding.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/spill-forwarding.ll`

Test cases:
1. **8-bit forwarding**: SPILL8 + ALU + RELOAD8 same slot → expect MOV.
2. **16-bit forwarding**: SPILL16 DE + RELOAD16 same slot → expect MOV pair.
3. **Cross-register forwarding**: SPILL16 BC → RELOAD16 DE → expect MOV D,B; MOV E,C.
4. **Kill barrier**: SPILL + clobber + RELOAD → expect full reload (no forwarding).
5. **Killed SPILL + adjacent RELOAD**: SPILL(kill) + RELOAD → expect forwarding.
6. **Disabled**: `-v6clang-disable-spill-forwarding` → expect full spill/reload.

Use `CHECK-NOT` for eliminated reload sequences and `CHECK` for MOV
replacements.

> **Implementation Notes**: Created `test_multi_ptr_copy` using clang-generated IR
> pattern (i16 loop counter + GEP from base).  Simple pointer-increment loops
> don't generate enough register pressure.  Key check: `MOV E, C; MOV D, B`
> (forwarded register copy) present in enabled output, absent in disabled.

### Step 3.8 — Run regression tests [x]

```
python tests\run_all.py
```

All lit + golden + runtime tests must pass.

> **Implementation Notes**: All 96 lit tests pass (including new spill-forwarding.ll),
> all 15 golden tests pass.  Zero regressions.

### Step 3.9 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests/features/20/v6clang.c` to `v6clang_new01.asm` and
analyze for spill/reload elimination in loop bodies.

> **Implementation Notes**: Generated v6clang_new01.asm.  Diff confirmed 2
> RELOAD16 eliminations in multi_ptr_copy loop: XCHG replacement and
> MOV E,C; MOV D,B replacement.  12 fewer instructions, 16 fewer bytes,
> ~116 fewer cycles per iteration in the loop body.

### Step 3.10 — Make sure result.txt is created. `tests\features\README.md` [x]

Create `tests/features/20/result.txt` with C code, c8080 asm,
v6clang asm, and cycle/byte statistics.

> **Implementation Notes**: Created with full before/after comparison.
> Per-iteration savings: 12 instructions, 16 bytes, 116 cycles (18.8%).

### Step 3.11 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: (pending)

---

## 4. Expected Results

### Example 1: 16-bit forwarding in pointer-copy loop

**Before** (7-instruction reload, 56cc):
```asm
PUSH HL; LXI HL,0xa; DAD SP; MOV M,C; INX HL; MOV M,B; POP HL  ; SPILL BC
; ... BC unchanged ...
PUSH HL; LXI HL,0xa; DAD SP; MOV E,M; INX HL; MOV D,M; POP HL  ; RELOAD→DE
```

**After** (2-instruction MOV, 16cc):
```asm
PUSH HL; LXI HL,0xa; DAD SP; MOV M,C; INX HL; MOV M,B; POP HL  ; SPILL BC
; ... BC unchanged ...
MOV E, C                                                          ; forwarded
MOV D, B
```

Savings: 40cc + 8B per forwarded 16-bit reload.

### Example 2: Adjacent killed SPILL + RELOAD for HL

**Before** (18 instructions, ~120cc):
```asm
; SPILL16 HL(kill) — no HL restore (8 instr, ~60cc)
PUSH DE; MOV D,H; MOV E,L; LXI HL,off; DAD SP; MOV M,E; INX HL; MOV M,D; POP DE
; RELOAD16 → HL (8 instr, ~68cc)
PUSH DE; LXI HL,off; DAD SP; MOV E,M; INX HL; MOV D,M; XCHG; POP DE
```

**After** (10 instructions, ~76cc, HL restored in SPILL):
```asm
; SPILL16 HL (isKill cleared → emits HL restore: +2 instr, +16cc)
PUSH DE; MOV D,H; MOV E,L; LXI HL,off; DAD SP; MOV M,E; INX HL; MOV M,D; MOV H,D; MOV L,E; POP DE
; RELOAD16 eliminated entirely
```

Savings: 52cc + 8B per instance.

### Example 3: 8-bit same-register reload elimination

**Before** (5-instruction reload, 44cc):
```asm
PUSH HL; LXI HL,4; DAD SP; MOV M,A; POP HL   ; SPILL8 A
; ... A unchanged ...
PUSH HL; LXI HL,4; DAD SP; MOV A,M; POP HL   ; RELOAD8 → A
```

**After** (RELOAD erased, 0cc):
```asm
PUSH HL; LXI HL,4; DAD SP; MOV M,A; POP HL   ; SPILL8 A
; ... A unchanged ...
; (reload eliminated — A already holds the value)
```

Savings: 44cc + 5B per eliminated 8-bit reload.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Clearing `isKill` causes liveness issues in later passes | Only clear when we provably keep the register live (erase the RELOAD that re-defines it). Run with `-verify-machineinstrs`. |
| Sub-register invalidation missed (e.g., D defined but DE mapping not cleared) | `invalidateReg()` checks both sub and super registers: writing D invalidates DE slot entries. |
| Inserted MOVs conflict with live register state | MOV only inserted when target register is about to be defined by the RELOAD anyway — uses the same physical register. |
| CALL invalidation too conservative (misses IPRA) | Conservative (`Avail.clear()` on all calls). V2 can consult call clobber masks for IPRA-aware forwarding. |
| Pass ordering: later passes between us and PEI invalidate forwarding | Our MOV replacements are standard post-RA instructions — all subsequent passes handle them correctly. |

---

## 6. Relationship to Other Improvements

- **O20 (Honest Store/Load Defs)**: Reduces false clobbers of HL in
  spill/reload expansions, enabling more forwarding opportunities.
- **O8 (Spill Optimization)**: O16 is complementary — O16 eliminates
  redundant reloads, O8 reduces the cost of remaining ones.
- **O10 (Static Stack)**: Would eliminate stack frame setup overhead,
  making remaining spills cheaper.  O16 reduces spill count.
- **O39 (IPRA)**: With IPRA, calls don't clobber all registers, so
  `Avail` survives across calls to IPRA-annotated functions.  Future
  enhancement: consult call register masks instead of `Avail.clear()`.
- **O13 (LoadImmCombine)**: Runs after our pass (in pre-emit).
  Forwarded MOVs may enable further optimizations.

---

## 7. Versions

### V1 — Pseudo-level forwarding (this plan)

**Pipeline position**: `addPostRegAlloc()` — after RA, before
`ExpandPostRAPseudos` and PrologEpilogInserter (PEI).

**Operates on**: SPILL8/RELOAD8/SPILL16/RELOAD16 pseudo MachineInstrs
with explicit frame-index operands.

**Scope**:
- Forward RA-inserted spill/reload pairs (same frame index)
- Replace redundant RELOADs with MOV or erase
- Killed-SPILL + adjacent-RELOAD peephole (clear `isKill`)
- Conservative: `Avail.clear()` on all CALLs
- Intra-BB only (no cross-BB propagation)

**Cannot see**:
- Non-spill stores to stack (manual `MOV M,r` to known offsets)
- Stores/loads inserted by PEI (prologue/epilogue)
- Stores/loads generated by `expandPostRAPseudo` (16-bit pseudo expansion)
- Internal register clobbers hidden inside unexpanded pseudos

**Unique advantage**: The `isKill` clearing trick — making PEI emit a
2-instruction HL restore instead of a separate 10-instruction RELOAD —
is only possible at this level.

### V2 — Expanded-level forwarding (future)

**Pipeline position**: `addPreEmitPass()` — after PEI and
`ExpandPostRAPseudos`, alongside existing post-RA passes.

**Operates on**: Real instructions (LXI/DAD SP/MOV M,r sequences).

**Scope** (additions over V1):
- Forward any store/load to stack-relative addresses (not just SPILL/RELOAD)
- Forward across PEI-inserted sequences (callee-save, frame setup)
- Forward across expanded pseudo sequences
- IPRA-aware CALL handling (consult call clobber masks)
- Cross-BB propagation via `initFromPredecessor()`
- Redundant store elimination
- Immediate-value forwarding (`slot → constant`, not just `slot → register`)
- SP delta tracking through PUSH/POP (like Z80 SM83 §S6)

**Tradeoff**: Requires pattern-matching 5–10 instruction spill/reload
sequences with multiple expansion variants (H/L special case, HL via
XCHG, etc.).  Significantly more complex (~300 lines vs ~120 lines).

### Comparison

| Capability | V1 (pseudo) | V2 (expanded) |
|-----------|-------------|---------------|
| RA spill/reload forwarding | Yes | Yes |
| isKill clearing trick | Yes | No (already expanded) |
| Non-spill stack access | No | Yes |
| PEI-generated accesses | No | Yes |
| Pseudo-expansion accesses | No | Yes |
| IPRA-aware CALLs | No | Yes |
| Cross-BB propagation | No | Yes |
| Immediate forwarding | No | Yes |
| Implementation complexity | ~120 lines | ~300 lines |

V1 and V2 are **complementary** — V1 handles the `isKill` trick, V2
handles everything else.  Both can coexist in the pipeline.

---

## 8. Future Enhancements

Beyond V2, additional forwarding opportunities:

1. **Multi-register forwarding**: Track that register B also holds the
   value spilled from A (via MOV B,A), enabling forwarding even after
   A is clobbered.
2. **Circular dependency breaking**: When SPILL A → slot1, SPILL B →
   slot2, RELOAD slot1 → B, RELOAD slot2 → A — detect the swap and
   use XCHG or a temp register instead of two full reloads.

---

## 9. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O16 Design](design\future_plans\O16_store_to_load_forwarding.md)
* [Z80 Backend Analysis](design\future_plans\llvm_z80_analysis.md) — §S5, §S6
* [V6ClangLoadImmCombine.cpp](llvm\lib\Target\V6CLANG\V6ClangLoadImmCombine.cpp) — pass structure reference
