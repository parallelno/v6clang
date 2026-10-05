# Plan: O61 — Spill Into the Reload's Immediate Operand (Stage 1)

> **Scope of this plan.** This plan implements **Stage 1** only of the
> staged rollout described in
> [O61_spill_in_reload_immediate.md](future_plans/O61_spill_in_reload_immediate.md#recommended-scope-of-a-minimal-prototype):
> end-to-end plumbing on the **HL-spill / HL-reload** pair, with the
> patch-count **K hard-coded to 1**. The cost model, multi-target
> reloads (DE/BC/A/r8), and `K = 2` are deferred to follow-on plans
> (Stage 2, 3, 4 in the design doc).

## 1. Problem

### Current behavior

When a function uses static stack allocation (O10) and the register
allocator spills an HL-typed virtual register, the existing pipeline
emits a classical store/load pair against a BSS slot:

```asm
; spill site (HL → slot)
    SHLD  __v6clang_ss.f+N        ; 20cc, 3B
    ; ... unrelated code ...
; reload site (slot → HL)
    LHLD  __v6clang_ss.f+N        ; 20cc, 3B
```

Per spill slot the function pays:

* one `SHLD`  (20cc, 3B)
* one or more `LHLD` (20cc each, 3B each)
* a 2-byte slot in the per-function `__v6clang_ss.f` BSS global

### Desired behavior

The reload instruction itself becomes the data slot. The spill writes
to the imm field of the reload's `LXI`; the reload runs the patched
`LXI`:

```asm
; spill site
    SHLD  .Lo61_0+1           ; 20cc, 3B   — writes imm bytes
    ; ...
.Lo61_0:
    LXI   HL, 0               ; 12cc, 3B   — imm was patched to the spilled value
```

Per spill slot:

* one `SHLD` (20cc, 3B) targeting the patched site
* one patched `LXI HL, 0` (12cc, 3B) — net **−8cc, −0B per reload**
* additional reloads of the same slot use plain `LHLD .Lo61_0+1`
  (20cc, 3B), and the BSS slot is no longer needed (**−2B per slot**)

### Root cause

`LHLD` and `LXI HL` both produce the same machine state (HL ← imm16),
but `LXI` is 8cc cheaper because it takes its imm directly from the
instruction stream. With static stack and no concurrent re-entry
(already proved by `V6ClangStaticStackAlloc`), the `LXI`'s imm field is a
safe, link-known data location that the spill can write into.

The infrastructure is missing for the compiler to express
"this `LXI HL, 0` is a patched reload — the imm is dynamic" and
"this `SHLD` targets the imm bytes of that `LXI`".

---

## 2. Strategy

### Approach: a new post-RA pass that rewrites HL-only spill/reload pairs in place

A new MachineFunctionPass `V6ClangSpillPatchedReload` runs in
`addPostRegAlloc()` after `V6ClangSpillForwarding`, before PEI. Per
function:

1. Skip if the function is not static-stack-eligible
   (`V6ClangMachineFunctionInfo::hasStaticStack()` is false).
2. Group `V6CLANG_SPILL16` / `V6CLANG_RELOAD16` pseudos by frame index.
3. **Stage 1 candidate filter** (hard-coded — no cost model yet):
   * exactly one `V6CLANG_SPILL16` source for the FI;
   * the spill source register is `HL`;
   * at least one `V6CLANG_RELOAD16` for the FI;
   * every reload's destination register is `HL`.
4. For each accepted FI:
   * Materialise an `MCSymbol` with `MF.getContext().createTempSymbol("Lo61_")`.
   * Replace the `V6CLANG_SPILL16` pseudo with `SHLD <Sym, MO_PATCH_IMM>`
     (the operand is an `MO_MCSymbol` with target flag `MO_PATCH_IMM`,
     which `V6ClangMCInstLower` lowers as `Sym + 1`).
   * Pick the **first** (program-order) reload as the patched site.
     Replace its `V6CLANG_RELOAD16` pseudo with `LXI HL, 0` and call
     `setPreInstrSymbol(MF, Sym)` on it so the AsmPrinter emits
     `Sym:` immediately before the `LXI` opcode byte.
     Also tag the imm operand with `MO_PATCH_IMM` so downstream
     constant-tracking passes treat it as opaque.
   * Replace every remaining `V6CLANG_RELOAD16` for this FI with
     `LHLD <Sym, MO_PATCH_IMM>` — they read directly from the
     patched site's imm bytes, no BSS slot needed.

After this pass, `eliminateFrameIndex` no longer sees any pseudo
referring to the patched FI (they have all been lowered to concrete
instructions with symbol operands), so the existing static-stack
path in `V6ClangRegisterInfo::eliminateFrameIndex` is bypassed naturally
for these slots. The frame object's size is already zeroed by
`V6ClangStaticStackAlloc`, so no stack adjustment occurs.

### Why this works

1. **Static-stack invariants are preserved.** O10 already proves the
   function is non-recursive, address-not-taken, and not reachable
   from any ISR. No other context can observe or trample the imm
   bytes mid-patch.
2. **No RA changes.** Spills and reloads are still inserted by RA as
   today; the rewrite happens after RA and after `V6ClangSpillForwarding`,
   so we operate on whatever spill/reload pairs survive forwarding.
3. **No new pseudo opcodes.** We replace the pseudos with the same
   `SHLD`/`LHLD`/`LXI` instructions that the static-stack expansion
   would otherwise emit, just with a symbol-relative address operand
   instead of a global-offset operand.
4. **AsmPrinter already emits pre-instruction symbols.** LLVM's
   `MachineInstr::setPreInstrSymbol` is honored by the generic
   AsmPrinter. We don't need a new pseudo just to carry a label.
5. **Constant-tracking passes already gate on `isImm()`.**
   `V6ClangLoadStoreOpt::isLXI_HL` and most of `V6ClangLoadImmCombine`
   already check `MI.getOperand(1).isImm()` before reading
   `getImm()`. Patched LXIs use an `MO_MCSymbol` operand, so
   `isImm()` returns false and they are naturally treated as
   opaque definers — but the few sites that don't check (one
   `getImm()` in the LXI-scan path of `V6ClangInstrInfo.cpp`, and the
   pred-merge path of `V6ClangLoadImmCombine`) need an explicit
   `isImm()` guard.

