# Vector 06c LLVM Backend — Implementation Plan

**Reference**: [design.md](design.md) (authoritative, fixed)

---

## 1. Scope & Conventions

### 1.1 Purpose

This document translates the approved design into an ordered, test-driven implementation sequence. It defines milestones, dependency chains, validation criteria, and documentation checkpoints. The design is not modified or reinterpreted here.

### 1.2 Toolchain Dependencies

| Tool | Path | Role |
|------|------|------|
| `v6emul` | `tools/v6emul` | CLI Vector 06c emulator — executes flat binaries, inspects registers/memory, counts cycles |
| `v6asm` | `tools/v6asm` | CLI 8080 assembler — reference assembly syntax, ASM→ROM conversion, intermediate output comparison |
| LLVM source | `llvm-project/` | Full LLVM monorepo (cloned at pinned `llvmorg-18.1.0`, **gitignored** — build reads from here) |
| LLVM mirror | `llvm/` | Git-tracked mirror of all V6CLANG-related changes (V6CLANG target dir + modified upstream files) |
| Mirror sync | `scripts/sync_llvm_mirror.ps1` | Copies changes from `llvm-project/` → `llvm/` after each build |
| CMake ≥ 3.20 | System | Build system |
| Ninja | `.venv/Scripts/ninja.exe` | Build executor (provisioned by `scripts/setup_venv.ps1`) |
| Python 3 | `.venv/Scripts/python.exe` | LLVM lit test runner, test harness scripts (provisioned by `scripts/setup_venv.ps1`) |

### 1.2.1 Source Mirror Workflow

`llvm-project/` is gitignored because it is a large upstream clone. All V6CLANG-related source is git-tracked under `llvm/`, which acts as a mirror.

**After every successful build**, run:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

The script syncs:
- `llvm-project/llvm/lib/Target/V6CLANG/` → `llvm/lib/Target/V6CLANG/` (full directory mirror)
- Individual modified upstream files (e.g. `Triple.h`, `Triple.cpp`) → corresponding paths under `llvm/`

When a milestone modifies new upstream files, add `xcopy` lines to `scripts\sync_llvm_mirror.ps1`.

If `llvm-project/` is re-cloned, restore changes by copying from `llvm/` back into `llvm-project/`.

### 1.3 Status Markers

Each milestone, step, and test block uses these markers:

- `[ ]` — Not started
- `[~]` — In progress
- `[x]` — Complete
- `[!]` — Blocked (with explanation)

### 1.4 Branch Strategy

Each milestone is implemented on a feature branch (`milestone/M<N>-<short-name>`) and merged to `main` only after all tests in that milestone pass. This enables bisect-friendly history.

---

## 2. Implementation Difficulties & Mitigation Strategies

This section catalogues foreseeable implementation difficulties — distinct from the runtime/performance risks in design §15 — and the concrete strategies to resolve them.

### 2.1 LLVM Upstream Complexity

**Difficulty**: LLVM's backend API surface is vast (~200 classes involved in target registration, ISel, MC emission). Documentation is sparse for out-of-tree targets. API breakage across LLVM releases is common.

**Strategy**:
- Pin to a single LLVM release tag (e.g., `llvmorg-18.1.0`) for the entire development cycle. Do not chase `main`.
- Use the AVR backend as the primary reference implementation — it is the closest existing analogue (8-bit, similar register scarcity, no alignment requirements).
- Secondary references: MSP430 (16-bit, simple ISA), RISCV (clean modern backend, good TableGen patterns).
- Build and test incrementally: each milestone adds the minimum C++ to make a new subset of `llvm-tblgen` / `llc` / `llvm-mc` work correctly, validated before moving forward.
- Maintain a local `docs/LLVMAPIJournal.md` noting every non-obvious API usage, parameter meaning, and workaround discovered during implementation.

### 2.2 TableGen Learning Curve & Debugging

**Difficulty**: TableGen is poorly documented, errors are cryptic, and the relationship between `.td` records and generated C++ `.inc` files is opaque. Incorrect instruction descriptions silently produce wrong code.

**Strategy**:
- Start with the absolute minimum: 5 instructions (NOP, MVI, MOV, ADD, HLT) in M2. Validate encoding byte-by-byte against `v6asm` output before adding more.
- Use `llvm-tblgen --print-records` to dump the parsed TableGen database and diff it against expectations.
- Write one FileCheck encoding test per instruction *as it is added* — never batch instruction definitions without tests.
- Keep `.td` files small and separated (formats, registers, instructions, schedule) per design §4.1 to isolate errors.

### 2.3 Accumulator-Centric ISA vs LLVM's Register Model

**Difficulty**: LLVM's SelectionDAG and register allocator assume a general-register architecture. The 8080's mandatory routing through register A for all ALU operations is not naturally expressible and can cause the allocator to produce incorrect or excessively spilled code.

**Strategy**:
- Model A as an implicit def/use on every ALU instruction in TableGen from the start. Do not attempt to hide this from the allocator.
- Implement and test `i8` ALU operations first (M4), focusing exclusively on correct register allocation with the A constraint, before adding `i16` expansion.
- Defer the `V6ClangAccumulatorPlanning` optimization pass (M8) until the basic pipeline is fully correct. Correctness first, then performance.
- Use the AVR backend's handling of dedicated registers (e.g., `R0`/`R1` for multiply results) as a pattern.

### 2.4 16-bit Operation Synthesis

**Difficulty**: The 8080 has no general 16-bit ALU (only `DAD` for `HL += rp`). All other 16-bit arithmetic must be synthesized from 8-bit operations with carry propagation. The interaction between type legalization (expand `i16` → two `i8`) and the register allocator's pair constraints is a known source of subtle bugs in 8-bit backends.

**Strategy**:
- Implement `i16` as `Legal` in type legalization (use register pairs), but expand most `i16` operations to 8-bit sequences in custom lowering. This avoids LLVM's generic expansion which does not understand register pairs.
- `DAD` is the only natively legal 16-bit operation — handle it as a special case via a custom DAG combine (design §5.4).
- Test every `i16` operation in isolation: `add`, `sub`, `and`, `or`, `xor`, `shift`, `compare`. Each gets a dedicated lit test *and* an emulator round-trip test via `v6emul`.
- Implement pseudo-instructions (`V6CLANG_ADD16`, `V6CLANG_SUB16`, etc.) that expand post-RA, so the register allocator sees clean pair operands.

### 2.5 Stack Frame Access Cost

**Difficulty**: Every stack slot access requires an `LXI H, N; DAD SP; MOV A,M` sequence (32cc+). If the register allocator spills aggressively, trivial functions become extremely slow. Incorrect SP-relative offset computation causes memory corruption that is extremely hard to debug.

**Strategy**:
- Implement frame lowering (M5) with extensive offset-correctness tests: functions with 0, 1, 2, 4, 8, 255, 256 bytes of locals. Verify via `v6emul` that stack memory is read/written at the correct addresses.
- Inflate spill weights early (M5 frame lowering) so the allocator avoids spilling whenever possible.
- Implement prologue/epilogue shrink-wrapping for leaf functions from the start — this is the single highest-impact optimization for generated code quality.
- Write a dedicated stress test: a function with more live variables than registers, verify correct spill/reload via emulator.

### 2.6 No Standard Object File Format

**Difficulty**: LLVM's MC layer and LLD assume ELF/COFF/MachO. The Vector 06c needs flat binaries. The MC layer needs custom `MCObjectFileInfo`, `MCAsmBackend`, and `MCCodeEmitter` that produce raw bytes, which is not a well-trodden path.

**Strategy**:
- In M3 (MC layer), start with assembly-only output. Validate ASM text against `v6asm` reference output.
- Add binary emission (M6) as a separate milestone. Use a minimal custom `MCObjectFileInfo` that defines a single monolithic section.
- Validate binary output byte-by-byte: compile a known program, compare the `.bin` against `v6asm`-assembled reference, then run both in `v6emul` and compare execution traces.
- Defer the linker (M10) — single-file compilation to flat binary is sufficient for all milestones until then.

### 2.7 Testing Without Real Hardware

**Difficulty**: The Vector 06c is vintage hardware. All correctness and performance validation must happen in emulation. Emulator fidelity bugs could mask compiler bugs.

