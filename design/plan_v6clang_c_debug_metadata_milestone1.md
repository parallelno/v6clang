# Plan: C Debug Metadata Milestone 1 - ABI, Registers, and ELF Integrity

**Status:** Complete
**Depends on:** Existing DWARF v5 line-table support
**Blocks:** Milestones 2-6

## 1. Problem

### Current behavior

V6CLANG emits DWARF v5 final ELFs, but the backend has no declared DWARF register
numbers. PC is not modeled as a target register, LLVM tools report the ELF as
`elf32-unknown` for some operations, and `llvm-dwarfdump` cannot create V6CLANG
MC register information when rendering locations. Final ELFs containing
GC-discarded auto-included runtime helpers can retain overlapping zero-address
DIE ranges.

### Desired behavior

A versioned ABI/debug contract must define stack, calls, frames, register
numbers, overlap semantics, and unwind boundaries. LLVM tools must recognize
V6CLANG objects and verify representative final DWARF v5 ELFs cleanly.

### Root cause

Target ABI facts are distributed across calling convention, frame lowering,
MC, linker, and runtime code. TableGen has no `DwarfRegNum` assignments and
V6CLANG ELF/target recognition is incomplete in generic object-tool paths.

## 2. Strategy

### Approach: freeze the vocabulary before emitting locations

Document the actual ABI, model non-allocatable PC, assign stable numbers to
byte registers, pairs, SP, PC, and only those special registers intentionally
exposed. Complete generic V6CLANG ELF architecture recognition and make linker GC
produce valid final metadata for discarded helper functions.

### Why this works

Variable expressions and CFI both use the same register-number namespace.
Freezing it first prevents incompatible producer and consumer conventions.
Fixing final-link integrity first ensures all later tests inspect trustworthy
artifacts.

### Summary of changes

- Add normative debugger ABI and register-map documentation.
- Add TableGen DWARF mappings with explicit byte/pair overlap policy.
- Model PC as non-allocatable and use it as the CFI return-address column.
- Complete V6CLANG mapping in LLVM object/target utilities as required.
- Correct GC handling of debug ranges for discarded runtime helpers.
- Update v4-era documentation and tests to the current DWARF v5 `-g` default.

## 3. Implementation Steps

### Step 3.1 - Read references and capture baselines [x]

Read the master plan, original design, ABI/calling-convention files, frame
lowering, MC target description, LLD V6CLANG target, build guide, and benchmark
README. Run and archive `python tests/benchmarks_c/run_benchmarks.py`, including
checksums, cycles, and code sizes for every v6clang row. Record hashes of the
normal optimized benchmark ROMs and `.text` sections.

> **Implementation Notes**: Captured the existing 15 V6CLANG benchmark ROMs and
> benchmark report. The stored O1/O2/Os ROMs are the pre-change baseline.

### Step 3.2 - Publish the debugger-relevant ABI [x]

Create a normative document covering stack growth/alignment, return-address
width and byte order, CALL/RET semantics, argument and return registers, stack
arguments, caller/callee saves, frame-pointer policy, prologue/epilogue forms,
tail calls, static stack, dynamic allocation, interrupts, trampolines, and
unwind stop policy.

> **Implementation Notes**: Added `docs/V6ClangDebugABI.md`, contract version 1.

### Step 3.3 - Define and implement the DWARF register map [x]

Assign stable numbers in `V6ClangRegisterInfo.td`. Model PC as non-allocatable.
Document whether pair values use pair numbers, byte pieces, or both, and ensure
pairs and halves have deterministic mappings. Do not expose FLAGS unless a
real debugger use case and representation are specified.

> **Implementation Notes**: Added A=0, B=1, C=2, D=3, E=4, H=5, L=6,
> BC=7, DE=8, HL=9, SP=10, PC=11. PC is reserved and is the generated
> return-address register; FLAGS/PSW remain unnumbered.

### Step 3.4 - Complete MC and ELF tool recognition [x]

Add only the required generic LLVM object/target mappings so `llvm-readobj`,
`llvm-objdump`, and `llvm-dwarfdump` identify V6CLANG and obtain its MC register
info. Mirror every modified upstream file through both sync/populate scripts.

> **Implementation Notes**: `ELFObjectFile` maps `EM_V6Clang` to `elf32-v6clang` and
> `Triple::i8080`; llvm-readobj and llvm-dwarfdump now initialize V6CLANG MC info.

### Step 3.5 - Fix final-link debug GC integrity [x]

Ensure discarded runtime-helper code does not leave address-zero subprogram
ranges that overlap live DIEs. Preserve valid metadata for live helpers and
line-only ASM. Do not retain dead executable code as a workaround.

