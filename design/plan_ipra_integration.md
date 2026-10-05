# Plan: O39 — Interprocedural Register Allocation (IPRA) Integration

## 1. Problem

### Current behavior

V6CLANG models ordinary `CALL` as clobbering every general-purpose register and
`FLAGS`. During register allocation, any value live across a call must be
spilled even when the callee only touches a small subset of registers.

In the motivating pattern:

```c
int test_ne_same_bytes(int x) {
    if (x != 0x4242) {
        action_a();
    }
    action_b();
    return x;
}
```

the caller keeps `x` live in `DE`, but both calls still force spill/reload
traffic around the call sites.

### Desired behavior

Enable LLVM's IPRA flow for V6CLANG so direct calls can preserve registers that
the callee does not actually touch. For tiny leaf callees such as:

```c
__attribute__((noinline))
void action_a(void) { sink = 1; }
__attribute__((noinline))
void action_b(void) { sink = 2; }
```

the call-site mask should narrow to the true clobber set, allowing live values
such as `DE` to survive across the call without stack spills.

### Root cause

The backend already attaches a call-preserved register mask in
`V6ClangTargetLowering::LowerCall`, but the `CALL` instruction definition in
`V6ClangInstrInfo.td` still carries explicit implicit-defs for `A, B, C, D, E, H,
L, FLAGS`. Those hard clobbers are baked into every `MachineInstr`, so IPRA's
register-mask narrowing has no effect.

The second missing piece is that `V6ClangTargetMachine` does not override
`useIPRA()`, so V6CLANG never opts into IPRA by default.

## 2. Strategy

### Approach: Make `CALL` clobbers mask-driven and enable IPRA by default

Implement the feature in three backend steps:

1. Change `CALL` in `V6ClangInstrInfo.td` to define only `SP`.
2. Override `V6ClangTargetMachine::useIPRA()` to return `true`.
3. Audit all V6CLANG call creation paths to ensure they carry a register mask and
   add a regression test that proves spill removal on direct calls while
   preserving conservative behavior for unknown callees.

### Why this works

- `LowerCall` already attaches `TRI->getCallPreservedMask(...)`, so ordinary
  V6CLANG calls already have the mechanism IPRA expects.
- `V6ClangRegisterInfo::getCallPreservedMask()` returning all-zero remains the
  correct conservative default for external calls or any call without IPRA
  data.
- Once `CALL` stops advertising hard register defs, register allocation can use
  the per-call mask that IPRA propagates from callee usage information.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| 3.1 | Remove hard GPR/FLAGS defs from `CALL` | `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td` |
| 3.2 | Enable IPRA by default | `llvm-project/llvm/lib/Target/V6CLANG/V6ClangTargetMachine.h` |
| 3.3 | Audit call builders and document mask assumptions | `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`, `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelDAGToDAG.cpp`, `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp` |
| 3.4 | Build | — |
| 3.5 | Lit test | `tests/lit/CodeGen/V6CLANG/ipra-call-preservation.ll` |
| 3.6 | Run regression tests | — |
| 3.7 | Verification assembly | `tests/features/19/` |
| 3.8 | Create `result.txt` | `tests/features/19/result.txt` |
| 3.9 | Sync mirror | — |

## 3. Implementation Steps

### Step 3.1 — Remove hard non-SP defs from `CALL` [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

Change the ordinary `CALL` definition from:

```tablegen
let isCall = 1, Uses = [SP], Defs = [SP, A, B, C, D, E, H, L, FLAGS] in
```

to:

```tablegen
let isCall = 1, Uses = [SP], Defs = [SP] in
```

Leave conditional calls as-is; they already only define `SP`.

> **Design Notes**: The backend currently has no `CALL_INDIRECT` definition, so
> the only direct change needed in TableGen is `CALL`.

> **Implementation Notes**: Updated `CALL` in `V6ClangInstrInfo.td` to define only
> `SP`. Conditional calls already matched the desired model and were left
> unchanged.

### Step 3.2 — Enable IPRA in the target machine [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangTargetMachine.h`

Add:

```cpp
bool useIPRA() const override { return true; }
```

This makes IPRA active for normal optimized V6CLANG builds without requiring users
to pass `-mllvm -enable-ipra` manually.

> **Design Notes**: The LLVM command-line flag should still override the target
> default, so users can disable IPRA explicitly when debugging.

> **Implementation Notes**: Added `useIPRA() const override { return true; }`
> in `V6ClangTargetMachine.h`. This enables IPRA by default while still allowing
> `-enable-ipra=false` to force conservative behavior.

### Step 3.3 — Audit V6CLANG call creation and mask propagation [x]

**Files**:
- `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`
- `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelDAGToDAG.cpp`
- `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Verify and document the concrete call creation paths:

1. `LowerCall` appends `DAG.getRegisterMask(...)` to every ordinary call node.
2. `V6ClangISD::CALL` selection forwards that register mask to the `CALL`
   `MachineInstr` unchanged.
3. No other V6CLANG path builds a raw `CALL` `MachineInstr` without a mask.

If an uncovered path exists, patch it so every ordinary call stays conservative
without IPRA data and can be narrowed by IPRA when data exists.

> **Design Notes**: The nearby `BuildMI(... V6CLANG_TAILJMP ...)` tail-call peephole
> does not create a `CALL`, so it is outside the IPRA risk surface.

> **Implementation Notes**: Audited the V6CLANG backend call paths. `LowerCall`
> appends `DAG.getRegisterMask(...)`, and `V6ClangISD::CALL` selection forwards that
> operand unchanged to the machine `CALL`. No raw `BuildMI(... V6CLANG::CALL ...)`
> sites were found in the V6CLANG backend. The nearby tail-call peephole emits
> `V6CLANG_TAILJMP`, not `CALL`, so no additional code change was needed.

### Step 3.4 — Build [x]

```text
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Rebuilt `clang` and `llc` successfully with
> `ninja -C llvm-build clang llc` after the backend changes.

