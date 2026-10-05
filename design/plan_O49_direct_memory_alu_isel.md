# Plan: O49 — Direct Memory ALU/Store ISel (M-Operand Instructions)

Supersedes O4 (ADD M / SUB M peephole, rejected) and O46 (MVI M ISel).

## 1. Problem

### Current behavior

The 8080 has 11 instructions that operate directly on memory through
`[HL]` without going through a register. All of them have empty ISel
patterns (`[]`) in `V6ClangInstrInfo.td` and are never selected by LLVM:

| Instruction | Opcode | Current codegen | Redundant cost |
|-------------|--------|-----------------|----------------|
| `ADD M` | 0x86 | `MOV r, M; ADD r`   | 4cc + 1B |
| `ADC M` | 0x8E | `MOV r, M; ADC r`   | 4cc + 1B |
| `SUB M` | 0x96 | `MOV r, M; SUB r`   | 4cc + 1B |
| `SBB M` | 0x9E | `MOV r, M; SBB r`   | 4cc + 1B |
| `ANA M` | 0xA6 | `MOV r, M; ANA r`   | 4cc + 1B |
| `ORA M` | 0xB6 | `MOV r, M; ORA r`   | 4cc + 1B |
| `XRA M` | 0xAE | `MOV r, M; XRA r`   | 4cc + 1B |
| `CMP M` | 0xBE | `MOV r, M; CMP r`   | 4cc + 1B |
| `MVI M` | 0x36 | `MVI A,imm; MOV M,A`| 5cc + 1B |
| `INR M` | 0x34 | `MOV A,M; INR A; MOV M,A` | 8cc + 2B |
| `DCR M` | 0x35 | `MOV A,M; DCR A; MOV M,A` | 8cc + 2B |

A representative fragment:

```asm
; Current:
LXI  HL, __v6clang_ss.acc
MOV  L, M          ;  7cc, 1B — load *HL into L
ADD  L             ;  4cc, 1B — A += L
```

### Desired behavior

```asm
; With O49:
LXI  HL, __v6clang_ss.acc
ADD  M             ;  8cc, 1B — A += *HL directly
```

The combined `ADD M` form saves 4cc and 1B per accumulator folded into
a direct memory operand, and larger savings for `INR M / DCR M`.

### Root cause

The ALU/INR/DCR/MVI M-variant instructions exist in `V6ClangInstrInfo.td`
but without DAG patterns. ISel therefore materialises values into
registers and uses the register-variant of each ALU op. A post-RA
peephole cannot safely rewrite `MOV r, M; ALU r` into `ALU M` because
cross-block liveness is not visible and kill flags are unreliable —
the approach explored in (rejected) O4.

ISel-level pattern matching avoids those pitfalls entirely: the load is
folded into the ALU op at the DAG level, and no intermediate register
is ever allocated for the loaded byte.

---

## 2. Strategy

### Approach: 11 new pseudos + shared post-RA expansion helper

Each M-operand instruction becomes a pseudo that takes a `GR16:$addr`
pointer operand in addition to its normal operands. The DAG pattern
folds `(i8 (load i16:$addr))` into the ALU/CMP operation, or folds the
whole RMW `(store (add (load $addr), 1), $addr)` idiom into `INR M`.

The pseudo expansion in `V6ClangInstrInfo::expandPostRAPseudo()` lowers to
the physical `XXXM` instruction, emitting the address-to-HL staging
needed when the allocator picked DE or BC for the pointer:

- `addr == HL` — direct `XXX M` (1 instruction)
- `addr == DE` — `XCHG; XXX M; XCHG` (swap always reversible, 8cc/2B
  overhead, no HL preservation needed)
- `addr == BC` — `PUSH HL; MOV L,C; MOV H,B; XXX M; POP HL` with O42
  liveness-aware skip of `PUSH/POP` when HL is dead after

Each of the 11 pseudos shares a single helper `expandMemOpM()` that
takes the target physical M-opcode and the extra operands (imm for
`MVI M`). The expansion mirrors the `V6CLANG_LOAD8_P` / `V6CLANG_LOAD16_P`
fallback pattern already proven in-tree.

### Why this works