> **Implementation Notes**: V6CLANG debug relocations against discarded sections
> use the all-ones tombstone. Dead helper text/symbols remain discarded and
> runtime-containing final ELFs pass `llvm-dwarfdump --verify`.

### Step 3.6 - Build [x]

Run `pwsh scripts/build.ps1 -SkipTests`. Resolve all compiler and TableGen
errors before continuing.

> **Implementation Notes**: `pwsh scripts/build.ps1 -SkipTests` passed; the
> affected llvm-dwarfdump/readobj/lld targets were rebuilt explicitly.

### Step 3.7 - Add MC, CodeGen, object, and linker lit tests [x]

Test exact register numbers, byte/pair overlap policy, PC availability,
DWARF v5 CU address size 2, object relocations, final linked addresses, helper
GC, and clean `llvm-dwarfdump --verify`. Author tests only under
`llvm-project/`; never under the `tests/lit` mirror.

> **Implementation Notes**: Added register-map and runtime-helper GC tests;
> upgraded line, GC, and mixed v6asm tests to the v5 producer contract.

### Step 3.8 - Add integration and emulator fixtures [x]

When implementation begins, prepare a dedicated feature fixture following
`tests/features/result.md`: compile a three-function C program, correlate ELF
symbols/line rows with ROM execution, and capture v6emul PC/SP snapshots. Pause
for fixture review before implementation changes, as required by the pipeline.

> **Implementation Notes**: Added `tests/features/78`; final ELF verifies and
> v6emul reaches HLT at PC 0x011e/SP 0x0000 after 1,524 cycles.

### Step 3.9 - Prove optimization and performance non-regression [x]

Do not disable or remove any optimization. Verify benchmark `-g0` assembly,
`.text`, and ROM hashes are unchanged from the captured baseline. Run the
benchmark matrix and require identical checksums with no cycle or code-size
increase in any normal v6clang result. Debug builds may differ in code layout
when preserving source variables; validate them for correctness and metadata
quality rather than byte identity with `-g0`.

> **Implementation Notes**: All 15 normal O1/O2/Os benchmark ROMs are
> byte-identical to baseline; full checksums, cycles, and sizes are unchanged.
> Debug-build layout differences were measured and accepted as expected debug
> behavior. No optimization was disabled or weakened.

### Step 3.10 - Run regression tests [x]

Run `python tests/run_all.py` without benchmark exclusions. Any failure or
benchmark regression blocks completion.

> **Implementation Notes**: `tests/run_all.py` passed all four suites: 16
> golden tests, 172 lit tests, packed-BSS integration, and benchmarks.

### Step 3.11 - Create the verification result [x]

Create the milestone fixture's `result.txt` with C source, relevant assembly,
ELF/DWARF dumps, register table, ROM/ELF address correlation, emulator state,
and baseline/new cycle and code-size tables. Assembly is expected to be
identical; unexplained differences are failures.

> **Implementation Notes**: `tests/features/78/result.txt` contains the ABI,
> ELF/DWARF, assembly identity, emulator, and benchmark evidence.

### Step 3.12 - Update documentation, sync, and mark complete [x]

Update build/debug documentation to DWARF v5, publish known limitations, run
`pwsh scripts/sync_llvm_mirror.ps1`, verify mirror hashes, then mark every step
and the master milestone complete.

> **Implementation Notes**: Documentation and mirror scripts are updated and
> representative hashes match. Milestone 1 is complete.

## 4. Expected Results

- V6CLANG has one stable, documented register namespace for locations and CFI.
- Minimal and runtime-containing final ELFs pass DWARF verification.
- Existing optimized ROMs, code size, and cycle counts do not change.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Pair and byte mappings become ambiguous | Freeze explicit overlap rules and test both representations. |
| PC modeling affects allocation | Keep PC non-allocatable and reserved from all register classes. |
| Generic LLVM edits are missed by mirrors | Update both sync and populate scripts and compare hashes. |
| GC fix retains unwanted code | Assert discarded `.text` and symbols remain absent while metadata verifies. |

## 6. Relationship to Other Improvements

This milestone extends source debug metadata and supplies the register/ELF
contract required by CFI and variable locations. It must not alter any O-series
optimization or its cost model.

## 7. Future Enhancements

Register aliases may be extended only through a versioned ABI revision. Actual
CFI and variable expressions belong to later milestones.

## 8. References

- [Master Plan](plan_v6clang_c_debug_metadata.md)
- [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
- [Future Improvements](future_plans/README.md)
- [Feature Result Format](../tests/features/result.md)
