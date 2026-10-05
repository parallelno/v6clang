# LLVM-Z80 Backend Optimization Analysis

Analysis of Z80 LLVM backend repositories for optimization strategies
applicable to the V6CLANG (i8080) backend.

## Repositories Surveyed

| Repo | Stars | Status | LLVM Version | Notes |
|------|-------|--------|-------------|-------|
| [jacobly0/llvm-project](https://github.com/jacobly0/llvm-project) (branch `z80`) | 171 | Stable (last commit 3y ago) | ~15 | Primary (e)Z80 backend, GlobalISel, mature |
| [llvm-z80/llvm-z80](https://github.com/llvm-z80/llvm-z80) | 34 | Active (updated 2 wks ago) | ~20 | New Z80+SM83 backend, ports from llvm-mos |

## Architecture Comparison: Z80 vs i8080

The Z80 is a **direct superset** of the Intel 8080 — every 8080 instruction
exists in the Z80 with the same encoding. This makes Z80 optimization
strategies *more directly applicable* to V6CLANG than the 6502 (llvm-mos) strategies.

| Feature | Z80 | i8080 (V6CLANG) | Impact |
|---------|-----|-------------|--------|
| Registers | A,B,C,D,E,H,L + IX,IY | A,B,C,D,E,H,L | Same core set |
| Register pairs | BC,DE,HL,IX,IY | BC,DE,HL | Z80 has 2 extra index regs |
| ALU operations | Accumulator-only (A) | Accumulator-only (A) | **Identical bottleneck** |
| Addressing modes | (HL), (BC), (DE), (IX+d), (IY+d) | (HL), (BC), (DE) | Z80 has indexed addressing |
| Stack-relative | Via IX+d (8-bit offset) | None | Major V6CLANG disadvantage |
| Branch types | JP abs, JR rel, DJNZ | JMP abs only | Z80 has relative branches |
| Conditional CALL | CALL CC, nn | CC/CNC/CZ/CNZ/CP/CM/CPE/CPO | **Both have it** |
| Barrel shifter | No (1-bit shifts only) | No (1-bit shifts only) | **Identical constraint** |
| Block instructions | LDIR, LDDR, CPIR | None | Z80 advantage |
| Shadow registers | EXX, EX AF | None | Z80 interrupt advantage |
| 16-bit ALU | ADC HL,rr; SBC HL,rr | DAD only (no ADC/SBC) | Z80 advantage |

**Key insight**: Because the Z80 is a superset, every pure-8080 optimization
from these backends applies directly. The challenge is identifying which Z80
features (IX+d, DJNZ, EXX, ADC HL) are used and finding equivalent 8080
strategies.

---

## Pass Pipeline Comparison

### jacobly0/llvm-project Pass Order

```
1. IRTranslator (GlobalISel)
2. Z80PreLegalizeCombiner
3. Legalizer
4. Z80PostLegalizeCombiner
5. RegBankSelect
6. InstructionSelect
7. Z80PostSelectCombiner
8. [Standard SSA opts]
9. Z80MachineEarlyOptimization    ← Conditional call conversion
10. Z80MachinePreRAOptimization    ← Load folding
11. [Register allocation]
12. [Standard post-RA opts]
13. Z80MachineLateOptimization     ← Value tracking + peephole
14. Z80BranchSelector              ← JR/JP relaxation
```

### llvm-z80/llvm-z80 Pass Order

```
1. LowerAtomic (IR)
2. [Standard IR passes]
3. InstCombine
4. IRTranslator (GlobalISel)
5. Z80PreLegalizerCombiner
6. Z80ShiftRotateChain             ← Shift chaining (from llvm-mos)
7. Legalizer
8. Z80PostLegalizerCombiner
9. Z80LowerSelect
10. RegBankSelect
11. Localizer
12. InstructionSelect
13. [Extra RegisterCoalescer + LiveIntervals]
14. Z80FixupImplicitDefs
15. [Register allocation]
16. FinalizeISel
17. ExpandPostRAPseudos
18. Z80PostRAScavenging
19. Z80LateOptimization             ← Store-to-load fwd + peepholes
20. Z80PostRACompareMerge           ← Redundant OR A removal
21. BranchRelaxation
22. Z80BranchCleanup                ← JR_CC+JP → JP_CC
23. Z80ExpandPseudo                 ← Inline mul/div expansion
```

### Z80IndexIV (IR-level loop pass)
```
Registered via registerPassBuilderCallbacks as a late loop optimization.
Runs before codegen, rewrites GEP SCEVs to use 8-bit indices.
```

---

## Strategy Catalog

### S1. Comprehensive Register Value Tracking (jacobly0)

**File**: `Z80MachineLateOptimization.cpp` (~500 lines)

The most sophisticated optimization in either backend. Maintains a
`RegVal` per physical register tracking known constant value (immediate
or GlobalAddress+offset) with sub-register composition. Combined with
flag state tracking (8 bits: S,Z,H,P/V,N,C with known mask/value).

**Optimizations enabled**:
- `LD r, imm` → `LD r, r'` when r' holds imm (register reuse)
- `LD r, imm` → `INC r`/`DEC r` when r holds imm±1
- Redundant instruction elimination (same value already in dst)
- `SLA A` → `ADD A,A` (2 bytes → 1 byte, same effect)
- `RLC A`/`RRC A`/`RL A`/`RR A` → `RLCA`/`RRCA`/`RLA`/`RRA` (prefix-free)
- `LD r, 0` → `SBC r,r` when carry flag is known clear
- `Sub16`/`Cmp16` → `SBC16` when carry flag is provably 0
- Dead/killed flag propagation for safe register reuse

**V6CLANG applicability**: **Very High**. The 8080 has the same register set
(minus IX/IY). This is a significantly more powerful version of O13
(Load-Immediate Combining). The flag tracking translates directly —
8080 has the same S,Z,AC,P,CY flags. The `SLA A` → `ADD A,A` pattern
maps to future peephole opportunities.

**Extends O13**: O13 only tracks immediates per register. This tracks
immediates, globals, sub-register composition, and flag state. Upgrading
O13 to this level would catch substantially more patterns.

---

### S2. Conditional Call Optimization (jacobly0)

**File**: `Z80MachineEarlyOptimization.cpp` (~100 lines)

Converts branch-around-call patterns to conditional call instructions.
When a conditional branch skips over a single call (and optional result
copies), this replaces the pattern with a conditional CALL.

**Pattern**:
```
  JR NZ, skip          →    CALL NZ, target
  CALL target               (result copies moved before call)
  <copy results>
skip:
```

**V6CLANG applicability**: **High**. The 8080 has conditional CALL instructions
(CC, CNC, CZ, CNZ, CP, CM, CPE, CPO) that are *never used* by V6CLANG today.
Converting `JNZ skip / CALL target / skip:` to `CNZ target` saves:
- 3 bytes (JNZ=3B + CALL=3B → CNZ=3B)
- ~6cc when the call happens, ~18cc when skipped (JNZ=12cc → 0cc)

The cost threshold (`z80-cond-call-threshold=10`) prevents conversion when
the call block has too many non-call instructions.

---

### S3. Pre-RA Load Folding (jacobly0)

**File**: `Z80MachinePreRAOptimization.cpp` (~60 lines)

Tracks single-use loads (`canFoldAsLoad()`) and tries to fold them into
their consumers via `TII.optimizeLoadInstr()`. This is a simplified
version of MachineLICM's load folding, targeted at the Z80's limited
addressing modes.

**V6CLANG applicability**: **Medium**. V6CLANG's `optimizeLoadInstr()` would need
implementation in `V6ClangInstrInfo`. The technique is sound but may yield
fewer opportunities on the 8080 which has fewer foldable patterns.

---

### S4. Optimal Stack Adjustment Strategy (jacobly0)

**File**: `Z80FrameLowering.cpp` — `getOptimalStackAdjustmentMethod()` (~80 lines)

Pre-computes the cheapest SP adjustment among 5 methods:
- **SAM_Tiny**: `INC SP`/`DEC SP` for 1-2 bytes (1 byte each, 6cc on Z80)
- **SAM_Small**: `POP r`/`PUSH r` for multiples of SlotSize (1 byte, 10-11cc)
- **SAM_Medium**: `LEA r, FP+offset; LD SP, r` via frame pointer (eZ80 only)
- **SAM_Large**: `LD r, offset; ADD r, SP; LD SP, r` (10-12 bytes, 21-27cc)
- **SAM_All**: `LD SP, FP` if restoring to frame pointer (1 instruction)

Considers `-Os` vs speed optimization and eZ80 vs Z80 instruction costs.

**V6CLANG applicability**: **High**. V6CLANG currently uses a simple approach for
stack adjustment. The POP-based strategy (1 byte per 2 bytes) is directly
applicable: `POP PSW` costs 12cc on 8080 (vs `INX SP; INX SP` = 12cc but
2 bytes). For sizes > 4 bytes, POP is more compact. For large frames,
`LXI HL, offset; DAD SP; SPHL` is the 8080 equivalent of SAM_Large.

---

### S5. Post-RA Store-to-Load Forwarding (llvm-z80/llvm-z80)

**File**: `Z80LateOptimization.cpp` — IX-indexed section (~150 lines)

Tracks which physical register value resides at each IX+d stack offset.
When a spill `LD (IX+d), R` is followed by a reload `LD R', (IX+d)`,
replaces the reload with `LD R', R` (or eliminates it if R'==R).

**Algorithm**:
- `DenseMap<int, MCPhysReg, IXOffsetInfo> AvailValues` tracks offset→register
- On store `LD (IX+d), R`: record `AvailValues[d] = R`
- On load `LD R', (IX+d)`: check `AvailValues[d]`, forward if possible
- On clobber of any tracked register: invalidate affected entries
- On call/unmodeled side effects: clear all entries

**V6CLANG applicability**: **Very High**. This is one of the most impactful
optimizations for V6CLANG. Stack access on the 8080 costs ~52cc (see O8). If
a spilled value is still in a register when reloaded, replacing the reload
with a `MOV R', R` (8cc) saves ~44cc per instance. The tracking mechanism
works identically — V6CLANG uses SHLD/LHLD or multi-instruction sequences
instead of IX+d, but the concept of "offset→register" mapping is the same.

---

### S6. SM83 SP-Relative Store-to-Load Forwarding (llvm-z80/llvm-z80)

**File**: `Z80LateOptimization.cpp` — SM83 section (~300 lines)

Similar to S5 but for SM83 which lacks IX (like the 8080). Tracks slot
values as either register or immediate at each SP-relative offset. Handles
16-bit store/load patterns, redundant store elimination, and full forwarding
with circular dependency checking.

**V6CLANG applicability**: **High**. SM83 is closer to 8080 than Z80 in terms
of stack access (neither has IX+d). The slot tracking with SP delta
management is directly applicable to V6CLANG's stack access patterns.

---

### S7. Redundant Flag-Setting Elimination (llvm-z80/llvm-z80)

**File**: `Z80PostRACompareMerge.cpp` (~80 lines)

Removes redundant `OR A` instructions that set the Z flag before a
conditional branch, when the preceding ALU instruction already set the
flag correctly.

**Pattern**:
```
  XOR E       ; sets Z flag based on A  →   XOR E
  OR A        ; redundant                     JR Z, label
  JR Z, label
```

**V6CLANG applicability**: **High**. The 8080 pattern is `ORA A` before `JZ`/`JNZ`.
After `ANA`, `ORA`, `XRA`, `ADD`, `ADC`, `SUB`, `SBB`, `CMP` — all set the
zero flag. The subsequent `ORA A` is redundant. V6CLANG's `V6ClangEliminateZeroTest`
already does a version of this for the `ZERO_TEST` pseudo, but a more general
post-RA pass that catches all missed patterns would be valuable.

---

### S8. Peephole Collection (llvm-z80/llvm-z80 LateOpt)

**File**: `Z80LateOptimization.cpp` (~600 lines total)

Collection of targeted peepholes beyond store-to-load forwarding:

| Peephole | Saving | 8080 Equivalent |
|----------|--------|-----------------|
| POP rr; PUSH rr → erase (when rr dead after) | 2B, 22T | POP/PUSH PSW (or pair) → erase |
| LD A,r; DEC A; LD r,A; OR A; JR NZ → DEC r; JR NZ | 3B, 14T | MOV A,r; DCR A; MOV r,A; ORA A; JNZ → DCR r; JNZ |
| XOR #0xFF → CPL (when FLAGS dead) | 1B | XRI 0FFH → CMA (always, CMA doesn't affect flags) |
| LD A,#0 → XOR A (when FLAGS dead) | 1B | MVI A,0 → XRA A (when flags dead) |
| ALU #n; ALU #n → ALU #n (idempotent) | varies | ANI n; ANI n → ANI n |
| XOR compare constant folding | 1B | XRI-based 16-bit compare folding |

**V6CLANG applicability**: **Very High** for the loop counter optimization in
particular. The `DCR r; JNZ` pattern (10cc, 2B) replaces the 5-instruction
decrement-and-branch-if-nonzero sequence (28T, 6B). The `CMA` and `XRA A`
patterns are also directly applicable.

---

### S9. Inline Arithmetic Expansion (llvm-z80/llvm-z80)

**File**: `Z80ExpandPseudo.cpp` (~500 lines)

Expands multiply, divide, modulo, and saturating arithmetic as inline loops
instead of library calls:
- **8-bit multiply**: shift-add loop (8 iterations)
- **8-bit unsigned divide**: restoring division (8 iterations)
- **8-bit signed divide**: sign handling + unsigned division
- **16-bit multiply**: shift-add (16 iterations, separate Z80/SM83 algorithms)
- **16-bit unsigned/signed divide**: 16-bit restoring division
- **Variable shifts**: DJNZ/DEC B loops
- **Saturating arithmetic**: branch-based clamping

**V6CLANG applicability**: **Medium-High**. V6CLANG currently uses library calls for
multiply and divide. Inline expansion eliminates:
- CALL/RET overhead (30cc)
- Full register save/restore in the called function (~40-80cc)
- Memory access for the library code (icache-like effect)

The tradeoff is code size — each inline expansion duplicates the algorithm.
For 8-bit multiply (the most common), the inline loop (~15 instructions) is
often smaller than the CALL + library function impact on total program size.
The SM83 algorithm variants (no DJNZ, no EX DE,HL) map directly to 8080.

---

### S10. Aggressive Inlining Control (llvm-z80/llvm-z80)

**File**: `Z80TargetTransformInfo.h` — `areInlineCompatible()` (~10 lines)

Restricts function inlining to:
- Functions with `InlineHint` attribute (e.g., Rust iterators, C++ `inline`)
- Small functions (≤ 10 instructions) where call overhead dominates

**Rationale**: With only 3 GP register pairs, inlining large functions causes
massive register spilling that dwarfs the benefit of eliminating the call/ret.

**V6CLANG applicability**: **High**. V6CLANG has the same 3 register pairs (BC, DE, HL).
LLVM's default inlining thresholds are tuned for targets with 16-32 GPRs.
Without TTI overrides, V6CLANG inlines aggressively, causing spill explosions
in the callers. This simple TTI hook prevents that with minimal code.

---

### S11. LSR Cost Tuning (llvm-z80/llvm-z80)

**File**: `Z80TargetTransformInfo.h` — `isLSRCostLess()` (~10 lines)

Overrides Loop Strength Reduction cost comparison to prioritize instruction
count over other metrics (NumRegs, AddRecCost, etc.).

**V6CLANG applicability**: **High**. Directly complements O7 (TTI for LSR).
The Z80's priority ordering (Insns first) makes sense for the 8080 too —
each extra instruction costs 4-12cc and 1-3 bytes, while extra registers
cause spills costing 52-104cc each.

---

### S12. Shift/Rotate Chaining (llvm-z80/llvm-z80, from llvm-mos)

**File**: `Z80ShiftRotateChain.cpp` (~120 lines)

Chains constant-amount shifts of the same base value:
`SHL x, 5` when `SHL x, 3` already exists → rewrite to `SHL (SHL x, 3), 2`.
Uses dominance analysis to move the earlier shift up if needed.

**V6CLANG applicability**: **Medium**. Already mentioned in llvm-mos analysis.
The Z80 version is essentially identical to the llvm-mos version ported for
the Z80's GlobalISel pipeline.

---

## Ranked Strategies (Impact × Feasibility for V6CLANG)

| Rank | Strategy | Impact | Feasibility | Notes |
|------|---------|--------|-------------|-------|
| 1 | S5. Store-to-Load Forwarding | Very High | High | ~44cc savings per forwarded reload |
| 2 | S2. Conditional Call Optimization | High | High | 8080 has CC/CNC/CZ etc., never used today |
| 3 | S1. Comprehensive Value Tracking | Very High | Medium | Extends O13 massively, ~500 lines |
| 4 | S8. Peephole Collection (loop counter) | High | High | DCR r; JNZ is immediately applicable |
| 5 | S10. Inlining Control | High | Very High | 10-line TTI hook, prevents spill explosions |
| 6 | S9. Inline Arithmetic | Medium-High | Medium | Eliminates libcall overhead, SM83 alg = 8080 |
| 7 | S4. Optimal Stack Adjustment | Medium-High | High | POP-based is more compact than INC SP |
| 8 | S7. Redundant Flag Elimination | Medium | High | Extends existing ZERO_TEST |
| 9 | S11. LSR Cost Tuning | Medium | Very High | 10-line TTI addition |
| 10 | S6. SP-Relative Forwarding | Medium | Medium | SM83 patterns closer to 8080 |
| 11 | S3. Load Folding | Low-Med | Medium | Requires V6ClangInstrInfo additions |
| 12 | S12. Shift/Rotate Chaining | Low | High | Already covered in llvm-mos analysis |

---

## Mapping to Existing V6CLANG Optimizations (O1-O14)

| Z80 Strategy | V6CLANG Item | Relationship |
|-------------|----------|-------------|
| S1 (Value Tracking) | O13 | **Extends** — O13 is a subset of S1 |
| S2 (Conditional Call) | — | **New** → O15 |
| S3 (Load Folding) | — | Lower priority, defer |
| S4 (Stack Adjustment) | O8 | **Enhances** — adds alternative methods |
| S5 (Store-to-Load Fwd) | — | **New** → O16 |
| S6 (SP-Relative Fwd) | — | Variant of S5, covered by O16 |
| S7 (Flag Elimination) | O13 area | **New** → O17 |
| S8 (Peepholes) | — | **New** → O18 (loop counter) + enhancements |
| S9 (Inline Arithmetic) | — | **New** → O19 |
| S10 (Inlining Control) | O7 area | **New** → add to O7's TTI |
| S11 (LSR Cost) | O7 | **Enhances** — adds isLSRCostLess |
| S12 (Shift Chain) | llvm-mos ref | Already documented |
