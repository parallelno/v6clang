# Plan: Static Stack Allocation for Non-Reentrant Functions (O10)

## 1. Problem

### Current behavior

The 8080 has **no stack-relative addressing** (`MOV r,[SP+offset]` does not
exist). Every spill/reload requires a multi-instruction sequence:

```asm
; Current V6CLANG_SPILL8 expansion (non-H/L register):  52cc, 8 bytes
PUSH HL           ; 12cc — save address register
LXI  HL, offset   ; 10cc — load frame offset
DAD  SP           ; 10cc — HL = SP + offset
MOV  M, r         ;  8cc — store via [HL]
POP  HL           ; 12cc — restore address register

; Current V6CLANG_RELOAD8 expansion (non-H/L register): 52cc, 8 bytes
PUSH HL           ; 12cc
LXI  HL, offset   ; 10cc
DAD  SP           ; 10cc
MOV  r, M         ;  8cc
POP  HL           ; 12cc
```

For 16-bit pairs the cost is even higher (66cc for BC/DE, ~80cc for HL due
to DE temp dance).

Additionally, every function with a stack frame pays prologue/epilogue costs:
```asm
; Prologue:  26cc, 5 bytes
LXI  HL, -FrameSize   ; 10cc
DAD  SP                ; 10cc
SPHL                   ;  6cc

; Epilogue: 26cc, 5 bytes
LXI  HL, FrameSize    ; 10cc
DAD  SP               ; 10cc
SPHL                  ;  6cc
```

### Desired behavior

For functions that are provably **non-reentrant** (non-recursive, not called
from interrupt handlers), replace the entire stack frame with a statically
allocated global memory region. This turns every spill/reload into a direct
memory access:

```asm
; Static SPILL8 for A:        16cc, 3 bytes
STA  __v6clang_ss+offset

; Static SPILL8 for other r:  42cc, 6 bytes
PUSH HL
LXI  HL, __v6clang_ss+offset
MOV  M, r
POP  HL

; Static SPILL16 for HL:      16cc, 3 bytes
SHLD __v6clang_ss+offset

; Static SPILL16 for DE:      24cc, 5 bytes
XCHG
SHLD __v6clang_ss+offset
XCHG

; Prologue/epilogue: ELIMINATED (0cc, 0 bytes)
```

### Root cause

Stack-relative addressing on the 8080 requires computing `SP + offset` at
runtime via `LXI HL, offset; DAD SP` (20cc, 4 bytes). For functions that
never need reentrant frames, this runtime computation is unnecessary — the
addresses are known at compile time.

### Impact

| Metric | Stack-relative | Static | Savings |
|--------|---------------|--------|---------|
| SPILL8 (A) | 52cc, 8B | 16cc, 3B | **36cc, 5B** |
| SPILL8 (B,C,D,E) | 52cc, 8B | 42cc, 6B | **10cc, 2B** |
| SPILL8 (H,L) | 80cc, 12B | ~58cc, 9B | **22cc, 3B** |
| SPILL16 (HL) | 80cc, 12B | 16cc, 3B | **64cc, 9B** |
| SPILL16 (DE) | 66cc, 10B | 24cc, 5B | **42cc, 5B** |
| SPILL16 (BC) | 66cc, 10B | 42cc, 6B | **24cc, 4B** |
| RELOAD8 (A) | 52cc, 8B | 16cc, 3B | **36cc, 5B** |
| RELOAD16 (HL) | 88cc, 13B | 16cc, 3B | **72cc, 10B** |
| RELOAD16 (DE) | 66cc, 10B | 24cc, 5B | **42cc, 5B** |
| Prologue | 26cc, 5B | 0 | **26cc, 5B** |
| Epilogue | 26cc, 5B | 0 | **26cc, 5B** |

A function with 4 spill/reload pairs saves **~200-400cc per call**
plus 52cc from eliminated prologue/epilogue.

---

## 2. Strategy

### Approach: Post-RA MachineFunctionPass + eliminateFrameIndex modification

Two components work together:

1. **V6ClangStaticStackAlloc** — a `MachineFunctionPass` registered in
   `addPostRegAlloc()` (runs after register allocation, before
   PrologEpilogInserter). For each eligible function:
   - Computes the local frame layout and total size
   - Creates a per-function `@__v6clang_ss.<funcname>` `GlobalVariable` in BSS
   - Stores per-function metadata in `V6ClangMachineFunctionInfo`
   - Zeros out frame object sizes so PEI computes StackSize = 0

   **Implementation note**: Originally planned as single shared GV
   `@__v6clang_static_stack`, changed to per-function GVs to avoid
   `GlobalVariable::setValueType` (not available in LLVM 18).

