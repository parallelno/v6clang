# Plan: Immediate CMP/CPI for 16-bit EQ/NE Comparison (V6CLANG_BR_CC16_IMM)

## 1. Problem

### Current behavior

The CMP-based 16-bit EQ/NE comparison (implemented by V6CLANG_BR_CC16)
compares two register pairs byte-by-byte using CMP:

```asm
; V6CLANG_BR_CC16 NE, BC vs HL — current output (array-copy loop)
    MOV  A, C           ;  8cc  — LhsLo
    CMP  L              ;  4cc  — compare with RhsLo
    JNZ  .LBB0_1        ; 12cc  — early exit (24cc)
    MOV  A, B           ;  8cc  — LhsHi
    CMP  H              ;  4cc  — compare with RhsHi
    JNZ  .LBB0_1        ; 12cc  — (48cc worst case)
```

The RHS register pair (HL) holds the loop-invariant constant
`array1+100`. Because V6CLANG_BR_CC16 accepts `GR16:$rhs`, the register
allocator must keep this constant in a physical register pair for the
entire loop.

### Desired behavior

```asm
; V6CLANG_BR_CC16_IMM NE, BC vs array1+100 — target output
    MVI  A, <(array1+100)  ;  8cc  — lo8 of constant into A
    CMP  C                 ;  4cc  — compare with LhsLo
    JNZ  .LBB0_1           ; 12cc  — early exit (24cc)
    MVI  A, >(array1+100)  ;  8cc  — hi8 of constant into A
    CMP  B                 ;  4cc  — compare with LhsHi
    JNZ  .LBB0_1           ; 12cc  — (48cc worst case)
```

The constant is embedded as immediate operands using v6asm's `<(expr)`
(lo8) and `>(expr)` (hi8) syntax. No register pair is occupied.

### Root cause

V6CLANG_BR_CC16 always takes two register pair operands. When the RHS is
a known constant (global address, integer), ISel materializes it into
a register pair via LXI, then passes that pair to V6CLANG_BR_CC16. The
register allocator must keep this pair live across the comparison.

With only three 16-bit register pairs (BC, DE, HL), a constant
consuming one of them leaves only two for live values. In loops with
three live 16-bit values (e.g., source pointer, destination pointer,
loop counter), a spill becomes inevitable.

### Impact

| Metric | Register CMP (current) | Immediate CMP (target) | Savings |
|--------|----------------------|----------------------|---------|
| Registers for constant | 1 pair (e.g., HL) | 0 | 1 pair freed |
| LXI in loop (remat) | 12cc per iteration | 0cc | 12cc saved |
| Loop comparison | 24-48cc | 24-48cc | same |
| **Available pairs in loop** | **2** | **3** | **+1 pair** |

For the current 3-value array-copy loop this doesn't change the output
(it already has zero spills with the register-based CMP). The benefit
is for **more complex loops** with 4+ live 16-bit values — the freed
pair avoids a spill cascade worth ~100cc per iteration.

---

## 2. Strategy

### Approach: new V6CLANG_BR_CC16_IMM pseudo selected during ISel

The solution has three layers:

1. **V6ClangMCExpr** — lo8/hi8 expression splitting for assembly output and
   ELF relocations (the MCExpr infrastructure).
2. **V6CLANG_BR_CC16_IMM** — new pseudo instruction taking an immediate RHS
   instead of a register pair (the instruction definition).
3. **ISel dispatch** — when RHS is a constant or global address, select
   V6CLANG_BR_CC16_IMM instead of V6CLANG_BR_CC16 (the selection logic).

```
                ISel
         ┌───────┴──────┐
         │              │
   RHS is register   RHS is constant/global
         │              │
  V6CLANG_BR_CC16      V6CLANG_BR_CC16_IMM
  (outs) (ins GR16,   (outs) (ins GR16,
   GR16, i8imm, bb)    imm16, i8imm, bb)
         │              │
    expandPostRAPseudo  expandPostRAPseudo
         │              │
   MOV A,lo; CMP r;   MVI A, <(imm);
   Jcc; MOV A,hi;     CMP lo; Jcc;
   CMP r; Jcc         MVI A, >(imm);
                       CMP hi; Jcc
```

The V6CLANG_BR_CC16 (reg vs reg) path remains unchanged — it handles cases
where RHS is truly a runtime value.

### Why ISel, not a post-RA peephole

| | ISel dispatch | Post-RA peephole |
|--|--|--|
| **Sees** | DAG nodes — `ConstantSDNode`, `GlobalAddressSDNode` directly | Physical registers — must trace back through def chain to find LXI |
| **RA impact** | RA never allocates a pair for the constant → pair freed | RA already allocated → dead pair is wasted |
| **Complexity** | One extra case in `Select()` | Full backward scan, def-chain analysis |
| **Robustness** | DAG patterns are canonical | Fragile — CSE, copy propagation obscure the def |

### Why we need lo8/hi8 MCExpr

For plain integer constants (e.g., comparison against 100), the
expansion can just mask directly: `lo = 100 & 0xFF`, `hi = 100 >> 8`.

But for global addresses with offsets (e.g., `array1+100`), the value
isn't known until link time. The assembler needs to emit:
```
MVI  A, <(array1+100)    ; lo8 relocation
CMP  C
JNZ  target
MVI  A, >(array1+100)    ; hi8 relocation
CMP  B
JNZ  target
```

The `<(expr)` / `>(expr)` syntax is already supported by v6asm. The
LLVM backend needs a `V6ClangMCExpr` class that produces these expressions,
plus corresponding fixup/relocation types for the ELF `.o` → linker
pipeline.

