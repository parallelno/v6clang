# O79. `MVI R, NN` + `ALU R` → `ALU-Immediate NN` Fold

## Problem

Whenever the i8 ALU consumer wants `A op imm` but the immediate is
materialized in a non-A register first (because of register pressure,
ISel choices, or earlier passes that hoisted the constant), V6CLANG codegen
emits the two-instruction sequence:

```asm
MVI  R, NN     ; 7cc, 2B   — R is one of B,C,D,E,H,L
ADD  R         ; 4cc, 1B   ; or SUB/ANA/ORA/ADC/SBB/XRA/CMP
```

The 8080 has direct **ALU-immediate** counterparts for every register-form
ALU op (`ADI`, `SUI`, `ANI`, `ORI`, `ACI`, `SBI`, `XRI`, `CPI`), each
costing 7cc / 2B and producing the **same A and FLAGS result** as
`MVI R,NN; ALU R`. When `R` is otherwise unused, replacing the pair
with the immediate form saves the entire `ALU R` instruction —
**4cc / 1B per fold** — and frees `R` for register allocation across
the surrounding region (an indirect win on top of the direct savings).

The two instructions need not be adjacent: as long as nothing between
them reads/writes `R` (or its alias), and `R` is dead after the ALU
op, the fold is sound.

## Pattern

**Match (within a single basic block)**:

1. `MVI R, NN`  where `R ∈ {B,C,D,E,H,L}` (i.e. not A — there's no
   `MVI A,NN; ADD A` style fold to make; that case is a different
   transformation outside this pass's scope).
2. Any of: `ADDr R / SUBr R / ANAr R / ORAr R / ADCr R / SBBr R /
   XRAr R / CMPr R` later in the same MBB.

**Side-conditions** (all must hold):

- No instruction strictly between the two reads or writes `R` (the
  16-bit pair containing `R` is also disqualifying — `INX H`,
  `LXI H,...`, `LHLD`, `XCHG`, `DAD ...`, `POP rp` covering `R`,
  any `MOV R,*` or `MOV *,R`, etc. — handled uniformly via
  `MO.isReg() && TRI->regsOverlap(MO.getReg(), R)` plus regmask
  check on calls).
- `R` is **dead after** the ALU op (no later use, not in successor
  liveins).
- No `CALL` between (regmask kills `R`); no inline asm with side
  effects on GPRs (treated conservatively as a barrier).
- The intervening region does not write A's inputs in a way that
  would be observed only via `R` — irrelevant: A is written only
  by the ALU op itself, so any A-write between would be by another
  instruction unrelated to the fold; the *value* in A at the ALU op
  is unchanged by removing the `MVI R`.

**FLAGS**: The replacement op (`ADI`, `ANI`, …) sets FLAGS identically
to its register-form counterpart (`ADDr`, `ANAr`, …) — the encoding
shares the ALU-function bits. No FLAGS-liveness check is required.

## Replacement

| Before                       | After             |
|------------------------------|-------------------|
| `MVI R,NN ; ... ; ADD R`     | `... ; ADI NN`    |
| `MVI R,NN ; ... ; SUB R`     | `... ; SUI NN`    |
| `MVI R,NN ; ... ; ANA R`     | `... ; ANI NN`    |
| `MVI R,NN ; ... ; ORA R`     | `... ; ORI NN`    |
| `MVI R,NN ; ... ; ADC R`     | `... ; ACI NN`    |
| `MVI R,NN ; ... ; SBB R`     | `... ; SBI NN`    |
| `MVI R,NN ; ... ; XRA R`     | `... ; XRI NN`    |
| `MVI R,NN ; ... ; CMP R`     | `... ; CPI NN`    |

Per fire:
- `MVI R,NN` removed: −2B / −7cc
- `ALU R` (1B / 4cc) replaced by `ALU-imm NN` (2B / 7cc): +1B / +3cc
- **Net: −1B / −4cc per fold**, plus `R` becomes available across
  the gap (indirect spill/RA win).

## Implementation Sketch

New peephole hook in `V6ClangPeephole.cpp`, called per basic block (this
pass already iterates per-MBB; add another `runOnMBB` helper named
`foldMviAluImm`).

```cpp
// Map register-form ALU opcode → immediate-form opcode.
static unsigned aluRegToImm(unsigned Opc) {
  switch (Opc) {
  case V6CLANG::ADDr: return V6CLANG::ADI;
  case V6CLANG::ADCr: return V6CLANG::ACI;
  case V6CLANG::SUBr: return V6CLANG::SUI;
  case V6CLANG::SBBr: return V6CLANG::SBI;
  case V6CLANG::ANAr: return V6CLANG::ANI;
  case V6CLANG::XRAr: return V6CLANG::XRI;
  case V6CLANG::ORAr: return V6CLANG::ORI;
  case V6CLANG::CMPr: return V6CLANG::CPI;
  default:       return 0;
  }
}

bool V6ClangPeephole::foldMviAluImm(MachineBasicBlock &MBB) {
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    MachineInstr &MVI = *I;
    if (MVI.getOpcode() != V6CLANG::MVIr) { ++I; continue; }

    Register R = MVI.getOperand(0).getReg();
    if (R == V6CLANG::A) { ++I; continue; }   // not in scope

    int64_t Imm = MVI.getOperand(1).getImm();

    // Forward-scan looking for a matching ALU-on-R, with no
    // intervening read/write of R (or its 16-bit pair).
    auto J = std::next(I);
    bool Blocked = false;
    for (; J != E; ++J) {
      if (J->isDebugInstr()) continue;
      // Hard barriers.
      if (J->isCall() || J->isInlineAsm() ||
          J->hasUnmodeledSideEffects()) {
        Blocked = true; break;
      }
      // Is this the ALU consumer?
      if (aluRegToImm(J->getOpcode())) {
        // Register-form ALU op: operand 0 is the source GR8.
        // (CMPr is identical shape: src in operand 0, no defs.)
        if (J->getOperand(0).getReg() == R)
          break;                          // candidate found
      }
      // Any read or write of R (or alias) blocks.
      for (const MachineOperand &MO : J->operands()) {
        if (MO.isRegMask() && MO.clobbersPhysReg(R)) { Blocked = true; break; }
        if (!MO.isReg() || !MO.getReg()) continue;
        if (TRI->regsOverlap(MO.getReg(), R)) { Blocked = true; break; }
      }
      if (Blocked) break;
    }
    if (Blocked || J == E) { ++I; continue; }

    // R must be dead after the ALU op.
    if (!isRegDeadAfter(MBB, J, R, TRI)) { ++I; continue; }

    // Rewrite: build ALU-imm at J, erase MVI and old ALU.
    // (See the "O61 patched-reload landing pads" section below for
    // the additional metadata transfer — pre-instr symbol and
    // MO_PATCH_IMM target flag — required for self-modifying spill
    // landing pads. Omitted here for brevity.)
    DebugLoc DL = J->getDebugLoc();
    unsigned ImmOpc = aluRegToImm(J->getOpcode());
    BuildMI(MBB, J, DL, TII->get(ImmOpc))
        // ADI/SUI/.../CPI shape: (outs Acc:$dst)(ins Acc:$lhs, i8imm:$imm)
        // for ALU; CPI is (outs)(ins Acc:$lhs, i8imm:$imm).
        // BuildMI here mirrors what ISel emits for these opcodes —
        // see V6ClangInstrInfo.td:372–402 for exact tied-operand layout.
        .addReg(V6CLANG::A, RegState::Define)
        .addReg(V6CLANG::A)
        .addImm(Imm);
    // Note: for CMPr → CPI the def-A operand is dropped — gate on
    // the opcode and use the matching builder.

    MBB.erase(J);
    I = MBB.erase(I);                     // I now points past MVI
    Changed = true;
  }
  return Changed;
}
```

Notes on the implementation:

- `MVIr` is the "MVI R,imm8" instruction (operand 0 = GR8, operand 1
  = i8imm). `MVIM` (memory destination) is unrelated.
- The exact `BuildMI` shape for each immediate form must match the
  `(outs)/(ins)` declared in `V6ClangInstrInfo.td:372–402`. ALU forms
  declare `Acc:$dst` tied to `Acc:$lhs`; `CPI` has no def. The fold
  must dispatch on whether the consumer was `CMPr` to drop the
  `addReg(A, Define)` operand.
- The `MO.isRegMask()` clobber-check is important for `CALL`
  instructions (they appear with regmasks rather than explicit
  defs). The early `J->isCall()` barrier already handles this, but
  the regmask scan is kept as a backstop.
- `isRegDeadAfter` is the same helper used by `V6ClangXchgOpt` and
  `V6ClangPeephole::foldXchgDad` — handles successor-livein checks.

### O61 patched-reload landing pads (pre-instr symbol + `MO_PATCH_IMM`)

The dominant motivating shape for this fold is the O61 self-modifying
spill landing pad emitted by `V6ClangSpillPatchedReload`:

```asm
;--- V6CLANG_RELOAD8 ---
.LLo61_0:
        MVI     L, 0          ; the "0" byte is patched at runtime
        ADD     L             ; consumer reads the patched value
```

The `MVI` instruction here carries two pieces of metadata that the
fold **must transfer** to the rewritten ALU-immediate instruction,
otherwise the spill stops working:

1. **Pre-instruction symbol** (`MachineInstr::setPreInstrSymbol`) —
   this is the `.LLo61_0:` label. The corresponding spill emits
   `STA <Sym+1>` (or `SHLD <Sym+1>` for i16, see Stage 5; the i8
   path uses `STA <Sym+1>`). The "+1" skips the opcode byte and
   targets the immediate byte. After the fold:
   - `MVI r,imm8` is 2 bytes: opcode at +0, imm at +1.
   - `ADI/SUI/.../CPI` is 2 bytes: opcode at +0, imm at +1.
   - **The +1 offset stays valid** — the fold simply re-attaches
     the same `MCSymbol` to the new instruction via
     `setPreInstrSymbol` on the new `BuildMI`'s `MachineInstr`.

2. **`MO_PATCH_IMM` target flag** on the immediate operand
   (`V6ClangII::MO_PATCH_IMM`, set on operand 1 of the MVI by
   `V6ClangSpillPatchedReload.cpp` lines 371 & 532). The asm printer
   uses this flag to emit the immediate verbatim (it remains a
   placeholder constant; the runtime `STA` overwrites it). The
   fold must call `setTargetFlags(V6ClangII::MO_PATCH_IMM)` on the
   new ALU-immediate's imm operand.

#### Updated rewrite (extends the sketch above)

```cpp
// Preserve O61 metadata before erasing.
MCSymbol *PreSym = MVI.getPreInstrSymbol();          // may be nullptr
unsigned ImmTF = MVI.getOperand(1).getTargetFlags(); // 0 or MO_PATCH_IMM

MachineInstrBuilder MIB =
    BuildMI(MBB, J, DL, TII->get(ImmOpc));
if (ImmOpc != V6CLANG::CPI)
  MIB.addReg(V6CLANG::A, RegState::Define).addReg(V6CLANG::A);
else
  MIB.addReg(V6CLANG::A);                                // CPI: lhs only
MIB.addImm(Imm);

MachineInstr *NewMI = MIB.getInstr();
// Transfer immediate target flags (MO_PATCH_IMM for O61 reloads).
NewMI->getOperand(NewMI->getNumOperands() - 1).setTargetFlags(ImmTF);
// Transfer pre-instruction symbol (.LLo61_N label for O61 reloads).
if (PreSym)
  NewMI->setPreInstrSymbol(*MBB.getParent(), PreSym);
```

#### Why this is correct for the patched case

The O61 spill emits `STA <Sym+1>` where the "+1" is computed by the
linker/assembler from the symbol position. The label `.LLo61_0` is
attached to the start of the patched instruction. Both `MVI r,imm8`
and `ADI/SUI/.../CPI` are 2-byte instructions with identical layout
(opcode at offset 0, imm at offset 1), so `<Sym+1>` lands on the
imm byte regardless of which instruction the label decorates. The
runtime store therefore overwrites the correct byte after the fold.

The fold also reduces the patched site from **3 bytes** (MVI=2 + ADD=1)
to **2 bytes** (ADI=2). The spill site is unchanged; the patched
value still occupies one byte. The dead `ADD R` between the
patched-immediate landing pad and the next instruction simply
disappears.

#### Liveness gate is unchanged

After the fold, the patched register `R` is no longer used at all —
which is exactly the precondition this pass already requires
(`R` dead after the ALU op, no intervening reads/writes). The
patched landing pad's only purpose was to deliver a value into `R`
for the immediately-following ALU op; folding to ALU-imm makes
that delivery direct (the patched byte becomes the imm operand
of the ALU op itself), and `R` is now free.

#### Frequency in the O61 pipeline

Every O61 i8 winner in real codegen has the shape `MVI R,0; ALU R`
or `MVI R,0; MOV X,R; …` at the consumer site (the `0` is
overwritten at runtime). The first shape is exactly what this fold
catches — at every fire we save **1 byte and 4 cycles per patched
reload winner**, which is the hottest size/cycle pressure point on
the O61 self-modifying path.

The second shape (`MOV X,R`) is **out of scope** for this fold but
already handled by O13 (`MOV X,R` collapses when `R` holds a known
constant). The patched case there breaks O13 (the imm is unknown
at compile time), so the `MOV` survives — that's a separate
follow-up, not part of O79.

### CLI toggle

Add `-v6clang-disable-mvi-alu-fold` (default false) to allow disabling
for bisection / lit gating, mirroring the convention used by every
other peephole in the pass.

### Pipeline placement

Add to `V6ClangPeephole::runOnMachineFunction` after the existing
`cancelAdjacentXchg` / `foldXchgDad` calls. The new fold composes
with O13 (`V6ClangLoadImmCombine`): O13 turns redundant `MVI R,N` into
`MOV R,R'` when another reg already holds N, so this pass should
run **before** O13 to claim the easy `MVI R,N; ALU R` shape first.
If O13 has already rewritten the `MVI` into a `MOV`, the fold no
longer applies (and the `MOV` is itself a candidate for other
existing peepholes).

Empirically the current pipeline order is
`AccumulatorPlanning → LoadImmCombine → Peephole → …`
(see `V6ClangPassConfig::addPreEmitPass`). The new fold lives in
`V6ClangPeephole` and runs **after** `LoadImmCombine`, so it will catch
only the residual `MVI R,N; … ; ALU R` pairs that O13 did not
collapse to `MOV R,R'`. That residual is still common (it occurs
whenever no other live register holds the constant — the dominant
shape on V6CLANG with its narrow GPR file).

## Frequency Evidence

Greppable shapes in the existing test/benchmark asm corpus
(`tests/benchmarks_c/asm/*.s`, `tests/features/**/*.s`, `temp/*.s`):

```
MVI  L, 0
ADD  L
```

is one of the most common 2-line patterns produced today, especially
post-O64 i8 spill lowering (the patched-reload landing pad emits
`MVI R, 0` as the post-call zero rematerialization, which is then
consumed by an `ALU R` in the immediately-following ALU chain).
Sample from the user's `temp/lod_store_fi.s` after the O79' fix:

```asm
;--- V6CLANG_RELOAD8 ---
.LLo61_0:
        MVI     L, 0
        ADD     L
```

That sequence becomes a single `ADI 0` (still 7cc/2B at this site;
the win is freeing `L` for the surrounding live ranges). When the
reloaded immediate is non-zero (most reload sites), the fold also
saves 4cc + 1B directly.

A conservative estimate over the existing benchmark suite:
~10–25 fires per non-trivial benchmark, with `-O2`/`-Os` showing
the most opportunities (RA aggressively re-uses `L`/`E` as the
constant-holding scratch).

## Risks & Edge Cases

1. **A re-defined between MVI and ALU**: A is not the matched
   register, so a write to A by an intervening instruction is fine
   *for the ALU op itself* (the `ADD R` reads whatever A is at that
   point, identical to `ADI NN` at the same point). The transform
   does not move A's defining instructions and does not depend on
   A's value at the `MVI` point.

2. **R is also written between by aliasing pair**: e.g. `MVI L,0;
   LHLD ...; ADD L`. The `LHLD` re-writes `L`, so the fold must
   bail. This is caught by the `regsOverlap(MO.getReg(), R)` check
   (the `LHLD` has a `Defs=[HL]` that overlaps `L`).

3. **R live-out via successor**: caught by `isRegDeadAfter` (checks
   successor liveins).

4. **CMPr → CPI**: `CMPr` has no destination operand; the builder
   must dispatch on opcode. Tested separately.

5. **Encoding**: `ADI/SUI/...` are 2 bytes (opcode + imm8), exactly
   like `MVI r,imm8`. The `MVI r,imm8 + ALU r` sequence is 3 bytes;
   the fold drops to 2 bytes. Code size is strictly better.

6. **Cycle accounting**:
   - `MVI r,imm8` = 7cc, `ALU r` = 4cc, total 11cc / 3B
   - `ALU-imm imm8` = 7cc, total 7cc / 2B
   - **Saves 4cc / 1B per fire**.

   (8080 official timings; v6clang emulator ditto. `MVI r` is documented
   at 7cc, not 8cc — the misquote in O55 §Pattern 2 inherited from
   z80 timings does not apply here; this plan uses 8080 numbers.)

7. **No FLAGS hazard**: every ALU-immediate form sets FLAGS the
   same way as its register-form sibling. No FLAGS-liveness check
   is needed (in contrast to O55 Pattern 2).

## Tests

- New lit test `peephole-mvi-alu-imm-fold.ll` covering all 8 ALU
  ops × {adjacent, non-adjacent gap, blocked-by-R-write,
  blocked-by-call, blocked-by-R-live-out}.
- Disable test `peephole-mvi-alu-imm-fold-disabled.ll` exercising
  `-v6clang-disable-mvi-alu-fold`.
- Feature regression test under `tests/features/<next>/`.
- Existing golden suite (16/16) and benchmark checksums must remain
  unchanged — the transform is a pure size/speed peephole.

## Estimated Size & Risk

- ~80 LOC of pass code (helper + main scan + opcode map + CLI flag).
- Risk: **Low**. Pattern-local, post-RA, no flag-liveness or
  register-allocation interaction. Symmetric to existing
  `cancelAdjacentXchg` / `foldXchgDad` peepholes.
- Complexity: **Low**.

## Dependencies

- None blocking. Composes with O13 (`LoadImmCombine`) — runs after
  it so O13 has first crack at the `MVI R,N` → `MOV R,R'` rewrites
  for cases where another register already holds `N`.
