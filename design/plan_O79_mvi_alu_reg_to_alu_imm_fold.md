# Plan: O79 — `MVI R, NN` + `ALU R` → `ALU-Immediate NN` Fold

## 1. Problem

### Current behavior

The V6CLANG backend frequently emits a two-instruction sequence to perform
an i8 ALU operation against an immediate value when the immediate has
already been materialized into a non-A register (post-RA, after
`V6ClangLoadImmCombine`, after O64 reload lowering, or as a result of
ISel choices that do not select the ALU-immediate form):

```asm
MVI  R, NN     ; 7cc, 2B   — R is one of B,C,D,E,H,L
;  ... no read or write of R ...
ADD  R         ; 4cc, 1B   ; or SUB/ANA/ORA/ADC/SBB/XRA/CMP
```

The two instructions need not be adjacent; `V6ClangLoadImmCombine` and
`V6ClangXchgOpt` may schedule unrelated instructions between them. The
register `R` is generally otherwise unused — its only purpose was to
hold the immediate for the ALU op.

The single most-frequent shape of this pattern is the O61
self-modifying patched-reload landing pad emitted by
`V6ClangSpillPatchedReload`:

```asm
;--- V6CLANG_RELOAD8 ---
.LLo61_0:
        MVI     L, 0          ; the "0" byte is patched at runtime
        ADD     L
```

### Desired behavior

```asm
ADI  NN        ; 7cc, 2B  — directly consumes the immediate
```

For the O61 case the patched landing pad becomes:

```asm
.LLo61_0:
        ADI     0             ; STA <Sym+1> still hits the imm byte
```

Per fire:

| Before                          | After          | Δ bytes | Δ cycles |
|---------------------------------|----------------|---------|----------|
| `MVI R,NN` (2B/7cc) + `ALU R` (1B/4cc) = 3B/11cc | `ALU-imm NN` (2B/7cc) | **−1B** | **−4cc** |

Plus `R` becomes available across the gap for register allocation
(an indirect win on top of the direct savings).

### Root cause

The 8080 ISA exposes both register-form ALU ops (`ADDr/.../CMPr`)
and immediate-form ALU ops (`ADI/.../CPI`) with identical FLAGS
semantics. ISel and the existing peepholes do not always pick the
immediate form — particularly when the constant is rematerialized
post-RA (O64 i8 spill landing pads) or fed through a register
because of accumulator-bottleneck scheduling. A late local peephole
recovers the optimal form.

---

## 2. Strategy

### Approach: forward-scan local peephole in `V6ClangPeephole`

Add a new MBB-local helper `foldMviAluImm` to `V6ClangPeephole.cpp`. For
each `MVIr R, imm` (with `R != A`), forward-scan the rest of the MBB
looking for an ALU-on-`R` instruction. Bail on any read/write of `R`
or its 16-bit alias, on calls (regmask kills `R`), on inline asm,
and on instructions with unmodeled side effects. Once found, rewrite:

- Build the ALU-immediate counterpart at the consumer's position
  with the same imm operand (preserving target flags and any
  `MO_PATCH_IMM`).
