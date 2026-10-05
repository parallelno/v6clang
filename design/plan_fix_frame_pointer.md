# Fix: Frame Pointer Default for V6CLANG Target

**Reference**: [design_improve_spilling.md](design_improve_spilling.md), [design.md](design.md) §7.2

---

## 1. Problem

The V6CLANG toolchain does not declare a frame pointer preference. The fallback
logic in `useFramePointerForTargetByDefault()` (CommonArgs.cpp) returns
`true` for unrecognized architectures, causing every function to receive
`"frame-pointer"="all"` — even at `-O2`.

This reserves BC as a frame pointer unconditionally, reducing allocatable
register pairs from 3 to 2 and causing unnecessary spills in loops with
two live pointers.

### Impact

- BC (B, C) unavailable for register allocation in all functions with stack
- Prologue: +38 cc / +8 B overhead (PUSH BC; LXI HL,0; DAD SP; MOV B,H; MOV C,L)
- Epilogue: +22 cc / +4 B overhead (MOV H,B; MOV L,C; SPHL; POP BC)
- Array copy loop: spills that would be eliminated with BC available

### Design Intent

[design.md §7.2](design.md): *"BC is reserved as the frame pointer in this
mode, reducing allocatable registers further. Enabled via
`-fno-omit-frame-pointer` or automatically when needed."*

[V6ClangCallingConvention.md §Frame Pointer](../docs/V6ClangCallingConvention.md):
*"For functions requiring one (e.g., alloca, variable-length arrays, or
-fno-omit-frame-pointer), BC is reserved."*

Both documents describe BC-as-FP as opt-in, not default.

---

## 2. Root Cause

**File**: `llvm-project/clang/lib/Driver/ToolChains/CommonArgs.cpp`
**Function**: `useFramePointerForTargetByDefault()`

The `i8080` architecture is not listed in the switch statement. The function
falls through to the final `return true`, enabling frame pointers by default.

Other minimal/baremetal targets (xcore, wasm32, wasm64, msp430) explicitly
return `false` in this function.

---

## 3. Fix

### Step 1 — Add i8080 case to useFramePointerForTargetByDefault [x]

**File**: `llvm-project/clang/lib/Driver/ToolChains/CommonArgs.cpp`

Add `case llvm::Triple::i8080:` to the group that returns `false`:

```cpp
  switch (Triple.getArch()) {
  case llvm::Triple::xcore:
  case llvm::Triple::wasm32:
  case llvm::Triple::wasm64:
  case llvm::Triple::msp430:
  case llvm::Triple::i8080:          // ← ADD THIS
    // XCore never wants frame pointers, regardless of OS.
    // WebAssembly never wants frame pointers.
    return false;
```

**Rationale**: The 8080 has only 3 register pairs. Reserving BC for a frame
pointer is catastrophic for register pressure. Frame pointers should only be
used when explicitly requested or structurally required (alloca, VLA).

### Step 2 — Add to sync script [x]

**File**: `scripts/sync_llvm_mirror.ps1`

Add an xcopy line for CommonArgs.cpp if not already present:

```powershell
xcopy /Y /D "llvm-project\clang\lib\Driver\ToolChains\CommonArgs.cpp" "clang\lib\Driver\ToolChains\"
```

### Step 3 — Build [x]

```bash
ninja -C llvm-build clang llc
```

### Step 4 — Verify IR attribute [x]

Compile a trivial function at `-O2` and check the IR attribute:

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S -emit-llvm ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2_fixed.ll
```

Verify the function does NOT have `"frame-pointer"="all"`. Expected:
`"frame-pointer"="none"` (or attribute absent).

### Step 5 — Verify assembly output [x]

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
    temp\compare\03\v6clang2.c -o temp\compare\03\v6clang2_fixed.asm
```

Verify:
- No `PUSH BC` / `POP BC` in prologue/epilogue (unless FP explicitly needed)
- No `MOV B,H; MOV C,L` SP-save pattern
- BC registers available to register allocator (visible as loop counter or
  pointer holder)
- Spill count reduced or eliminated in the array copy loop

### Step 6 — Lit test for frame pointer behavior [x]

**File**: `tests/lit/Clang/V6Clang/frame-pointer-default.c`

```c
// RUN: %clang -target i8080-unknown-v6clang -O2 -S -emit-llvm %s -o - | FileCheck %s
// CHECK-NOT: "frame-pointer"="all"
// CHECK-NOT: "frame-pointer"="non-leaf"
int simple(int x) { return x + 1; }
```

**File**: `tests/lit/Clang/V6Clang/frame-pointer-explicit.c`

```c
// RUN: %clang -target i8080-unknown-v6clang -O2 -fno-omit-frame-pointer -S -emit-llvm %s -o - | FileCheck %s
// CHECK: "frame-pointer"="all"
int simple(int x) { return x + 1; }
```

### Step 7 — Regression tests [x]

Run full test suite to ensure no regressions:

```bash
python tests/run_all.py
```

All existing tests must pass. Functions that previously relied on BC being
reserved (none expected — hasFP only affects register allocation) should be
unaffected.

### Step 8 — Sync mirror [x]

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Array copy loop (temp\compare\03\v6clang2.c)

Before (BC reserved, 2 pairs):
- ~30 instructions per iteration
- 2 spill/reload pairs (~208 cc of spill overhead per iteration)
- ~60 cc prologue, ~30 cc epilogue

After (BC free, 3 pairs):
- Loop counter in BC or DE, both pointers in remaining pairs
- 0 spill/reload pairs expected
- ~25 cc prologue (LXI+DAD+SPHL only if stack needed), ~25 cc epilogue

### General impact

- Every function with a stack frame saves ~60 cc in prologue/epilogue
- Functions with 2+ live register pairs gain a third pair, reducing spills
- No impact on functions that explicitly use `-fno-omit-frame-pointer`

---

## 5. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Existing test expectations on BC presence | Low | Medium | Run full test suite; fix any CHECK lines that assumed BC prologue |
| Functions that actually need FP (alloca) | None | None | `hasFP()` still returns true for those — fix only affects default |
| Upstream file modification tracking | Low | Low | Add CommonArgs.cpp to sync script |