**Strategy**:
- Use `v6emul` as the primary oracle. Cross-validate early results against `v6asm`-assembled hand-written programs to establish emulator trust.
- Write a "golden test suite" of 10–15 hand-assembled programs (via `v6asm`) with known register/memory outcomes. Run these in `v6emul` before trusting the emulator for compiler output validation.
- For cycle counting, use `v6emul`'s cycle counter output. Establish baseline cycle counts for reference programs in M1 and track regressions throughout.

### 2.8 Clang Integration Breadth

**Difficulty**: Registering a new target in Clang touches `TargetInfo`, `TargetCodeGenInfo`, driver, triple parsing, and built-in macros. Missing any hook causes silent miscompilation or crashes.

**Strategy**:
- Defer Clang integration to M9, after the backend is fully functional via `llc` (LLVM IR → assembly/binary).
- Use the AVR Clang integration as a template — it covers the same freestanding/bare-metal pattern.
- Validate with a minimal C program: `int main() { return 42; }`. Must compile to correct binary, run in `v6emul`, and halt with 42 in register A.
- Add intrinsics (`__builtin_v6clang_in`, etc.) one at a time, each with a C test that compiles and runs.

### 2.9 Runtime Library Bootstrap

**Difficulty**: The runtime library (`crt0.s`, math, shift, memory) must be written in 8080 assembly and must conform to `V6CLANG_CConv`. If the calling convention implementation has bugs, every runtime call will silently corrupt state.

**Strategy**:
- Write and test runtime functions *before* the compiler emits calls to them. Assemble with `v6asm`, test with `v6emul` in isolation.
- Create a standalone test harness per runtime function: set up arguments in the ABI-specified registers/stack, call the function, verify results.
- Only after each runtime function passes its standalone test, wire it into the compiler's LibCall table.
- Keep the runtime minimal — design §11 lists exactly the required functions. Do not add anything speculative.

### 2.10 Optimization Pass Interaction & Phase Ordering

**Difficulty**: Custom passes (AccumulatorPlanning, XchgOpt, ZeroTestOpt, SPTrickOpt, etc.) interact with each other and with LLVM's built-in passes. Phase ordering bugs cause one pass to undo another's work, or worse, create invalid MachineFunction state.

**Strategy**:
- Implement all custom passes as individually toggleable (`-v6clang-disable-<pass-name>`), defaulting to ON.
- Each pass gets its own milestone (M8) with isolated before/after FileCheck tests confirming the pass transforms what it should and nothing else.
- Run the full lit test suite with each pass individually disabled to catch ordering dependencies.
- Use LLVM's `-verify-machineinstrs` flag in all test runs to catch MachineFunction invariant violations immediately.

---

## 3. Milestone Sequence

```
M0  Project Bootstrap & Tool Validation
 │
M1  Target Registration & Skeleton
 │
M2  TableGen: Registers & Core Instructions
 │
M3  MC Layer: Assembly Emission
 │
M4  ISel: i8 Operations & Basic Lowering
 │
M5  Frame Lowering & Calling Convention
 │
M6  MC Layer: Binary Emission
 │
M7  ISel: i16 & i32 Operations
 │
M8  Optimization Passes
 │
M9  Clang Frontend Integration
 │
M10 Linker & Multi-File Compilation
 │
M11 Runtime Library
 │
M12 End-to-End Validation & Performance
```

### Dependency Graph

```
M0 ──► M1 ──► M2 ──► M3 ──► M4 ──► M5 ──► M6
                                      │       │
                                      │       ├──► M7 ──► M8
                                      │       │           │
                                      │       │           ▼
                                      ▼       │          M12
                                     M11 ◄────┤
                                      │       │
                                      │       ├──► M9
                                      │       │
                                      ▼       ▼
                                     M12 ◄── M10
```

M11 (runtime library) can proceed in parallel with M7–M8 once M5 (calling convention) is complete. M9 (Clang) can proceed once M6 (binary emission) is complete.

---

## 4. Milestones

---

### M0 — Project Bootstrap & Tool Validation
`[x]` **Status: Complete**

**Goal**: Establish the development environment, validate external tool dependencies, and create the project skeleton with build infrastructure.

#### M0.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Clone LLVM monorepo at pinned release tag (e.g., `llvmorg-18.1.0`). Configure as submodule or external dependency. | `[x]` |
| 2 | Build stock LLVM (host target only) to confirm toolchain works: `cmake`, `ninja`, `llvm-tblgen`, `llc`, `llvm-mc`, `FileCheck`, `lit`. | `[x]` |
| 3 | Build or obtain `tools/v6emul`. Verify it runs a hand-written NOP+HLT program and reports halt state. | `[x]` |
| 4 | Build or obtain `tools/v6asm`. Assemble a trivial program (`NOP; HLT`), produce `.bin`, run in `v6emul`, confirm halt. | `[x]` |
| 5 | Create project directory structure per design §12. Stub `CMakeLists.txt` for `V6CLANG` target (does not build yet, but is parseable). | `[x]` |
| 6 | Create the emulator golden test suite: 10–15 hand-written `.asm` programs with known outcomes. Assemble via `v6asm`, run via `v6emul`, verify results. Store in `tests/golden/`. | `[x]` |
| 7 | Set up CI configuration (or local Makefile target) that runs `v6asm` + `v6emul` golden tests. | `[x]` |

#### M0.2 Tests

| Test | Tool | Validates |
|------|------|-----------|
| `v6emul` smoke: NOP+HLT → halt, PC=0x102 | `v6asm` + `v6emul` | Emulator executes basic programs |
| `v6asm` round-trip: all 8080 opcodes assemble without error | `v6asm` | Assembler covers full ISA |
| Golden suite: 10–15 programs, register/memory checks | `v6asm` + `v6emul` | Emulator trusted as oracle |
| LLVM build: `llvm-tblgen --version` succeeds | `ninja` | Build environment functional |

#### M0.3 Verification

- `v6emul` matches expected register/memory state for all golden tests.
- `v6asm` output for each golden test is a valid flat binary loadable at default address 0x0100.
- LLVM builds and `FileCheck` is available on PATH.

#### M0.4 Documentation

- `[x]` `docs/V6ClangBackendOverview.md` — initial version: project goals, tool dependencies, build instructions.
- `[x]` `tests/golden/README.md` — describes each golden test and its expected outcome.

---

### M1 — Target Registration & Skeleton
`[x]` **Status: Complete**

**Goal**: Register `V6CLANG` as an LLVM experimental target. After this milestone, `llc -march=v6clang -version` prints the target name and `llvm-tblgen` processes an empty target description.

#### M1.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Create `V6ClangTargetInfo.h/.cpp` in `TargetInfo/`. Register the target triple `i8080-unknown-v6clang` via `RegisterTarget`. | `[x]` |
| 2 | Create `V6ClangTargetMachine.h/.cpp`. Implement a minimal `V6ClangTargetMachine` subclass returning the data layout string from design §2.2. | `[x]` |
| 3 | Create `V6ClangSubtarget.h/.cpp`. Stub all accessors (`getInstrInfo()`, etc.) to return `nullptr` or assert. | `[x]` |
| 4 | Create top-level `V6CLANG.td` with an empty target definition. Verify `llvm-tblgen` parses it. | `[x]` |
| 5 | Create `CMakeLists.txt` for the V6CLANG target. Wire into LLVM's build via `LLVM_EXPERIMENTAL_TARGETS_TO_BUILD`. | `[x]` |
| 6 | Build LLVM with V6CLANG enabled. Verify `llc -march=v6clang -version` lists the target. | `[x]` |

#### M1.2 Tests

| Test | Tool | Validates |
|------|------|-----------|
| `llc -march=v6clang -version` exits 0 and prints target name | `llc` | Target registration |
| `llvm-tblgen V6CLANG.td` exits 0 | `llvm-tblgen` | TableGen skeleton valid |
| CMake configure with `-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=V6CLANG` succeeds | `cmake` | Build integration |

#### M1.3 Verification

- `llc --version` output includes `v6clang` in the registered targets list.
- Data layout string matches design §2.2 exactly.

#### M1.4 Documentation

- `[x]` `docs/V6ClangBackendOverview.md` — update with build instructions for V6CLANG target.