- Transfer `getPreInstrSymbol` from the `MVI` to the new ALU-imm
  instruction (so O61 spills' `STA <Sym+1>` keep working).
- Erase both the `MVI` and the original ALU-on-`R`.

The fold requires `R` to be **dead after** the consumer ALU op
(so the consumer's only purpose was to read the materialized
constant). This is checked with the existing `isRegDeadAfter`
helper already used by other peepholes in this file.

### Why this works

- `MVI r,imm8` and the ALU-immediate forms (`ADI/SUI/.../CPI`)
  encode in the same 2 bytes (opcode + imm8). For O61 patched
  sites, the spill emits `STA <Sym+1>` where `+1` skips the
  opcode byte; both old and new instructions place the imm at
  offset +1, so the patch remains correct.
- Every register-form ALU op sets FLAGS identically to its
  immediate-form counterpart (same ALU-function bits in the
  encoding), so no FLAGS-liveness reasoning is needed.
- `A`'s value at the consumer is unchanged: removing the
  `MVI R` does not affect any A-defining instruction in between.
- The intervening region is required to neither read nor write
  `R` (or its 16-bit pair), so there is no observable use of
  the value held in `R` other than the consumer ALU op.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp` | Add `foldMviAluImm` method + opcode map + CLI flag; wire into `runOnMachineFunction` |
| `llvm-project/llvm/test/CodeGen/V6CLANG/peephole-mvi-alu-imm-fold.ll` | New lit test covering all 8 ALU ops + 5 edge cases |
| `tests/features/61/` | Feature regression test (c8080.c, v6clang.c, asms, result.txt) |
| `design/future_plans/README.md` | Mark O79 complete |
| `design/future_plans/O79_mvi_alu_reg_to_alu_imm_fold.md` | (already authored) — implementation reference |

---

## 3. Implementation Steps

### Step 3.1 — Add `foldMviAluImm` to `V6ClangPeephole.cpp` [x]

Add the new method and opcode helper at the end of the helper
section (after `foldXraCmpZeroTest` / before
`runOnMachineFunction`). Declaration goes into the private
section of the `V6ClangPeephole` class.

Key details:

- Opcode map (8 entries):
  `ADDr→ADI, ADCr→ACI, SUBr→SUI, SBBr→SBI, ANAr→ANI, XRAr→XRI,
  ORAr→ORI, CMPr→CPI`.
- Source MI: `V6CLANG::MVIr` only. Skip if dst register == A.
- Forward scan from `std::next(MVI)`:
  - Hard barriers: `isCall`, `isInlineAsm`,
    `hasUnmodeledSideEffects`. Also `regmask.clobbersPhysReg(R)`.
  - Any operand that is a register overlapping `R` (use or def)
    blocks — except the ALU consumer's source-R operand itself,
    which is the success case.
  - Recognise the consumer by `aluRegToImm(opc) != 0` AND the
    GR8 source operand register equals `R`. For non-CMPr that's
    operand 2 (after `dst`, `lhs`); for CMPr that's operand 1.
- Liveness: require `isRegDeadAfter(MBB, J, R, TRI)` — `R` dead
  after the ALU op.
- Rewrite:
  - Capture `MCSymbol *PreSym = MVI.getPreInstrSymbol()`.
  - Build the new instruction with the matching shape:
    - For ALU writers: `BuildMI(...).addReg(A, Define).addReg(A).add(MVI.getOperand(1))`
    - For CPI:        `BuildMI(...).addReg(A).add(MVI.getOperand(1))`
  - `MIB.add(MVI.getOperand(1))` carries the imm value AND the
    `MO_PATCH_IMM` target flag.
  - If `PreSym` is non-null, `setPreInstrSymbol(*MF, PreSym)` on
    the new MI.
- Erase the consumer first, then erase the MVI; advance the
  outer iterator carefully (use `make_early_inc_range` style or
  capture `Next = std::next(I)` before erasing).

> **Design Notes**:
> - The existing `isO61PatchedImm` helper in this file *blocks*
>   peepholes that erase the patched MI without replacement. This
>   fold preserves the metadata onto the new MI, so it is correct
>   to apply on O61 patched MVIs and we do **not** call
>   `isO61PatchedImm` to skip them.
> - `MIB.add(MO)` (where `MO` is the source operand) preserves
>   target flags by design — confirmed by reading
>   `MachineInstrBuilder::add` semantics.
> - The plan keeps the fold within a single MBB; cross-MBB
>   cases are rare for this pattern and out of scope.

> **Implementation Notes**: Done.

### Step 3.2 — Add CLI flag [x]

Add a new `cl::opt<bool> DisableMviAluFold("v6clang-disable-mvi-alu-fold", ...)`
near the existing `DisablePeephole`. Honour it by an early
`if (DisableMviAluFold) return false;` at the top of
`foldMviAluImm`.

> **Implementation Notes**: Done.

### Step 3.3 — Wire into `runOnMachineFunction` [x]

Add `Changed |= foldMviAluImm(MBB);` to the per-MBB pass list
in `V6ClangPeephole::runOnMachineFunction`. Place it after
`foldXraCmpZeroTest` so it can consume any residual
`MVI R, NN; ... ; ALU R` produced by earlier peepholes in the
same pass.

> **Implementation Notes**: Done.

### Step 3.4 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Done.

### Step 3.5 — Lit test: `peephole-mvi-alu-imm-fold.ll` [x]

New file at `llvm-project/llvm/test/CodeGen/V6CLANG/peephole-mvi-alu-imm-fold.ll`.

Cases (one per CHECK label):
1. `add_l`: `MVI L,5; ADD L; A live` → `ADI 5`.
2. `sub_h`: `MVI H,3; SUB H` → `SUI 3`.
3. `ana_b`: `MVI B,0xF0; ANA B` → `ANI 240`.
4. `ora_c`: `MVI C,1; ORA C` → `ORI 1`.
5. `xra_d`: `MVI D,7; XRA D` → `XRI 7`.
6. `adc_e`: `MVI E,0; ADC E` → `ACI 0`.
7. `sbb_l`: `MVI L,4; SBB L` → `SBI 4`.
8. `cmp_h`: `MVI H,9; CMP H` → `CPI 9`.
9. `gap_no_clobber`: `MVI L,5; <unrelated MOV B,C>; ADD L` → folds.
10. `blocked_by_l_clobber`: `MVI L,5; LXI HL,0x1000; ADD L` → no fold.
11. `blocked_by_r_live_out`: `MVI L,5; ADD L; OUT 0xde,L` → no fold.
12. `disabled` variant exercising `-v6clang-disable-mvi-alu-fold` (run-line).

> **Implementation Notes**: Plain `MVI R, imm; ALU R` cannot be
> reached at -O0 (no MVI-r emitted) and at -O2 ISel selects ALU-imm
> directly, so a synthetic LL-only test cannot exercise the fold
> in isolation. The shipped test instead drives the fold through
> O61 patched-reload (the only path that produces real `MVI R,0;
> ALU R` shapes in production): an 8-arg i8 XOR-chain function
> with `norecurse`, compiled at `-O2 -mv6clang-spill-patched-reload`,
> spills H through a non-A landing pad whose reload site is
> `MVI L, 0; XRA L`. The test checks `XRI 0` after `.LLo61_0:` in
> the `CHECK` mode and `MVI [BCDEHL], 0; XRA [BCDEHL]` in the
> `DIS` (-v6clang-disable-mvi-alu-fold) mode — directly proving the
> patched-reload-symbol is preserved across the fold.

### Step 3.6 — Run regression tests [x]

```
python tests\run_all.py
```

If anything fails, diagnose, fix, return to Step 3.4.

> **Implementation Notes**: Done.

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests/features/61/v6clang.c` to `v6clang_new01.asm`,
compare against `v6clang_old.asm`, and verify each test function
shows the expected `MVI ... ; ALU ...` → `ALU-imm` collapse.

> **Implementation Notes**: `fold_spill` shows the only effective
> change: `.LLo61_0: MVI L, 0; XRA L` → `.LLo61_0: XRI 0`
> (−1 byte / −4 cc, label and `STA .LLo61_0+1` patch site
> preserved). The simple `fold_*` functions are untouched (already
> ALU-imm by ISel) — confirms no regression on the trivial cases.

### Step 3.8 — Make sure result.txt is created [x]

Per `tests/features/result.md` — include C source, c8080 asm,
v6clang old + new asm, and a comparison table (cycles & bytes
per function across all three).

> **Implementation Notes**: Done.

### Step 3.9 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Done.

---

## 4. Expected Results

### Example 1 — Direct constant materialization

A trivial source pattern:

```c
uint8_t f(uint8_t a) { return (a + 5) & 0xF0; }
```

Today (post-O64, post-O13):

```asm
        MOV     A, L      ;  arg  (8cc/1B)
        ADI     5         ; (7cc/2B)
        MVI     L, 0xF0   ; (7cc/2B)
        ANA     L         ; (4cc/1B)
        RET
```

After O79 fires on the second pair:

```asm
        MOV     A, L
        ADI     5
        ANI     0xF0      ; folded
        RET
```

**Save: 1B / 4cc** on this single function.

### Example 2 — O61 patched reload

```asm
;--- V6CLANG_RELOAD8 ---
.LLo61_0:
        MVI     L, 0
        ADD     L
```

After O79:

```asm
;--- V6CLANG_RELOAD8 ---
.LLo61_0:
        ADI     0
```

`STA <Sym+1>` from the spill site still patches the imm byte
(byte offset +1 from `.LLo61_0`). **Save: 1B / 4cc** at the
reload site, plus `L` is freed across the surrounding live
region — measurable on every i8 spill in O61's hot path.

### Example 3 — Composes with O13

When O13 has already turned the `MVI R,N` into `MOV R,R'`
(another live reg holds N), O79 doesn't fire. When O13 cannot
collapse (no live constant-holder — the dominant case on V6CLANG's
narrow GPR file), O79 catches the residual.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Erasing the O61 patched MVI loses the `.LLo61_N` label, orphaning the spill `STA <Sym+1>`. | Transfer `getPreInstrSymbol` to the new ALU-imm; both old/new MI are 2 bytes opcode+imm so `+1` offset stays valid. |
| Imm operand carries `MO_PATCH_IMM` (O61) — must not be lost. | Use `MIB.add(MVI.getOperand(1))` which copies operand wholesale including target flags. |
| Intervening reg-pair write on `R`'s 16-bit alias (e.g. `LHLD` redefines L). | `regsOverlap(MO.getReg(), R)` check catches it (LHLD declares Defs=[HL]). |
| Call inserts regmask clobber. | `isCall` is a hard barrier; backstopped by `regmask.clobbersPhysReg`. |
| Inline asm with side effects. | `isInlineAsm` + `hasUnmodeledSideEffects` are hard barriers. |
| `R` live-out via successor MBB. | `isRegDeadAfter` checks successor liveins via `MCRegAliasIterator`. |
| `CMPr` has no destination operand, different `BuildMI` shape. | Dispatch on opcode; `CPI` builder uses `(outs)(ins Acc:$lhs, imm)`, no `addReg(A, Define)`. |
| Pass placement — running before O13 might claim shapes O13 could collapse. | Place after existing peepholes in `V6ClangPeephole`. Pipeline order is: `Peephole → LoadImmCombine → ...`. The fold runs in Peephole (which precedes LoadImmCombine) so the residual O79 catches what LoadImmCombine would not have collapsed anyway. |

---

## 6. Relationship to Other Improvements

- **O13 (LoadImmCombine)** — composes; O13 turns `MVI R,N` into
  `MOV R,R'` when another live register already holds `N`. After
  O13, fewer O79 candidates remain, but the residual is still
  common when no live register holds the constant.
- **O44 (Adjacent XCHG cancellation)** / **O55 (XRA A)** —
  independent peepholes in the same pass; the fold layers
  cleanly on top.
- **O61 (Patched reload)** — primary beneficiary. O79 reduces
  every patched i8 reload+ALU pair from 3B/11cc to 2B/7cc and
  releases the patched register.
- **O64 (Liveness-aware i8 spill lowering)** — the post-call
  re-zero-and-ALU shape becomes a single `ALU-imm 0`.
- **O67/O68/O38** — unaffected.

## 7. Future Enhancements

- **Cross-MBB extension** (defer): track patched values across a
  single-predecessor edge — likely <5% extra hits, more code.
- **`MOV X,R; ALU R` companion** (defer): when `MOV X,R` survives
  (because `R` is later used elsewhere), rewriting still saves
  bytes if `X` is dead-after; out of scope here, would need a
  separate peephole.

## 8. References

- [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
- [Future Improvements](design\future_plans\README.md)
- [O79 Design](design\future_plans\O79_mvi_alu_reg_to_alu_imm_fold.md)
- [Pipeline Feature](design\pipeline_feature.md)
- [Plan Format Reference](design\plan_cmp_based_comparison.md)