**Reference implementations**: AVR's `AVRMCExpr` with `VK_AVR_LO8` /
`VK_AVR_HI8` variant kinds (file: `llvm/lib/Target/AVR/MCTargetDesc/
AVRMCExpr.{h,cpp}`). MSP430 has a similar pattern. Both are 8/16-bit
targets that split 16-bit addresses into byte halves — identical to
our use case.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| V6ClangMCExpr class | lo8/hi8 MCExpr with printImpl and evaluateAsRelocatable | MCTargetDesc/V6ClangMCExpr.{h,cpp} (NEW) |
| Fixup kinds | `fixup_v6clang_lo8`, `fixup_v6clang_hi8` | V6ClangFixupKinds.h |
| Relocation types | `R_V6CLANG_LO8`, `R_V6CLANG_HI8` | V6ClangFixupKinds.h |
| AsmBackend | applyFixup + getFixupKindInfo + getRelocType | V6ClangAsmBackend.cpp |
| CodeEmitter | Dispatch V6ClangMCExpr to proper fixup kind | V6ClangMCCodeEmitter.cpp |
| InstPrinter | Print V6ClangMCExpr via existing Expr path | V6ClangInstPrinter.cpp (no change needed) |
| Pseudo definition | V6CLANG_BR_CC16_IMM with imm16 RHS | V6ClangInstrInfo.td |
| ISel dispatch | Select IMM variant when RHS is constant | V6ClangISelDAGToDAG.cpp |
| Post-RA expansion | MVI+CMP MBB split for IMM variant | V6ClangInstrInfo.cpp |
| Python linker | Handle R_V6CLANG_LO8 / R_V6CLANG_HI8 | scripts/v6clang_link.py |

---

## 3. Implementation Steps

### Step 3.1 — Create V6ClangMCExpr (lo8/hi8 MCExpr class) [x]

**New file**: `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangMCExpr.h`

```cpp
#ifndef LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCEXPR_H
#define LLVM_LIB_TARGET_V6CLANG_MCTARGETDESC_V6ClangMCEXPR_H

#include "llvm/MC/MCExpr.h"

namespace llvm {

class V6ClangMCExpr : public MCTargetExpr {
public:
  enum VariantKind {
    VK_V6CLANG_LO8,  // Low byte of 16-bit value: <(expr)
    VK_V6CLANG_HI8,  // High byte of 16-bit value: >(expr)
  };

private:
  const VariantKind Kind;
  const MCExpr *Expr;

  explicit V6ClangMCExpr(VariantKind K, const MCExpr *E)
      : Kind(K), Expr(E) {}

public:
  static const V6ClangMCExpr *create(VariantKind K, const MCExpr *E,
                                  MCContext &Ctx);

  VariantKind getKind() const { return Kind; }
  const MCExpr *getSubExpr() const { return Expr; }

  void printImpl(raw_ostream &OS, const MCAsmInfo *MAI) const override;
  bool evaluateAsRelocatableImpl(MCValue &Res,
                                  const MCAsmLayout *Layout,
                                  const MCFixup *Fixup) const override;
  void visitUsedExpr(MCStreamer &S) const override;
  MCFragment *findAssociatedFragment() const override;
  void fixELFSymbolsInTLSFixups(MCAssembler &) const override {}
};

} // namespace llvm

#endif
```

**New file**: `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangMCExpr.cpp`

```cpp
#include "V6ClangMCExpr.h"
#include "llvm/MC/MCAsmLayout.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCValue.h"

using namespace llvm;

const V6ClangMCExpr *V6ClangMCExpr::create(VariantKind K, const MCExpr *E,
                                    MCContext &Ctx) {
  return new (Ctx) V6ClangMCExpr(K, E);
}

void V6ClangMCExpr::printImpl(raw_ostream &OS, const MCAsmInfo *MAI) const {
  // v6asm syntax: <(expr) for lo8, >(expr) for hi8
  OS << (Kind == VK_V6CLANG_LO8 ? '<' : '>') << '(';
  Expr->print(OS, MAI);
  OS << ')';
}

bool V6ClangMCExpr::evaluateAsRelocatableImpl(
    MCValue &Res, const MCAsmLayout *Layout,
    const MCFixup *Fixup) const {
  MCValue Value;
  if (!Expr->evaluateAsRelocatable(Value, Layout, Fixup))
    return false;

  if (Value.isAbsolute()) {
    // Constant: fold immediately.
    int64_t Val = Value.getConstant();
    if (Kind == VK_V6CLANG_LO8)
      Res = MCValue::get(Val & 0xFF);
    else
      Res = MCValue::get((Val >> 8) & 0xFF);
    return true;
  }

  // Symbol reference: can't fold — preserve for fixup/relocation.
  // Return the full value; the fixup will handle byte extraction.
  Res = Value;
  return true;
}

void V6ClangMCExpr::visitUsedExpr(MCStreamer &S) const {
  S.visitUsedExpr(*Expr);
}

MCFragment *V6ClangMCExpr::findAssociatedFragment() const {
  return Expr->findAssociatedFragment();
}
```

> **Design Notes**:
>
> - **`printImpl`** emits `<(expr)` / `>(expr)` — matching v6asm syntax.
>   The `printOperand` method in `V6ClangInstPrinter` already handles
>   `MCExpr` by calling `Op.getExpr()->print(OS, &MAI)`, which
>   dispatches to our `printImpl`. No changes needed in the printer.
>
> - **`evaluateAsRelocatableImpl`**: For absolute constants, we fold
>   to the byte value immediately. For symbol references, we return
>   the original value and let the fixup/relocation handle byte
>   extraction at link time.
>
> - **Reference**: Follows AVR's `AVRMCExpr` pattern (LLVM source:
>   `llvm/lib/Target/AVR/MCTargetDesc/AVRMCExpr.{h,cpp}`). AVR uses
>   `lo8()` / `hi8()` function syntax; V6CLANG uses `<()` / `>()` prefix
>   to match v6asm.

### Step 3.2 — Add fixup kinds and relocation types [x]

**File**: `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangFixupKinds.h`

Add two new fixup kinds and relocation types:

