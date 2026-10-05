# Plan: Tail Call Optimization (CALL+RET → JMP)

## 1. Problem

### Current behavior

When a function's last action is calling another function and returning
the result, the compiler emits CALL + RET:

```asm
wrapper:
    CALL helper         ; 24cc, 3B — push PC, jump
    RET                 ; 12cc, 1B — pop PC, jump
    ; Total: 36cc, 4B
```

The CALL pushes the return address, jumps to the callee. The callee's
RET returns to the instruction after CALL (our RET). Then our RET
returns to our caller. This is a wasted round-trip through the stack.

### Desired behavior

```asm
wrapper:
    JMP helper          ; 12cc, 3B — jump (no push)
    ; Total: 12cc, 3B
```

JMP does not push a return address. The callee's RET pops the return
address that was pushed by our caller's CALL, returning directly to
the original caller. One fewer stack round-trip.

### Root cause (and pre-existing bug)

The V6CLANG backend does not implement tail call optimization at any level
(neither ISel nor post-RA). LLVM's generic tail call support requires
target-specific lowering (`LowerTailCall`) which V6CLANG doesn't provide.

**Critical bug**: V6CLANG's `LowerCall` ignores the `CLI.IsTailCall` flag
and does not reset it to `false`. LLVM's contract requires that if a
target _cannot_ lower a tail call, it must set `CLI.IsTailCall = false`
so the generic machinery falls back to emitting a normal CALL + RET.
Since V6CLANG leaves `CLI.IsTailCall = true`, LLVM assumes the tail call
was handled and **skips emitting the RET instruction**. The result is a
`CALL target` without a following `RET` — the function falls through
into whatever code follows it in memory, producing incorrect execution.

This fix is a prerequisite: add `CLI.IsTailCall = false;` in LowerCall
so that CALL+RET is always emitted. Then the post-RA peephole can
safely convert eligible CALL+RET patterns back to JMP.

---

## 2. Strategy

### Approach: Post-RA peephole pattern in V6ClangPeephole.cpp

Add a new `eliminateTailCall` method to the existing peephole pass.
Scan each basic block for CALL immediately followed by RET (skipping
debug instructions). Replace both with a new `V6CLANG_TAILJMP` instruction.

A dedicated `V6CLANG_TAILJMP` instruction is needed (rather than reusing
JMP) because `V6CLANG::JMP` has `isBranch = 1` — other passes
(`analyzeBranch`, `BranchOpt::removeRedundantJMP`) call `getMBB()` on
JMP operands, which would crash on a function-symbol operand.
`V6CLANG_TAILJMP` uses `isReturn = 1` instead of `isBranch = 1`, so these
passes correctly treat it as a return terminator and skip it.

### Why this works

1. **Adjacency guarantees safety**: The epilogue (`emitEpilogue`) inserts
   stack cleanup code _before_ RET. If a function has any prologue/epilogue
   (non-zero stack frame or frame pointer), the epilogue code will be
   between CALL and RET, breaking adjacency. The peephole only matches
   when CALL is immediately before RET — which can only happen when:
   - The function has zero stack size (no locals, no outgoing stack args)
   - No frame pointer is used
   - ADJCALLSTACKUP is zero (callee takes all args in registers)

2. **No callee-saved registers**: V6CLANG's calling convention clobbers all
   registers across calls, so there are no register save/restore
   instructions between CALL and RET.

3. **Stack correctness**: When the function has no frame, SP at the JMP
   is the same as on entry (after our caller's CALL pushed the return
   address). The callee's RET pops that return address, returning
   directly to our caller. The stack is in the correct state.

4. **Post-RA timing**: By the time the peephole runs, register allocation
   is complete, frame lowering has inserted the epilogue, and
   ADJCALLSTACKUP pseudos have been expanded. The adjacency check
   implicitly verifies all safety conditions.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Define V6CLANG_TAILJMP | New instruction, same encoding as JMP (0xC3), `isReturn = 1` | V6ClangInstrInfo.td |
| Add eliminateTailCall | Pattern: CALL + RET → V6CLANG_TAILJMP | V6ClangPeephole.cpp |

---

## 3. Implementation Steps

### Step 3.1 — Fix IsTailCall bug in LowerCall [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`

At the start of `V6ClangTargetLowering::LowerCall`, reset the tail call flag
so LLVM always emits `CALL + RET` (instead of CALL without RET):

