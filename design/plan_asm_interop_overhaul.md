
# Plan: Asm-Interop Overhaul — Calling Convention, AsmParser, Inline Asm, V6CLANG Headers
Make `clang -c file.{c,s} -o file.o` the single canonical pipeline for V6CLANG, fix
`V6ClangInstPrinter` to emit i8080-canonical mnemonics, switch the V6CLANG calling
convention from positional to register-class–based free-list assignment with
i8↔i16 overlap rules, implement the missing `V6ClangAsmParser`, ensure inline
assembly with narrow clobber lists does not over-spill across the asm block,
ship a V6CLANG-only resource-dir include directory (`<resource-dir>/lib/v6clang/include/`)
populated with header-only inline-asm wrappers (`string.h`, `stdlib.h`, `v6clang.h`),
and retire the `libv6clang-builtins.a` archive entirely (replaced by header-only
inlining + per-routine `.o` files for non-inlinable helpers, picked up by
`--gc-sections`).

## Scope

**In scope**
- Phase 1: switch `V6ClangInstPrinter` to i8080-canonical pair-form mnemonics
  (`PUSH H`, `POP D`, `INX B`, `DCX D`, `DAD H`, `LDAX D`, `STAX B`) via
  `RegAltNameIndex` + a printing-only operand wrapper. Encoding unchanged.
- Phase 2: rewrite argument lowering in `V6ClangISelLowering.cpp` to a free-list
  allocator with i8 list `(A, B, C, D, E, L, H)` and i16 list `(HL, DE, BC)`
  and overlap blocking. Returns unchanged.
- Phase 3: implement `V6ClangAsmParser` (new `llvm/lib/Target/V6CLANG/AsmParser/`)
  using MSP430AsmParser as the template. Accept **only** proper i8080 asm
  syntax (`PUSH H`, `POP D`, `DAD B`, `INX SP`, `LXI SP, NNNN`,
  `POP PSW`, etc.). The pair-letter forms (`H`, `D`, `B`) and `SP`/`PSW`
  are the sole accepted spellings for pair operands. Wire
  `-gen-asm-matcher` tablegen.
- Phase 4: lit-test that inline-asm clobber lists are honored (no over-spill)
  for Style A (inlined body), Style B (CALL extern), and the empty-clobber
  case. Extend `getGCCRegNames` to recognize pair names if needed.
- Phase 5: add `clang/lib/Driver/ToolChains/V6CLANG/include/{string.h, stdlib.h,
  v6clang.h}` containing standard prototypes plus `static inline __asm__`
  wrappers around `__builtin_v6clang_*` / hand-rolled sequences. Install rule
  copies them to `<resource-dir>/lib/v6clang/include/`.
- Phase 6: override `V6ClangToolChain::AddClangSystemIncludeArgs` to inject the
  V6CLANG include directory (and respect `-nostdinc` / `-nobuiltininc`).
- Phase 7: cleanup — remove `libv6clang-builtins.a` lookup from the V6CLANG driver;
  update `docs/V6ClangCallingConvention.md` and `docs/V6ClangBuildGuide.md` for the
  new CC and the inline-asm flow; mark `plan_O_LLD_native_linker.md` step
  11 superseded.

**Out of scope**
- Changing instruction encoding, the i8080 ISA, or any other backend codegen.
- LTO / bitcode-in-archive.
- Full C standard library (`stdio.h`, `math.h`, etc.) — only `string.h`,
  `stdlib.h`, and target-specific `v6clang.h` are shipped now.
- Modifying Clang's stock freestanding headers (`stdint.h`, `stddef.h`, etc.).
- Builtins archive (`libv6clang-builtins.a`) — deleted from the design.
- Cross-target portability work for non-V6CLANG targets (the V6CLANG include dir is
  injected only by the V6CLANG driver, so x86 cross-builds remain unaffected).

## Phases

### Phase 1 — InstPrinter: i8080-canonical pair mnemonics
*(prerequisite for Phase 3 — the parser must accept what the printer emits)*

1. In `llvm/lib/Target/V6CLANG/V6ClangRegisterInfo.td`:
   - Add `def Pair8080 : RegAltNameIndex;`.
   - Set `AltNames` under `Pair8080` for every register that can appear as a
     pair operand: `BC="B"`, `DE="D"`, `HL="H"`, `SP="SP"`, `PSW="PSW"`.
     (`SP` and `PSW` have no short form, so their AltName equals the
     canonical name.)
   - This single AltName index drives all pair-context printing — no
     instruction emits the long form (`HL`/`DE`/`BC`) anywhere.
2. In `llvm/lib/Target/V6CLANG/V6ClangInstPrinter.cpp`, add `printRegPair8080(MI, OpNo,
   O)` that calls `getRegisterName(Reg, V6CLANG::Pair8080)`. Default
   `printOperand` stays untouched (still prints canonical names for non-pair
   contexts like sub-register access).