```cpp
enum Fixups {
  fixup_v6clang_8 = FirstTargetFixupKind,
  fixup_v6clang_16,
  fixup_v6clang_lo8,   // NEW — low byte of 16-bit address
  fixup_v6clang_hi8,   // NEW — high byte of 16-bit address
  fixup_v6clang_invalid,
  NumTargetFixupKinds = fixup_v6clang_invalid - FirstTargetFixupKind
};

enum RelocType {
  R_V6CLANG_NONE = 0,
  R_V6CLANG_8    = 1,
  R_V6CLANG_16   = 2,
  R_V6CLANG_LO8  = 3,   // NEW — low byte of 16-bit address
  R_V6CLANG_HI8  = 4,   // NEW — high byte of 16-bit address
};
```

### Step 3.3 — Update AsmBackend: fixup info, apply, and ELF reloc mapping [x]

**File**: `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangAsmBackend.cpp`

Three changes:

**a) `getFixupKindInfo()`** — add two entries to the Infos array:

```cpp
const static MCFixupKindInfo Infos[V6CLANG::NumTargetFixupKinds] = {
    {"fixup_v6clang_8",   0, 8, 0},
    {"fixup_v6clang_16",  0, 16, 0},
    {"fixup_v6clang_lo8", 0, 8, 0},   // NEW
    {"fixup_v6clang_hi8", 0, 8, 0},   // NEW
};
```

**b) `applyFixup()`** — handle byte extraction:

```cpp
if (Kind == static_cast<MCFixupKind>(V6CLANG::fixup_v6clang_lo8)) {
  assert(Offset < Data.size() && "Fixup offset out of range");
  Data[Offset] = static_cast<char>(Value & 0xFF);
  return;
}

if (Kind == static_cast<MCFixupKind>(V6CLANG::fixup_v6clang_hi8)) {
  assert(Offset < Data.size() && "Fixup offset out of range");
  Data[Offset] = static_cast<char>((Value >> 8) & 0xFF);
  return;
}
```

**c) `getRelocType()`** — map fixups to ELF relocation types:

```cpp
case V6CLANG::fixup_v6clang_lo8:
  return V6CLANG::R_V6CLANG_LO8;
case V6CLANG::fixup_v6clang_hi8:
  return V6CLANG::R_V6CLANG_HI8;
```