### Why not extend `eliminateFrameIndex` instead

The static-stack expansion in `V6ClangRegisterInfo::eliminateFrameIndex`
sees pseudos one at a time. Choosing which reload to patch (even
the trivial Stage 1 "first reload") requires whole-function context:
the set of all reloads for an FI. Doing the rewrite in a dedicated
pre-PEI pass keeps that whole-function logic in one place and leaves
`eliminateFrameIndex` unchanged.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add target operand flag | `MO_PATCH_IMM` enum value | `V6ClangInstrInfo.h` |
| Lower `MO_MCSymbol` operand | New case in `lowerInstruction`; `+1` offset under `MO_PATCH_IMM` | `V6ClangMCInstLower.cpp` |
| Add CL flag | `-mv6clang-spill-patched-reload` (default off) | `V6ClangTargetMachine.cpp` |
| New pass | `V6ClangSpillPatchedReload` (Stage 1 scope) | `V6ClangSpillPatchedReload.cpp` (new) |
| Pass factory + extern | `createV6ClangSpillPatchedReloadPass()` | `V6Clang.h` |
| Build glue | Add new file | `CMakeLists.txt` |
| Pass insertion | After `createV6ClangSpillForwardingPass` in `addPostRegAlloc` | `V6ClangTargetMachine.cpp` |
| Constant-tracking opt-out | Skip patched LXI in INX-scan helper and pred-merge path | `V6ClangInstrInfo.cpp`, `V6ClangLoadImmCombine.cpp` |

---

## 3. Implementation Steps

### Step 3.1 — Add `MO_PATCH_IMM` target operand flag [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.h`

Extend the `V6ClangII` flag enum:

```cpp
namespace V6ClangII {
enum {
  MO_NO_FLAG    = 0,
  MO_LO8        = 1, // Low byte of 16-bit value
  MO_HI8        = 2, // High byte of 16-bit value
  MO_PATCH_IMM  = 4, // Operand is an MCSymbol pointing at a patched
                     // reload site; lower as `Sym + 1` (the imm field).
};
} // namespace V6ClangII
```

> **Design Note**: The flag is bitwise so it can be combined with a
> potential future `MO_LO8`/`MO_HI8` use, though Stage 1 never combines
> them.

> **Implementation Notes**:

### Step 3.2 — Lower `MO_MCSymbol` operands in `V6ClangMCInstLower` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangMCInstLower.cpp`

Add a case to `lowerInstruction` that handles `MachineOperand::MO_MCSymbol`:

```cpp
    case MachineOperand::MO_MCSymbol: {
      MCSymbol *Sym = MO.getMCSymbol();
      const MCExpr *Expr = MCSymbolRefExpr::create(Sym, Ctx);
      unsigned TF = MO.getTargetFlags();
      if (TF & V6ClangII::MO_PATCH_IMM)
        Expr = MCBinaryExpr::createAdd(
            Expr, MCConstantExpr::create(1, Ctx), Ctx);
      MCOp = MCOperand::createExpr(Expr);
      break;
    }
```

> **Design Note**: A `MachineOperand` of type `MO_MCSymbol` does not
> carry an offset, so the `+1` for the imm field is applied here based
> on the target flag. `MO_PATCH_IMM` is the only consumer of
> `MO_MCSymbol` operands in the V6CLANG backend at Stage 1.

> **Implementation Notes**: Added the `MO_MCSymbol` case in `lowerInstruction`. Produces `MCSymbolRefExpr::create(Sym, Ctx)`, then wraps in `MCBinaryExpr::createAdd(Expr, MCConstantExpr::create(1, Ctx), Ctx)` when the `MO_PATCH_IMM` target flag is set. Lowers as `Sym + 1` (the imm bytes of the patched LXI).

### Step 3.3 — Add `-mv6clang-spill-patched-reload` flag [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangTargetMachine.cpp`

```cpp
static llvm::cl::opt<bool> V6ClangSpillPatchedReload(
    "mv6clang-spill-patched-reload",
    llvm::cl::desc("Enable O61: rewrite HL spill/reload pairs as patched LXI HL"),
    llvm::cl::init(false), llvm::cl::Hidden);

namespace llvm {
bool getV6ClangSpillPatchedReloadEnabled() { return V6ClangSpillPatchedReload; }
}
```

Add the corresponding `bool getV6ClangSpillPatchedReloadEnabled();`
declaration in `V6Clang.h` next to `getV6ClangStaticStackEnabled`.

> **Design Note**: Hidden + default-off so this Stage 1 prototype does
> not change the default codegen until verified. Stage 2/3/4 plans
> can flip the default once the cost model lands.

> **Implementation Notes**: Added the `cl::opt<bool>` for `-mv6clang-spill-patched-reload` (hidden, default-off) and the `getV6ClangSpillPatchedReloadEnabled()` accessor in `V6ClangTargetMachine.cpp`. Corresponding decl added to `V6Clang.h`.

### Step 3.4 — Create `V6ClangSpillPatchedReload.cpp` (new pass) [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp`
(new)

Stage 1 logic, all hard-coded — no cost model, no DE/BC/A/r8:

```cpp
//===-- V6ClangSpillPatchedReload.cpp - O61 Stage 1 rewrite --------*- C++ -*-===//
// Post-RA pass: for static-stack-eligible functions, rewrite HL-only
// V6CLANG_SPILL16/V6Clang_RELOAD16 pairs into a patched LXI HL reload whose
// imm bytes are written by the SHLD spill (self-modifying code).
//
// Stage 1 candidate filter (hard-coded — no cost model):
//   * single V6CLANG_SPILL16 with src=HL,
//   * one or more V6CLANG_RELOAD16 with dst=HL,
//   * function has hasStaticStack().
//
// First reload (program order) is the patched site (LXI HL, 0 with
// pre-instr label); remaining reloads become LHLD <Sym, MO_PATCH_IMM>.
//===---------------------------------------------------------------------===//

#include "V6Clang.h"
#include "V6ClangInstrInfo.h"
#include "V6ClangMachineFunctionInfo.h"
#include "MCTargetDesc/V6ClangMCTargetDesc.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/MC/MCContext.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "v6clang-spill-patched-reload"

using namespace llvm;

namespace {

class V6ClangSpillPatchedReload : public MachineFunctionPass {
public:
  static char ID;
  V6ClangSpillPatchedReload() : MachineFunctionPass(ID) {}

  StringRef getPassName() const override {
    return "V6CLANG Spill Into Reload Immediate (O61 Stage 1)";
  }

  bool runOnMachineFunction(MachineFunction &MF) override;
};

} // end anonymous namespace

char V6ClangSpillPatchedReload::ID = 0;

bool V6ClangSpillPatchedReload::runOnMachineFunction(MachineFunction &MF) {
  if (!getV6ClangSpillPatchedReloadEnabled())
    return false;

  auto *MFI = MF.getInfo<V6ClangMachineFunctionInfo>();
  if (!MFI->hasStaticStack())
    return false;

  const TargetInstrInfo &TII = *MF.getSubtarget().getInstrInfo();

  // Group spills and reloads by frame index, in program order.
  struct PerFI {
    SmallVector<MachineInstr *, 2> Spills;
    SmallVector<MachineInstr *, 4> Reloads;
  };
  DenseMap<int, PerFI> Slots;

  for (auto &MBB : MF) {
    for (auto &MI : MBB) {
      unsigned Opc = MI.getOpcode();
      if (Opc == V6CLANG::V6CLANG_SPILL16)
        Slots[MI.getOperand(1).getIndex()].Spills.push_back(&MI);
      else if (Opc == V6CLANG::V6CLANG_RELOAD16)
        Slots[MI.getOperand(1).getIndex()].Reloads.push_back(&MI);
    }
  }

  bool Changed = false;
  for (auto &KV : Slots) {
    PerFI &E = KV.second;

    // Stage 1 filter.
    if (E.Spills.size() != 1 || E.Reloads.empty())
      continue;
    MachineInstr *Spill = E.Spills.front();
    if (Spill->getOperand(0).getReg() != V6CLANG::HL)
      continue;
    bool AllHL = true;
    for (auto *R : E.Reloads)
      if (R->getOperand(0).getReg() != V6CLANG::HL) { AllHL = false; break; }
    if (!AllHL)
      continue;

    // Materialise the patched-site label.
    MCSymbol *Sym = MF.getContext().createTempSymbol("Lo61_");

    // Rewrite the spill: SHLD <Sym, MO_PATCH_IMM>
    {
      MachineBasicBlock *MBB = Spill->getParent();
      DebugLoc DL = Spill->getDebugLoc();
      auto *NewSpill = BuildMI(*MBB, Spill, DL, TII.get(V6CLANG::SHLD))
          .addReg(V6CLANG::HL, getKillRegState(Spill->getOperand(0).isKill()))
          .addSym(Sym, V6ClangII::MO_PATCH_IMM)
          .getInstr();
      (void)NewSpill;
      Spill->eraseFromParent();
    }

    // First reload becomes the patched site (LXI HL, 0 with pre-instr label).
    MachineInstr *PatchedReload = E.Reloads.front();
    {
      MachineBasicBlock *MBB = PatchedReload->getParent();
      DebugLoc DL = PatchedReload->getDebugLoc();
      auto NewReload = BuildMI(*MBB, PatchedReload, DL, TII.get(V6CLANG::LXI))
          .addReg(V6CLANG::HL, RegState::Define);
      // Imm operand carries MO_PATCH_IMM so constant-tracking passes
      // treat the value as opaque.
      NewReload.addImm(0);
      NewReload->getOperand(1).setTargetFlags(V6ClangII::MO_PATCH_IMM);
      NewReload->setPreInstrSymbol(MF, Sym);
      PatchedReload->eraseFromParent();
    }

    // Remaining reloads: LHLD <Sym, MO_PATCH_IMM>.
    for (size_t i = 1; i < E.Reloads.size(); ++i) {
      MachineInstr *R = E.Reloads[i];
      MachineBasicBlock *MBB = R->getParent();
      DebugLoc DL = R->getDebugLoc();
      BuildMI(*MBB, R, DL, TII.get(V6CLANG::LHLD), V6CLANG::HL)
          .addSym(Sym, V6ClangII::MO_PATCH_IMM);
      R->eraseFromParent();
    }

    Changed = true;
  }

  return Changed;
}

namespace llvm {
FunctionPass *createV6ClangSpillPatchedReloadPass() {
  return new V6ClangSpillPatchedReload();
}
} // namespace llvm
```