1. **ISel handles specificity correctly** — the combined pattern
   `(add Acc, (load addr))` is strictly more specific than the
   split load + register-ALU pattern. LLVM prefers deeper pattern
   matches by complexity; `AddedComplexity` can be raised if needed.
2. **Post-RA expansion is the standard pattern** — the 8/16-bit
   load/store pseudos (`V6CLANG_LOAD8_P`, `V6CLANG_LOAD16_P`, `V6CLANG_STORE16_P`)
   already use exactly this HL/DE/BC staging pattern, and
   `isRegDeadAtMI(V6CLANG::HL, ...)` (O42) already enables the PUSH/POP
   skip. No new infrastructure required.
3. **No register allocator surprises** — the pseudos do not declare
   `Defs=[HL]`. The RA may assign the pointer to HL/DE/BC and keep
   other live values in the untouched pair(s). HL is either used in
   place, swapped and swapped back (DE case), or saved/restored (BC).
4. **Covers all existing O4 + O46 intent** — O4 (ADD/SUB M peephole)
   becomes unnecessary; O46 (MVI M ISel) is subsumed by the
   `V6CLANG_STORE8_IMM_P` pseudo defined below.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Pseudos for ALU M (7) | ADD/ADC/SUB/SBB/ANA/ORA/XRA M | V6ClangInstrInfo.td |
| Pseudo for CMP M | V6CLANG_CMP_M_P | V6ClangInstrInfo.td |
| Pseudo for MVI M | V6CLANG_STORE8_IMM_P | V6ClangInstrInfo.td |
| Pseudos for INR/DCR M | V6CLANG_INR_M_P / V6CLANG_DCR_M_P | V6ClangInstrInfo.td |
| Shared expansion helper | `expandMemOpM()` | V6ClangInstrInfo.cpp |
| `expandPostRAPseudo` dispatch | 11 new cases | V6ClangInstrInfo.cpp |
| Regression tests | Lit CodeGen + feature test | tests/ |

---

## 3. Implementation Steps

### Step 3.1 — Define ALU M pseudos (ADD/ADC/SUB/SBB/ANA/ORA/XRA) [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

Add seven pseudos next to the existing 8-bit ALU block. Each takes the
accumulator (tied input/output) and a `GR16:$addr` pointer. The load is
folded into the DAG pattern so ISel picks the combined form whenever a
loaded i8 feeds an ALU op.

```tablegen
let mayLoad = 1, Defs = [FLAGS] in {
  let Constraints = "$dst = $lhs" in {
    def V6CLANG_ADD_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# ADD_M_P $dst, ($addr)",
        [(set Acc:$dst, (add Acc:$lhs, (i8 (load i16:$addr))))]>;
    def V6CLANG_ADC_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# ADC_M_P $dst, ($addr)", []>;
    def V6CLANG_SUB_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# SUB_M_P $dst, ($addr)",
        [(set Acc:$dst, (sub Acc:$lhs, (i8 (load i16:$addr))))]>;
    def V6CLANG_SBB_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# SBB_M_P $dst, ($addr)", []>;
    def V6CLANG_ANA_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# ANA_M_P $dst, ($addr)",
        [(set Acc:$dst, (and Acc:$lhs, (i8 (load i16:$addr))))]>;
    def V6CLANG_ORA_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# ORA_M_P $dst, ($addr)",
        [(set Acc:$dst, (or Acc:$lhs, (i8 (load i16:$addr))))]>;
    def V6CLANG_XRA_M_P : V6ClangPseudo<(outs Acc:$dst), (ins Acc:$lhs, GR16:$addr),
        "# XRA_M_P $dst, ($addr)",
        [(set Acc:$dst, (xor Acc:$lhs, (i8 (load i16:$addr))))]>;
  }
}
```