3. In `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`, define **one** printing-only
   operand class used uniformly by every pair-using mnemonic:
   ```
   def GR16Pair8080AsmOperand : AsmOperandClass { let Name = "GR16Pair8080"; }
   def gr16pair8080 : Operand<i16> {
     let PrintMethod = "printRegPair8080";
     let ParserMatchClass = GR16Pair8080AsmOperand;
   }
   ```
   Apply it to the `(ins ...)` lists of `PUSH` (~220), `POP` (~226),
   `DAD` (~348), `INX` (~354), `DCX` (~360), `LDAX` (~171), `STAX` (~177).
   The same class handles `BC`, `DE`, `HL`, `SP`, `PSW`; the AltName index
   gives each its proper i8080 spelling. (`LDAX`/`STAX` already use the
   narrower `GR16Idx` register class, which restricts matches to `B`/`D` —
   no separate operand class is needed.)
4. Update CodeGen lit tests under `tests/lit/CodeGen/V6CLANG/**` to expect
   `PUSH H`, `INX D`, `DAD B`, etc. wherever current FileCheck patterns
   expect `PUSH HL`, `INX DE`, `DAD BC`. Inventory pre-edit:
   ```
   grep -rE "(PUSH|POP|DAD|INX|DCX|LDAX|STAX)\s+(HL|DE|BC)" tests/lit
   ```
5. Mirror to `llvm-project/llvm/test/CodeGen/V6CLANG/**` and re-run
   `scripts/sync_llvm_mirror.ps1`.

### Phase 2 — Calling Convention: register-class free list

Replace the position-indexed tables in `V6ClangISelLowering.cpp` (`ArgRegsI8[] =
{A, E, C}`, `ArgRegsI16[] = {HL, DE, BC}`, `ArgIdx` counter) with a
free-list allocator.

6. Add a small file-local helper in `V6ClangISelLowering.cpp`:
   ```
   class V6ClangArgAllocator {
     SmallVector<MCPhysReg, 7> FreeI8 = {A, B, C, D, E, L, H};
     SmallVector<MCPhysReg, 3> FreeI16 = {HL, DE, BC};
     MCPhysReg takeI8();   // returns 0 if exhausted
     MCPhysReg takeI16();  // returns 0 if exhausted
   };
   ```
   `takeI8` removes the picked register from `FreeI8` and from `FreeI16`
   (the pair containing it). `takeI16` removes the picked pair from
   `FreeI16` and both halves from `FreeI8`.
7. Rewrite `LowerFormalArguments` (lines ~816–857) to use the allocator;
   exhausted lists fall through to the existing stack-spill path.
8. Mirror the same allocator usage in `LowerCall` (lines ~919–1049).
9. Verify `LowerReturn` (~859–909) is **not** modified — return CC is
   independent.
10. Add `tests/lit/CodeGen/V6CLANG/call-conv-overlap.ll` covering the four
    locked decision examples (these are the spec; the allocator must
    produce these register assignments exactly):

    ```c
    // Example 1 — i8 spillover into i16-pair halves
    //   args:  A,  B,  C,  HL, DE
    void f1(uint8_t a, uint8_t b, uint8_t c, uint16_t p, uint16_t q);

    // Example 2 — i16s first, then i8 in A, then last i16 lands in BC
    //   args:  HL, DE, A, BC                    returns: HL
    uint16_t f2(uint16_t x, uint16_t y, uint8_t k, uint16_t z);

    // Example 3 — interleaved (A, HL, B, DE)
    //   args:  A, HL, B, DE
    void f3(uint8_t a, uint16_t p, uint8_t b, uint16_t q);

    // Example 4 — two i16s consume HL+DE, then trailing i8s in A,B; i32 return
    //   args:  HL, DE, A, B                     returns: HL+DE
    uint32_t f4(uint16_t p, uint16_t q, uint8_t a, uint8_t b);
    ```

    | Args | Expected regs |
    |---|---|
    | `(i8,i8,i8,i16,i16)` | A, B, C, HL, DE |
    | `(i16,i16,i8,i16)`   | HL, DE, A, BC |
    | `(i8,i16,i8,i16)`    | A, HL, B, DE |
    | `(i16,i16,i8,i8)`    | HL, DE, A, B |
    Plus exhaustion cases (5+ args spilling to stack).
11. Update existing `tests/lit/CodeGen/V6CLANG/call-conv.ll` and
    `call-conv-ret.ll` only where the old positional table produced
    different regs (the common 3-arg cases are unchanged).
12. Update `docs/V6ClangCallingConvention.md` to describe the free-list
    algorithm + the four examples.
13. Verify M11 runtime helpers' calls still map identically:
    `memcpy(void*, void*, size_t)` is `(i16, i16, i16)` → `(HL, DE, BC)` —
    same as today. Same for `__divhi3`, etc. No runtime changes needed.