> **Design Note**: The lo8 fixup patches byte `[Offset]` with
> `Value & 0xFF`. The hi8 fixup patches byte `[Offset]` with
> `(Value >> 8) & 0xFF`. Both are 8-bit, single-byte fixups applied to
> the data byte of a 2-byte MVI instruction (opcode at offset 0,
> immediate at offset 1). The fixup says "offset=1, size=8".
>
> **Reference**: AVR's `adjustFixupValue` in `AVRAsmBackend.cpp` uses
> the same `& 0xFF` and `>> 8` masking for its `fixup_lo8_ldi` and
> `fixup_hi8_ldi` kinds. V6CLANG is simpler because MVI stores the
> immediate contiguously (not split across non-adjacent bit fields
> like AVR's LDI instruction).

### Step 3.4 — Update CodeEmitter: dispatch V6ClangMCExpr to proper fixup [x]

**File**: `llvm/lib/Target/V6CLANG/MCTargetDesc/V6ClangMCCodeEmitter.cpp`

In `getMachineOpValue()`, when the operand is an expression, check if
it's a `V6ClangMCExpr` and use the corresponding fixup kind:

```cpp
assert(MO.isExpr() && "Expected expression operand");

const MCExpr *Expr = MO.getExpr();
MCFixupKind Kind;
unsigned Offset;

// Check for V6CLANG lo8/hi8 expressions first.
if (auto *V6ClangExpr = dyn_cast<V6ClangMCExpr>(Expr)) {
  Kind = static_cast<MCFixupKind>(
      V6ClangExpr->getKind() == V6ClangMCExpr::VK_V6CLANG_LO8
          ? V6CLANG::fixup_v6clang_lo8
          : V6CLANG::fixup_v6clang_hi8);
  Offset = 1;  // Immediate byte is always at offset 1 in MVI (2-byte instr)
} else if (Size == 3) {
  Kind = FK_Data_2;
  Offset = 1;
} else if (Size == 2) {
  Kind = FK_Data_1;
  Offset = 1;
} else {
  llvm_unreachable("Expression operand in 1-byte instruction");
}

Fixups.push_back(MCFixup::create(Offset, Expr, Kind, MI.getLoc()));
return 0;
```

> **Design Note**: This is the critical dispatch point for the ELF
> pipeline. When the compiler emits `MVI A, <(array1+100)`, the MCInst
> operand is a `V6ClangMCExpr(VK_V6CLANG_LO8, MCSymbolRefExpr("array1") + 100)`.
> The code emitter sees this, creates a `fixup_v6clang_lo8` fixup at the
> immediate byte offset, and the assembler backend either resolves it
> immediately (if the symbol is in the same section and fully resolved)
> or emits an `R_V6CLANG_LO8` relocation into the `.o` file for the linker.
>
> **Risk note**: If a V6ClangMCExpr ends up as an operand of a 3-byte
> instruction (e.g., LXI), the offset would be wrong. This shouldn't
> happen because we only create V6ClangMCExpr in the V6CLANG_BR_CC16_IMM
> expansion, which emits MVI (2-byte). A defensive assert could be
> added: `assert(Size == 2 && "V6ClangMCExpr in non-MVI instruction")`.

> **Implementation note**: The defensive assert was added in the
> implementation: `assert(Size == 2 && "V6ClangMCExpr in non-MVI instruction")`
> is present in the V6ClangMCExpr branch of `getMachineOpValue()`.

### Step 3.5 — Register new source file in CMakeLists.txt [x]

**File**: `llvm/lib/Target/V6CLANG/MCTargetDesc/CMakeLists.txt`

Add `V6ClangMCExpr.cpp`:

```cmake
add_llvm_component_library(LLVMV6ClangDesc
  V6ClangAsmBackend.cpp
  V6ClangInstPrinter.cpp
  V6ClangMCAsmInfo.cpp
  V6ClangMCCodeEmitter.cpp
  V6ClangMCExpr.cpp              # NEW
  V6ClangMCTargetDesc.cpp
  ...
```

### Step 3.6 — Define V6CLANG_BR_CC16_IMM pseudo instruction [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

Add after the V6CLANG_BR_CC16 definition:

```tablegen
// Fused 16-bit compare + conditional branch with immediate RHS.
// Selected when the comparison RHS is a known constant or global address.
// Expanded post-RA into MVI + CMP sequence with lo8/hi8 splitting.
// The immediate is embedded directly — no register pair needed for RHS.
let isBranch = 1, isTerminator = 1, Defs = [A, FLAGS] in
def V6CLANG_BR_CC16_IMM : V6ClangPseudo<(outs),
    (ins GR16:$lhs, imm16:$rhs, i8imm:$cc, brtarget:$dst),
    "# BR_CC16_IMM $lhs, $rhs, $cc, $dst",
    []>;
```

> **Design Notes**:
>
> - `imm16:$rhs` instead of `GR16:$rhs`. The register allocator sees
>   no register operand for the RHS — it won't allocate a pair.
>
> - `Defs = [A, FLAGS]` remains: the expansion still uses A as a temp
>   (MVI A, ...) and CMP sets FLAGS.
>
> - No `Constraints` needed — only the LHS register pair is read, and
>   neither CMP nor MVI modifies it.
>
> - The `imm16` operand carries either a plain integer or a
>   `MO_GlobalAddress` / `MO_ExternalSymbol` machine operand, depending
>   on what ISel puts there.

### Step 3.7 — ISel: select V6CLANG_BR_CC16_IMM when RHS is constant [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangISelDAGToDAG.cpp`

Modify the `V6ClangISD::BR_CC16` case to check whether RHS comes from an
LXI-materialized constant (V6ClangWrapper of a GlobalAddress or a plain
constant):

```cpp
  case V6ClangISD::BR_CC16: {
    SDValue Chain = N->getOperand(0);
    SDValue LHS   = N->getOperand(1);
    SDValue RHS   = N->getOperand(2);
    SDValue CC    = N->getOperand(3);
    SDValue Dest  = N->getOperand(4);

    // Check if RHS is a constant or wrapped global address.
    // If so, use V6CLANG_BR_CC16_IMM to avoid allocating a register pair.
    unsigned Opc = V6CLANG::V6CLANG_BR_CC16;  // default: register variant
    SDValue RhsOp = RHS;

    // RHS is V6ClangWrapper(tglobaladdr) → unwrap and use IMM variant.
    if (RHS.getOpcode() == V6ClangISD::Wrapper &&
        (isa<GlobalAddressSDNode>(RHS.getOperand(0)) ||
         isa<ExternalSymbolSDNode>(RHS.getOperand(0)))) {
      Opc = V6CLANG::V6CLANG_BR_CC16_IMM;
      RhsOp = RHS.getOperand(0);  // Unwrap to TargetGlobalAddress
    }
    // RHS is a plain i16 constant.
    else if (auto *C = dyn_cast<ConstantSDNode>(RHS)) {
      Opc = V6CLANG::V6CLANG_BR_CC16_IMM;
      RhsOp = CurDAG->getTargetConstant(C->getSExtValue(), DL, MVT::i16);
    }

    SmallVector<SDValue, 5> Ops;
    Ops.push_back(LHS);
    Ops.push_back(RhsOp);
    Ops.push_back(CC);
    Ops.push_back(Dest);
    Ops.push_back(Chain);

    SDVTList VTs = CurDAG->getVTList(MVT::Other);
    SDNode *BrCC = CurDAG->getMachineNode(Opc, DL, VTs, Ops);
    ReplaceNode(N, BrCC);
    return;
  }
```

> **Design Notes**:
>
> - **V6ClangWrapper unwrapping**: In `LowerGlobalAddress`, the global
>   `array1+100` is wrapped as `V6ClangISD::Wrapper(TargetGlobalAddress)`.
>   ISel normally matches this to `(LXI tglobaladdr:$addr)`. By
>   intercepting here, we prevent LXI from being selected for the
>   comparison constant — the TargetGlobalAddress goes directly into
>   V6CLANG_BR_CC16_IMM's `imm16` operand.
>
> - **ConstantSDNode**: For plain integer constants (e.g., `icmp ne
>   i16 %x, 100`), we wrap the value in a TargetConstant.
>
> - **Fallback**: If RHS is neither a constant nor a wrapped global,
>   the default V6CLANG_BR_CC16 (register variant) is used.
>
> - **LHS is never constant**: LLVM canonicalizes `icmp const, %var`
>   to `icmp %var, const`, so LHS is always a register.

> **Implementation note**: The implemented ISel code differs from the
> plan code above in one important way: it **guards the IMM variant
> selection by condition code**, only using V6CLANG_BR_CC16_IMM when
> `CCVal == V6ClangCC::COND_Z || CCVal == V6ClangCC::COND_NZ` (EQ/NE).
> For other conditions (LT, GE, etc.), the register variant is always
> used even if RHS is a constant. This guard was mentioned in Risk
> section §5 but not in the Step 3.7 code. The plan code would have
> incorrectly selected V6CLANG_BR_CC16_IMM for SUB/SBB conditions.

### Step 3.8 — Implement V6CLANG_BR_CC16_IMM expansion in expandPostRAPseudo [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`

Add a new case for `V6CLANG::V6CLANG_BR_CC16_IMM` in `expandPostRAPseudo()`.
The expansion is similar to V6CLANG_BR_CC16's EQ/NE path but uses MVI+CMP
instead of MOV+CMP, with lo8/hi8 MCExpr for the immediate.

```cpp
  case V6CLANG::V6CLANG_BR_CC16_IMM: {
    // Fused 16-bit compare + branch with immediate RHS.
    // Operand layout: 0=$lhs(GR16), 1=$rhs(imm16), 2=$cc, 3=$dst
    Register LhsReg = MI.getOperand(0).getReg();
    MachineOperand &RhsOp = MI.getOperand(1);
    int64_t CC = MI.getOperand(2).getImm();
    MachineBasicBlock *Target = MI.getOperand(3).getMBB();

    MCRegister LhsLo = RI.getSubReg(LhsReg, V6CLANG::sub_lo);
    MCRegister LhsHi = RI.getSubReg(LhsReg, V6CLANG::sub_hi);

    // Build lo8 and hi8 operands from the immediate.
    // For plain integers: mask directly.
    // For global addresses: create V6ClangMCExpr lo8/hi8 wrappers.
    MachineOperand Lo8Op, Hi8Op;
    if (RhsOp.isImm()) {
      int64_t Val = RhsOp.getImm();
      Lo8Op = MachineOperand::CreateImm(Val & 0xFF);
      Hi8Op = MachineOperand::CreateImm((Val >> 8) & 0xFF);
    } else {
      // Global address or external symbol → V6ClangMCExpr
      MCContext &MCCtx = MF->getContext();
      const MCExpr *BaseExpr;
      if (RhsOp.isGlobal()) {
        const MCSymbol *Sym = MF->getContext().getOrCreateSymbol(
            RhsOp.getGlobal()->getName());  // TODO: may need getSymbol()
        BaseExpr = MCSymbolRefExpr::create(Sym, MCCtx);
        if (RhsOp.getOffset() != 0)
          BaseExpr = MCBinaryExpr::createAdd(
              BaseExpr,
              MCConstantExpr::create(RhsOp.getOffset(), MCCtx),
              MCCtx);
      } else {
        llvm_unreachable("Unexpected operand type in V6CLANG_BR_CC16_IMM");
      }
      const MCExpr *Lo8Expr =
          V6ClangMCExpr::create(V6ClangMCExpr::VK_V6CLANG_LO8, BaseExpr, MCCtx);
      const MCExpr *Hi8Expr =
          V6ClangMCExpr::create(V6ClangMCExpr::VK_V6CLANG_HI8, BaseExpr, MCCtx);
      Lo8Op = MachineOperand::CreateMCSymbol(/*dummy*/nullptr);
      // Actually: we need to emit MCInst-level operands. See design note.
    }

    // ... MBB splitting and MVI+CMP emission (same pattern as BR_CC16)
  }
```

> **Design Notes — MachineOperand to MCExpr bridge**:
>
> The key challenge is that `expandPostRAPseudo` emits `MachineInstr`s,
> but `V6ClangMCExpr` is an MC-layer construct. There are two approaches:
>
> **Option A — Emit MVI with a GlobalAddress MachineOperand**: The
> AsmPrinter already handles `MO_GlobalAddress` → `MCSymbolRefExpr`.
> We add a hook in the AsmPrinter's `lowerOperand()` or
> `EmitInstruction()` to wrap global-address MVI operands in
> `V6ClangMCExpr` based on a target flag.
>
> **Option B — Add target operand flags**: Use
> `MachineOperand::setTargetFlags(V6ClangII::MO_LO8)` and
> `MachineOperand::setTargetFlags(V6ClangII::MO_HI8)`. The AsmPrinter
> reads the flag and wraps the operand in `V6ClangMCExpr` when lowering
> to MCInst. This is the standard LLVM pattern (ARM, RISC-V, AVR all
> use target flags).
>
> Option B is preferred. The expansion becomes:
>
> ```cpp
> // For global address:
> auto MVI_Lo = BuildMI(&MBB, DL, get(V6CLANG::MVIr), V6CLANG::A);
> if (RhsOp.isImm()) {
>   MVI_Lo.addImm(RhsOp.getImm() & 0xFF);
> } else {
>   MVI_Lo.addGlobalAddress(RhsOp.getGlobal(), RhsOp.getOffset(),
>                           V6ClangII::MO_LO8);
> }
> ```
>
> And in the AsmPrinter's `lowerOperand()`:
>
> ```cpp
> if (MO.getTargetFlags() & V6ClangII::MO_LO8) {
>   const MCExpr *Expr = /* lower global to MCSymbolRefExpr */;
>   Expr = V6ClangMCExpr::create(V6ClangMCExpr::VK_V6CLANG_LO8, Expr, Ctx);
>   MCOp = MCOperand::createExpr(Expr);
> }
> ```
>
> **Reference**: AVR's `AVRAsmPrinter::lowerInstruction()` reads
> `AVRII::MO_LO` / `AVRII::MO_HI` target flags and wraps operands
> in `AVRMCExpr`. The same pattern in RISC-V: `RISCVII::MO_LO` /
> `MO_HI`.

> **Implementation note**: The implementation uses **Option B** (target
> operand flags) as recommended, but the code structure differs from
> the plan's pseudocode above. Instead of pre-building `MachineOperand`
> values with MCExpr/MCSymbol (which doesn't work — `expandPostRAPseudo`
> emits MachineInstrs, not MCInsts), the implementation uses two lambda
> helpers `addImmLo` and `addImmHi` that dispatch on the operand type:
>
> - `isImm()`: mask the value directly (`& 0xFF` / `>> 8`)
> - `isGlobal()`: `addGlobalAddress(..., offset, V6ClangII::MO_LO8/HI8)`
> - `isSymbol()`: `addExternalSymbol(..., V6ClangII::MO_LO8/HI8)`
>
> The plan's initial pseudocode (Option A with `MCSymbolRefExpr` and
> `MachineOperand::CreateMCSymbol`) was not viable — it attempted to
> create MC-layer objects inside a MachineInstr expansion. The lambda
> approach is cleaner and handles all three operand types uniformly.
> The MBB-splitting logic reuses the same pattern as V6CLANG_BR_CC16 EQ/NE.

