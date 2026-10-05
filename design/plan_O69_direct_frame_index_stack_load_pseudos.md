# O69 Implementation Plan: Direct Frame-Index Memory Pseudos

## 1. Problem

### Current behavior
Stack-relative loads/stores selected through a frame index currently lower as `V6CLANG_LEA_FI` followed by `V6CLANG_LOAD*_P` or `V6CLANG_STORE*_P`. This creates a temporary address register before register allocation and can emit redundant address copies such as `HL -> BC -> HL`.

### Desired behavior
Select direct frame-index memory pseudos before register allocation:

- `V6CLANG_LOAD8_FI`
- `V6CLANG_LOAD16_FI`
- `V6CLANG_STORE8_FI`
- `V6CLANG_STORE16_FI`

These pseudos compute the stack-relative address internally with `LXI H, Offset; DAD SP` and perform the memory operation directly.

### Root cause
The existing selection pipeline treats the frame-index address as an ordinary `GR16` value. RA must allocate that address even when its only use is the immediately-following memory operation.

## 2. Strategy

### Approach
Add direct FI pseudos to `V6ClangInstrInfo.td`, select them in `V6ClangISelDAGToDAG.cpp` for `ISD::LOAD/STORE` whose base pointer is `ISD::FrameIndex`, and expand them in `V6ClangRegisterInfo::eliminateFrameIndex`.

### Why this works
The address temporary disappears before RA. The pseudos model `HL` and `FLAGS` clobbers honestly, allowing RA to copy values when needed instead of forcing spill/reload-style internal preservation.

### Summary of changes
- Add `GR8NoHL` register class for store sources that must not be in `H/L`.
- Add four direct FI pseudos.
- Add DAG selector cases for frame-index loads/stores.
- Add PEI expansion for the new pseudos.
- Add lit and feature tests covering i8/i16 loads and stores.

## 3. Implementation Steps

### Step 3.1 — Add register class and pseudos [x]
Add `GR8NoHL` and the four `V6CLANG_*_FI` pseudos.

> **Implementation Notes**:
> Added `GR8NoHL` plus `V6CLANG_LOAD8_FI`, `V6CLANG_LOAD16_FI`, `V6CLANG_STORE8_FI`, and `V6CLANG_STORE16_FI` in the V6CLANG TableGen files. The direct FI pseudos model `HL` and `FLAGS` clobbers.

### Step 3.2 — Select FI loads/stores [x]
Teach `V6ClangISelDAGToDAG.cpp` to select direct FI pseudos for non-extending i8/i16 loads and i8/i16 stores whose base is a frame index.

> **Implementation Notes**:
> Added `ISD::LOAD` and `ISD::STORE` manual selection for frame-index bases, preserving chains and memory operands.

### Step 3.3 — Expand FI pseudos [x]
Expand direct FI pseudos in `V6ClangRegisterInfo::eliminateFrameIndex` using the existing offset model.

> **Implementation Notes**:
> Added PEI expansion for all four pseudos. Also changed the `V6CLANG_LEA_FI dst=DE` expansion from `XCHG` to `MOV D,H; MOV E,L` so the expansion does not read an undefined old `DE` value.

### Step 3.4 — Build [x]
Run `ninja -C llvm-build clang llc` through the MSVC developer environment.

> **Implementation Notes**:
> Passed: `ninja -C llvm-build clang llc`, then passed again after the `V6CLANG_LEA_FI` verifier cleanup.

### Step 3.5 — Lit tests [x]
Add and run CodeGen lit coverage for `V6CLANG_LOAD8_FI`, `V6CLANG_LOAD16_FI`, `V6CLANG_STORE8_FI`, and `V6CLANG_STORE16_FI`.

> **Implementation Notes**:
> Added `llvm-project/llvm/test/CodeGen/V6CLANG/frame-index-direct-fi.ll`. Targeted run passed: 1/1.

### Step 3.6 — Feature verification [x]
Create/compile the O69 feature test and compare old/new assembly per `tests\features\README.md`.

> **Implementation Notes**:
> Added `tests/features/48` with c8080 and v6clang sources plus assembly artifacts. `v6clang_new01.asm` contains all four direct FI pseudo shapes.

### Step 3.7 — Regression tests [x]
Run `python tests\run_all.py`.

> **Implementation Notes**:
> Golden tests passed 16/16. Lit passed 121/122; the remaining failure is the unrelated existing `lsr-strategy-size.ll` `.comm __v6clang_ss.axpy3` expectation (`10` expected, `12` emitted).

### Step 3.8 — Sync mirror [x]
Run `powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1`.

> **Implementation Notes**:
> Completed mirror sync after backend and lit changes.

### Step 3.9 — Completion docs [x]
Mark O69 complete in future plans and update plan notes/results.

> **Implementation Notes**:
> Marked O69 implemented in the future plan and future plan index.

## 4. Expected Results

- Stack-arg i16 load drops the `HL -> BC -> HL` round trip.
- Stack-arg i8 load can use `LXI H, Offset; DAD SP; MOV A,M` rather than `XCHG; LDAX D`.
- Direct stack stores no longer require the store itself to carry a separate frame-address temporary.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Incorrect frame offset | Reuse `eliminateFrameIndex` offset formula. |
| `HL` clobber mis-modeled | Declare `Defs=[HL, FLAGS]` on every direct FI pseudo. |
| Store source allocated in `H/L` | Use `GR8NoHL` for i8 stores and `GR16Idx` for i16 stores. |
| Missed memory chain | Preserve load/store chains and memory operands in manual selection. |

## 6. Relationship to Other Improvements

Complements O54/O54c stack-argument work and O49 direct memory operations by making stack-relative memory operations first-class before RA.

## 8. References

- `design\future_plans\O69_lea_fi_pointer_use_folding.md`
- `design\pipeline_feature.md`
- `tests\features\README.md`
- `docs\V6ClangBuildGuide.md`