2. **Modified `eliminateFrameIndex`** in `V6ClangRegisterInfo.cpp` — checks
   `V6ClangMachineFunctionInfo` for static allocation data. If present,
   expands spill/reload pseudos using direct global addressing instead
   of SP-relative `LXI+DAD SP`.

3. **Modified `emitPrologue`/`emitEpilogue`** in `V6ClangFrameLowering.cpp` —
   for fully-static functions, skips SP adjustment (existing code already
   handles `StackSize == 0` correctly; we just need to mark the function).

### Why this works

- **After RA**: all frame objects (spill slots, locals) are finalized with
  known sizes. The pass can compute the exact static memory layout.
- **Before PEI**: the pass stores metadata; PEI then calls `emitPrologue`
  (which checks the flag) and `eliminateFrameIndex` (which uses static
  addresses). No pseudo expansion is duplicated.
- **Correctness**: static allocation is only applied to non-reentrant
  functions where at most one invocation is active at any time. The
  global memory region safely replaces the stack frame.
- **No overlap (v1)**: each eligible function gets its own region in the
  static stack. This wastes some BSS but is simple and correct. SCC-based
  overlap can be added as a future enhancement.

### Eligibility criteria

A function is eligible if ALL of:
1. The `-mv6clang-static-stack` target option is enabled (opt-in for safety)
2. The function has `norecurse` attribute (inferred by LLVM's
   `PostOrderFunctionAttrs` at -O2)
3. The function is not marked with `"interrupt"` attribute
4. The function is **not reachable from any interrupt handler** (see
   interrupt reachability analysis below)
5. The function has non-fixed frame objects (spill slots or locals)

### Interrupt reachability analysis

LLVM's `norecurse` attribute only means "does not call itself directly or
indirectly." It does NOT mean "can never be active twice." A `norecurse`
function called from both `main()` and an interrupt handler IS reentrant:

```c
void foo(void) { /* norecurse */ }
void isr(void) __attribute__((interrupt)) { foo(); }
int main(void) { foo(); /* interrupted here → isr → foo again! */ }
```

To close this correctness gap, the pass must compute the set of functions
reachable from interrupt entry points and exclude them:

1. Scan all functions in the module for `"interrupt"` attribute
2. For each interrupt function, BFS/DFS the call graph collecting all
   transitive callees
3. Mark every function in the reachable set as **interrupt-reachable**
4. Interrupt-reachable functions are ineligible for static allocation

This matches the approach used by llvm-mos's `MOSNonReentrant` pass, which
walks the call graph from interrupt roots and marks all reachable functions
as reentrant. The analysis is ~20 lines of code (BFS from interrupt roots).

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Create V6ClangMachineFunctionInfo | Per-MF metadata for static stack | V6ClangMachineFunctionInfo.h (new) |
| Register MFInfo in target | Override `createMachineFunctionInfo` | V6ClangTargetMachine.h |
| Create V6ClangStaticStackAlloc | Post-RA pass computing allocation | V6ClangStaticStackAlloc.cpp (new) |
| Add `-mv6clang-static-stack` flag | Opt-in target option | V6ClangTargetMachine.cpp |
| Modify eliminateFrameIndex | Static expansion for eligible FIs | V6ClangRegisterInfo.cpp |
| Modify emitPrologue / emitEpilogue | Skip SP adjust for static frames | V6ClangFrameLowering.cpp |
| Register pass + CMake | Pipeline integration | V6ClangTargetMachine.cpp, V6Clang.h, CMakeLists.txt |

---

## 3. Implementation Steps

### Step 3.1 — Create V6ClangMachineFunctionInfo [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangMachineFunctionInfo.h` (new)

Create a `MachineFunctionInfo` subclass to store per-function static
allocation metadata.

```cpp
struct StaticFrameSlot {
  int64_t StaticOffset;  // Offset within __v6clang_static_stack
};

class V6ClangMachineFunctionInfo : public MachineFunctionInfo {
  bool UseStaticStack = false;
  GlobalVariable *StaticStackGV = nullptr;
  DenseMap<int, StaticFrameSlot> StaticSlots;  // FI → static offset

public:
  bool hasStaticStack() const;
  void setStaticStack(GlobalVariable *GV);
  void addStaticSlot(int FI, int64_t Offset);
  int64_t getStaticOffset(int FI) const;
  GlobalVariable *getStaticStackGV() const;
};
```

> **Design Notes**: Stores the mapping from frame index to absolute offset
> within the static stack global. `eliminateFrameIndex` queries this to
> decide whether to use static or SP-relative expansion.