```cpp
SDValue V6ClangTargetLowering::LowerCall(TargetLowering::CallLoweringInfo &CLI,
                                      SmallVectorImpl<SDValue> &InVals) const {
  // V6CLANG does not support tail calls at the ISel level. Reset the flag so
  // LLVM's generic machinery emits a normal CALL + RET sequence.
  CLI.IsTailCall = false;

  SelectionDAG &DAG = CLI.DAG;
  // ... rest unchanged ...
```

> **Design Notes**: Without this fix, Clang's `-O2` marks many calls as
> `tail call` in IR. LLVM then skips emitting V6ClangISD::RET for the return
> block, producing CALL without RET — the function falls through into
> whatever follows in memory. This is a correctness bug that must be fixed
> before the tail call peephole optimization makes sense.

> **Implementation Notes**: Added `CLI.IsTailCall = false;` as the first line
> of `LowerCall`. Now `tail call` in IR correctly produces `CALL + RET`.

### Step 3.2 — Define V6CLANG_TAILJMP instruction [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

Add after the RET/conditional-return definitions:

```tablegen
// V6CLANG_TAILJMP — tail call via JMP encoding (0xC3).
// Used by peephole pass: CALL target; RET → V6CLANG_TAILJMP target.
// Marked isReturn (not isBranch) so analyzeBranch/BranchOpt skip it.
let isReturn = 1, isTerminator = 1, isBarrier = 1 in
def V6CLANG_TAILJMP : V6ClangInstImm16Opc<0xC3,
    (outs), (ins brtarget:$addr),
    "JMP\t$addr", []>;
```