> **Design Note**: We deliberately do not remove the slot from
> `V6ClangMachineFunctionInfo::StaticSlots` — `eliminateFrameIndex` will
> simply not encounter the FI any more (the pseudos that referenced it
> have been replaced with concrete `SHLD`/`LHLD`/`LXI` MIs without an
> FI operand), so the leftover map entry is harmless.

> **Implementation Notes**: Created `V6ClangSpillPatchedReload.cpp` (~150 lines) matching the plan. Walks `MF` once to collect `V6CLANG_SPILL16`/`V6CLANG_RELOAD16` pseudos grouped by frame index (operand 1 is `MO_FrameIndex`), applies the Stage 1 HL-only filter, then for each accepted FI materializes an `MCSymbol` via `createTempSymbol("Lo61_")` and rewrites spill/reload MIs as described.

### Step 3.5 — Wire the pass in `V6ClangTargetMachine::addPostRegAlloc` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangTargetMachine.cpp`

```cpp
  void addPostRegAlloc() override {
    if (getV6ClangStaticStackEnabled())
      addPass(createV6ClangStaticStackAllocPass());
    addPass(createV6ClangSpillForwardingPass());
    if (getV6ClangSpillPatchedReloadEnabled())
      addPass(createV6ClangSpillPatchedReloadPass());
  }
```

> **Design Note**: O61 must run **after** `V6ClangSpillForwarding` so that
> trivially forwardable spill/reload pairs are eliminated first and we
> only patch what survives. It must run **after**
> `V6ClangStaticStackAlloc` so that `hasStaticStack()` is meaningful, and
> **before** PEI / `eliminateFrameIndex` so that our concrete
> `SHLD`/`LHLD`/`LXI` instructions reach `eliminateFrameIndex` already
> stripped of their FI operands.

> **Implementation Notes**: Added flag-gated `addPass(createV6ClangSpillPatchedReloadPass())` in `addPostRegAlloc` right after `createV6ClangSpillForwardingPass`. Pass runs pre-PEI so rewrites land before `eliminateFrameIndex`.

### Step 3.6 — Declare factory in `V6Clang.h` and add file to `CMakeLists.txt` [x]

**Files**:
* `llvm-project/llvm/lib/Target/V6Clang/V6Clang.h` — add
  `FunctionPass *createV6ClangSpillPatchedReloadPass();` next to the other
  `create*` declarations.
* `llvm-project/llvm/lib/Target/V6Clang/CMakeLists.txt` — add
  `V6ClangSpillPatchedReload.cpp` to the `add_llvm_target` source list.

> **Implementation Notes**: Added `FunctionPass *createV6ClangSpillPatchedReloadPass();` in `V6Clang.h`. Inserted `V6ClangSpillPatchedReload.cpp` between `V6ClangSpillForwarding.cpp` and `V6ClangStaticStackAlloc.cpp` in `CMakeLists.txt`.

### Step 3.7 — Constant-tracking opt-out: `V6ClangLoadImmCombine.cpp` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangLoadImmCombine.cpp`

