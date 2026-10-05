# Plan: O86 Constant-Amount i16 Shift Specialization

## 1. Problem

### Current behavior

`V6CLANG_SHL16` / `V6CLANG_SRL16` / `V6CLANG_SRA16` constant shifts still use broad,
accumulator-heavy expansion strategies in
`llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp` and
`llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`.

Current gaps from the design:

- `SHL16 1..7` is lowered as repeated `add i16, i16`, which expands to the
  generic `A`-clobbering 16-bit add chain instead of `DAD H`.
- The plan does not yet encode the strategy split from O86's implementation
  note, so the backend is still organized around three broad shift pseudos
  instead of truthful per-strategy variants.
- `SHL16 9..13` still pays the byte-lane move plus repeated `ADD A,A` on the
  high byte instead of the cheaper `MOV A,Lo; ADD A x N; MOV Hi,A` path.
- `SHL16 14..15` does not use the `RRC + ANI` specialization.
- `SRL16 3..7` does not use the 24-bit `DAD H ; ADC A` trick.
- `SRL16 9..15` and `SRA16 9..15` still always materialize the dead zero/sign
  half even when it is unused.
- The current shift pseudos over-claim `A` clobbers for all paths, even those
  that can avoid the accumulator.

### Desired behavior

Constant i16 shifts should specialize by amount and by register-pair shape:

- `SHL16 1..7`:
  - `HL`: `DAD H` repeated
  - `DE`: `XCHG ; DAD H x N ; XCHG`
- `SHL16 9..13`:
  - `MOV A,Lo ; ADD A x (N-8) ; MOV Hi,A ; [MVI Lo,0]`
- `SHL16 14..15`:
  - `MOV A,Lo ; RRC x (8 - (N % 8)) ; ANI mask ; MOV Hi,A ; [MVI Lo,0]`
- `SRL16 1..2`:
  - keep the current per-bit `ORA A ; RAR` loop because the 24-bit trick loses
- `SRL16 3..7`:
  - `XRA A ; (DAD H ; ADC A) x (8-N) ; MOV L,H ; MOV H,A`
- `SRL16/SRA16 9..15`:
  - rotate-and-mask on the surviving byte, with trailing `MVI Hi,0` omitted if
    the high half is provably dead

### Root cause

The lowering path and the post-RA expander are still organized around one
generic pseudo per direction. `LowerSHL_i16` rewrites small left shifts to
generic ADD DAGs, which bypasses a dedicated shift pseudo entirely, and the
current expander uses one conservative accumulator-based template for each
direction. That structure prevents the DAD-based strategies from advertising
their true clobber set to register allocation.

## 2. Strategy

### Approach: amount-specialized lowering plus post-RA expansion

Introduce a dedicated `V6ClangISD::SHL16` node so constant left shifts reach a
shift pseudo instead of generic ADD expansion. Split the broad shift pseudos
into strategy-specific variants first, then specialize the post-RA expander by
shift amount:

- `SHL16 1..7` first, because it is the highest-confidence slice and the DAD
  form is the main case where the allocator should stop seeing a fake `A`
  clobber.
- Then `SHL16 9..15`, split between ADD-A and RRC+ANI strategies.
- Then `SRL16` amount ranges: keep 1..2, add 24-bit trick for 3..7, and add
  rotate-and-mask for 9..15.
- Then `SRA16` amount ranges using the same structure with sign propagation.
- Finally add dead-half omission where the discarded byte is provably unused.

### Why this works

- Constant amount is known during lowering, so strategy choice is a simple
  table lookup.
- Post-RA expansion already owns the physical pair choice, which is the right
  place to decide between `HL` and `DE`/`XCHG` forms.
- The change is testable in small slices: each amount family has a distinct,
  easy-to-spot assembly signature.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| 1 | Add `V6ClangISD::SHL16` target node and node-name plumbing | `V6ClangISelLowering.h/.cpp` |