> **Design Notes**: Uses the same 0xC3 encoding and "JMP" mnemonic as regular
> JMP. Distinguished by `isReturn = 1` (not `isBranch = 1`) so:
> - `analyzeBranch` treats it as unknown terminator → returns true (can't analyze) — same as RET
> - `BranchOpt::removeRedundantJMP` checks `V6CLANG::JMP` opcode → skips V6CLANG_TAILJMP
> - `BranchOpt::invertConditionalBranch` checks `V6CLANG::JMP` → skips V6CLANG_TAILJMP

> **Implementation Notes**: Added after conditional return block.
> Uses `V6ClangInstImm16Opc<0xC3>` with `isReturn=1, isTerminator=1, isBarrier=1`.

### Step 3.3 — Add eliminateTailCall to V6ClangPeephole.cpp [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangPeephole.cpp`

Add a new method to the V6ClangPeephole class and call it from `runOnMachineFunction`:

```cpp
/// Replace CALL target; RET → V6CLANG_TAILJMP target (tail call elimination).
/// Only matches when CALL is immediately before RET (no epilogue between).
bool V6ClangPeephole::eliminateTailCall(MachineBasicBlock &MBB) {
  // Need at least 2 instructions.
  if (MBB.size() < 2)
    return false;

  // Find the last non-debug instruction — must be RET.
  auto RetIt = MBB.getLastNonDebugInstr();
  if (RetIt == MBB.end() || RetIt->getOpcode() != V6CLANG::RET)
    return false;

  // Find the instruction before RET, skipping debug instrs.
  auto CallIt = std::prev(RetIt);
  while (CallIt != MBB.begin() && CallIt->isDebugInstr())
    CallIt = std::prev(CallIt);

  if (CallIt->getOpcode() != V6CLANG::CALL)
    return false;

  // Build V6CLANG_TAILJMP with the CALL's target operand.
  const TargetInstrInfo &TII = *MBB.getParent()->getSubtarget().getInstrInfo();
  BuildMI(MBB, *CallIt, CallIt->getDebugLoc(), TII.get(V6CLANG::V6CLANG_TAILJMP))
      .add(CallIt->getOperand(0));

  RetIt->eraseFromParent();
  CallIt->eraseFromParent();
  return true;
}
```

Call from `runOnMachineFunction`:
```cpp
bool V6ClangPeephole::runOnMachineFunction(MachineFunction &MF) {
  if (DisablePeephole)
    return false;

  bool Changed = false;
  for (MachineBasicBlock &MBB : MF) {
    Changed |= eliminateSelfMov(MBB);
    Changed |= eliminateRedundantMov(MBB);
    Changed |= eliminateTailCall(MBB);
  }
  return Changed;
}
```

> **Design Notes**:
> - Adjacency check (CALL immediately before RET) implicitly validates all
>   safety conditions: zero stack frame, no frame pointer, no ADJCALLSTACKUP.
> - The CALL's operand(0) is the target symbol (GlobalAddress or ExternalSymbol).
>   V6CLANG_TAILJMP accepts `brtarget` which handles both MBB and symbol operands.
> - No separate CLI toggle needed — `-v6clang-disable-peephole` disables all
>   peephole patterns including this one.

> **Implementation Notes**: Added method + declaration. Required additional
> includes: `TargetInstrInfo.h` and `TargetSubtargetInfo.h`. BuildMI takes
> iterator (not MachineInstr ref) for insertion point.

### Step 3.4 — Build [x]

```bash
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Expected: clean build.

### Step 3.5 — Lit test: tail-call-opt.ll [x]

**File**: `tests/lit/CodeGen/V6CLANG/tail-call-opt.ll`

```llvm
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

; Test 1: Simple tail call — CALL+RET replaced with JMP.
define i16 @wrapper(i16 %x) {
; CHECK-LABEL: wrapper:
; CHECK-NOT:   CALL
; CHECK:       JMP helper
; CHECK-NOT:   RET
entry:
  %r = call i16 @helper(i16 %x)
  ret i16 %r
}
declare i16 @helper(i16)

; Test 2: Void tail call.
define void @void_wrapper() {
; CHECK-LABEL: void_wrapper:
; CHECK-NOT:   CALL
; CHECK:       JMP void_func
; CHECK-NOT:   RET
entry:
  call void @void_func()
  ret void
}
declare void @void_func()

; Test 3: NOT a tail call — work after call prevents optimization.
define i16 @not_tail(i16 %x) {
; CHECK-LABEL: not_tail:
; CHECK:       CALL helper
; CHECK:       RET
entry:
  %r = call i16 @helper(i16 %x)
  %r2 = add i16 %r, 1
  ret i16 %r2
}

; Test 4: Dispatch — both branches get tail-call optimized.
define void @dispatch(i8 %cmd) {
; CHECK-LABEL: dispatch:
; CHECK:       JMP func_a
; CHECK:       JMP func_b
; CHECK-NOT:   CALL
entry:
  %cmp = icmp eq i8 %cmd, 1
  br i1 %cmp, label %a, label %b

a:
  call void @func_a()
  ret void

b:
  call void @func_b()
  ret void
}
declare void @func_a()
declare void @func_b()

; Test 5: Tail call disabled via -v6clang-disable-peephole.
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -v6clang-disable-peephole < %s \
; RUN:   | FileCheck %s --check-prefix=DISABLED

; DISABLED-LABEL: wrapper:
; DISABLED:       CALL helper
; DISABLED:       RET
```

### Step 3.6 — Run regression tests [x]

```bash
python tests\run_all.py
```

All existing tests must pass. The tail call optimization only adds a new
pattern — it doesn't change the behavior of existing test cases as they
either don't end with CALL+RET, or the optimization is a strict improvement.

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [x]

```bash
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
    tests\features\01\v6clang.c -o tests\features\01\v6clang_improve01.asm
```

Inspect the assembly for:
1. `wrapper:` should contain `JMP helper` (not `CALL helper` + `RET`)
2. `void_wrapper:` should contain `JMP void_func` (not `CALL` + `RET`)

### Step 3.8 — Sync mirror [x]

```powershell
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### Per-instance improvement

| Metric | Before (CALL+RET) | After (JMP) | Savings |
|--------|-------------------|-------------|---------|
| Cycles | 36cc (24+12) | 12cc | 24cc (3× faster) |
| Bytes  | 4B (3+1) | 3B | 1B |
| Stack depth | +2 bytes (return addr pushed) | 0 | 2 bytes stack |

### Example: wrapper function

```c
int wrapper(int x) { return helper(x); }
```

Before:
```asm
wrapper:
    CALL helper     ; 24cc, 3B
    RET             ; 12cc, 1B
    ; Total: 36cc, 4B, stack +2
```

After:
```asm
wrapper:
    JMP helper      ; 12cc, 3B
    ; Total: 12cc, 3B, stack +0
```

### Example: dispatch pattern

```c
void dispatch(int cmd) {
    if (cmd == 1) func_a();
    else func_b();
}
```

Two tail calls optimized — saves 48cc and 2 bytes total.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Fixing IsTailCall causes regression in existing tests | The fix changes `CALL` (wrong, missing RET) to `CALL+RET` (correct). Then the peephole converts eligible CALL+RET to JMP. Net effect: same or better code, correct behavior. Existing tests that happened to work with the bug will still work — the peephole restores the JMP optimization. |
| JMP with function-symbol operand crashes `getMBB()` in BranchOpt | Use dedicated `V6CLANG_TAILJMP` with `isReturn = 1` (not `isBranch`). BranchOpt and analyzeBranch only check `V6CLANG::JMP` opcode, skip TAILJMP. |
| Tail call applied when stack isn't clean (frame/epilogue exists) | Adjacency check: epilogue inserts code before RET, breaking the CALL+RET pattern. Only matches when no epilogue exists (zero-frame functions). |
| ADJCALLSTACKUP not expanded yet when peephole runs | ADJCALLSTACKUP is expanded in eliminateCallFramePseudoInstr during PEI, which runs before the peephole pass. If non-zero, it inserts SP-adjustment instructions between CALL and RET. |
| Callee expects different stack arguments than what our caller passed | If our function pushed stack args for the callee, ADJCALLSTACKDOWN inserts SP adjustment before CALL or reserves space in the frame. Both break adjacency. Safe. |
| Peephole runs before BranchOpt — TAILJMP might prevent BranchOpt patterns | TAILJMP is a terminal barrier (like RET). BranchOpt handles blocks ending with RET the same way — it's already a no-op for return blocks. |
| Encoding conflict: V6CLANG_TAILJMP and JMP both use 0xC3 | No disassembler exists for V6CLANG. The MCCodeEmitter encodes based on format class + opcode, not on instruction uniqueness. Both produce identical bytes. |

---

## 6. Relationship to Other Improvements

- **O15 (Conditional Call Optimization)**: Complements this optimization.
  O15 converts `Jcc over CALL → CZ/CNZ` conditional calls. Combined with
  O14, a conditional call at function end could become a conditional _jump_
  (RZ/RNZ or CZ/CNZ depending on the pattern). Future enhancement.

- **O12 (Global Copy Optimization)**: May expose more tail call patterns by
  eliminating register copies between CALL and RET.

- This optimization has **no dependencies** on other improvements and can
  be implemented independently.

---

## 7. Future Enhancements

- **Conditional tail calls**: Pattern `Jcc .Lskip; CALL target; RET; .Lskip: RET`
  could become `Jcc_inv target_via_tailcall; RET` using conditional return
  instructions (RZ, RNZ, etc.) or conditional jumps depending on the pattern.

- **ISel-level tail call support**: Implement `LowerTailCall` in
  V6ClangISelLowering.cpp to recognize tail calls at DAG level. This would
  catch cases where the post-RA peephole can't (e.g., when argument
  registers need shuffling but the function still qualifies for tail call).