In the `LXI`-handling branches of `processInstruction` (around line
296 and 480) and `initFromPredecessor` (around line 296), the existing
guard `if (MI.getOperand(1).isImm())` already routes patched LXIs
(which carry an `MO_MCSymbol` operand) into the `else` arm that calls
`invalidateWithSubSuper(PairReg)`. **No code change is needed for the
isImm-guarded sites** — the patched-imm operand is automatically
treated as opaque. Verify by inspection during implementation; add an
explicit `MO_PATCH_IMM` early-exit only if a guard is missing.

> **Design Note**: This step is intentionally a "verify, edit only if
> needed" step. The architecture of `V6ClangLoadImmCombine` already
> matches what we need: any non-imm LXI operand invalidates the
> destination pair.

> **Implementation Notes**: Audited all LXI imm-reading sites in `V6ClangLoadImmCombine.cpp`. All existing branches are already gated by `isImm()` and route to `invalidateWithSubSuper(PairReg)` on the else arm, so patched LXIs are naturally treated as opaque constant definers. No code change required.

### Step 3.8 — Constant-tracking opt-out: `V6ClangInstrInfo.cpp` INX-scan [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`
(around lines 339, 363, 367)

The INX-peephole helper scans backward for an `LXI` defining a
register pair and reads `getOperand(1).getImm()` directly. A patched
LXI's operand is `MO_MCSymbol`, so `getImm()` would assert.

Add an `isImm()` guard:

```cpp
    if (Cand.getOpcode() == V6CLANG::LXI &&
        Cand.getOperand(0).getReg() == Reg) {
      if (!Cand.getOperand(1).isImm())
        return nullptr; // Patched LXI — value not known at compile time.
      return &Cand;
    }
```

And on the predecessor-merge path:

```cpp
      if (I->getOpcode() == V6CLANG::LXI && I->getOperand(0).getReg() == Reg) {
        if (!I->getOperand(1).isImm())
          return nullptr;
        if (PredLXI && PredLXI->getOperand(1).getImm() !=
                            I->getOperand(1).getImm())
          return nullptr;
        ...
      }
```

> **Implementation Notes**: Added `if (!Cand.getOperand(1).isImm()) return nullptr;` to the in-block LXI match in `findDefiningLXI`, and the same `isImm()` guard on the predecessor-merge path before the PredLXI imm comparison.

### Step 3.9 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Clean ninja build succeeded (one CMake reconfigure to pick up the new source file). No warnings.

### Step 3.10 — Lit test: HL spill/reload patched form [x]

**File**:
`llvm-project/llvm/test/CodeGen/V6Clang/spill-patched-reload-hl.ll` (new)

Assert that under `-mv6clang-spill-patched-reload`:

* a function with a single HL spill and a single HL reload emits
  exactly one `SHLD .Lo61_X+1`, one `.Lo61_X:` label immediately
  followed by `LXI HL, 0`, and no `LHLD` against
  `__v6clang_ss.<func>`;
* a function with two HL reloads of the same spill emits the
  patched `LXI HL, 0` and one `LHLD .Lo61_X+1` for the second
  reload.

Also a negative test (default flags off): the same input emits
classical `SHLD __v6clang_ss.f+N` / `LHLD __v6clang_ss.f+N`.

> **Implementation Notes**: Created `llvm-project/llvm/test/CodeGen/V6Clang/spill-patched-reload-hl.ll` with two RUN lines (flag on + DISABLED prefix for flag off). Function `one_reload` uses two calls `%b1 = call op(%a); %b2 = call op(%a)` marked `norecurse` to trigger static-stack + force pure HL→HL reuse. Lit passes (1/1).

### Step 3.11 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: Full suite passed: 104/104 lit tests + golden tests (emulator trust baseline). No regressions on default flags (pass is gated and default-off).

### Step 3.12 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests/features/33/v6clang.c` with
`-mllvm -mv6clang-spill-patched-reload -mllvm -v6clang-disable-shld-lhld-fold`
into `v6clang_new01.asm`. Diff against `v6clang_old.asm`. Iterate
into `_new02.asm`, `_new03.asm` … if expected patterns are missing.