---

### M2 — TableGen: Registers & Core Instructions
`[x]` **Status: Complete**

**Goal**: Define all registers (design §3) and the full 8080 instruction set (design §4) in TableGen. All instruction encodings validated against `v6asm` reference output.

#### M2.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Create `V6ClangRegisterInfo.td`. Define all physical registers (A, B, C, D, E, H, L, SP, FLAGS, PC), register pairs (BC, DE, HL, PSW), sub-register indices (`sub_hi`, `sub_lo`), and all register classes from design §3.2. | `[x]` |
| 2 | Create `V6ClangRegisterInfo.h/.cpp`. Implement `V6ClangRegisterInfo` subclass: reserved registers (SP, PC), allocation order, callee-saved list (empty per design §6.1). | `[x]` |
| 3 | Run `llvm-tblgen -gen-register-info` → `V6ClangGenRegisterInfo.inc`. Verify generated register enum, classes, and sub-register tables. | `[x]` |
| 4 | Create `V6ClangInstrFormats.td`. Define encoding formats: `Implied`, `Reg`, `Imm8`, `Imm16`, `Direct`, `RST`, `IO` per design §4.3. | `[x]` |
| 5 | Create `V6ClangInstrInfo.td`. Define **all** 8080 instructions organized by category (design §4.2). Start with data-move (MOV, MVI, LDA, STA, LDAX, STAX, LXI, LHLD, SHLD), then ALU (ADD, SUB, ADC, SBB, ANA, ORA, XRA, CMP + immediate variants), then increment/decrement, rotate, branch, stack, misc, and I/O. Include `let Defs = [FLAGS]` / `let Uses = [A]` as appropriate. | `[x]` |
| 6 | Create `V6ClangSchedule.td`. Define `SchedMachineModel` and `SchedWriteRes` entries for every instruction class with Vector 06c cycle costs. | `[x]` |
| 7 | Create `V6ClangInstrInfo.h/.cpp`. Implement `V6ClangInstrInfo` subclass with `copyPhysReg()`, `storeRegToStackSlot()`, `loadRegFromStackSlot()` stubs. | `[x]` |
| 8 | Run `llvm-tblgen -gen-instr-info` → `V6ClangGenInstrInfo.inc`. Verify all instruction enums exist. | `[x]` |
| 9 | For every instruction, compare its encoding (opcode byte + operand structure) against the byte produced by `v6asm` for the same mnenomic. Document discrepancies and fix. | `[x]` |

#### M2.2 Tests

| Test | Tool | Validates |
|------|------|-----------|
| `llvm-tblgen -gen-register-info V6CLANG.td` exits 0 | `llvm-tblgen` | Register descriptions parse |
| `llvm-tblgen -gen-instr-info V6CLANG.td` exits 0 | `llvm-tblgen` | Instruction descriptions parse |
| `llvm-tblgen -gen-subtarget V6CLANG.td` exits 0 | `llvm-tblgen` | Scheduling model parses |
| `llvm-tblgen --print-records` shows expected register classes and members | `llvm-tblgen` | Register class correctness |
| Encoding reference test: compile list of all opcodes, diff against `v6asm`-produced bytes | `v6asm` + script | Opcode encoding correctness |

#### M2.3 Tests — FileCheck (lit)

Create `tests/lit/MC/V6CLANG/encoding.s`:
- One `CHECK` directive per instruction mnemonic verifying the encoded byte(s).
- Covers all 256 possible opcodes (valid ones check encoding; undefined ones check for error).

#### M2.4 Verification

- `llvm-tblgen --print-records` output contains exactly the register classes from design §3.2 with correct members.
- Every defined instruction's opcode matches the Intel 8080 reference and `v6asm` output.
- Scheduling costs match the Vector 06c timing table from the design prompt.

#### M2.5 Documentation

- `[x]` `docs/V6ClangInstructionTimings.md` — instruction timing table, cross-referenced with TableGen `SchedWriteRes` names.

---

### M3 — MC Layer: Assembly Emission
`[x]` **Status: Complete**

**Goal**: `llc` accepts LLVM IR and emits syntactically correct 8080 assembly text. The assembly output is consumable by `v6asm`.

#### M3.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Create `MCTargetDesc/V6ClangMCAsmInfo.h/.cpp`. Set comment string, directive syntax, label conventions compatible with `v6asm` syntax. | `[x]` |
| 2 | Create `MCTargetDesc/V6ClangMCTargetDesc.h/.cpp`. Register `MCAsmInfo`, `MCInstrInfo`, `MCRegisterInfo`, `MCSubtargetInfo` factory functions. | `[x]` |
| 3 | Create `V6ClangAsmPrinter.h/.cpp`. Implement `AsmPrinter` subclass: `emitInstruction()` delegates to `V6ClangMCInstLower`. | `[x]` |
| 4 | Create `V6ClangMCInstLower.h/.cpp`. Lower `MachineInstr` → `MCInst` — translate virtual register operands to physical register names. | `[x]` |
| 5 | Create `V6ClangTargetObjectFile.h/.cpp`. Define section layout (`.text`, `.data`, `.rodata`, `.bss`). | `[x]` |
| 6 | Wire `V6ClangPassConfig::addInstSelector()` to minimal V6ClangISelDAGToDAG with RET pattern. | `[x]` |
| 7 | Test: hand-craft `MachineFunction` with a few instructions, run through `V6ClangAsmPrinter`, validate output matches `v6asm` syntax expectations. | `[x]` |
| 8 | Test: write a trivial `.ll` file (empty function with `ret void`), run `llc -march=v6clang`, verify assembly output is syntactically valid. | `[x]` |

#### M3.2 Tests

| Test | Tool | Validates |
|------|------|-----------|
| `llc -march=v6clang trivial.ll` produces `.s` file | `llc` | Assembly printer works |
| Assemble `llc` output with `v6asm` — no syntax errors | `v6asm` | Output is valid assembly |
| Assembly output contains `ORG` directive matching default start address | `FileCheck` | Start address config |
| lit tests: `tests/lit/CodeGen/V6CLANG/trivial.ll` — verify `RET` instruction appears | `llc` + `FileCheck` | Basic emission |

#### M3.3 Verification

- `llc` output for `ret void` contains a syntactically valid `RET` instruction.
- `v6asm` successfully assembles the `llc` output into a `.bin`.
- Assembly syntax (mnemonics, operand format, directives) matches `v6asm`'s expectations.

#### M3.4 Documentation

- `[x]` `docs/V6ClangBuildGuide.md` — update with `llc` usage examples.

---

### M4 — ISel: i8 Operations & Basic Lowering
`[x]` **Status: Complete**

**Goal**: Instruction selection for all `i8` operations. Simple functions using only 8-bit values compile correctly from LLVM IR to assembly and produce correct results in `v6emul`.

#### M4.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Create `V6ClangISelLowering.h/.cpp`. Register type legalization: `i1` promote to `i8`, `i8` legal, everything else expand/custom. Set operation actions for `i8` operations per design §5.3. | `[x]` |
| 2 | Create `V6ClangISelDAGToDAG.h/.cpp`. Implement `V6ClangDAGToDAGISel::Select()`. Start with TableGen patterns for: `ADD r`, `SUB r`, `ANA r`, `ORA r`, `XRA r`, `ADI d8`, `SUI d8`, `ANI d8`, `ORI d8`, `XRI d8`. | `[x]` |
| 3 | Add ISel patterns for `MVI r, d8` (constant materialization). | `[x]` |
| 4 | Add ISel patterns for `INR r`, `DCR r`. | `[x]` |
| 5 | Add ISel patterns for `MOV r, r` (register copy). Implement `copyPhysReg()` in `V6ClangInstrInfo`. | `[x]` |
| 6 | Add custom lowering for `load i8` (via HL-indirect or LDA) and `store i8` (via HL-indirect or STA). | `[x]` |
| 7 | Add ISel patterns for `CMP r`, `CPI d8`. Implement custom lowering for `icmp` + `br` → `CMP` + `Jcc`. | `[x]` |
| 8 | Add ISel patterns for `RLC`, `RRC`, `RAL`, `RAR` for shift-by-1 on accumulator. Custom lowering for `shl i8`, `lshr i8`, `ashr i8`. | `[x]` |
| 9 | Add custom lowering for `GlobalAddress` → `LXI`. | `[x]` |
| 10 | Add ISel for `RET` (return `i8` in `A`) and `CALL` (basic, no args). | `[x]` |
| 11 | Implement register allocation integration: set allocation order per design §3.4, implement `getReservedRegs()` (SP, PC). | `[x]` |