- **Sibling call optimization**: When the callee's args partially overlap
  with the caller's args, restructure the argument setup to enable the
  tail call even when some shuffling is needed.

> **Not pursued — ISel-level tail call (April 2026):** The simple
> CALL+RET→JMP peephole (O14, done) already catches the common case where
> no argument shuffling is needed. Full ISel-level `LowerTailCall` requires
> teaching ISel to mark calls as tail-position during lowering, argument
> register shuffling logic, frame cleanup before the jump, and callee-saved
> register handling — high complexity for diminishing returns. The
> conditional-branch extension is captured separately as O23.

> **Not pursued — Sibling call optimization (April 2026):** A strict subset
> of ISel-level tail calls, handling partially-overlapping arguments. On 8080
> with only 3 register pairs, argument shuffling (e.g. swapping DE↔BC)
> requires temporary storage (PUSH/POP or XCHG). The shuffle cost (24-48cc)
> typically negates the 18cc savings from eliminating CALL+RET→JMP, making it
> a net loss. The only clearly beneficial case — identical arguments — is a
> regular tail call that O14 already handles.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [llvm-mos Analysis — §S9 tailJMP](design\future_plans\llvm_mos_analysis.md)
* [V6ClangPeephole.cpp](llvm\lib\Target\V6CLANG\V6ClangPeephole.cpp) — target pass for the new pattern
* [V6ClangInstrInfo.td](llvm\lib\Target\V6CLANG\V6ClangInstrInfo.td) — instruction definitions