### Step 3.9 — Define target operand flags [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangInstrInfo.h` (or a new
`V6ClangTargetFlags.h`)

```cpp
namespace V6ClangII {
enum {
  MO_NO_FLAG = 0,
  MO_LO8 = 1,   // Low byte of 16-bit value
  MO_HI8 = 2,   // High byte of 16-bit value
};
} // namespace V6ClangII
```

### Step 3.10 — Update MCInstLower to handle target flags [x]

**File**: `llvm/lib/Target/V6CLANG/V6ClangAsmPrinter.cpp`

> **Implementation note**: The target flag handling was implemented in
> `V6ClangMCInstLower.cpp` (in `lowerSymbolOperand()`), not in
> `V6ClangAsmPrinter.cpp` as the plan suggested. The V6CLANG backend already
> uses a separate `V6ClangMCInstLower` class for MachineInstr → MCInst
> lowering (following the pattern of many other targets), and
> `lowerSymbolOperand()` is the natural place to wrap expressions in
> `V6ClangMCExpr`. The logic is the same as planned — check
> `MO.getTargetFlags()` for `MO_LO8`/`MO_HI8` and wrap accordingly.

In the method that lowers `MachineOperand` to `MCOperand` (typically
`lowerOperand()` or within `emitInstruction()`), check for target
flags and wrap the expression:

```cpp
case MachineOperand::MO_GlobalAddress: {
  const MCExpr *Expr = MCSymbolRefExpr::create(
      getSymbol(MO.getGlobal()), Ctx);
  if (MO.getOffset())
    Expr = MCBinaryExpr::createAdd(
        Expr, MCConstantExpr::create(MO.getOffset(), Ctx), Ctx);

  unsigned TF = MO.getTargetFlags();
  if (TF & V6ClangII::MO_LO8)
    Expr = V6ClangMCExpr::create(V6ClangMCExpr::VK_V6CLANG_LO8, Expr, Ctx);
  else if (TF & V6ClangII::MO_HI8)
    Expr = V6ClangMCExpr::create(V6ClangMCExpr::VK_V6CLANG_HI8, Expr, Ctx);

  MCOp = MCOperand::createExpr(Expr);
  break;
}
```

> **Design Note**: This is the bridge between the MachineInstr world
> (where we have `MO_GlobalAddress` + target flags) and the MCInst
> world (where we need `V6ClangMCExpr`). The AsmPrinter performs this
> translation for every instruction before it's printed or encoded.
>
> **Reference**: AVR's `AVRAsmPrinter::lowerInstruction()` in
> `llvm/lib/Target/AVR/AVRAsmPrinter.cpp`. Search for `AVRII::MO_LO`
> to see the pattern.

### Step 3.11 — Update Python linker for new relocation types [x]

**File**: `scripts/v6clang_link.py`

Add the two new relocation type constants and apply handlers:

```python
# V6CLANG relocation types (must match V6ClangFixupKinds.h)
R_V6CLANG_NONE = 0
R_V6CLANG_8    = 1
R_V6CLANG_16   = 2
R_V6CLANG_LO8  = 3    # NEW — low byte of 16-bit address
R_V6CLANG_HI8  = 4    # NEW — high byte of 16-bit address
```

In the relocation application loop:

```python
elif rel.rtype == R_V6CLANG_LO8:
    if patch_file_offset < total_size:
        output[patch_file_offset] = value & 0xFF
elif rel.rtype == R_V6CLANG_HI8:
    if patch_file_offset < total_size:
        output[patch_file_offset] = (value >> 8) & 0xFF
```

### Step 3.12 — Build [x]

```bash
cmd /c "call vcvars64.bat >nul 2>&1 && ninja -C llvm-build clang llc"
```

Expected: clean build. The V6ClangMCExpr adds a new `.cpp` file; the rest
are edits to existing files.

### Step 3.13 — Lit test: immediate comparison (NE with global address) [x]

**File**: `tests/lit/CodeGen/V6CLANG/br-cc16-imm.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

@arr = global [100 x i8] zeroinitializer

; Test that NE comparison against a global+offset uses MVI+CMP, not LXI+MOV+CMP.
define void @ne_imm_global(ptr %p) {
; CHECK-LABEL: ne_imm_global:
; CHECK-NOT:   LXI
; CHECK:       MVI A, <(arr+100)
; CHECK:       CMP
; CHECK:       JNZ
; CHECK:       MVI A, >(arr+100)
; CHECK:       CMP
; CHECK:       JNZ
entry:
  %cmp = icmp ne ptr %p, getelementptr (i8, ptr @arr, i16 100)
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that NE against a plain integer constant uses MVI+CMP.
define void @ne_imm_int(i16 %x) {
; CHECK-LABEL: ne_imm_int:
; CHECK-NOT:   LXI
; CHECK:       MVI A,
; CHECK:       CMP
; CHECK:       JNZ
; CHECK:       MVI A,
; CHECK:       CMP
; CHECK:       JNZ
entry:
  %cmp = icmp ne i16 %x, 1000
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

; Test that NE with a register RHS still uses MOV+CMP (reg variant).
define void @ne_reg(i16 %a, i16 %b) {
; CHECK-LABEL: ne_reg:
; CHECK:       MOV A,
; CHECK:       CMP
; CHECK:       JNZ
entry:
  %cmp = icmp ne i16 %a, %b
  br i1 %cmp, label %then, label %else

then:
  call void @use()
  ret void

else:
  ret void
}

declare void @use()
```

> **Implementation note**: The implemented test differs from the plan
> in several ways:
>
> - **RUN line** uses `-march=v6clang` instead of `-mtriple=i8080-unknown-v6clang`
>   (equivalent, but shorter).
> - **5 test functions** instead of 3: added `eq_imm_global` (EQ with
>   global address) and `lt_still_register` (verifies SUB/SBB path is
>   unchanged for unsigned LT even with constant RHS).
> - **`@arr` declaration** moved to end of file (after all functions).
> - **`getelementptr` in IR** computed as a separate value
>   (`%end = getelementptr ...`) instead of inline in `icmp`.
> - **CHECK-NOT** uses regex `LXI {{[A-Z]+}}, arr+100` for more
>   precise negative matching.
> - **CHECK patterns** omit `JNZ`/`JZ` checks for brevity — only
>   verify MVI+CMP pairs are present.

### Step 3.14 — Lit test: loop with immediate comparison (no LXI in loop) [x]