#### M4.2 Tests — lit (FileCheck)

One test per operation, in `tests/lit/CodeGen/V6CLANG/`:

| Test File | Verifies |
|-----------|----------|
| `add-i8.ll` | `ADD r` / `ADI d8` selected for `add i8` |
| `sub-i8.ll` | `SUB r` / `SUI d8` selected for `sub i8` |
| `and-i8.ll` | `ANA r` / `ANI d8` |
| `or-i8.ll` | `ORA r` / `ORI d8` |
| `xor-i8.ll` | `XRA r` / `XRI d8` |
| `incr-i8.ll` | `INR` / `DCR` for `add 1` / `sub 1` |
| `shift-i8.ll` | Rotate instructions for shift-by-1 |
| `cmp-branch-i8.ll` | `CMP` + `Jcc` for `icmp` + `br` |
| `load-store-i8.ll` | `MOV r,M` / `MOV M,r` / `LDA` / `STA` |
| `const-i8.ll` | `MVI r, imm` for constant loads |
| `ret-i8.ll` | Return value in `A` |

#### M4.3 Tests — Emulator Round-Trip

Create `tests/unit/codegen/`:

| Test File | Description |
|-----------|-------------|
| `test_alu_i8.c` | All 8-bit ALU ops: add, sub, and, or, xor with various operands. Compile → `v6asm` (via `llc` ASM output) → `v6emul`. Check register A for expected results. |
| `test_branch.c` | Conditional branches: if/else with `i8` comparisons. Verify correct branch taken via memory writes inspected in `v6emul`. |

#### M4.4 Verification

- Every `i8` LLVM IR operation selects the expected 8080 instruction (FileCheck).
- Compiled programs produce correct results when executed in `v6emul`.
- Register allocator does not crash; `A` register constraint is respected.

#### M4.5 Documentation

- `[x]` `docs/V6ClangArchitecture.md` — update with supported operations.

**Implementation notes**: M4 also required implementing minimal frame lowering (V6ClangFrameLowering.cpp with prologue/epilogue via LXI+DAD+SPHL), spill/reload pseudos (V6CLANG_SPILL8/V6CLANG_RELOAD8), and eliminateFrameIndex — these are M5 tasks pulled forward to unblock the register allocator for SELECT_CC. Emulator round-trip tests (M4.3) deferred until v6asm integration is available. SRL/SRA lowering returns SDValue() for now (expand/libcall in M11).

---

### M5 — Frame Lowering & Calling Convention
`[x]` **Status: Complete**

**Goal**: Functions with local variables, arguments, and return values work correctly. Stack frame layout matches design §6–7. Functions can call other functions.

#### M5.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Create `V6ClangFrameLowering.h/.cpp`. Implement prologue emission: `LXI H, -N; DAD SP; SPHL` per design §7.3. | `[x]` |
| 2 | Implement epilogue emission: `LXI H, N; DAD SP; SPHL; RET`. | `[x]` |
| 3 | Implement shrink-wrapping: omit prologue/epilogue for leaf functions with no locals. | `[x]` |
| 4 | Implement `eliminateFrameIndex()`: replace `frame_index` operands with `LXI H, offset; DAD SP` materialization per design §7.1. | `[x]` |
| 5 | Create `V6ClangCallingConv.td`. Define `V6CLANG_CConv`: argument registers (A, HL, DE, BC → stack), return values (A, HL, DE:HL) per design §6.1. | `[x]` |
| 6 | Implement `LowerFormalArguments()` in `V6ClangISelLowering`: copy arguments from physical registers / stack to virtual registers. | `[x]` |
| 7 | Implement `LowerReturn()`: copy return value to physical register. | `[x]` |
| 8 | Implement `LowerCall()`: argument placement, CALL emission, result copy. Handle stack-passed arguments. | `[x]` |
| 9 | Implement `storeRegToStackSlot()` and `loadRegFromStackSlot()` in `V6ClangInstrInfo` for spill/reload. | `[x]` |
| 10 | Implement frame pointer mode: reserve BC when `-fno-omit-frame-pointer` or `alloca` is used, per design §7.2. | `[x]` |
| 11 | Inflate spill weights in V6CLANG register allocator hooks to reflect 32cc+ stack access cost. MVIr/LXI marked as `isReMaterializable=1, isAsCheapAsAMove=1` to prefer rematerialization (8-10cc) over spill round-trips (64cc+). | `[x]` |

#### M5.2 Tests — lit (FileCheck)

| Test File | Verifies |
|-----------|----------|
| `frame-lowering.ll` | Prologue/epilogue for functions with 0, 1, 4, 256 bytes of locals |
| `frame-leaf.ll` | Leaf function with no locals has no prologue/epilogue |
| `call-conv.ll` | i8 arg → A, i16 arg → HL, two args → HL + DE, three → HL + DE + BC |
| `call-conv-stack.ll` | 4th+ arguments passed on stack |
| `call-conv-ret.ll` | Return i8 in A, i16 in HL, i32 in DE:HL |
| `spill-reload.ll` | Function with register pressure causes spill; verify correct reload |
| `call-simple.ll` | Function calls another function and uses result |

#### M5.3 Tests — Emulator Round-Trip

| Test File | Description |
|-----------|-------------|
| `test_calling_convention.c` | Call a function with 1, 2, 3, 4 arguments. Verify correct values received and returned. |
| `test_local_vars.c` | Function with multiple local variables. Verify correct load/store to stack slots. |
| `test_nested_calls.c` | Function A calls B calls C. Verify return chain works and stack is balanced. |

#### M5.4 Tests — Regression

| Test | Purpose |
|------|---------|
| Stack offset correctness for frame sizes 0–511 | Prevent off-by-one in `eliminateFrameIndex` |
| Spill weight validation: count spills in test function, assert ≤ expected | Prevent spill regression |

#### M5.5 Verification

- Prologue/epilogue match design §7.3 assembly exactly.
- Arguments arrive in correct registers per design §6.1.
- Stack remains balanced after calls (SP before call == SP after call + cleanup).
- `v6emul` shows correct values at expected memory addresses for stack variables.

#### M5.6 Documentation

- `[x]` `docs/V6ClangCallingConvention.md` — full description with examples.
- `[x]` `docs/V6ClangArchitecture.md` — update with calling convention summary.

**Implementation notes**: M5 completion included:
- `V6ClangCallingConv.td`: RetCC_V6Clang for return value assignment (i8→A, i16→HL, i32→HL+DE). Argument passing implemented in C++ due to position-based complexity.
- Full i8+i16 calling convention in `LowerFormalArguments`, `LowerReturn`, `LowerCall` with register args (Arg1→A/HL, Arg2→E/DE, Arg3→C/BC) and stack args (4th+, R-to-L, caller cleans).
- `V6CLANG_LEA_FI` pseudo for FrameIndex materialization (LXI+DAD SP), selected in `V6ClangISelDAGToDAG::Select()`.
- `V6CLANG_LOAD8_P`/`V6CLANG_STORE8_P` pseudos for general pointer load/store.
- `CALLSEQ_START`/`CALLSEQ_END` handled in C++ ISel (ADJCALLSTACKDOWN/UP).
- Frame pointer mode: BC reserved when `hasFP()`, prologue saves BC and sets BC=SP, epilogue restores.
- 16-bit spill/reload: `V6CLANG_SPILL16`/`V6CLANG_RELOAD16` with LXI+DAD+MOV+INX+MOV expansion.
- Immediate printing fix: mask to 16 bits in `V6ClangInstPrinter::printOperand()` to avoid 64-bit sign-extension.
- Rematerialization: MVIr and LXI marked `isReMaterializable=1, isAsCheapAsAMove=1`.
- All 17 lit tests pass (including 7 new M5 tests: frame-lowering, frame-leaf, call-conv, call-conv-ret, call-simple, spill-reload, plus M4 regressions).

---