> **Design Note**: `ADC/SBB` have no direct DAG pattern because LLVM
> does not expose carry-in ALU nodes at the generic DAG level. They
> are defined for completeness and to allow future manual ISel (e.g.
> multi-precision add lowering). This matches the existing `ACI/SBI`
> immediate ALU entries.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.2 — Define CMP M pseudo [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

```tablegen
let mayLoad = 1, Defs = [FLAGS] in
def V6CLANG_CMP_M_P : V6ClangPseudo<(outs), (ins Acc:$lhs, GR16:$addr),
    "# CMP_M_P $lhs, ($addr)",
    [(V6Clangcmp Acc:$lhs, (i8 (load i16:$addr)))]>;
```

> **Design Note**: `V6Clangcmp` is the `V6ClangISD::CMP` SDNode already used by
> `CMPr/CPI`. Output is FLAGS only — no register written.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.3 — Define MVI M pseudo (V6CLANG_STORE8_IMM_P) [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

```tablegen
let mayStore = 1 in
def V6CLANG_STORE8_IMM_P : V6ClangPseudo<(outs), (ins imm8:$imm, GR16:$addr),
    "# STORE8_IMM_P $imm, ($addr)",
    [(store (i8 imm:$imm), i16:$addr)]>;
```

> **Design Note**: This pseudo intentionally uses a register pointer
> (`GR16:$addr`) only. Stores of an immediate to a global address
> already have a pattern through `STA` (accumulator must hold the
> immediate — one `MVI A`); O49 does not optimise the global-address
> case. Tracking feature work for `MVI M` on global pointers is a
> follow-up.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.4 — Define INR M / DCR M pseudos [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

```tablegen
let mayLoad = 1, mayStore = 1, Defs = [FLAGS] in {
  def V6CLANG_INR_M_P : V6ClangPseudo<(outs), (ins GR16:$addr),
      "# INR_M_P ($addr)",
      [(store (add (i8 (load i16:$addr)), 1), i16:$addr)]>;
  def V6CLANG_DCR_M_P : V6ClangPseudo<(outs), (ins GR16:$addr),
      "# DCR_M_P ($addr)",
      [(store (add (i8 (load i16:$addr)), -1), i16:$addr)]>;
}
```

> **Design Note**: The DAG matcher requires the load and store to
> reference the same `$addr` SDValue; this mirrors how LLVM generic
> ISel folds RMW patterns elsewhere. If pattern-matching turns out
> to be unreliable for RMW through the same pointer (due to chain
> ordering), this step may be deferred and handled via a small
> peephole instead — the ALU/CMP/STORE pseudos above are the bulk of
> the savings.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.5 — Build (catch TableGen errors) [x]

Run:

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

TableGen should produce entries for the 11 new `V6CLANG_*_M_P` opcodes.
Build will fail at `expandPostRAPseudo` (the pseudos have no case yet);
that is addressed in Step 3.6.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.6 — Shared expansion helper `expandMemOpM()` [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Add a file-local helper above `V6ClangInstrInfo::expandPostRAPseudo`.
Takes the physical M-opcode, the address reg, and optional extra
operands (for `MVI M` immediate and for ALU `$dst/$lhs` accumulator
operands). Inserts HL staging on DE/BC paths; restores HL on BC.

```cpp
/// Emit a direct-memory M-operand instruction at MI's position.
/// Handles HL/DE/BC address staging. `Emit` receives an insertion
/// point and emits the actual physical instruction (e.g. ADDM with
/// A tied in/out, or MVIM with the immediate operand).
template <typename EmitFn>
static void expandMemOpM(MachineBasicBlock &MBB, MachineInstr &MI,
                         const V6ClangInstrInfo &TII,
                         const V6ClangRegisterInfo &RI,
                         Register AddrReg, EmitFn Emit) {
  DebugLoc DL = MI.getDebugLoc();

  if (AddrReg == V6CLANG::HL) {
    Emit(MBB, MI.getIterator());
    return;
  }
  if (AddrReg == V6CLANG::DE) {
    // XCHG; OP M; XCHG — always restores HL and DE.
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::XCHG));
    Emit(MBB, MI.getIterator());
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::XCHG));
    return;
  }
  // AddrReg == V6CLANG::BC — no swap instruction; copy B→H, C→L, restore HL.
  bool HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI);
  if (!HLDead)
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::PUSH))
        .addReg(V6CLANG::HL, RegState::Kill)
        .addReg(V6CLANG::SP, RegState::ImplicitDefine);
  BuildMI(MBB, MI, DL, TII.get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::C);
  BuildMI(MBB, MI, DL, TII.get(V6CLANG::MOVrr), V6CLANG::H).addReg(V6CLANG::B);
  Emit(MBB, MI.getIterator());
  if (!HLDead)
    BuildMI(MBB, MI, DL, TII.get(V6CLANG::POP), V6CLANG::HL)
        .addReg(V6CLANG::SP, RegState::ImplicitDefine);
}
```

> **Design Note**: The BC path intentionally uses the same O42 liveness
> check as `V6CLANG_LOAD8_P`. When O48 (scavenger) lands later the
> PUSH/POP logic can be centralised, but until then the helper keeps
> the duplication in one place.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.7 — Wire the 11 pseudos into `expandPostRAPseudo` [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Add cases next to the existing `V6CLANG_LOAD8_P` / `V6CLANG_STORE8_P` cases.
Each case:

1. Read `AddrReg` from the pointer operand.
2. Call `expandMemOpM` with an `Emit` lambda that builds the physical
   `XXXM` / `MVIM` / `INRM` / `DCRM`.
3. `MI.eraseFromParent(); return true;`

Example — ALU M:

```cpp
case V6CLANG::V6CLANG_ADD_M_P: {
  Register AddrReg = MI.getOperand(2).getReg();
  expandMemOpM(MBB, MI, *this, RI, AddrReg,
      [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
        BuildMI(B, Ip, DL, get(V6CLANG::ADDM), V6CLANG::A).addReg(V6CLANG::A);
      });
  MI.eraseFromParent();
  return true;
}
```

Example — CMP M (no Acc output, `A` still the read operand):

```cpp
case V6CLANG::V6CLANG_CMP_M_P: {
  Register AddrReg = MI.getOperand(1).getReg();
  expandMemOpM(MBB, MI, *this, RI, AddrReg,
      [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
        BuildMI(B, Ip, DL, get(V6CLANG::CMPM)).addReg(V6CLANG::A);
      });
  MI.eraseFromParent();
  return true;
}
```

Example — MVI M (immediate):

```cpp
case V6CLANG::V6CLANG_STORE8_IMM_P: {
  int64_t Imm    = MI.getOperand(0).getImm();
  Register AddrReg = MI.getOperand(1).getReg();
  expandMemOpM(MBB, MI, *this, RI, AddrReg,
      [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
        BuildMI(B, Ip, DL, get(V6CLANG::MVIM)).addImm(Imm);
      });
  MI.eraseFromParent();
  return true;
}
```

Example — INR M / DCR M (no operands beyond the address):

```cpp
case V6CLANG::V6CLANG_INR_M_P: {
  Register AddrReg = MI.getOperand(0).getReg();
  expandMemOpM(MBB, MI, *this, RI, AddrReg,
      [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
        BuildMI(B, Ip, DL, get(V6CLANG::INRM));
      });
  MI.eraseFromParent();
  return true;
}
case V6CLANG::V6CLANG_DCR_M_P: { /* analogous, V6CLANG::DCRM */ }
```

> **Design Note**: The 7 ALU pseudos share the same operand layout
> (`dst, lhs, addr`) and differ only in the physical opcode. They can
> be collapsed into one `case` with a table lookup if the switch grows
> too large. An explicit switch is chosen initially for clarity while
> debugging.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.8 — Build [x]

Run the build command from Step 3.5. Expect a clean build.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.9 — Lit test: `mem-alu-isel.ll` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/mem-alu-isel.ll` (create)

Add FileCheck lit tests that:

1. An `add` of a loaded byte through an `i16*` pointer compiles to
   `ADD M`, not `MOV ?,M; ADD ?`.
2. Same for `sub`, `and`, `or`, `xor` via the M form.
3. `CMP` against a loaded byte compiles to `CMP M`.
4. Storing an immediate through a pointer compiles to `MVI M, imm`.
5. `*p += 1` and `*p -= 1` patterns compile to `INR M` / `DCR M`
   (or, if the DAG pattern proves unreliable, document in Step 3.4
   Implementation Notes and drop these two checks).

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.10 — Update `V6ClangLoadStoreOpt` / `V6ClangRedundantFlagElim` coverage [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangLoadStoreOpt.cpp`,
`V6ClangRedundantFlagElim.cpp`

These passes already switch on the physical `ADDM/…/INRM/DCRM/MVIM`
opcodes so post-expansion forms are handled. No changes expected,
but Verify with -verify-machineinstrs that the new pseudos do not
break existing invariants.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.11 — Run regression tests [x]

```
python tests\run_all.py
```

Expected: every existing lit test, golden test, M7 round-trip, M10
link round-trip passes. New test `mem-alu-isel.ll` passes.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.12 — Verification assembly steps from `tests/features/README.md` [x]

Compile `tests/features/41/v6clang.c` to `v6clang_new01.asm`; compare
against the c8080 baseline. Iterate (new02, new03, …) until the
expected ADD/SUB/CMP/INR M forms appear.

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.13 — Create `result.txt` per `tests/features/README.md` [x]

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

### Step 3.14 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Done — see "Completion Summary" at end of file.

---

## 4. Expected Results

### Example 1 — accumulate bytes from a static array

```c
unsigned char acc_sum(void) {
    extern unsigned char arr[8];
    unsigned char a = 0;
    for (unsigned i = 0; i < 8; ++i) a += arr[i];
    return a;
}
```

Before: inner load + ADD sequence generates `MOV r, M; ADD r` per
iteration. After: `ADD M` folds both, saving 4cc + 1B per iteration —
32cc + 8B across the loop body.

### Example 2 — pointer compare

```c
int byte_eq(const unsigned char *p, unsigned char k) { return *p == k; }
```

Before: `MOV r, M; CMP r`. After: `CMP M`. 4cc + 1B saved.

### Example 3 — immediate memory store

```c
void zero_byte(unsigned char *p) { *p = 0; }
```

Before: `MVI A, 0; MOV M, A`. After: `MVI M, 0`. 5cc + 1B saved.

### Example 4 — counter increment through a pointer

```c
void inc(unsigned char *p) { (*p)++; }
```

Before: `MOV A, M; INR A; MOV M, A` (20cc, 3B). After: `INR M`
(8cc, 1B). 12cc + 2B saved per call.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| ISel pattern priority picks the split load + reg-ALU form instead of the combined pseudo | Add `AddedComplexity = 10` to the new pseudo defs if FileCheck shows the split form is still emitted. Pattern complexity should already prefer the combined match. |
| RMW patterns (`INR M / DCR M`) fail to match due to chain ordering in the DAG | If FileCheck for INR/DCR patterns fails, defer those two pseudos and consider a post-expansion peephole as follow-up. ALU/CMP/STORE coverage is independent and still delivers the bulk of the win. |
| BC-case PUSH/POP regresses code that already relies on O42 (dead-HL skip) | Reuse `isRegDeadAtMI` — same API, same call sites as `V6CLANG_LOAD8_P`. Regression tests cover BC-case expansion via existing liveness-aware tests. |
| `V6CLANG_STORE8_IMM_P` conflicts with existing `(store i8, (V6Clangwrapper tglobaladdr))` pattern | New pattern requires `GR16:$addr` register, so global-address stores (which go through `V6Clangwrapper`) do not match. Verified by inspection of existing patterns. |
| Verifier errors on implicit FLAGS def or Acc tied constraint | Mirror the tie/Defs declarations from the register-form ALU ops (`ADDr`, `SUBr`, …). Run `-verify-machineinstrs` in Step 3.11. |

---

## 6. Relationship to Other Improvements

- **Supersedes O4** (ADD M / SUB M peephole) — post-RA peephole
  approach deemed unsafe. ISel avoids all liveness pitfalls.
- **Supersedes O46** (MVI M ISel) — covered by `V6CLANG_STORE8_IMM_P`.
- **Dependency — O42** (liveness-aware pseudo expansion) — used for
  BC PUSH/POP skip via `isRegDeadAtMI(V6CLANG::HL, …)`. Already complete.
- **Optional — O48** (scavenger) — once complete, the BC PUSH/POP
  logic can move into the scavenger, simplifying the helper.
- **Interacts with O65** (MOV r, M + ALU r peephole) — O65 is a
  backstop for cases where ISel still emits the split form. They
  compose cleanly.

---

## 7. Future Enhancements

- Global-address variants: `ADD M` with a `V6Clangwrapper tglobaladdr`
  pointer could be selected by lowering through `LDA + ADDr` or by a
  dedicated `V6CLANG_*_M_G` pseudo.
- Post-RA scavenger (O48) eliminating manual HL preservation.
- Extend `V6CLANG_INR_M_P` / `V6CLANG_DCR_M_P` to folded `(+= 2)`-style small
  increments (2× `INR M`, cheaper than `LXI+ADD`).

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O49 feature description](design\future_plans\O49_direct_memory_alu_isel.md)
* [Pipeline Feature](design\pipeline_feature.md)
* [O42 — liveness-aware expansion](design\future_plans\O42_liveness_aware_expansion.md)


---

## 7. Completion Summary

Implemented — all 14 steps green.

- **TableGen (V6ClangInstrInfo.td):** 11 new pseudos added after `V6CLANG_STORE8_P` —
  `V6CLANG_{ADD,ADC,SUB,SBB,ANA,ORA,XRA,CMP}_M_P`, `V6CLANG_STORE8_IMM_P`,
  `V6CLANG_{INR,DCR}_M_P`. ALU pseudos use `Acc:$dst = Acc:$lhs` tie and
  `Defs = [FLAGS]`. DAG patterns: `[(set Acc, (op Acc, (i8 (load i16:$addr))))]`
  for ADD/SUB/AND/OR/XOR M; `[(V6Clangcmp Acc, (i8 (load i16:$addr)))]` for CMP M;
  `[(store (i8 imm:$imm), i16:$addr)]` for MVI M; `[(store (add (i8 (load i16:$addr)), (i8 ±1)), i16:$addr)]`
  for INR/DCR M. ADC/SBB M have empty `[]` because V6CLANG has no carry SDNode.
- **Post-RA expansion (V6ClangInstrInfo.cpp):** Single template helper
  `expandMemOpM<EmitFn>()` placed before `expandPostRAPseudo`. Branches on
  `$addr` reg class:
  - HL → direct emit.
  - DE → `XCHG` / emit / `XCHG`.
  - BC → `[PUSH HL]; MOV L,C; MOV H,B; emit; [POP HL]` with O42
    `isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI)` gating the PUSH/POP pair.
  11 `case` arms in `expandPostRAPseudo` invoke the helper with tiny
  emit lambdas that call `BuildMI(...get(V6CLANG::ADDM/SUBM/ANAM/ORAM/XRAM/ADCM/SBBM/CMPM/MVIM/INRM/DCRM))`.
- **Lit test:** `llvm-project/llvm/test/CodeGen/V6CLANG/mem-alu-isel.ll` —
  9 functions covering ADD/SUB/ANA/ORA/XRA M (DE path), MVI M, INR M, DCR M,
  plus CMP M via branch form (`cmp_m_br`). Passes.
- **Regression:** `python tests\run_all.py` — 110/110 lit PASS, golden PASS,
  2/2 suites green.
- **Feature 41 results (v6clang_new01.asm vs v6clang_old.asm):**
  `sub_m` −27cc/−4B; `inc_m` −9cc/−3B; `dec_m` −9cc/−3B; `store_imm` −4cc/−1B;
  `sum_bytes` inner loop −4cc/−1B per iteration. `add_m`/`and_m`/`or_m`/`xor_m`
  roughly tie (the old path already used `LDAX DE` + `<op> L`; the new form
  is `XCHG; <op> M; XCHG` which trails a dead XCHG before RET — noted as
  follow-up peephole opportunity, not part of O49 scope).
- **Pass compat:** No changes needed in `V6ClangLoadStoreOpt` or
  `V6ClangRedundantFlagElim` — neither pass references the physical
  ADDM/SUBM/etc. opcodes; the new M-form is emitted after they run.
- **Mirror sync:** `scripts\sync_llvm_mirror.ps1` run; `llvm/` mirrors
  `llvm-project/`.