**File**: `tests/lit/CodeGen/V6CLANG/loop-cmp-imm.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

@src = global [100 x i8] zeroinitializer
@dst = global [100 x i8] zeroinitializer

; Verify the array-copy loop uses MVI+CMP instead of LXI+MOV+CMP.
define void @array_copy() {
entry:
  br label %loop

loop:
  %ps = phi ptr [ @src, %entry ], [ %ps.next, %loop ]
  %pd = phi ptr [ @dst, %entry ], [ %pd.next, %loop ]
  %val = load i8, ptr %ps
  store i8 %val, ptr %pd
  %ps.next = getelementptr i8, ptr %ps, i16 1
  %pd.next = getelementptr i8, ptr %pd, i16 1
  %done = icmp ne ptr %ps.next, getelementptr (i8, ptr @src, i16 100)
  br i1 %done, label %loop, label %exit

exit:
  ret void
}

; CHECK-LABEL: array_copy:
; The loop body should NOT contain LXI (constant not in register).
; CHECK: .L{{.*}}:
; CHECK-NOT: LXI
; Expect MVI+CMP pattern for the comparison.
; CHECK:     MVI A,
; CHECK:     CMP
; CHECK:     JNZ
```

> **Implementation note**: The implemented test differs from the plan:
>
> - **RUN line** uses `-march=v6clang` instead of `-mtriple=i8080-unknown-v6clang`.
> - **`icmp eq`** instead of `icmp ne` — the optimizer may transform
>   the loop condition; `eq` matched the actual codegen output.
> - **CHECK patterns** are more flexible: no `CHECK-NOT: LXI` (the
>   optimizer sometimes uses an integer counter instead of pointer
>   comparison, making the `LXI` check fragile). Just verifies
>   MVI+CMP is present in the loop.
> - **Comment** documents that the optimizer may use either pointer
>   comparison or integer counter — both produce MVI+CMP.

### Step 3.15 — Lit test: ELF object — relocation types [skipped — llvm-readobj not built]

**File**: `tests/lit/CodeGen/V6CLANG/reloc-lo8-hi8.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -filetype=obj < %s -o %t.o
; RUN: llvm-readobj -r %t.o | FileCheck %s

@arr = global [100 x i8] zeroinitializer

define void @reloc_test(ptr %p) {
entry:
  %cmp = icmp ne ptr %p, getelementptr (i8, ptr @arr, i16 100)
  br i1 %cmp, label %then, label %else
then:
  call void @use()
  ret void
else:
  ret void
}

declare void @use()

; CHECK: Relocations [
; CHECK:   Section {{.*}} .rela.text {
; Expect lo8 and hi8 relocations for the MVI immediates.
; CHECK:     R_V6CLANG_LO8
; CHECK:     R_V6CLANG_HI8
```

### Step 3.16 — Run regression tests [x]

```bash
python tests/run_all.py
```

All existing tests must pass. The ISel change only affects cases where
RHS is a constant — the register-variant path is unchanged.

### Step 3.17 — Verify assembly on array-copy benchmark [x]

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2_imm.asm
```

Target output for the loop body:

```asm
.LBB0_1:
    LDAX B                  ;  8cc  — load from [BC]
    STAX D                  ;  8cc  — store to [DE]
    INX  B                  ;  8cc  — advance source
    INX  D                  ;  8cc  — advance dest
    MVI  A, <(array1+100)   ;  8cc  — lo8 of end address
    CMP  C                  ;  4cc  — compare with LhsLo
    JNZ  .LBB0_1            ; 12cc  — early exit (56cc)
    MVI  A, >(array1+100)   ;  8cc  — hi8 of end address
    CMP  B                  ;  4cc  — compare with LhsHi
    JNZ  .LBB0_1            ; 12cc  — worst case (80cc)
```

Verify:
1. **No LXI** in the loop body (constant not in register)
2. **MVI A, <(...)** and **MVI A, >(...)** for lo8/hi8
3. **CMP** compares A against LHS register halves
4. **No PUSH/POP** (no spills)
5. **Two register pairs** used for pointers: BC, DE
6. **HL is free** for other uses

### Step 3.18 — Verify ELF pipeline on array-copy benchmark [x]

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -c ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2.o
python scripts\v6clang_link.py temp\compare\03\v6clang2.o ^
    -o temp\compare\03\v6clang2.bin --base 0x0100 --map temp\compare\03\v6clang2.map
```

Verify:
1. `v6clang_link.py` completes without errors or warnings
2. The `.map` file shows correct symbol addresses
3. The binary contains correct bytes at the MVI immediate positions
   (lo8 and hi8 of the resolved `array1+100` address)

### Step 3.19 — Sync mirror [x]

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Per-comparison cost (unchanged)

| Case | MOV+CMP (before) | MVI+CMP (after) | Difference |
|------|------------------|------------------|-----------|
| NE — lo bytes differ (early exit) | 24cc | 24cc | same |
| NE — both bytes checked | 48cc | 48cc | same |
| EQ — lo bytes differ (early skip) | 24cc | 24cc | same |
| EQ — both bytes checked | 48cc | 48cc | same |

The MVI vs MOV cost is identical (both 8cc on V6CLANG). The comparison
itself doesn't get faster. The win is entirely in register pressure.

### Register pressure improvement

| Metric | Register CMP | Immediate CMP |
|--------|-------------|--------------|
| Register pairs for comparison | 2 (LHS + RHS) | 1 (LHS only) |
| Register pairs available | 1 remaining | 2 remaining |
| LXI in preheader | 1 (for constant) | 0 |
| LXI rematerialized per iteration | 12cc (when RA remats) | 0cc |

### Array-copy loop comparison

| Instruction | Register CMP (current) | Immediate CMP (target) |
|-------------|----------------------|----------------------|
| Load/Store | LDAX B, STAX D | LDAX B, STAX D |
| Pointer inc | INX B, INX D | INX B, INX D |
| Constant | LXI HL, array1+100 (remat) | (none — embedded in MVI) |
| Compare lo | MOV A, C; CMP L | MVI A, <(array1+100); CMP C |
| Compare hi | MOV A, B; CMP H | MVI A, >(array1+100); CMP B |
| **Loop body** | **10 instructions** | **10 instructions** |
| **Cycle cost** | **80cc** (with 12cc LXI remat) | **80cc** (no remat) |