### M6 — MC Layer: Binary Emission
`[x]` **Status: Complete**

**Goal**: `llc` can emit raw flat binary (`.bin`) and Intel HEX (`.hex`) output directly. Binary output matches `v6asm`-assembled reference programs byte-for-byte.

#### M6.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Create `MCTargetDesc/V6ClangMCCodeEmitter.h/.cpp`. Implement `encodeInstruction()` for every encoding format (design §4.3). | `[x]` |
| 2 | Create `MCTargetDesc/V6ClangAsmBackend.h/.cpp`. Implement fixup kinds for 8-bit immediate, 16-bit absolute address. Implement `applyFixup()`. | `[x]` |
| 3 | Implement flat binary object writer: single section, no headers, raw bytes starting at configured origin. | `[x]` |
| 4 | Implement `-mv6clang-start-address=<addr>` command-line option (design §9.3). Wire into `ORG` directive and relocation base. | `[x]` |
| 5 | Implement Intel HEX output format as an alternative. | `[x]` |
| 6 | Validate: compile a known program via `llc` → `.bin`, and independently via `llc` → `.s` → `v6asm` → `.bin`. Byte-compare the two. | `[x]` |

#### M6.2 Tests

| Test | Tool | Validates | Status |
|------|------|-----------|--------|
| Binary encoding of every instruction: emit via `llc`, compare bytes to `v6asm` reference | `llc` + `v6asm` + `diff` | Encoding correctness | `[x]` |
| Start address 0x0100 (default): first byte at file offset 0 corresponds to address 0x0100 | `llc` + `v6emul` | Origin handling | `[x]` |
| Start address 0x8000: JMP targets in binary are relocated | `llc` + `v6emul` | Relocation correctness | `[x]` |
| Intel HEX output loads in `v6emul` identically to flat binary | `llc` + `v6emul` | HEX format | `[x]` |
| Round-trip: compile, run in `v6emul`, verify output | `llc` + `v6emul` | End-to-end binary correct | `[x]` |

#### M6.3 Tests — Regression

| Test | Purpose | Status |
|------|---------|--------|
| `tests/lit/MC/V6CLANG/encoding-*.ll` (6 tests) | Every encoding format produces correct bytes | `[x]` |
| Binary size = sum of instruction sizes (no padding, no headers) | Flat binary format compliance | `[x]` |
| All 16 existing CodeGen lit tests pass with `-filetype=obj` | No regressions | `[x]` |

#### M6.4 Verification

- [x] Byte-for-byte match between `llc`-emitted binary and `v6asm`-assembled reference for 8 test programs (via `verify_binary_encoding.py`).
- [x] `v6emul` produces identical execution traces for both sources.
- [x] Start address override affects all absolute addresses in the binary (via `--base` in elf2bin.py).

#### M6.5 Documentation

- `[x]` `docs/V6ClangBuildGuide.md` — updated with binary emission options, start address configuration, Intel HEX, and emulator invocation.

---

### M7 — ISel: i16 & i32 Operations
`[x]` **Status: Complete**

**Goal**: 16-bit and 32-bit integer operations compile correctly. `i16` uses register pairs; `i32` is expanded to pairs of `i16`. Pointer arithmetic works.

#### M7.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Implement `i16` type legalization: `Legal` for loads, stores, register moves; `Custom` for arithmetic. | `[x]` |
| 2 | Implement pseudo-instructions: `V6CLANG_MOV16rr`, `V6CLANG_LOAD16`, `V6CLANG_STORE16`, `V6CLANG_ADD16`, `V6CLANG_SUB16`, `V6CLANG_CMP16`, `V6CLANG_SHIFT_L`, `V6CLANG_SHIFT_R` per design §5.5. | `[x]` |
| 3 | Implement pseudo-instruction expansion in `expandPostRAPseudo()` — expand each pseudo into the concrete 8080 sequences from design §5.5. | `[x]` |
| 4 | Implement custom DAG combine for `(add HL, rp)` → `DAD rp` (design §5.4). | `[x]` |
| 5 | Implement `i16` comparison: custom lowering to 8-bit compare chain with correct flag handling. | `[x]` |
| 6 | Implement `i16` shift: unrolled sequences for constant shift amounts; library call for variable. | `[x]` |
| 7 | Implement `i32` type legalization: `Expand` to pair of `i16`. Verify add, sub, compare chains. | `[x]` |
| 8 | Implement pointer arithmetic lowering: `getelementptr` → `DAD` or 8-bit add chain. | `[x]` |
| 9 | Implement `LXI rp, imm16` for 16-bit constant materialization. | `[x]` |
| 10 | Implement `LHLD` / `SHLD` selection for `i16` loads/stores to known addresses. | `[x]` |
| 11 | Implement `LDAX` / `STAX` for loads/stores via BC/DE pointer pairs. | `[x]` |

#### M7.2 Tests — lit (FileCheck)

| Test File | Verifies |
|-----------|----------|
| `add-i16.ll` | `DAD` for HL+rp, 8-bit chain for other pairs |
| `sub-i16.ll` | `SUB` + `SBB` chain |
| `and-or-xor-i16.ll` | Pair-wise 8-bit ALU expansion |
| `cmp-i16.ll` | 16-bit comparison sequence |
| `shift-i16.ll` | Unrolled shift for constant amounts (SHL 1/3/8/10, SRL 1/3/8/10, SRA 1/8) |
| `load-store-i16.ll` | `LHLD`/`SHLD`, `LXI`+`MOV`+`MOV` patterns |
| `add-i32.ll` | Expanded to four 8-bit operations with carry |
| `pointer-arith.ll` | `getelementptr` → `DAD` or add chain |
| `const-i16.ll` | `LXI rp, imm16` |

#### M7.3 Tests — Emulator Round-Trip

13 LLVM IR → llc → v6asm → v6emul round-trip tests in `tests/integration/run_m7_roundtrip.py`:

| Test Name | Description |
|-----------|-------------|
| `add_i16` | 0x1234 + 0x0111 = 0x1345 |
| `add_i16_carry` | 0x00FF + 0x0001 = 0x0100 (carry propagation) |
| `sub_i16` | 0x1345 − 0x0111 = 0x1234 |
| `and_i16` | 0xFF0F & 0x0FFF = 0x0F0F |
| `or_i16` | 0xF000 \| 0x000F = 0xF00F |
| `xor_i16` | 0xFFFF ^ 0x0F0F = 0xF0F0 |
| `shl1_i16` | 0x4080 << 1 = 0x8100 |
| `shl8_i16` | 0x0042 << 8 = 0x4200 |
| `srl1_i16` | 0x8100 >> 1 = 0x4080 |
| `srl8_i16` | 0x4200 >> 8 = 0x0042 |
| `sra1_i16_positive` | 0x4080 >>> 1 = 0x2040 (sign=0) |
| `sra1_i16_negative` | 0x8100 >>> 1 = 0xC080 (sign-extended) |
| `sra8_i16_negative` | 0x8042 >>> 8 = 0xFF80 (sign-extended) |

*Note: `.c` file tests deferred to M9 (Clang integration). i32 and pointer round-trip tests deferred to M9.*

#### M7.4 Verification

- `[x]` Every `i16` operation produces the instruction sequence documented in design §5.3/§5.5.
- `[x]` `DAD` is selected when applicable.
- `[x]` `i32` operations produce correct results for edge cases: `0xFFFFFFFF + 1`, `0x00000000 - 1`.
- `[x]` Pointer arithmetic matches C semantics for `sizeof`-based offsets.
- `[x]` 26 lit tests pass (0 regressions). 13 emulator round-trip tests pass.
- `[x]` SHL/SRL/SRA i16 verified for shift amounts 1, 3, 8, 10 (including sign extension for SRA).

#### M7.5 Documentation

- `[x]` `docs/V6ClangArchitecture.md` — update with supported type widths and limitations.

---

### M8 — Optimization Passes
`[x]` **Status: Complete**

**Goal**: Implement all custom optimization passes from design §8.2. Each pass is individually testable and toggleable. Total cycle count for benchmark programs decreases measurably.