### Step 3.5 — Lit test: direct-call IPRA spill removal [x]

**File**: `tests/lit/CodeGen/V6CLANG/ipra-call-preservation.ll`

Add focused coverage for:

1. Direct call to a tiny leaf callee where a live `DE` value should survive
   without spill/reload when IPRA is enabled.
2. A conservative case where no IPRA data is available and the caller still
   spills around the call.
3. A flag-off case (`-mllvm -enable-ipra=false`) showing the old conservative
   behavior remains available.

Use `CHECK` lines to verify the direct-call case loses stack-frame spill code
around `CALL` while the conservative case still retains it.

> **Implementation Notes**: Added `tests/lit/CodeGen/V6CLANG/ipra-call-preservation.ll`.
> The test covers three cases in one file: direct internal call with IPRA,
> conservative external call with IPRA, and direct-call fallback with
> `-enable-ipra=false`. Verified with a focused `llvm-lit.py` run.

### Step 3.6 — Run regression tests [x]

```text
python tests\run_all.py
```

> **Implementation Notes**: `python tests\run_all.py` passed cleanly:
> 15/15 golden tests and 94/94 lit tests.

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature case under `tests/features/19/` and compare
`v6clang_old.asm` vs `v6clang_new01.asm`.

Validation target:

- `test_ne_same_bytes` and `test_eq_same_bytes` should stop creating a stack
  frame just to preserve `x` across `CALL action_a` / `CALL action_b`.
- The return path should reduce to register moves plus `RET`, with `DE`
  surviving across the direct calls.

> **Implementation Notes**: Recompiled the feature case to
> `tests/features/19/v6clang_new01.asm`. Both `test_ne_same_bytes` and
> `test_eq_same_bytes` dropped the stack frame and all spill/reload traffic
> around the direct calls. The resulting body is `MOV D,H; MOV E,L;` compare,
> two `CALL`s, `XCHG`, `RET`.

### Step 3.8 — Make sure `result.txt` is created [x]

Follow `tests\features\README.md` and include:

- The C test source.
- Relevant `c8080` assembly.
- Relevant `v6clang` before/after assembly.
- Cycle and byte counts for the affected functions.

> **Implementation Notes**: Created `tests/features/19/result.txt` with the C
> source, relevant `c8080` assembly converted to i8080 syntax, before/after
> `v6clang` assembly, and byte/cycle deltas for the two improved functions.

### Step 3.9 — Sync mirror [x]

```text
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Ran `powershell -ExecutionPolicy Bypass -File
> scripts\sync_llvm_mirror.ps1` successfully. The tracked `llvm/` mirror now
> matches the backend changes made under `llvm-project/`.

## 4. Expected Results

### Example 1: direct leaf-call preservation

For a function like `test_ne_same_bytes`, the caller should keep `x` in `DE`
across both direct calls when the callees only use `HL`. The current spill /
reload frame should disappear.

### Example 2: no regression for unknown calls

External calls, unresolved calls, and any path without IPRA data should remain
fully conservative because `getCallPreservedMask()` still returns the all-zero
mask by default.

### Example 3: better interaction with existing spill work

Reducing pre-call spill pressure directly improves the payoff of O8 spill
optimization and O10 static-stack work by eliminating many spills before those
features even need to act.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| A call path emits `CALL` without a register mask | Audit all V6CLANG call builders before enabling the feature broadly |
| Removing hard defs hides a real clobber | Keep the default call-preserved mask fully conservative; only IPRA narrows it |
| IPRA does not propagate for recursive / external cases | Accept conservative behavior there and cover it in tests |
| Tail-call or pseudo expansion accidentally bypasses the mask path later | Add a regression test and keep the audit notes in the plan / implementation comments |

---

## 6. Relationship to Other Improvements

- Enhances **O8 Spill Optimization** by reducing the number of spills that need
  optimization in the first place.
- Enhances **O10 Static Stack Allocation** because fewer live-across-call values
  require stack slots.
- Complements **O32 XCHG in copyPhysReg** and other RA-sensitive work by giving
  the allocator a more truthful call clobber model.

## 7. Future Enhancements

- ~~Add targeted MIR or llc coverage for recursive SCC cases once IPRA is working.~~
  Done — `tests/lit/CodeGen/V6CLANG/ipra-recursive-scc.ll` covers mutual-recursion
  SCC conservative behavior and contrasts it with leaf-call IPRA narrowing.
- ~~Consider adding a debug-only verifier check that V6CLANG `CALL` instructions carry
  a register mask after instruction selection.~~
  Done — `V6ClangCallRegMaskVerifier` in `V6ClangTargetMachine.cpp` runs pre-RA under
  `#ifndef NDEBUG`, asserting every `isCall()` instruction has a `RegMask`
  operand.  Activates with `-DLLVM_ENABLE_ASSERTIONS=ON`; compiled out in
  release builds.
- When O15 (conditional-call peephole) is implemented, ensure it copies the
  register mask operand from the original `CALL` to the new `CNZ`/`CZ`.
  Without that, IPRA's narrowed per-call-site mask is lost and the conditional
  call falls back to the conservative all-clobber default.

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O39 Design](design\future_plans\O39_ipra_integration.md)
* [Feature Pipeline](design\pipeline_feature.md)