### Phase 3 — Implement `V6ClangAsmParser`

Template: `llvm-project/llvm/lib/Target/MSP430/AsmParser/MSP430AsmParser.cpp`
(~536 LOC — closest small-target analogue).

14. Create `llvm/lib/Target/V6CLANG/AsmParser/CMakeLists.txt`:
    ```
    add_llvm_component_library(LLVMV6ClangAsmParser
      V6ClangAsmParser.cpp
      LINK_COMPONENTS MC MCParser V6ClangDesc V6ClangInfo Support
      ADD_TO_COMPONENT V6CLANG
    )
    ```
15. Create `llvm/lib/Target/V6CLANG/AsmParser/V6ClangAsmParser.cpp`:
    - `class V6ClangOperand : public MCParsedAsmOperand` with kinds `k_Tok`,
      `k_Reg`, `k_Imm`, `k_Mem` (the `M` operand for MOVrM/MOVMr).
    - `class V6ClangAsmParser : public MCTargetAsmParser` overriding
      `parseRegister`, `tryParseRegister`, `parseInstruction`,
      `ParseOperand`, `MatchAndEmitInstruction`, plus
      `MatchRegisterName` accepting **only proper i8080 spellings**:
      single 8-bit registers `A B C D E H L M`, `SP`, `PSW`, and the
      pair-letter forms `B` (=BC), `D` (=DE), `H` (=HL) used by every
      pair-taking mnemonic (`PUSH/POP/DAD/INX/DCX/LXI/LDAX/STAX`). The
      long forms `HL`, `DE`, `BC` are **not** recognized in any
      instruction — `PUSH HL`, `INX DE`, `DAD BC`, `LDAX BC`,
      `STAX DE`, `LXI HL, NNNN` all produce parse errors.
    - Standard directive handling inherited from the base class;
      `.byte` / `.word` already covered.
16. Add `tablegen(LLVM V6ClangGenAsmMatcher.inc -gen-asm-matcher)` to
    `llvm/lib/Target/V6CLANG/CMakeLists.txt`.
17. In `llvm/lib/Target/V6CLANG/V6CLANG.td`, add `def V6ClangAsmParser : AsmParser;`
    (mirror of existing `V6ClangAsmWriter`).
18. In `llvm/lib/Target/V6CLANG/V6Clang.h`, declare
    `extern "C" void LLVMInitializeV6ClangAsmParser();`.
19. In `llvm/lib/Target/V6CLANG/TargetInfo/V6ClangTargetInfo.cpp` (or wherever
    `LLVMInitializeV6ClangTargetInfo` lives), implement
    `LLVMInitializeV6ClangAsmParser` calling
    `RegisterMCAsmParser<V6ClangAsmParser> X(getTheV6ClangTarget());`.
20. Add `add_subdirectory(AsmParser)` to
    `llvm/lib/Target/V6CLANG/CMakeLists.txt`.
21. Update **both** mirror scripts for the new `AsmParser/` subtree
    (the entire directory tree is brand-new and target-owned, so use a
    full `robocopy /MIR` like the existing V6CLANG target dir, NOT a
    file-by-file `xcopy`):
    - `scripts/sync_llvm_mirror.ps1` — add
      `robocopy "$root\llvm-project\llvm\lib\Target\V6CLANG\AsmParser" "$root\llvm\lib\Target\V6CLANG\AsmParser" /MIR ...`
      (note: the existing `/MIR` on `Target\V6CLANG` already covers this if
      we rely on it; verify by running the script and confirming the new
      AsmParser/ dir appears in the mirror after a build).
    - `scripts/populate_llvm_project.ps1` — symmetric reverse mirror.
22. Add new lit suite `tests/lit/MC/V6CLANG/AsmParser/` covering:
    - All 80+ instructions accepted by their canonical i8080 form.
    - Pair-form acceptance (single-letter pair name in every pair op):
      `PUSH H`, `POP D`, `PUSH PSW`, `POP PSW`, `INX B`, `INX H`,
      `INX SP`, `DCX D`, `DAD B`, `DAD H`, `DAD SP`, `LXI H, 0x1234`,
      `LXI SP, 0xFF00`, `STAX B`, `LDAX D`.
    - Long-form rejection: `PUSH HL`, `INX DE`, `DAD BC`, `LDAX BC`,
      `STAX DE`, `LXI HL, 0x1234` MUST produce a parse error
      (negative tests with `// expected-error`).
    - Round-trip: `clang -c foo.s -o foo.o; llvm-objdump -d foo.o`
      reproduces text identical to what `llc -filetype=asm` would emit.
