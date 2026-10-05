# V6CLANG LLVM Backend — Documentation

An LLVM backend targeting the **Vector 06c** home computer (Intel 8080 / KR580VM80A, 3 MHz, 64 KB RAM).

Goal: **C source → Clang → LLVM IR → V6CLANG backend → flat binary → Vector 06c**

## Table of Contents

### Getting Started

| Document | Description |
|----------|-------------|
| [V6ClangBuildGuide.md](V6ClangBuildGuide.md) | Prerequisites, build commands, mirror sync workflow, running tests, binary emission |
| [V6ClangUsage.md](V6ClangUsage.md) | Clang frontend reference: type sizes, builtins, attributes, inline assembly, resource-dir headers |
| [V6ClangDebugMetadata.md](V6ClangDebugMetadata.md) | Debug-build artifacts: DWARF v5, retained ELF companions, C/v6asm usage, and inspection |
| [V6ClangDebugABI.md](V6ClangDebugABI.md) | Normative debugger ABI, stack contract, unwind boundaries, and DWARF register map |
| [V6ClangCompilerOptions.md](V6ClangCompilerOptions.md) | Backend tuning flags and debug-output toggles (`-mv6clang-annotate-pseudos`, `-mv6clang-print-rt-helpers`, …) |
| [V6ClangRelease.md](V6ClangRelease.md) | Release procedure: tagging, workflow trigger, rollback |
| [V6ClangProjectStructure.md](V6ClangProjectStructure.md) | Directory layout and key paths |

### Architecture & Design

| Document | Description |
|----------|-------------|
| [V6ClangArchitecture.md](V6ClangArchitecture.md) | Target CPU, data layout, memory map |
| [V6ClangInstructionTimings.md](V6ClangInstructionTimings.md) | Intel 8080 instruction cycle costs, TableGen `SchedWriteRes` cross-reference |
| [V6ClangIPRA.md](V6ClangIPRA.md) | Interprocedural Register Allocation on V6CLANG, default behavior, safety model, and disable flags |
| [V6ClangStaticStackAlloc.md](V6ClangStaticStackAlloc.md) | Static stack allocation for non-reentrant functions (O10): eligibility, interrupt attribute, BFS analysis |
| [V6ClangInlineAsmGuide.md](V6ClangInlineAsmGuide.md) | Inline-assembly reference: `asm` keyword forms, V6CLANG constraint letters (`r`/`a`/`p`/`I`/`J`), clobber names, `volatile` / `"memory"` semantics, local register variables, worked examples |
| [V6ClangRuntimeAndInlineAsm.md](V6ClangRuntimeAndInlineAsm.md) | Header-only runtime: math (`v6clang_arith.h`, auto-included) and `mem*`/`str*` (`<string.h>`, opt-in). `V6CLANG_RT` helper pattern, IPRA interaction, `annotate("v6clang-rt-helper")` suppression |
| [Design Document](../design/design.md) | Authoritative architecture specification (registers, instructions, calling convention) |
| [Implementation Plan](../design/plan.md) | Milestone-driven development sequence with steps, tests, and status markers |

### Quick Links

- **Build instructions**: [V6ClangBuildGuide.md](V6ClangBuildGuide.md)
- **Mirror sync**: [sync_llvm_mirror.ps1](../scripts/sync_llvm_mirror.ps1) — run after every build ([details](V6ClangBuildGuide.md#syncing-the-mirror))
- **V6CLANG backend source**: [llvm/lib/Target/V6Clang/](../llvm/lib/Target/V6Clang/) — git-tracked mirror
- **Golden tests**: [tests/golden/](../tests/golden/) — emulator trust baseline
- **Vector 06c CPU timings**: [Vector_06c_instruction_timings.md](Vector_06c_instruction_timings.md)
- **Benchmarks vs other 8080 C compilers**: [benchmarks.md](benchmarks.md) (driver: [tests/benchmarks_c/](../tests/benchmarks_c/README.md))

## Milestone Status

| Milestone | Description | Status |
|-----------|-------------|--------|
| M0 | Project Bootstrap & Tool Validation | Complete |
| M1 | Target Registration & Skeleton | Complete |
| M2 | TableGen: Registers & Core Instructions | Complete |
| M3 | MC Layer: Assembly Emission | Complete |
| M4 | ISel: i8 Operations & Basic Lowering | Complete |
| M5 | Frame Lowering & Calling Convention | Complete |
| M6 | MC Layer: Binary Emission | Complete |
| M7 | ISel: i16 & i32 Operations | Complete |
| M8 | Optimization Passes | Complete |
| M9 | Clang Frontend Integration | Complete |
| M10 | Linker & Multi-File Compilation | Complete |
| M11 | Runtime Library | Complete |
| M12 | End-to-End Validation & Performance | Complete |