| 2 | Lower constant `SHL16` through the dedicated target node | `V6ClangISelLowering.cpp` |
| 3 | Split broad shift pseudos into strategy-specific variants with truthful `Defs` | `V6ClangInstrInfo.td` |
| 4 | Specialize `SHL16 1..7` expansion via the DAD strategy variants | `V6ClangISelLowering.cpp`, `V6ClangInstrInfo.cpp` |
| 5 | Add lit coverage for `SHL16 1..7` | `llvm-project/llvm/test/CodeGen/V6Clang/` |
| 6 | Specialize `SHL16 9..15` via ADD-A / RRC+ANI variants | `V6ClangISelLowering.cpp`, `V6ClangInstrInfo.cpp` |
| 7 | Specialize `SRL16 3..7` and `9..15` via dedicated variants | `V6ClangISelLowering.cpp`, `V6ClangInstrInfo.cpp` |
| 8 | Specialize `SRA16 3..7` and `9..15` via dedicated variants | `V6ClangISelLowering.cpp`, `V6ClangInstrInfo.cpp` |
| 9 | Add dead-half omission when truncated user makes zero-fill dead | lowering and/or post-RA peephole |
| 10 | Verify feature test assembly and create `result.txt` | `tests/features/68/` |

## 3. Implementation Steps

### Step 3.1 — Read reference docs and inspect current shift lowering [x]

Read:

- `design/future_plans/O86_constant_shift_specialization.md`
- `design/future_plans/README.md`
- `docs/V6ClangBuildGuide.md`
- `tests/features/result.md`

> **Implementation Notes**: Reviewed the O86 design note, backlog entry,
> build guide, and feature-result format before implementation. Revisited the
> pipeline document later to audit missed process steps and bring the plan back
> into sync with the actual work.

### Step 3.2 — Add `V6ClangISD::SHL16` and route constant left shifts through it [x]

Files:

- `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.h`
- `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp`

Replace the current `LowerSHL_i16` ADD-chain lowering with a dedicated target
node for constant amounts `1..15`.

> **Design Notes**: This is the root fix for the current `SHL16 1..7`
> pessimization. Without it, the post-RA `V6CLANG_SHL16` specialization never sees
> the small constant shifts.
>
> **Implementation Notes**: Completed in a slightly stronger final form than
> the original step text. Instead of landing a single broad `V6ClangISD::SHL16`
> node, constant left shifts now route through strategy-specific SHL nodes so
> the old ADD-chain bypass is gone entirely.

### Step 3.2b — Split broad shift pseudos into strategy-specific variants [x]

Files:

- `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`
- `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp`

Replace the single `V6CLANG_SHL16` / `V6CLANG_SRL16` / `V6CLANG_SRA16` pseudo family with
strategy-specific variants so the allocator sees the real clobbers for each
path.

Implement at least these families explicitly:

- `SHL16_DAD` with no `A` clobber
- `SHL16_RAM_HI`
- `SRL16_RAR`, `SRL16_24BIT`, `SRL16_RAM_LO`
- `SRA16_RAR`, `SRA16_24BIT`, `SRA16_RAM_LO`

> **Design Notes**: This is the missing requirement from the O86
> implementation note. The DAD-based left-shift pseudo must stop over-claiming
> `A`, and the amount-specific strategies must stop sharing one conservative
> pseudo definition.
>
> **Implementation Notes**: Landed strategy-specific SHL/SRL/SRA SDNodes and
> pseudos in `V6ClangISelLowering.h/.cpp` and `V6ClangInstrInfo.td`. The DAD-based
> SHL family now has `Defs = [FLAGS]` rather than over-claiming `A`.

### Step 3.3 — Specialize `V6CLANG_SHL16` for amounts `1..7` [x]

File:

- `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp`
- `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Implement:

- lowering of `SHL16 1..7` to the DAD strategy pseudo
- `HL`: `DAD H x N`
- non-`HL` fallback path that remains correct when RA does not place the value
  in `HL`

> **Design Notes**: Keep the fallback path correct first; strict HL-only would
> recreate register-pressure problems noted in O86.
>
> **Implementation Notes**: Implemented via `V6CLANG_SHL16_DAD`. `HL` uses repeated
> `DAD H`, `DE` uses the `XCHG`-wrapped fast path, and non-`HL` destinations use
> the same HL-temporary preservation model as the existing `V6CLANG_DAD` expander.

### Step 3.4 — Build [x]

Run:

```powershell
cmd /c "call \"\"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat\"\" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Validated the refactor with focused backend builds.
> `ninja -C llvm-build llc` passed after the shift-family split; `clang` was
> rebuilt later before regenerating feature assembly.