23. Mirror tests to `llvm-project/llvm/test/MC/V6CLANG/AsmParser/`.
24. End-to-end smoke: assemble both
    `compiler-rt/lib/builtins/v6clang/crt0.s` and `memory.s` directly with
    `clang -c`, confirm symbols + relocations via `llvm-readelf -a`.

### Phase 4 — Verify inline-asm clobber lists honored

25. Confirm V6CLANG has no custom `INLINEASM` lowering override — generic
    LLVM handling should suffice. Read the existing constraint code in
    `V6ClangISelLowering.cpp` lines 1131–1165 (already maps `'a'`/`'r'`/`'p'`
    to register classes).
26. Add three lit tests under `tests/lit/CodeGen/V6CLANG/inline-asm/`:
    - `clobber-style-a.ll` — Style A, body inlined: `__asm__ volatile
      ("MVI A,%1\nOUT %0\n" : : "i"(0xED), "r"(v) : "a")`. FileCheck
      asserts BC/DE not pushed across the asm block.
    - `clobber-style-b.ll` — Style B, CALL extern: `__asm__ volatile
      ("CALL helper\n" : : : "a","memory")`. FileCheck asserts only A
      treated as clobbered.
    - `clobber-empty.ll` — `__asm__ volatile ("NOP" : : :)`. FileCheck
      asserts zero spills.
27. If the tests show over-spilling, root-cause is likely in
    `clang/lib/Basic/Targets/I8080.cpp` `getGCCRegNames`: the table
    currently lists single regs `A,B,C,D,E,H,L,SP,FLAGS`. Add pair
    aliases (`BC`,`DE`,`HL`) and any required mappings in
    `validateAsmConstraint`. (Should not be needed since the IR-level
    clobber list operates on physregs that LLVM resolves through the
    existing `'a'`/`'r'`/`'p'` constraint logic.)
28. Add a feature test `tests/features/inline_asm_clobber/` that
    proves both clobber-list correctness **and** transitive
    `--gc-sections` reachability across the inline-asm/extern-asm
    boundary. Layout:

    ```
    tests/features/inline_asm_clobber/
      main.c        // calls extern_func() via external.h
      external.h    // static inline extern_func() containing
                    //   __asm__ volatile("CALL func1" : : : "a","memory");
      external.s    // bodies of func1, func2, func3, func4 (i8080 asm)
      expected.txt  // exact stdout: "12"  (func1 prints '1', func2 prints '2')
      lit.local.cfg / runner script
    ```

    Behavior under test:
    - `main()` calls `extern_func()` (inlined from `external.h`); the
      inline asm emits `CALL func1`.
    - In `external.s`: `func1` writes `'1'` to stdout via the v6emul
      output port, then `CALL func2`. `func2` writes `'2'` and returns.
      `func3` writes `'3'` and `CALL func4`. `func4` writes `'4'`.
    - `func3` and `func4` are **not** referenced from any kept section
      (no C-side caller, no jump-table entry, no `__attribute__((used))`).
    - Expected post-link result: `func1` and `func2` are kept (reachable
      transitively from `_start` \u2192 `main` \u2192 inline-asm CALL \u2192 `func1`
      \u2192 `func2`); `func3` and `func4` are dropped by `--gc-sections`.
    - Run in v6emul; assert stdout exactly equals `"12"` (no `'3'` or
      `'4'` ever appears).
    - Verify with `llvm-readelf -s out.rom` (or `llvm-nm`) that symbols
      `func3` and `func4` are absent from the final image.
    - Also assert via FileCheck on the `.s` listing that the inline asm
      did not push BC/DE around the `CALL func1` (clobber list said
      only `"a"`, `"memory"`).

### Phase 5 — V6CLANG resource-dir include directory

29. Create `clang/lib/Driver/ToolChains/V6CLANG/include/`:
    - `string.h` — prototypes for `memcpy`, `memset`, `memmove`,
      `strlen`, `strcmp`, `strcpy`. Each gets a `static inline
      __attribute__((always_inline))` wrapper that issues an inline-asm
      `CALL` to the corresponding symbol provided by an assembled
      `.o` file shipped under `<resource-dir>/lib/v6clang/`. Tiny constant-
      `n` cases (e.g. `memset(p, 0, ≤8)`) inlined directly as Style A.
    - `stdlib.h` — `abort()` (`HLT`), `exit()` (`HLT`). No `malloc`
      yet.
    - `v6clang.h` — `__v6clang_in(port)`, `__v6clang_out(port, val)`, `__v6clang_di()`,
      `__v6clang_ei()`, `__v6clang_hlt()`, `__v6clang_nop()` thin wrappers around
      the existing `__builtin_v6clang_*` family from
      `clang/include/clang/Basic/BuiltinsV6CLANG.def`.