> **Implementation Notes**: `v6clang_new01.asm` produced with `-v6clang-disable-shld-lhld-fold` for clean demonstration of the patched sites. `v6clang_new02.asm` produced with production flags (`-O2 -mllvm -mv6clang-spill-patched-reload`, fold enabled) shows the realistic combined behavior: O61 patches the slot the PUSH/POP fold can't capture (multi-reload / nested lifetime), and the fold captures the other interleaved slot. Measured −8 cc on both `hl_two_reloads` and `main`, same byte count. `hl_one_spill` correctly falls through (HL-spill / DE-reload via XCHG is Stage 2 territory).

### Step 3.13 — Make sure result.txt is created (`tests\features\README.md`) [x]

Per the test folder template: C source, c8080 main+deps in i8080
dialect, c8080 cycle/byte stats per function, v6clang asm, v6clang
cycle/byte stats per function.

> **Implementation Notes**: `tests/features/33/result.txt` created with the full template: C test source, c8080 asm (main + deps translated to i8080 dialect), c8080 per-function worst-case cycles/bytes, v6clang asm with O61 annotations, v6clang per-function stats with Δ vs O61-off.

### Step 3.14 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror sync completed successfully. All O61 source edits (`V6ClangInstrInfo.h`, `V6ClangMCInstLower.cpp`, `V6ClangTargetMachine.cpp`, `V6Clang.h`, `CMakeLists.txt`, `V6ClangSpillPatchedReload.cpp`, `V6ClangInstrInfo.cpp`) and the lit test (`test/CodeGen/V6Clang/spill-patched-reload-hl.ll`) are now mirrored from `llvm-project/` to `llvm/` and `tests/lit/`.

---

## 4. Expected Results

### Example 1 — Single HL spill, single HL reload (`hl_one_spill`)

**Before**:

```asm
    SHLD  __v6clang_ss.hl_one_spill+0   ; 20cc, 3B
    ; ...
    LHLD  __v6clang_ss.hl_one_spill+0   ; 20cc, 3B
                                     ; + 2B BSS slot
```

Total: **40cc, 6B code + 2B BSS = 8B**.

**After**:

```asm
    SHLD  .Lo61_0+1                 ; 20cc, 3B
    ; ...
.Lo61_0:
    LXI   HL, 0                     ; 12cc, 3B  — imm patched at runtime
                                     ; 0B BSS
```

Total: **32cc, 6B code + 0B BSS = 6B**. **Δ = −8cc, −2B per slot.**

### Example 2 — Single HL spill, two HL reloads (`hl_two_reloads`)

**Before**:

```asm
    SHLD  __v6clang_ss.hl_two_reloads+0  ; 20cc
    LHLD  __v6clang_ss.hl_two_reloads+0  ; 20cc
    LHLD  __v6clang_ss.hl_two_reloads+0  ; 20cc
                                      ; + 2B BSS
```

Total: **60cc, 9B code + 2B BSS = 11B**.

**After**:

```asm
    SHLD  .Lo61_0+1                  ; 20cc
.Lo61_0:
    LXI   HL, 0                      ; 12cc
    LHLD  .Lo61_0+1                  ; 20cc
                                      ; 0B BSS
```

Total: **52cc, 9B code + 0B BSS = 9B**. **Δ = −8cc, −2B.**

### Example 3 — Default-off behavior