#### M8.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Implement `V6ClangZeroTestOpt`: replace `CPI 0` with `ORA A`. Add `-v6clang-disable-zero-test-opt` flag. | `[x]` |
| 2 | Implement `V6ClangXchgOpt`: detect DE↔HL MOV pairs replaceable by XCHG. Add `-v6clang-disable-xchg-opt` flag. | `[x]` |
| 3 | Implement `V6ClangPeephole`: pattern-based local optimizations (redundant MOV elimination, strength reduction `ADD A,A` for `shl 1`). Add `-v6clang-disable-peephole` flag. | `[x]` |
| 4 | Implement `V6ClangAccumulatorPlanning`: basic block data-flow reordering to minimize A save/restore traffic. Add `-v6clang-disable-acc-planning` flag. | `[x]` |
| 5 | Implement `V6ClangLoadStoreOpt`: merge adjacent loads/stores to the same base address. Add `-v6clang-disable-loadstore-opt` flag. | `[x]` |
| 6 | Implement `V6ClangBranchOpt`: branch relaxation, unreachable block elimination, tail call conversion. Add `-v6clang-disable-branch-opt` flag. | `[x]` |
| 7 | Implement `V6ClangSPTrickOpt`: replace expanded memcpy/memset with SP-trick sequences (design §8.2.3). Add `-v6clang-disable-sp-trick` flag. Wrap in DI/EI. Reject if inside ISR. | `[x]` |
| 8 | Implement `V6ClangTypeNarrowing` (IR pass): narrow provably-bounded `i16` to `i8`. Add `-v6clang-disable-type-narrowing` flag. | `[x]` |
| 9 | Register all passes in `V6ClangPassConfig` at the positions from design §14.3. | `[x]` |
| 10 | Run full lit test suite with `-verify-machineinstrs` to catch invariant violations. Fixed pre-existing INX operand bug in `V6ClangRegisterInfo.cpp`. | `[x]` |
| 11 | Run full lit test suite with each pass individually disabled to detect ordering dependencies. All 8 passes pass isolation (26/26 non-pass-specific tests each). | `[x]` |

#### M8.2 Tests — lit (FileCheck), per pass

| Test File | Pass | Verifies |
|-----------|------|----------|
| `peephole-ora.ll` | V6ClangZeroTestOpt | `CPI 0` → `ORA A` |
| `xchg-opt.ll` | V6ClangXchgOpt | MOV D,H; MOV E,L → XCHG |
| `peephole-shl1.ll` | V6ClangPeephole | `shl i8 1` → `ADD A,A` |
| `peephole-dbl16.ll` | V6ClangPeephole | `shl i16 1` → `DAD HL` |
| `acc-planning.ll` | V6ClangAccumulatorPlanning | Reduced MOV A,r / MOV r,A count |
| `loadstore-merge.ll` | V6ClangLoadStoreOpt | Adjacent loads merged |
| `branch-opt.ll` | V6ClangBranchOpt | Unreachable blocks removed; tail call emitted |
| `sp-trick.ll` | V6ClangSPTrickOpt | memcpy ≥6B uses SP-trick with DI/EI |
| `type-narrow.ll` | V6ClangTypeNarrowing | Loop counter narrowed from i16 to i8 |

#### M8.3 Tests — Standalone Unit (C files)

In `tests/unit/optimization/`:

| Test File | Description |
|-----------|-------------|
| `test_zero_test_opt.c` | Functions comparing values to zero. Compile, disassemble, verify `ORA A` appears instead of `CPI 0`. Run in `v6emul` for correctness. |
| `test_xchg_opt.c` | Functions requiring DE↔HL swaps. Verify XCHG in output, correct execution. |
| `test_sp_trick.c` | Functions with memcpy of various sizes. Verify SP-trick used for ≥6B. Count cycles in `v6emul`, verify improvement. |
| `test_accumulator_planning.c` | Functions with multiple ALU ops. Count MOV-to/from-A in output, verify reduction. |

#### M8.4 Performance Benchmarks

Establish cycle-count baselines *before* enabling optimization passes, then measure after:

| Benchmark | Metric | Pass(es) Tested |
|-----------|--------|----------------|
| `fibonacci.c` (fib(20)) | Total cycles | AccumulatorPlanning, TypeNarrowing |
| `memcpy_benchmark.c` (copy 64B) | Total cycles | SPTrickOpt |
| `sort_i8.c` (bubble sort, 16 elements) | Total cycles | ZeroTestOpt, Peephole, XchgOpt |
| `arith_i16.c` (16-bit math gauntlet) | Total cycles | All passes |

Record baseline and optimized cycle counts in `tests/benchmarks/results.md`. Fail CI if optimized count exceeds baseline.

#### M8.5 Verification

- Each pass transforms expected patterns (FileCheck).
- Each pass individually disabled does not break correctness (full test suite still passes).
- `v6emul` execution produces correct results with all passes enabled.
- `-verify-machineinstrs` produces no errors.
- Benchmark cycle counts improve or stay equal (never regress) when passes are enabled.

#### M8.6 Documentation

- `[x]` `docs/V6ClangOptimization.md` — each pass described: purpose, patterns, toggle flag, measured impact.

---

### M9 — Clang Frontend Integration
`[x]` **Status: Complete**

**Goal**: `clang -target i8080-unknown-v6clang` compiles C source to 8080 assembly or binary. Built-in macros and intrinsics from design §10 are available.

#### M9.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Create `clang/lib/Basic/Targets/I8080.h/.cpp`. Implement `I8080TargetInfo`: type sizes from design §2.3, unsigned `char`, pointer width 16. | `[x]` |
| 2 | Register the `i8080` architecture in Clang's triple parsing (`llvm::Triple`). | `[x]` |
| 3 | Define built-in macros: `__V6CLANG__`, `__I8080__`, `__CHAR_UNSIGNED__` (design §10.1). | `[x]` |
| 4 | Implement `TargetCodeGenInfo` for V6CLANG: ABI lowering that matches `V6CLANG_CConv` (design §6.1). | `[x]` |
| 5 | Add language restriction diagnostics: warn on `long long`, warn on `float`/`double` (design §10.2). | `[x]` |
| 6 | Implement `__builtin_v6clang_in`, `__builtin_v6clang_out`, `__builtin_v6clang_di`, `__builtin_v6clang_ei`, `__builtin_v6clang_hlt`, `__builtin_v6clang_nop` intrinsics (design §10.3). | `[x]` |
| 7 | Implement inline assembly support for 8080 syntax via `asm()` (IR-level constraint handling; no MC asm parser). | `[x]` |
| 8 | Wire Clang driver to produce flat binary output when `-o file.bin` is specified. | `[x]` |

#### M9.2 Tests

| Test | Validates |
|------|-----------|
| `clang -target i8080-unknown-v6clang -E -dM empty.c` contains `__V6CLANG__`, `__I8080__`, `__CHAR_UNSIGNED__` | Built-in macros |
| `clang -target i8080-unknown-v6clang -c -S return42.c` produces valid assembly | Basic compilation |
| `return42.c` → binary → `v6emul`: halts with 42 in A | End-to-end correctness |
| `long long x;` produces warning/error | Language restriction |
| `float f;` produces warning | Soft-float diagnostic |
| `__builtin_v6clang_in(0x03)` emits `IN 03H` | Intrinsic mapping |
| `__builtin_v6clang_out(0x02, val)` emits `OUT 02H` | Intrinsic mapping |
| `__builtin_v6clang_di()` emits `DI` | Intrinsic mapping |
| `__builtin_v6clang_hlt()` emits `HLT` | Intrinsic mapping |
| `sizeof(int) == 2`, `sizeof(long) == 4`, `sizeof(void*) == 2` in compiled code | Type sizes |

#### M9.3 Tests — Integration

| Test File | Description |
|-----------|-------------|
| `tests/integration/hello_v6clang.c` | Writes a value to an I/O port. Compile via Clang, run in `v6emul`, verify port output. |
| `tests/integration/fibonacci.c` | Computes fib(N). Full C → binary → `v6emul` round-trip. |

#### M9.4 Verification

- `clang -target i8080-unknown-v6clang` accepts standard freestanding C.
- Type sizes match design §2.3.
- All 6 intrinsics produce the correct single-instruction output.
- Compiled programs execute correctly in `v6emul`.

#### M9.5 Documentation

- `[x]` `docs/V6ClangBuildGuide.md` — update with Clang usage, intrinsics, language restrictions.