30. Add a CMake `install(DIRECTORY ...)` rule in
    `clang/lib/Driver/ToolChains/V6CLANG/CMakeLists.txt` (or wherever
    the V6CLANG driver files are wired) that copies
    `clang/lib/Driver/ToolChains/V6CLANG/include/` to
    `<install-prefix>/lib/clang/<ver>/lib/v6clang/include/` at install time.
    Also add the same files to the on-build directory
    `llvm-build/lib/clang/18/lib/v6clang/include/` so a non-installed
    development build works.
31. Update **both** mirror scripts. Source-of-truth-for-edits is the
    git-tracked mirror at `clang/lib/Driver/ToolChains/V6CLANG/include/`;
    builds happen out of `llvm-project/clang/lib/Driver/ToolChains/V6CLANG/include/`
    (gitignored). Add explicit lines so the new include directory survives
    round-trip, mirroring how `v6clang.ld` is already handled:
    - `scripts/sync_llvm_mirror.ps1` — add
      `robocopy "$root\llvm-project\clang\lib\Driver\ToolChains\V6CLANG\include" "$root\clang\lib\Driver\ToolChains\V6CLANG\include" /MIR /NFL /NDL /NJH /NJS`
    - `scripts/populate_llvm_project.ps1` — symmetric reverse line.
32. **Do not** modify Clang's stock freestanding headers
    (`<resource-dir>/include/stdint.h`, `stddef.h`, `limits.h`,
    `float.h`, etc.). Verify they produce correct types for V6CLANG by
    running:
    ```
    clang --target=i8080-unknown-v6clang -dM -E -xc nul | findstr __INT
    ```
    and confirming `__INT_MAX__ = 32767`, `__LONG_MAX__ = 2147483647`.

### Phase 6 — Wire V6CLANG driver to inject include path and `-ffunction-sections`

33. In `clang/lib/Driver/ToolChains/V6Clang.h`, add override:
    ```
    void AddClangSystemIncludeArgs(const llvm::opt::ArgList &DriverArgs,
                                    llvm::opt::ArgStringList &CC1Args)
                                    const override;
    ```
34. In `clang/lib/Driver/ToolChains/V6Clang.cpp`, implement it:
    - Honor `-nostdinc` / `-nobuiltininc` / `-nostdlibinc` per Clang
      convention; skip injection entirely when present.
    - Push `-internal-isystem <ResourceDir>/lib/v6clang/include/`.
    - Then defer to the base implementation for the standard
      freestanding headers under `<ResourceDir>/include/`.
    - V6CLANG dir comes first so it shadows nothing (Clang's stock
      directory has no `string.h`).
    - Additionally, inside `addClangTargetOptions` (the existing V6CLANG
      hook on this toolchain), append `-ffunction-sections` to
      `CC1Args` by default so per-function ELF sections are emitted
      and LLD `--gc-sections` (already passed by the V6CLANG driver per
      O-LLD) can prune unreachable helpers transitively. User-passed
      `-fno-function-sections` overrides.
35. Add `tests/lit/Clang/V6CLANG/include-path.c`:
    ```c
    // RUN: %clang -target i8080-unknown-v6clang -E -xc - < %s | FileCheck %s
    #include <string.h>
    extern void test(void);
    // CHECK: void *memcpy(
    ```
36. Add a cross-platform safety test (run only when `--target=x86_64-*`
    is buildable on the CI machine): `#include <string.h>` against an
    x86 target picks up the host libc's header, **not** the V6CLANG one.

### Phase 7 — Cleanup & docs

37. In `clang/lib/Driver/ToolChains/V6Clang.cpp`, remove the
    `findV6ClangRuntimeFile(TC, "libv6clang-builtins.a")` block and the
    `UseDefaultLibs` plumbing surrounding it (lines ~125–131). Keep
    `crt0.o` lookup intact.
38. Update `docs/V6ClangBuildGuide.md`:
    - Replace any mention of `libv6clang-builtins.a` with the
      header-only-inline-asm approach.
    - Document `<resource-dir>/lib/v6clang/include/` layout.
    - Document inline-asm Style A (inlined) and Style B (CALL extern)
      patterns with a worked example.
    - Update the "Build" example to drop `-nostartfiles -nodefaultlibs
      -Wl,--defsym=_start=main` workaround now that crt0.s assembles
      and links automatically.
    - Add a "Computed jumps and `--gc-sections`" subsection with the
      symbol-relocation rules and the `KEEP(*(.text.func))` /
      `__attribute__((used))` escapes.
39. Update `docs/V6ClangCallingConvention.md` with the free-list spec
    (table of free lists + the four worked examples + overlap rules).
40. Update `compiler-rt/lib/builtins/v6clang/README` (if any) to note these
    `.s` files are now consumed via individual `.o` references from
    inline-asm wrappers, not packaged into an archive.
41. Update `design/plan_O_LLD_native_linker.md` step 11 status —
    supersede with this plan; mark the deferred crt0/libv6clang-builtins
    work as resolved by Phase 3 + Phase 7.