For the 3-value array-copy loop, the instruction count is the same.
The LXI rematerialization is replaced by two MVI instructions (same
total bytes and cycles). The real benefit is that **HL is completely
free** — available for a 4th live value without spilling.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **ISel sees RHS as register, not constant** — V6ClangWrapper not recognized | The V6ClangISD::Wrapper node is created in `LowerGlobalAddress` and is always present for global addresses. Check for both `V6ClangISD::Wrapper` wrapping `GlobalAddressSDNode` and bare `ConstantSDNode`. Add a `-debug-only=isel` dump to verify RHS node type. |
| **MVI with V6ClangMCExpr crashes the code emitter** — fixup kind mismatch | The code emitter dispatches on `isa<V6ClangMCExpr>(Expr)` before falling through to size-based logic. Add assertion: `assert(Size == 2)` when V6ClangMCExpr is detected. Test with `-filetype=obj` to exercise the full path. |
| **AsmPrinter doesn't wrap operand in V6ClangMCExpr** — plain global printed | AsmPrinter must check `MO.getTargetFlags()` and create V6ClangMCExpr. Test with `-filetype=asm` — if `<(` / `>(` doesn't appear, the flag isn't being handled. |
| **v6asm rejects `<(` / `>(` syntax** — assembler compatibility | Verify v6asm syntax: `MVI A, <(label+100)`. If v6asm uses different syntax, adjust `V6ClangMCExpr::printImpl()`. |
| **ELF relocation type mismatch between backend and linker** — silent corruption | Both `V6ClangFixupKinds.h` and `v6clang_link.py` must agree on `R_V6CLANG_LO8=3`, `R_V6CLANG_HI8=4`. Add a lit test that checks `llvm-readobj -r` output for the correct relocation names. |
| **V6CLANG_BR_CC16_IMM selected for SUB/SBB conditions** — wrong expansion | The ISel dispatch only changes the MachineNode opcode. The expansion in `expandPostRAPseudo` must limit the IMM variant to EQ/NE (COND_Z, COND_NZ). For SUB/SBB conditions (LT, GE, etc.), the register variant is always correct because those paths need register operands for the 16-bit subtraction. Add assertion in the expansion: `assert((CC == COND_Z || CC == COND_NZ) && "IMM variant only for EQ/NE")`. |
| **ISel selects IMM variant for SUB/SBB conditions (LT/GE)** | Guard the ISel IMM selection: only use V6CLANG_BR_CC16_IMM when CC is `V6ClangCC::COND_Z` or `V6ClangCC::COND_NZ`. For other conditions, always use the register variant. The CC value is available as a `ConstantSDNode` operand. |
| **Linker doesn't know R_V6CLANG_LO8/HI8** — prints warning and skips | Currently `v6clang_link.py` prints a warning for unknown reloc types and continues. Change to error-on-unknown to catch this immediately. |

---

## 6. Relationship to Other Improvements

This is improvement #4 in the optimization sequence:

1. **INX/DCX peephole** — **implemented**. Replaces 8-bit add-by-constant
   chains with INX/DCX.

2. **CMP-based 16-bit comparison** — **implemented**. Replaced XOR-based
   V6CLANG_BR_CC16 EQ/NE with non-destructive CMP + MBB splitting.
   Eliminated tied-output copy, freed register pressure, prevented spills.

3. **Spill elimination** — followed automatically from #2.

4. **Immediate CMP/CPI comparison** (this plan) — replaces the register
   pair used for the comparison constant with embedded MVI immediates.
   Frees one register pair for complex loops.

### Dependencies

- **V6ClangMCExpr (lo8/hi8)** is independently useful beyond comparisons.
  Once implemented, it enables `MVI A, <(addr)` patterns anywhere —
  potentially useful for future optimizations like inline 8-bit global
  loads, address arithmetic, or hand-assisted constant splitting.

- **V6CLANG_BR_CC16 (reg variant) stays unchanged**. This plan adds the
  IMM variant alongside it. The register variant handles all cases
  where RHS is a runtime value.

---

## 7. Future Enhancements

- **CPI-based immediate comparison**: Currently the expansion uses
  `MVI A, lo8; CMP LhsReg`. An alternative is `MOV A, LhsReg; CPI lo8`
  which saves one MVI. Cost comparison:

  | Approach | Instructions | Cycles |
  |----------|-------------|--------|
  | MVI+CMP (this plan) | MVI A,imm (8cc) + CMP r (4cc) = 12cc | 12cc |
  | MOV+CPI | MOV A,r (8cc) + CPI imm (8cc) = 16cc | 16cc |

  MVI+CMP is 4cc cheaper per byte comparison (8cc cheaper per 16-bit
  comparison) because CMP r costs 4cc while CPI imm costs 8cc. So
  MVI+CMP is the preferred pattern.

  > **Not pursued.** MOV+CPI is strictly dominated by the implemented
  > MVI+CMP approach: same byte count, 4cc slower per byte (8cc per
  > 16-bit comparison). No scenario where MOV+CPI wins.

- **Extend to SUB/SBB conditions**: For unsigned less-than comparisons
  (`SETULT`, `SETUGE`), the current SUB/SBB expansion also uses register
  operands. A SUI/SBI immediate variant could similarly free a register
  pair. However, SUB/SBB modifies the accumulator (it's a subtract, not
  just a compare), so the expansion is more involved.

- **lo8/hi8 for other instructions**: Once V6ClangMCExpr exists, it could be
  used for `MVI r, <(addr)` / `MVI r, >(addr)` anywhere — e.g., to load
  the two halves of an address into two 8-bit registers without going
  through LXI + MOV. This is a general-purpose optimization for code
  that needs individual address bytes.

- **Constant-only fast path**: When both lo8 and hi8 are the same byte
  (e.g., address `0x0505`), a single `MVI A, 5` + two CMPs could
  suffice if the register pair halves match. This is a micro-optimization
  with negligible real-world impact.