> **Implementation Notes**: <empty>

### Step 3.2 — Register MFInfo in V6ClangTargetMachine [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangTargetMachine.h`

Override `createMachineFunctionInfo()` in `V6ClangTargetMachine` so that LLVM
creates a `V6ClangMachineFunctionInfo` for each `MachineFunction`:

```cpp
MachineFunctionInfo *createMachineFunctionInfo(
    BumpPtrAllocator &Allocator, const Function &F,
    const TargetSubtargetInfo *STI) const override;
```

> **Implementation Notes**: <empty>

### Step 3.3 — Add `-mv6clang-static-stack` target option [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangTargetMachine.cpp`

Add a `cl::opt<bool>` for the static stack feature:

```cpp
static cl::opt<bool> V6ClangStaticStack(
    "mv6clang-static-stack",
    cl::desc("Use static memory for non-reentrant function stack frames"),
    cl::init(false));
```

Expose via a getter in `V6Clang.h`:

```cpp
bool getV6ClangStaticStackEnabled();
```

> **Implementation Notes**: <empty>

### Step 3.4 — Create V6ClangStaticStackAlloc pass [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangStaticStackAlloc.cpp` (new)

The core module-aware allocation pass. Registered as a `MachineFunctionPass`
in `addPostRegAlloc()`.

**Algorithm (executed lazily on first MF invocation):**

1. Access `Module` from `MF.getFunction().getParent()`
2. Access `MachineModuleInfo` via `getAnalysis<MachineModuleInfoWrapperPass>()`
3. **Compute interrupt-reachable set:**
   a. For each function `F` in the Module with `"interrupt"` attribute,
      add `F` to a worklist
   b. BFS: for each function in the worklist, iterate its call graph
      callees; add unseen callees to the worklist and to the
      `InterruptReachable` set
   c. All functions in `InterruptReachable` are ineligible
4. For each function `F` in the Module:
   a. Get `MachineFunction *MF = MMI.getMachineFunction(F)`
   b. If null, not `norecurse`, has `"interrupt"` attr, is in
      `InterruptReachable`, or has no non-fixed frame objects → skip
   c. Compute local frame layout:
      - Iterate non-fixed, non-dead frame objects
      - Assign sequential offsets with alignment
      - Record total local frame size
5. Assign global offsets: each function's base = running total
6. Create `@__v6clang_static_stack` GlobalVariable:
   ```cpp
   auto *ArrTy = ArrayType::get(Type::getInt8Ty(Ctx), TotalSize);
   auto *GV = new GlobalVariable(M, ArrTy, false,
       GlobalValue::InternalLinkage,
       ConstantAggregateZero::get(ArrTy),
       "__v6clang_static_stack");
   ```
7. Store per-function info in V6ClangMachineFunctionInfo

**Per-function application (every invocation):**

For each eligible function:
- Mark all non-fixed frame objects as dead (size → 0) so PEI computes
  StackSize = 0. This auto-eliminates prologue/epilogue SP adjustment.
- Leave FrameIndex operands in place for `eliminateFrameIndex` to process.

> **Design Notes**:
> - Creating a GlobalVariable during a MachineFunctionPass is unusual but
>   safe — it has precedent in constant pool and jump table creation.
> - `addPostRegAlloc()` runs after RA but before PrologEpilogInserter,
>   ensuring frame objects exist but haven't been finalized.
> - Marking objects as dead via `MFI.setObjectSize(FI, 0)` makes PEI
>   compute StackSize = 0, so `emitPrologue`/`emitEpilogue` skip SP
>   adjustment without code changes.

> **Implementation Notes**: <empty>

### Step 3.5 — Modify eliminateFrameIndex for static expansion [x]

**File**: `llvm/lib/Target/V6Clang/V6ClangRegisterInfo.cpp`

At the top of `eliminateFrameIndex`, check for static allocation:

```cpp
auto *FuncInfo = MF.getInfo<V6ClangMachineFunctionInfo>();
if (FuncInfo && FuncInfo->hasStaticStack() &&
    FuncInfo->hasStaticSlot(FrameIndex)) {
  return expandStaticFrameIndex(II, SPAdj, FIOperandNum, FuncInfo);
}
// ... existing SP-relative expansion ...
```

**`expandStaticFrameIndex` handles each pseudo:**

**V6CLANG_LEA_FI** → `LXI HL, __v6clang_ss+offset` (no DAD SP):
```cpp
BuildMI(MBB, II, DL, TII.get(V6CLANG::LXI))
    .addReg(DstReg, RegState::Define)
    .addGlobalAddress(GV, StaticOffset);
```