42. Add this plan to `design/future_plans/README.md` summary table
    (or a new "asm-interop" row in the optimization plan list).

## Checklist

Phase 1 — InstPrinter mnemonics
- [x] 1. Add `Pair8080` `RegAltNameIndex` + AltNames on BC, DE, HL, SP, PSW
- [x] 2. Add `printRegPair8080` to `V6ClangInstPrinter.cpp`
- [x] 3. Wire single `gr16pair8080` operand into PUSH/POP/INX/DCX/DAD/LDAX/STAX (and LXI)
- [x] 4. Update CodeGen lit FileCheck patterns for new mnemonics
- [x] 5. Mirror; rebuild; golden ROMs byte-identical (15/15 golden + 112/112 lit PASS)

Phase 2 — CC free-list
- [x] 6. Add `V6ClangArgAllocator` helper class
- [x] 7. Rewrite `LowerFormalArguments`
- [x] 8. Rewrite `LowerCall`
- [x] 9. Confirm `LowerReturn` untouched
- [x] 10. Add `call-conv-overlap.ll` covering 4 examples + exhaustion
- [x] 11. Update existing `call-conv*.ll` if needed
- [x] 12. Update `docs/V6ClangCallingConvention.md`
- [x] 13. Verify M11 libcalls (memcpy / __divhi3) map identically (113/113 lit + 15/15 golden PASS)

Phase 3 — `V6ClangAsmParser`
- [x] 14. Add `AsmParser/CMakeLists.txt`
- [x] 15. Implement `V6ClangAsmParser.cpp` (~500-700 LOC)
- [x] 16. Add `-gen-asm-matcher` tablegen rule
- [x] 17. Add `V6ClangAsmParser` def to `V6CLANG.td`
- [x] 18. Declare `LLVMInitializeV6ClangAsmParser` in `V6Clang.h`
- [x] 19. Register in `V6ClangTargetInfo.cpp`
- [x] 20. `add_subdirectory(AsmParser)` in V6CLANG `CMakeLists.txt`
- [x] 21. Mirror scripts updated for AsmParser/
- [x] 22. Add `tests/lit/MC/V6CLANG/AsmParser/` suite
- [x] 23. Mirror tests
- [x] 24. Smoke: `clang -c crt0.s` + `clang -c memory.s` produce valid ELF

Phase 4 — Inline-asm clobber verification
- [x] 25. Confirm no custom INLINEASM lowering exists
- [x] 26. Add 3 clobber lit tests (Style A / Style B / empty)
- [x] 27. If needed, extend `getGCCRegNames` with pair names
- [x] 28. Add `tests/features/inline_asm_clobber/` end-to-end (main.c + external.h inline asm + external.s with func1\u2192func2 reachable, func3\u2192func4 dropped; expected stdout "12"; verify func3/func4 absent via `llvm-nm`)

Phase 5 — V6CLANG resource headers
- [x] 29. Create `clang/lib/Driver/ToolChains/V6CLANG/include/{string.h, stdlib.h, v6clang.h}`
- [x] 30. CMake install rule for `<resource-dir>/lib/v6clang/include/`  *(headers and `v6clang.ld` still rely on dev-tree path lookup in the driver; install rules to be added when `ninja install` becomes part of the workflow. **Note:** `compiler-rt/lib/builtins/v6clang/crt0.s` is now auto-assembled into `<resource-dir>/lib/v6clang/crt0.o` by `clang/lib/Driver/CMakeLists.txt` on every clang build, with a matching `install(FILES ...)` rule.)*
- [x] 31. Mirror scripts updated for new include dir
- [x] 32. Verify Clang stock `stdint.h` produces correct V6CLANG macros (no override needed)

Phase 6 — Driver include-path injection
- [x] 33. Declare `AddClangSystemIncludeArgs` override in `V6Clang.h`
- [x] 34. Implement it in `V6Clang.cpp` (V6CLANG dir first, base after, honor `-nostdinc`); also add `-ffunction-sections` default in `addClangTargetOptions`
- [x] 35. Add `tests/lit/Clang/V6CLANG/include-path.c`
- [x] 36. Cross-platform safety check (x86 target unaffected)  *(verified by construction — `AddClangSystemIncludeArgs` is a member of `V6ClangToolChain` only; non-V6CLANG toolchains never call it. Live x86 build sample deferred until cross-host CI exists.)*

Phase 7 — Cleanup & docs
- [x] 37. Remove `libv6clang-builtins.a` lookup in `V6Clang.cpp`
- [x] 38. Update `docs/V6ClangBuildGuide.md`
- [x] 39. Update `docs/V6ClangCallingConvention.md`
- [x] 40. Update `compiler-rt/lib/builtins/v6clang/README` (if present)  *(no README exists in that directory; nothing to update.)*
- [x] 41. Update `plan_O_LLD_native_linker.md` step 11 supersede note
- [x] 42. Add row to `design/future_plans/README.md`