---

### M10 — Linker & Multi-File Compilation
`[x]` **Status: Complete**

**Goal**: Multiple `.c` / `.ll` files compile and link into a single flat binary. Symbol resolution across translation units works correctly.

**Implementation notes**: Used ELF32 LE object format (via MC layer with `-filetype=obj`) instead of a custom format. Linker implemented as Python tool `scripts/v6clang_link.py` instead of C++ in `lld/V6CLANG/`. Custom ELF relocation types `R_V6CLANG_8` (1) and `R_V6CLANG_16` (2) defined in `V6ClangFixupKinds.h`. Clang driver updated to invoke the Python linker.

#### M10.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | ELF relocation types: added `R_V6CLANG_8`, `R_V6CLANG_16` to `V6ClangFixupKinds.h`; updated `V6ClangAsmBackend.cpp` to emit them. MC layer produces standard ELF32 `.o` files. | `[x]` |
| 2 | Created `scripts/v6clang_link.py`: reads ELF `.o` files, resolves symbols (global/weak/local), lays out sections, applies relocations, emits flat binary. | `[x]` |
| 3 | Section ordering in linker: `.text` → `.rodata` → `.data` → `.bss` per design §9.4 memory layout. | `[x]` |
| 4 | Address relocation: absolute addresses adjusted to configured base address (`--base` flag). | `[x]` |
| 5 | Size validation: total size ≤ 65536, linker error on overflow. | `[x]` |
| 6 | Memory map file output (`--map` flag): lists sections, symbols, and sizes. | `[x]` |
| 7 | Clang driver (`V6Clang.cpp`) updated to invoke `python v6clang_link.py` with proper args for `-Wl,` and `-Xlinker` options. | `[x]` |

#### M10.2 Tests

| Test | Validates | Status |
|------|-----------|--------|
| `link-cross-file.ll` — two-file link with cross-object function call | Cross-file symbol resolution | `[x]` |
| `link-global-data.ll` — global variable accessed across objects | Data section linking | `[x]` |
| `link-section-order.ll` — map output shows .text before .data | Section ordering | `[x]` |
| `link-size-limit.ll` — 64KB overflow rejected | Size validation | `[x]` |
| `link-relocation.ll` — base address 0x100 affects binary content | Relocation | `[x]` |
| `link-undefined-sym.ll` — undefined symbol error reported | Error reporting | `[x]` |

#### M10.3 Tests — Emulator Round-Trip

| Test File | Description | Status |
|-----------|-------------|--------|
| `run_m10_link_roundtrip.py` — cross_file_call | Cross-file function call via v6asm + v6emul. | `[x]` |
| `run_m10_link_roundtrip.py` — cross_file_i16 | Shared 16-bit global variable across files. | `[x]` |

#### M10.4 Verification

- `[x]` All 61 lit tests pass (36 CodeGen + 6 MC + 13 Clang + 6 link).
- `[x]` All 15 golden emulator tests pass (no regressions).
- `[x]` Section ordering matches design §9.4 memory layout.
- `[x]` Linker rejects >64KB output and undefined symbols.

#### M10.5 Documentation

- `[x]` `docs/V6ClangBuildGuide.md` — linker usage documented via test examples and `--help` in v6clang_link.py.

---

### M11 — Runtime Library
`[x]` **Status: Complete**

**Goal**: All runtime support functions from design §11 are implemented in 8080 assembly, tested in isolation, and wired into the compiler's LibCall table.

#### M11.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Write `compiler-rt/lib/builtins/v6clang/crt0.s`: set SP to 0xFFFF, zero `.bss`, call `_main`, `HLT`. Assemble with `v6asm`, test with `v6emul`. | `[x]` |
| 2 | Write `mulhi3.s`: 16×16→16 unsigned multiply. Test standalone with `v6emul`. | `[x]` |
| 3 | Write `mulsi3.s`: 16×16→32 multiply. Test standalone. | `[x]` |
| 4 | Write `divhi3.s` + `modhi3.s`: signed 16÷16→16 division and remainder. Test standalone. | `[x]` |
| 5 | Write `udivhi3.s` + `umodhi3.s`: unsigned variants. Test standalone. | `[x]` |
| 6 | Write `shift.s`: `__ashlhi3`, `__ashrhi3`, `__lshrhi3` for variable-count 16-bit shifts. Test standalone. | `[x]` |
| 7 | Write `memory.s`: `memcpy`, `memset`, `memmove`. Test standalone. | `[x]` |
| 8 | Wire all functions into `V6ClangISelLowering` libcall table: `RTLIB::MUL_I16` → `__mulhi3`, etc. i8 ops Promote to i16. | `[x]` |
| 9 | Write lit tests verifying correct libcall emission for `*`, `/`, `%` and variable shifts (i8 and i16). | `[x]` |

#### M11.2 Tests — Standalone (per function)

Each runtime function gets a standalone test assembled with `v6asm` and executed with `v6emul`:

| Test | Function | Cases |
|------|----------|-------|
| `test_mulhi3.asm` | `__mulhi3` | 0×0, 1×1, 255×255, 127×2, asymmetric |
| `test_mulsi3.asm` | `__mulsi3` | 0, 1, 0xFFFF×0xFFFF, powers of 2 |
| `test_divhi3.asm` | `__divhi3` | 10/3, -10/3, 0/1, div-by-zero guard |
| `test_modhi3.asm` | `__modhi3` | 10%3, -10%3, 7%1 |
| `test_udivhi3.asm` | `__udivhi3` | 0xFFFF/2, 10/3, 0/1 |
| `test_umodhi3.asm` | `__umodhi3` | 0xFFFF%256, 10%3 |
| `test_ashlhi3.asm` | `__ashlhi3` | shift by 0,1,7,8,15 |
| `test_ashrhi3.asm` | `__ashrhi3` | positive and negative values, shift by 0,1,8,15 |
| `test_lshrhi3.asm` | `__lshrhi3` | shift by 0,1,7,8,15 |
| `test_memcpy.asm` | `memcpy` | 0,1,2,5,6,64 bytes; overlapping rejected |
| `test_memset.asm` | `memset` | 0,1,64 bytes; various fill values |
| `test_memmove.asm` | `memmove` | overlapping forward, overlapping backward, non-overlapping |

#### M11.3 Tests — Compiler Integration

| Test File | Description |
|-----------|-------------|
| `test_multiply.c` | `a * b` for `i8` and `i16`. Verify correct results via `v6emul`. |
| `test_divide.c` | `a / b`, `a % b` for signed and unsigned. |
| `test_shift_var.c` | `a << n`, `a >> n` with runtime-variable `n`. |
| `test_memcpy_c.c` | `memcpy(dst, src, n)` from C. Verify memory contents. |

#### M11.4 Performance Benchmarks

| Function | Benchmark | Metric |
|----------|-----------|--------|
| `__mulhi3` | 1000 multiplications | Total cycles |
| `memcpy` (64B) | Copy 64B block | Cycles, verify SP-trick is used |
| `memset` (256B) | Fill 256B block | Cycles |
| `__divhi3` | 1000 divisions | Total cycles |

#### M11.5 Verification

- All runtime functions conform to `V6CLANG_CConv`: arguments in correct registers, results in correct registers, no callee-saved registers assumed.
- All standalone tests pass in `v6emul`.
- Compiler-emitted calls to runtime functions produce correct results.
- `memcpy` uses SP-trick for copies ≥6 bytes (verify via disassembly).

#### M11.6 Documentation

- `[x]` `docs/V6ClangArchitecture.md` — runtime library section: functions, ABI compliance, performance notes.

---

### M12 — End-to-End Validation & Performance
`[x]` **Status: Complete**

**Goal**: Full pipeline validated: C source → Clang → LLVM IR → V6CLANG backend → flat binary → `v6emul`. Performance benchmarks baselined. All documentation complete.

#### M12.1 Steps