### Step 3.5 — Lit test: `SHL16 1..7` specialization [x]

Add focused CodeGen coverage that checks `<<1`, `<<3`, and `<<7` for:

- `DAD H` in the `HL` shape
- no `MOV A,` / `ADC` chain in the optimized cases

> **Implementation Notes**: Updated the existing focused shift lit coverage in
> `shift-i16.ll` / `shift-i16-byte-aligned.ll` and revalidated the `DAD H`
> shape for the optimized HL path.

### Step 3.6 — Specialize `SHL16 9..15` [x]

File:

- `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Implement:

- `9..13`: `MOV A,Lo ; ADD A x (N-8) ; MOV Hi,A ; [MVI Lo,0]`
- `14..15`: `MOV A,Lo ; RRC x ... ; ANI mask ; MOV Hi,A ; [MVI Lo,0]`

> **Implementation Notes**: `V6CLANG_SHL16_RAM_HI` now uses the intended direct
> `MOV A, SrcLo` path for `9..13` and the `RRC + ANI` form for `14..15`.
> A stale regression back to the old DstHi loop was caught and fixed during
> focused lit validation.

### Step 3.7 — Build [x]

> **Implementation Notes**: Rebuilt `llc` after the `SHL16 9..15` repair; the
> backend linked cleanly.

### Step 3.8 — Lit test: `SHL16 9..15` specialization [x]

Check `<<9`, `<<13`, `<<14`, `<<15` for the expected sequence families.

> **Implementation Notes**: `shift-i16.ll` / `shift-i16-byte-aligned.ll`
> verify `<<9`, `<<13`, `<<14`, and `<<15`; both files passed after the final
> SHL RAM-HI fix.

### Step 3.9 — Specialize `SRL16` constant ranges [ ]

File:

- `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Implement:

- keep `1..2`
- `3..7`: 24-bit trick
- `9..15`: rotate-and-mask with optional dead `MVI Hi,0` omission

> **Implementation Notes**: The core specialization landed as
> `V6CLANG_SRL16_RAR`, `V6CLANG_SRL16_24BIT`, `V6CLANG_SRL16_BYTE`, and
> `V6CLANG_SRL16_RAM_LO`, and the emitted assembly is validated. This step remains
> open because the optional dead `MVI H,0` omission described in the plan has
> not been implemented yet.

### Step 3.10 — Build [x]

> **Implementation Notes**: Included in the same focused backend rebuild cycle
> used to validate the SRL strategy split.

### Step 3.11 — Lit test: `SRL16` specialization [x]

Check `>>1`, `>>2`, `>>7`, `>>9`, `>>15`.

> **Implementation Notes**: The focused V6CLANG shift lit tests passed with the new
> `>>7`, `>>9`, and `>>15` sequences, and feature 68 confirms the expected
> `shr_u16_7/9/15` codegen in `v6clang_new02.asm`.

### Step 3.12 — Specialize `SRA16` constant ranges [x]

File:

- `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Implement arithmetic versions of the `3..7` and `9..15` strategies.

> **Implementation Notes**: Landed `V6CLANG_SRA16_RAR`, `V6CLANG_SRA16_24BIT`,
> `V6CLANG_SRA16_BYTE`, and `V6CLANG_SRA16_RAM_LO`. `sar >> 9` intentionally keeps the
> cheaper byte-lane-plus-one-step form rather than the longer rotate/mask path.

### Step 3.13 — Build [x]

> **Implementation Notes**: Rebuilt the backend again after the final SRA/local
> fixups; `llc` linked cleanly and `clang` was refreshed before feature output.

### Step 3.14 — Lit test: `SRA16` specialization [x]

Check `sar 7`, `sar 9`, `sar 15`.

> **Implementation Notes**: The focused shift lit tests passed with the final
> `sar 7`, `sar 9`, and `sar 15` expectations.

### Step 3.15 — Prepare/maintain feature test folder `tests/features/68` [x]

Files:

- `tests/features/68/v6clang.c`
- `tests/features/68/c8080.c`
- `tests/features/68/c8080.asm`
- `tests/features/68/v6clang_old.asm`

The test case must call every specialized shift family from `main()` so the
assembly is directly comparable.

> **Implementation Notes**: Feature folder 68 was prepared with `v6clang.c`,
> `c8080.c`, `c8080.asm`, and `v6clang_old.asm`. The test case exercises every
> specialized shift family from `main()`.

### Step 3.16 — Verification assembly steps from `tests/features/result.md` [x]

Compile:

- `tests/features/68/v6clang_new01.asm`

Explain the improvement against `v6clang_old.asm` and iterate if needed.

> **Implementation Notes**: Generated and inspected `v6clang_new01.asm`, then
> regenerated `v6clang_new02.asm` after the pseudo-family refactor and the
> restored cheaper `sar_i16_9` path. `v6clang_new02.asm` is the current source
> of truth for feature verification.

### Step 3.17 — Run regression tests [x]

Run:

```powershell
python tests/run_all.py
```

> **Implementation Notes**: `python tests/run_all.py` passed: 16/16 golden,
> 145/145 lit, and benchmark correctness 3/3 suites.

### Step 3.18 — Make sure `result.txt` is created [x]

Create `tests/features/68/result.txt` with the required structure from
`tests/features/result.md`.

> **Implementation Notes**: Created `tests/features/68/result.txt` with the C
> testcase, converted c8080 asm excerpts, old/new V6CLANG asm excerpts, c8080 stats,
> and the three-way size/cycle comparison table.

### Step 3.19 — Sync mirror [x]

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/sync_llvm_mirror.ps1
```

> **Implementation Notes**: Synced the tracked mirror with
> `scripts/sync_llvm_mirror.ps1` after backend validation.

## 4. Expected Results

### Example 1 — `x << 3`

Expected to shrink from the current accumulator-heavy 16-bit add chain to
`DAD H` repeated three times, saving roughly 84cc in the HL case.

### Example 2 — `x << 15`

Expected to shrink from the current byte-lane + 7-step high-byte shift path to
`MOV A,L ; RRC ; ANI 0x80 ; MOV H,A ; [MVI L,0]`, saving about 120cc.

### Example 3 — `x >> 7`

Expected to shrink from the 7-iteration `RAR` chain to the 24-bit trick,
saving about 272cc.

### Example 4 — `x >> 9`

Expected to collapse to the surviving-byte rotate-and-mask form, with the
trailing `MVI H,0` omitted when only the low byte is consumed.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `SHL16` lowering change perturbs existing `ADD16` combines | Land in a small slice first and add focused lit coverage for `<<1`, `<<3`, `<<7` before widening |
| HL-only fast path causes register pressure regressions | Keep DE/XCHG path and preserve a fallback for non-HL destinations |
| Dead-half omission drops required zero/sign semantics | Restrict omission to proven truncation/extract users, or use a dead-def peephole only after validation |
| SRA sign propagation is subtle for `9..15` | Add separate lit coverage for signed right shifts and keep SRL/SRA implementation steps split |
| c8080 baseline source rejects some C constructs | Keep the feature C sources simple, C89-style, and adjust prototypes as needed |

---

## 6. Relationship to Other Improvements

- Builds directly on `O62_efficient_shift_expansion.md`.
- Complements `O68_wide_shl_rotate_dad_h.md` by extending `DAD H` use from
  rotate-left-by-1 and add-address cases to constant shift-left.
- Partially supersedes `O57_shift_rotate_chaining.md` for the constant-amount
  case.

## 7. Future Enhancements

- Split the broad shift pseudos into truthful clobber-specific variants if the
  one-pseudo approach still costs register-allocation quality.
- Add a dedicated post-RA pass for dead-half cleanup if selection-time omission
  proves too narrow.
- Consider analogous specialization for variable shifts when the runtime helper
  sees a compile-time-bounded amount.

## 8. References

* `docs/V6ClangBuildGuide.md`
* `docs/V6ClangInstructionTimings.md`
* `design/future_plans/README.md`
* `design/future_plans/O62_efficient_shift_expansion.md`
* `design/future_plans/O68_wide_shl_rotate_dad_h.md`
* `design/future_plans/O86_constant_shift_specialization.md`
* `tests/features/result.md`