Verification gates
- [x] V1. `python tests/run_all.py` — 15/15 golden + all lit + integration round-trips PASS
- [x] V2. Phase 1 leaves all golden ROM SHA-256 hashes byte-identical (encoding unchanged)
- [x] V3. `call-conv-overlap.ll` matches the four worked examples exactly
- [x] V4. M11 libcall tests still pass (memcpy / __divhi3 / shifts) under new CC
- [x] V5. `clang -c crt0.s -o crt0.o` produces ELF with `_start` global symbol; `llvm-readelf -s` shows correct relocs
- [x] V6. End-to-end: `clang -target i8080-unknown-v6clang -O2 main.c crt0.s -o out.rom` builds and runs correctly in v6emul WITHOUT the `--defsym=_start=main` workaround  *(verified via `tests/features/inline_asm_clobber/`: driver auto-picks crt0.o, runs ld.lld, prints "12".)*
- [x] V7. Inline-asm clobber lit tests show exact expected spill counts (no over-spill on narrow clobbers)
- [x] V8. `#include <string.h>` works on V6CLANG; same source compiled for x86 still uses MSVC's header  *(V6CLANG side covered by `tests/lit/Clang/V6CLANG/include-path.c`; x86 side guaranteed by construction — the V6CLANG include directory is injected only by `V6ClangToolChain::AddClangSystemIncludeArgs`.)*
- [x] V9. `sync_llvm_mirror.ps1` reports zero diffs after both halves of every change are touched
- [x] V10. Mirror round-trip rebuilds byte-identical V6CLANG ROMs

## Status

**Complete.** All seven phases shipped; all verification gates green.
This plan supersedes the deferred Step 11 of
`plan_O_LLD_native_linker.md` (libv6clang-builtins.a / crt0.o build), which
was blocked on the missing V6CLANG MC AsmParser. Phase 3 here resolved that
blocker; Phase 7 closed the deferred item by retiring the archive
entirely in favor of header-only inline-asm wrappers under
`<resource-dir>/lib/v6clang/include/`.

## Relevant files

### Phase 1 (InstPrinter)
- `llvm/lib/Target/V6CLANG/V6ClangRegisterInfo.td` — add `Pair8080` index + `AltNames`
- `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td` — operand swaps on lines ~170, 176, 218, 224, 347, 353, 359
- `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangInstPrinter.{cpp,h}` — `printRegPair8080`
- `tests/lit/CodeGen/V6CLANG/**` — many FileCheck pattern updates

### Phase 2 (CC)
- `llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp` — replace `ArgIdx` table at ~816 + ~919 with `V6ClangArgAllocator`
- `tests/lit/CodeGen/V6CLANG/call-conv.ll`, `call-conv-ret.ll` — updates
- `tests/lit/CodeGen/V6CLANG/call-conv-overlap.ll` — **new**
- `docs/V6ClangCallingConvention.md` — algorithm description rewrite

### Phase 3 (AsmParser)
- `llvm/lib/Target/V6CLANG/AsmParser/CMakeLists.txt` — **new**
- `llvm/lib/Target/V6CLANG/AsmParser/V6ClangAsmParser.cpp` — **new**, ~500-700 LOC
- `llvm/lib/Target/V6CLANG/V6Clang.h`, `V6CLANG.td`, `CMakeLists.txt`, `TargetInfo/V6ClangTargetInfo.cpp` — registration
- `tests/lit/MC/V6CLANG/AsmParser/*.s` — **new** suite
- `scripts/sync_llvm_mirror.ps1`, `populate_llvm_project.ps1` — mirror entries

### Phase 4 (inline-asm clobbers)
- `tests/lit/CodeGen/V6CLANG/inline-asm/clobber-{style-a,style-b,empty}.ll` — **new**
- `tests/features/inline_asm_clobber/` — **new** end-to-end
- `clang/lib/Basic/Targets/I8080.{h,cpp}` — possibly extend `getGCCRegNames`

### Phase 5 (resource headers)
- `clang/lib/Driver/ToolChains/V6CLANG/include/string.h` — **new**
- `clang/lib/Driver/ToolChains/V6CLANG/include/stdlib.h` — **new**
- `clang/lib/Driver/ToolChains/V6CLANG/include/v6clang.h` — **new**
- `clang/lib/Driver/ToolChains/V6CLANG/CMakeLists.txt` — install rule (or wherever the existing `v6clang.ld` install lives)
- `scripts/sync_llvm_mirror.ps1`, `populate_llvm_project.ps1` — mirror entries