**V6CLANG_SPILL8** — register-specific:
- **A**: `STA __v6clang_ss+offset` (16cc, 3B)
- **B,C,D,E**: `PUSH HL; LXI HL, addr; MOV M, r; POP HL` (42cc, 6B)
- **H or L**: `PUSH DE; MOV D,H/E,L; LXI HL, addr; MOV M, D/E;
  restore HL from DE; POP DE` (~58cc, 9B)

**V6CLANG_RELOAD8** — register-specific:
- **A**: `LDA __v6clang_ss+offset` (16cc, 3B)
- **B,C,D,E**: `PUSH HL; LXI HL, addr; MOV r, M; POP HL` (42cc, 6B)
- **H or L**: `PUSH DE; save non-target half; LXI HL, addr;
  MOV H/L, M; restore; POP DE` (~58cc, 9B)

**V6CLANG_SPILL16** — pair-specific:
- **HL**: `SHLD __v6clang_ss+offset` (16cc, 3B)
- **DE**: `XCHG; SHLD __v6clang_ss+offset; XCHG` (24cc, 5B)
- **BC**: `PUSH HL; LXI HL, addr; MOV M, C; INX HL; MOV M, B;
  POP HL` (50cc, 8B)

**V6CLANG_RELOAD16** — pair-specific:
- **HL**: `LHLD __v6clang_ss+offset` (16cc, 3B)
- **DE**: `XCHG; LHLD __v6clang_ss+offset; XCHG` (24cc, 5B)
- **BC**: `PUSH HL; LXI HL, addr; MOV C, M; INX HL; MOV B, M;
  POP HL` (50cc, 8B)

> **Design Notes**:
> - The static expansions mirror the SP-relative expansions but remove
>   `DAD SP` and use a GlobalAddress operand instead of an immediate
>   offset. For A and HL, dedicated instructions (STA/LDA/SHLD/LHLD)
>   are much cheaper.
> - XCHG for DE spill/reload: swaps DE↔HL (4cc, 1B), then SHLD/LHLD
>   stores/loads the value, then XCHG restores the swap. Non-destructive
>   and saves ~42cc vs SP-relative.
> - All expansions preserve registers other than the spilled/reloaded
>   register and FLAGS, matching the pseudo contracts.

> **Implementation Notes**: <empty>

### Step 3.6 — Register pass in pipeline [x]

**Files**: `llvm/lib/Target/V6Clang/V6ClangTargetMachine.cpp`,
`llvm/lib/Target/V6Clang/V6Clang.h`, `llvm/lib/Target/V6Clang/CMakeLists.txt`

1. In `V6Clang.h`, declare:
   ```cpp
   FunctionPass *createV6ClangStaticStackAllocPass();
   ```

2. In `V6ClangPassConfig`, add `addPostRegAlloc()` override:
   ```cpp
   void addPostRegAlloc() override {
     if (getV6ClangStaticStackEnabled())
       addPass(createV6ClangStaticStackAllocPass());
   }
   ```

3. In `CMakeLists.txt`, add `V6ClangStaticStackAlloc.cpp`.

> **Implementation Notes**: <empty>

### Step 3.7 — Build [x]

```bash
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

### Step 3.8 — Lit test: static spill/reload [x]

**File**: `llvm/lib/Target/V6Clang/tests/lit/CodeGen/V6Clang/static-stack-alloc.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -mv6clang-static-stack < %s | FileCheck %s

; Test that non-reentrant function with spills uses STA/LDA instead of
; DAD SP stack-relative access.
define i16 @spill_test(i16 %a, i16 %b) norecurse {
entry:
  %x = add i16 %a, 1
  %y = add i16 %b, 2
  %z = add i16 %x, %y
  call void @sink(i16 %x)         ; force %y, %z to survive the call
  %r = add i16 %y, %z
  ret i16 %r
}

declare void @sink(i16)

; CHECK-LABEL: spill_test:
; Static spill should use STA/SHLD, not DAD SP.
; CHECK-NOT: DAD SP
; CHECK: {{STA|SHLD}}
; CHECK: CALL sink
; CHECK: {{LDA|LHLD}}
; CHECK-NOT: DAD SP
```

### Step 3.9 — Run regression tests [x]

```bash
python tests\run_all.py
```

### Step 3.10 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case and verify static stack allocation in
the generated assembly; confirm elimination of DAD SP in eligible
functions.

### Step 3.11 — Make sure result.txt is created. `tests\features\README.md` [x]

### Step 3.12 — Sync mirror [x]

```bash
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Example 1: Function with multiple i16 spills across a call