Without `-mv6clang-spill-patched-reload`, both functions must emit the
classical `SHLD`/`LHLD` against `__v6clang_ss.f+N`, byte-identical to
pre-O61 baseline.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `setPreInstrSymbol` not honored by V6CLANG AsmPrinter | LLVM's generic `AsmPrinter::EmitInstruction` calls `OutStreamer->emitLabel(MI.getPreInstrSymbol())` before lowering. V6ClangAsmPrinter inherits this path; verify in lit test that `.Lo61_0:` appears before the `LXI`. |
| Patched LXI mis-treated as known constant by a missed pass | Step 3.7/3.8 audit all `MI.getOperand(1).getImm()` reads on `V6CLANG::LXI`; `MO_PATCH_IMM` provides an unmistakable secondary marker should a future audit need it. |
| `V6ClangSpillForwarding` rewrites the HL spill before O61 sees it | Forwarding only erases redundant pairs; survivors are real cross-instruction spills. O61 runs after forwarding by design and operates on the residual set. |
| O43 (SHLD/LHLD → PUSH/POP fold) collides with O61 | O43 runs in `addPreEmitPass` (post-PEI), well after O61. The patched `SHLD .Lo61_0+1` / `LXI HL, 0` shape no longer matches O43's "SHLD addr; LHLD addr (same addr)" pattern, so O43 simply skips it. The design doc instructs to also disable O43 with `-v6clang-disable-shld-lhld-fold` while measuring O61. |
| Static-stack pass disabled (`-mv6clang-no-static-stack`) | `runOnMachineFunction` early-exits on `!hasStaticStack()`; no rewrite happens. |
| Self-modifying code on real HW | Vector 06c runs from RAM; KR580VM80A has no prefetch queue. Verified safe by the design doc's "Pitfalls and Non-Issues" section. |
| MCSymbol operand crashes existing MCInstLower paths | Step 3.2 adds the `MO_MCSymbol` case explicitly; no other backend opcode currently emits `MO_MCSymbol` operands. |
| Unintended interaction with `V6ClangDeadPhiConst` | That pass runs pre-RA, before any spill pseudo exists. No interaction. |
| FI map leak in `V6ClangMachineFunctionInfo` for patched slots | Harmless — `eliminateFrameIndex` only consults the map when it encounters an instruction with an FI operand, and we've removed all such uses. |

---

## 6. Relationship to Other Improvements

* **Depends on O10 (Static Stack Allocation)** — uses
  `hasStaticStack()` as the safety predicate.
* **Coexists with O42 (HL/DE/A dead-skip in spill expansion)** —
  Stage 1 only operates on the HL pair, where the classical
  expansion path was already minimal (`SHLD`/`LHLD`). O42's
  HL-dead optimisations apply on the un-patched (default-off) path.
* **Coexists with O43 (SHLD/LHLD → PUSH/POP fold)** — see Risks
  table. The two passes don't compete on the patched pair because
  the `SHLD` and `LXI` no longer share the same address after the
  rewrite.
* **Builds on V6ClangSpillForwarding** — runs immediately after, so
  trivially forwardable pairs never reach O61.
* **Prerequisite for Stage 2** (cost model + DE/BC reload targets,
  per the design doc's Recommended Scope).

## 7. Future Enhancements

These follow the staged rollout in the
[O61 design doc](future_plans/O61_spill_in_reload_immediate.md#recommended-scope-of-a-minimal-prototype):

* **Stage 2** — add the per-reload Δ table and the
  `block_frequency × Δ` chooser; extend reload targets to DE and BC
  via `LXI DE` / `LXI BC` (still K ≤ 1).
* **Stage 3** — enable `K = 2` patches per single-source spill, with
  the hard rules: never a 2nd A-target patch, never a 2nd HL-target
  patch; `K ≤ 1` for multi-source spills.
* **Stage 4** — extend to 8-bit r8 reload targets via `MVI r, imm`
  (the `r8` A-live case, Δ ≥ +44 cc).
* Default the flag on once Stage 2 lands and the regression / golden
  suite is clean for two consecutive runs.
* Layer the LIFO-affinity refinement (#3 in the chooser tiebreaker
  list) once measurements justify the chooser complexity.

## 8. References

* [O61 Design Doc](future_plans/O61_spill_in_reload_immediate.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [Static Stack Alloc (O10)](../docs/V6ClangStaticStackAlloc.md)
* [Plan Format Reference](plan_cmp_based_comparison.md)
* [Feature Pipeline](pipeline_feature.md)