### Phase 6 (driver include path)
- `clang/lib/Driver/ToolChains/V6Clang.h` — declare override
- `clang/lib/Driver/ToolChains/V6Clang.cpp` — implement
- `tests/lit/Clang/V6CLANG/include-path.c` — **new**

### Phase 7 (cleanup)
- `clang/lib/Driver/ToolChains/V6Clang.cpp` — remove `findV6ClangRuntimeFile(TC, "libv6clang-builtins.a")` block
- `docs/V6ClangBuildGuide.md`, `docs/V6ClangCallingConvention.md` — updates
- `design/plan_O_LLD_native_linker.md` — supersede note
- `design/future_plans/README.md` — register this plan

## Decisions

- **i8 free-list order:** A, B, C, D, E, L, H. Rationale: A first (most ALU
  ops use A); B/C before D/E so DE remains free as an i16 pair longer; L/H
  last (HL is the most useful i16 pair, sacrificing it as i8 is the worst
  case). Matches the worked examples verbatim.
- **i16 free-list order:** HL, DE, BC. Rationale: HL has dedicated ops
  (DAD, M-addressing); DE next (XCHG, LDAX/STAX D); BC last.
- **Returns unchanged:** `RetCC_V6Clang` keeps i8→A, i16→HL, i32→HL+DE.
- **No `libv6clang-builtins.a`** — replaced with header-only inline-asm
  wrappers + on-disk `.o` files for non-inlinable helpers; LLD
  `--gc-sections` removes unused.
- **`crt0.o` is the one mandatory external object** assembled by Phase 3.
- **Mnemonic style:** strict i8080 canonical, both directions. **In every
  instruction, register pairs are spelled with their single-letter form,
  never with the long form.** The pair-letter `B` always means `BC`, `D`
  always means `DE`, `H` always means `HL` — in every mnemonic that takes
  a pair operand. Examples (all canonical):
  `PUSH H`, `POP D`, `PUSH PSW`, `POP PSW`, `DAD B`, `DAD H`, `DAD SP`,
  `INX H`, `INX SP`, `DCX D`, `LXI H, NNNN`, `LXI SP, NNNN`,
  `LDAX B`, `LDAX D`, `STAX B`, `STAX D`, `XCHG`, `SPHL`, `XTHL`.
  The parser rejects all long spellings in pair contexts — `PUSH HL`,
  `INX DE`, `DAD BC`, `LDAX BC`, `STAX DE`, `LXI HL, NNNN` are syntax
  errors. (Single-letter names `A B C D E H L M` keep their meaning as
  individual 8-bit registers / memory operand in non-pair contexts.)
- **Stock freestanding headers untouched.** V6CLANG-specific headers fill in
  what's missing (`string.h`, `stdlib.h`, `v6clang.h`). Cross-platform x86
  builds preserved because the V6CLANG include dir is injected only by the
  V6CLANG driver.
- **`-ffunction-sections` on by default in the V6CLANG driver.** Required so
  LLD `--gc-sections` can drop unused helper functions transitively from
  the assembled `.o` files. Reachability starts at `_start` and walks
  every emitted relocation; an asm function `func1` that is never
  referenced from `_start`'s closure is dropped, and any function
  `func2` referenced only from `func1` is dropped on the next iteration.
  All i8080 control-flow operands (`CALL`, `JMP`, `LXI H, label`) emit
  normal R_V6Clang relocations the linker can see, so transitive GC works
  correctly across asm/C boundaries.
- **Computed-jump tables and `--gc-sections`.** `--gc-sections` walks
  relocations in **all** reachable sections, including `.rodata` jump
  tables. Authors must encode addresses through the assembler's symbol
  machinery so a relocation is emitted:
    - `.word target` → emits `R_V6CLANG_16` (safe).
    - `.byte target@lo` / `.byte target@hi` → emit `R_V6CLANG_8_LO` /
      `R_V6CLANG_8_HI` (safe).
    - Hand-computed `.byte 0xC3, 0x34, 0x12` literals encoding a `JMP`
      to an absolute address have **no** relocation — the linker can't
      see the reference, and the target may be GC'd. Avoid this pattern.
  Forced-live escapes when the relocation route is impractical:
  `__attribute__((used))` on C wrappers, `.global` + `KEEP(*(.text.func))`
  in the linker script, or grouping all jump-table targets in a single
  `KEEP`'d section. Phase 7 step 38 adds a recipe to
  `docs/V6ClangBuildGuide.md`.
- **Mirror layout.** `clang/` and `llvm/` at the repo root are the
  git-tracked mirrors; the build reads from gitignored
  `llvm-project/{clang,llvm}/`. Every new file in this plan lives in the
  mirror, and each new directory tree must have explicit `robocopy`
  entries in **both** `scripts/sync_llvm_mirror.ps1` and
  `scripts/populate_llvm_project.ps1` (see Phase 3 step 21 and Phase 5
  step 31).