**Before** (stack-relative, 2 spill/reload pairs + prologue/epilogue):
```asm
spill_test:
    LXI  HL, -4        ; 10cc — prologue
    DAD  SP             ; 10cc
    SPHL                ;  6cc
    ; ... compute x, y, z ...
    PUSH HL             ; 12cc — spill y (52cc per)
    LXI  HL, 2
    DAD  SP
    MOV  M, E
    INX  HL
    MOV  M, D
    POP  HL             ; 12cc
    ; ... spill z similarly ...
    CALL sink
    ; ... reload y, z (52cc per) ...
    LXI  HL, 4          ; 10cc — epilogue
    DAD  SP             ; 10cc
    SPHL                ;  6cc
    RET
; Total overhead: 52cc prologue + 52cc epilogue + 4×52cc spill/reload = ~312cc
```

**After** (static allocation):
```asm
spill_test:
    ; No prologue!
    ; ... compute x, y, z ...
    XCHG                ;  4cc — spill DE (y) via XCHG+SHLD
    SHLD __v6clang_ss+0     ; 16cc
    XCHG                ;  4cc
    ; ... spill z via SHLD ...
    CALL sink
    ; ... reload y via LHLD+XCHG ...
    ; ... reload z via LHLD ...
    ; No epilogue!
    RET
; Total overhead: 2×24cc spill + 2×24cc reload = ~96cc (3.3× faster)
```

### Example 2: Leaf function with A register spill

```asm
; Before: PUSH HL + LXI + DAD SP + STA... no, MOV M,A + POP HL = 52cc
; After:  STA __v6clang_ss+0 = 16cc  (3.3× faster)
```

### Example 3: Prologue/epilogue elimination

Every call to a statically-allocated function saves 52cc
(26cc prologue + 26cc epilogue) even with no spills.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Incorrect norecurse inference | Rely on LLVM's well-tested PostOrderFunctionAttrs; gate on opt-in flag |
| Interrupt handler reentrancy | BFS from interrupt entry points excludes all transitively reachable functions (matches llvm-mos `MOSNonReentrant`) |
| Function pointer callbacks | Functions whose address is taken are naturally not `norecurse` in LLVM |
| GlobalVariable creation in MachineFunctionPass | Has precedent (constant pools, jump tables); safe after ISel |
| Static memory usage (no overlap) | Acceptable for 8080 programs (small total frame sizes); SCC overlap as future enhancement |
| AsmPrinter handling of GlobalAddress on LXI/STA/LDA | Existing patterns for global loads/stores already work this way |
| MFI.setObjectSize(0) confuses other passes | Only done after RA, before PEI; no other pass depends on object sizes at this point |

---

## 6. Relationship to Other Improvements

- **O8 (Spill Optimization T1/T2)**: O10 **supersedes T2** (ad-hoc global BSS
  variables) with automatic, optimally-packed static allocation. T1 (PUSH/POP)
  remains complementary for LIFO-safe slots within a BB.
- **O6 (LDA/STA absolute addr)**: O10 reuses the same instructions (STA, LDA,
  SHLD, LHLD) and the same AsmPrinter GlobalAddress handling.
- **O21 (LHLD/SHLD absolute addr)**: Same.
- **O16 (Store-to-Load Forwarding)**: After O10, many spill/reload sequences
  become simpler (direct STA/LDA), making store-to-load forwarding patterns
  more visible to later peepholes.
- **O39 (IPRA)**: IPRA reduces the number of spills across calls. O10 makes
  the remaining spills cheaper. They compound.

---

## 7. Future Enhancements

1. **SCC-based memory overlap**: Build the call graph SCC DAG and assign
   overlapping static regions for functions that cannot be simultaneously
   active. Reduces total BSS usage by ~50%.
2. **A-register liveness analysis**: For SPILL8 of B/C/D/E, if A is dead
   at the spill point, use `MOV A, r; STA addr` (24cc, 4B) instead of
   `PUSH HL; LXI HL, addr; MOV M, r; POP HL` (42cc, 6B) — additional
   18cc savings per spill.
3. **Default-on at -O2**: After thorough testing, enable static stack by
   default when compiling at -O2 or higher.
4. **Whole-program mode**: Add `-mv6clang-whole-program` flag that makes ALL
   non-recursive functions eligible (not just those with `norecurse`
   attribute), for single-TU embedded builds.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O10 Feature Description](design\future_plans\O10_static_stack_allocation.md)
* [O08 Spill Optimization](design\future_plans\O08_spill_optimization.md)
* [llvm-mos Analysis](design\future_plans\llvm_mos_analysis.md)
* [LLVM PostOrderFunctionAttrs](https://llvm.org/docs/Passes.html#function-attrs)