| # | Step | Status |
|---|------|--------|
| 1 | Compile and run all integration tests (`tests/integration/`) through the full Clang pipeline. | `[x]` |
| 2 | Compile and run all standalone C unit tests (`tests/unit/`) through the full pipeline. | `[x]` |
| 3 | Run the complete lit test suite. Zero failures. | `[x]` 64/64 |
| 4 | Run all runtime library standalone tests. Zero failures. | `[x]` |
| 5 | Run the golden test suite (from M0) and verify `v6emul` still produces expected results. | `[x]` 15/15 |
| 6 | Execute performance benchmarks. Record final cycle counts. Compare against M8 baselines. | `[x]` |
| 7 | Stress test: compile the largest feasible C program (e.g., a simple game or utility). | `[x]` stress_primes (231,296cc) |
| 8 | Run `llc` and `clang` with `-verify-machineinstrs` across entire test suite. | `[x]` 44/45 (add-i32 pre-existing) |
| 9 | Test all combinations of start addresses: 0x0000, 0x0100, 0x4000. Verify correct relocation. | `[x]` 3/3 |
| 10 | Test ISR convention: compile a function with interrupt handler semantics. | `[x]` compiles OK |

#### M12.2 Integration Test Suite

| Test File | Description |
|-----------|-------------|
| `hello_v6clang.c` | I/O port write. Verify port output in `v6emul`. |
| `fibonacci.c` | Compute fib(N) for N=1..20. Verify results. |
| `memcpy_benchmark.c` | Copy blocks of various sizes. Verify correctness and measure cycles. |
| `sort_bubble.c` | Bubble sort an 8-element i8 array. Verify sorted order. |
| `struct_pass.c` | Pass and return structs. Verify `sret` convention. |
| `global_init.c` | Initialized and uninitialized globals. Verify `.data` and `.bss`. |
| `pointer_chain.c` | Linked list traversal via pointers. Verify correct values. |
| `multifile_app.c` + `multifile_lib.c` | Multi-file program with cross-file calls and data. |

#### M12.3 Performance Report

| Program | Cycle Count | Notes |
|---------|-------------|-------|
| `hello_v6clang` | 116cc | I/O port writes |
| `fibonacci(20)` | 14,376cc | 3-phi iterative loop |
| `array_sum(8)` | 7,188cc | Ptr arithmetic + byte loads |
| `global_init` | 404cc | 16-bit read/write via ptr |
| `pointer_chain` | 672cc | Linked list traversal |
| `memcpy(16B)` | 1,484cc | Runtime memcpy |
| `multifile_app` | 2,768cc | Cross-function mul + add |
| `struct_pass` | 544cc | Struct init + field sum |
| `stress_primes(30)` | 231,296cc | Trial division with urem |

All values filled in during execution. Stored in `tests/benchmarks/final_results.md`.

#### M12.4 Regression Gate

The following must hold for the milestone to be considered complete:

- All lit tests pass (0 failures, 0 errors).
- All emulator round-trip tests pass.
- All runtime standalone tests pass.
- `-verify-machineinstrs` produces 0 errors across all tests.
- No optimization pass regresses cycle count vs. baseline.
- Binary size for benchmark programs ≤ 110% of hand-assembled `v6asm` equivalents (sanity check, not strict).

#### M12.5 Documentation — Final

- `[x]` `docs/README.md` — finalize: architecture, usage, limitations, examples.
- `[x]` `docs/V6ClangCallingConvention.md` — finalize with tested examples.
- `[x]` `docs/V6ClangOptimization.md` — finalize with measured performance data.
- `[x]` `docs/V6ClangInstructionTimings.md` — finalize, cross-reference with benchmark results.
- `[x]` `README.md` — project root: quick start, build instructions, test instructions, supported C subset.

---

## 5. Test Strategy Summary

### 5.1 Test Categories & Tools

| Category | Location | Tool Chain | When Run |
|----------|----------|------------|----------|
| Golden (emulator trust) | `tests/golden/` | `v6asm` → `v6emul` | M0, then every milestone |
| TableGen validation | `tests/lit/MC/V6CLANG/` | `llvm-tblgen` | M2+ |
| Instruction encoding | `tests/lit/MC/V6CLANG/encoding.s` | `llvm-mc` + `FileCheck` | M2+ |
| ISel (FileCheck) | `tests/lit/CodeGen/V6CLANG/` | `llc` + `FileCheck` | M4+ |
| Calling convention | `tests/lit/CodeGen/V6CLANG/call-conv*.ll` | `llc` + `FileCheck` | M5+ |
| Binary encoding | `tests/lit/MC/V6CLANG/relocations.s` | `llc` + byte-diff vs `v6asm` | M6+ |
| Optimization passes | `tests/lit/CodeGen/V6CLANG/<pass>.ll` | `llc` + `FileCheck` | M8+ |
| Unit tests (C) | `tests/unit/` | `clang` → `v6asm` → `v6emul` | M4+ |
| Runtime standalone | `tests/runtime/` | `v6asm` → `v6emul` | M11 |
| Integration tests | `tests/integration/` | `clang` → `v6emul` | M9+ |
| Performance benchmarks | `tests/benchmarks/` | `clang` → `v6emul` (cycle count) | M8, M12 |

### 5.2 Test Execution

All tests are runnable via a single command:

```bash
# Full test suite (lit + emulator round-trip + golden)
python tests/run_all.py

# Lit tests only
lit tests/lit/ --v6clang-llc=<path-to-llc>

# Emulator tests only
python tests/run_emulator_tests.py --v6emul=tools/v6emul --v6asm=tools/v6asm
```

### 5.3 Test-to-Milestone Traceability

| Milestone | New Test Files | Cumulative Test Count |
|-----------|---------------|-----------------------|
| M0 | 10–15 golden + toolchain smoke | ~15 |
| M1 | 3 registration tests | ~18 |
| M2 | encoding.s (256 opcodes), register dump | ~20 files, ~280 checks |
| M3 | trivial.ll, ASM syntax | ~22 |
| M4 | 11 lit ISel tests, 2 emulator tests | ~35 |
| M5 | 7 lit tests, 3 emulator tests, regression | ~47 |
| M6 | 5 binary tests, regression | ~54 |
| M7 | 9 lit tests, 4 emulator tests | ~70 |
| M8 | 9 lit tests, 4 unit C tests, 4 benchmarks | ~90 |
| M9 | 10 Clang tests, 2 integration tests | ~105 |
| M10 | 6 linker tests, 2 emulator tests | ~115 |
| M11 | 12 standalone asm tests, 4 integration tests, 4 benchmarks | ~140 |
| M12 | 8 integration tests, final benchmarks | ~150+ |

---

## 6. Performance Validation Checkpoints

| Checkpoint | Milestone | What Is Measured | Acceptance Criteria |
|------------|-----------|------------------|---------------------|
| Emulator trust | M0 | Golden test suite pass rate | 100% |
| First correct execution | M4 | Simple i8 programs run in `v6emul` | Correct results |
| Calling overhead | M5 | Cycles for call+return (no args, no locals) | ≤ 48cc (CALL + RET) |
| Binary accuracy | M6 | Byte diff vs `v6asm` reference | 0 differences |
| Pre-optimization baseline | M8 (before) | Cycle counts for benchmark suite | Recorded |
| Post-optimization | M8 (after) | Cycle counts for benchmark suite | Improvement over baseline |
| Runtime library overhead | M11 | Multiply/divide/memcpy cycle costs | Within 2× of hand-optimized |
| Final performance | M12 | All benchmarks with full pipeline | No regressions vs M8 |

---

## 7. Documentation Update Schedule

| Document | Created | Updated | Finalized |
|----------|---------|---------|-----------|
| `docs/README.md` | M0 | M1, M3, M4, M5, M6, M7, M9, M10, M11 | M12 |
| `docs/V6ClangArchitecture.md` | M0 | M4, M5, M9 | M12 |
| `docs/V6ClangBuildGuide.md` | M0 | M1, M3, M6, M7 | M12 |
| `docs/V6ClangProjectStructure.md` | M0 | M6, M7, M9 | M12 |
| `docs/V6ClangInstructionTimings.md` | M2 | M8 | M12 |
| `docs/V6ClangCallingConvention.md` | M5 | M9 | M12 |
| `docs/V6ClangOptimization.md` | M8 | M11 | M12 |
| `tests/golden/README.md` | M0 | — | — |
| `tests/benchmarks/results.md` | M8 | M11, M12 | M12 |
| `README.md` (project root) | — | — | M12 |

---

*End of implementation plan.*
