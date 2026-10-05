# Plan: Conditional Call Optimization (O15)

## 1. Problem

### Current behavior

The V6CLANG backend emits a branch-over-call sequence for `if (c) foo();`:

```asm
; if (c) foo();
    ORA  A           ;  4cc, 1B   (set Z from c)
    JZ   .Lskip      ; 12cc, 3B   ← jump over CALL when c==0
    CALL foo         ; 18cc, 3B
.Lskip:
    ...
```

The 8080 has dedicated conditional CALL opcodes (`CNZ`/`CZ`/`CC`/`CNC`/
`CP`/`CM`/`CPE`/`CPO`) that fuse the test and call in one instruction.
They are defined in `V6ClangInstrInfo.td` (lines 470-481) but **no pass ever
emits them** — confirmed by grep for `V6CLANG::CNZ`/`V6CLANG::CZ` etc.

### Desired behavior

```asm
; if (c) foo();
    ORA  A           ;  4cc, 1B
    CNZ  foo         ; 18cc taken / 12cc not taken, 3B
.Lskip:
    ...
```

Saves **3 bytes** unconditionally and **12cc** when the call is taken
(or, equivalently, replaces a 12cc Jcc + 18cc CALL = 30cc with a single
18cc Cxx).

### Root cause

No pass scans for the `Jcc skip / CALL fn / skip:` pattern. Sister
patterns are landed (`foldConditionalReturns`, `invertConditionalOverRET`,
`eliminateTailCall` cross-block in `V6ClangPeephole`); only conditional
CALL is missing.

---

## 2. Strategy

### Approach: New `foldConditionalCalls` in `V6ClangBranchOpt`

Add a post-RA fold to `V6ClangBranchOpt.cpp`, alongside
`foldConditionalReturns` and `invertConditionalOverRET`. The pattern:

```
bb.MBB:                ; ends with Jcc skip
    ...
    Jcc bb.skip
bb.call:               ; layout successor of MBB
    CALL fn            ; (only non-debug instruction)
bb.skip:               ; layout successor of bb.call
    ...
```

becomes:

```
bb.MBB:
    ...
    Cxx_inv fn         ; same regmask as the original CALL
bb.skip:
    ...
```

`Cxx_inv` = inverted-condition CALL (JZ→CNZ, JNZ→CZ, JC→CNC, JNC→CC,
JM→CP, JP→CM, JPE→CPO, JPO→CPE) — the call fires precisely when the
Jcc would *not* skip it.

`bb.call` becomes dead (single predecessor, no other entry) and is
removed.

### Why this works

- The `Cxx` opcode preserves the entire CALL semantics (push PC, jump,
  and `Defs=[SP]`). The TableGen def already lists `Uses=[SP, FLAGS]`,
  matching the post-RA reality.
- **IPRA correctness**: the original `CALL` MachineInstr carries a
  RegMask operand added by `LowerCall`. We **copy that RegMask onto the
  new Cxx instruction** so IPRA's narrowed clobber set carries through
  (see O39). All other operands (target, implicit reg uses for args,
  implicit defs for return value) are also forwarded.
- **Pre-emit timing**: the pass runs in `addPreEmitPass()` after
  spilling/RA, so we are not changing register allocation. The CALL
  block's only non-debug instruction must be exactly the CALL — there
  are no result COPYs at this stage if the result was unused (the
  compiler removes dead copies before BranchOpt runs).
- **Conservative**: we fold only when `bb.call` contains exactly one
  non-debug, non-terminator instruction (the CALL). If a result COPY
  follows, we skip — making the call conditional would also make the
  copy conditional, and the COPY is in the wrong block.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| `getConditionalCall` | Map Jcc opcode → Cxx (inverted) opcode | V6ClangBranchOpt.cpp |
| `foldConditionalCalls` | Detect & rewrite Jcc-over-CALL pattern | V6ClangBranchOpt.cpp |
| Wire into runOnMachineFunction | Order: after threadJMPOnlyBlocks | V6ClangBranchOpt.cpp |
| Lit test | `conditional-call.ll` | tests/lit/CodeGen/V6Clang/ |
| Feature test | `tests/features/49/` | tests/features/ |
| Update README | Mark O15 ✅ | design/future_plans/README.md |

---

## 3. Implementation Steps

### Step 3.1 — Add `getConditionalCall` mapping helper [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangBranchOpt.cpp`

Static helper next to `getConditionalReturn`:

```cpp
/// Map Jcc opcode to the corresponding *inverted-condition* Cxx call
/// opcode. The inversion is intentional: `Jcc skip / CALL` calls iff
/// the Jcc condition is FALSE, so the equivalent fused opcode tests
/// the inverse predicate.
static unsigned getConditionalCall(unsigned JccOpc) {
  switch (JccOpc) {
  case V6CLANG::JZ:  return V6CLANG::CNZ;
  case V6CLANG::JNZ: return V6CLANG::CZ;
  case V6CLANG::JC:  return V6CLANG::CNC;
  case V6CLANG::JNC: return V6CLANG::CC;
  case V6CLANG::JPE: return V6CLANG::CPO;
  case V6CLANG::JPO: return V6CLANG::CPE;
  case V6CLANG::JP:  return V6CLANG::CM;
  case V6CLANG::JM:  return V6CLANG::CP;
  default: return 0;
  }
}
```

> **Implementation Notes**:

### Step 3.2 — Implement `foldConditionalCalls` [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangBranchOpt.cpp`

Algorithm (mirrors `invertConditionalOverRET`, simplified):

For each `MachineBasicBlock` MBB:
1. Last terminator must be `Jcc target` with `target` an MBB
   (not an external symbol — branch threading would have folded that).
2. `bb.call` = layout successor of MBB; must be different from `target`
   and a successor of MBB.
3. `bb.call` must have exactly one predecessor (MBB) and exactly one
   successor (which must equal `target`).
4. `bb.call` must contain **exactly one** non-debug instruction, and
   that instruction must satisfy `MI.isCall()` and not be a tail call
   (i.e. opcode == `V6CLANG::CALL`, not `V6CLANG_TAILJMP`).
5. Look up `Cxx_inv = getConditionalCall(Jcc.opcode)`; bail if 0.

Rewrite:

```cpp
auto MIB = BuildMI(MBB, Jcc, Jcc.getDebugLoc(), TII.get(CxxOpc));
// Forward target operand verbatim (brtarget — global/symbol/MBB).
MIB.add(CallMI->getOperand(0));
// Forward all remaining operands of the original CALL: implicit reg
// uses (args), implicit defs (return value), and crucially the
// RegMask operand (IPRA narrowing — see O39).
for (unsigned I = 1, E = CallMI->getNumOperands(); I != E; ++I)
  MIB.add(CallMI->getOperand(I));

Jcc.eraseFromParent();
CallMI->eraseFromParent();

MBB.removeSuccessor(&CallBB);  // bb.call is now dead
DeadBlocks.push_back(&CallBB);
```

After the loop, erase dead blocks (after detaching their remaining
successor edges).

> **Design Notes**: We require `pred_size() == 1` on `bb.call` so we
> can safely delete it. If another predecessor reaches `bb.call`, the
> CALL there must remain — but we still cannot fold *this* edge,
> because the Cxx replaces both the branch and the call.
>
> The implicit-operand copy is critical: omitting the RegMask would
> defeat IPRA (O39); omitting the implicit-use list (HL/DE/A for
> args) could mislead later passes about liveness.

> **Implementation Notes**:

### Step 3.3 — Wire `foldConditionalCalls` into the pipeline [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangBranchOpt.cpp`

In `runOnMachineFunction`, add a call to the new helper. Place it
**after** `invertConditionalBranch` (which simplifies `Jcc;JMP` →
inverted Jcc) and **before** `foldConditionalReturns` (which is
unrelated). New order:

```cpp
Changed |= invertConditionalOverRET(MF);
Changed |= foldZeroSelectReturn(MF);
Changed |= threadJMPOnlyBlocks(MF);
Changed |= invertConditionalBranch(MF);
Changed |= foldConditionalCalls(MF);   // new
Changed |= removeRedundantJMP(MF);
Changed |= foldConditionalReturns(MF);
Changed |= removeDeadBlocks(MF);
```

Also forward-declare the method in the class body.

> **Implementation Notes**:

### Step 3.4 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**:

### Step 3.5 — Lit test: conditional-call.ll [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/conditional-call.ll`

Cases:

1. **Basic Z fold** — `if (x == 0) foo();` → expect `CZ foo`.
2. **Basic NZ fold** — `if (x != 0) foo();` → expect `CNZ foo`.
3. **C / NC fold** — `if (x < 10u) foo();` → expect a conditional CALL.
4. **Negative — return value used** — `int r = c ? foo() : 0;` must
   keep `CALL` because the result COPY in the call block forbids
   folding.
5. **Negative — multi-pred CALL block** — two `if`s funneling into
   a shared call block must keep `CALL`.

Add explicit `CHECK-NOT: CALL\tfoo` plus `CHECK: C{{N?Z}}\tfoo` for
positive cases, and `CHECK: CALL\tfoo` for negative cases.

> **Implementation Notes**:

### Step 3.6 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**:

### Step 3.7 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests\features\49\v6clang.c` to `v6clang_new01.asm`, confirm
that conditional `if (c) foo();` patterns lower to single `Cxx foo`
opcodes and that there is no `Jcc; CALL foo;` sequence in the output.

> **Implementation Notes**:

### Step 3.8 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**:

### Step 3.9 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

### Step 3.10 — Update `design/future_plans/README.md` [x]

Mark O15 with `✅` and set `[x]` in the summary table.

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1 — `if (cond) foo();`

```asm
; Before                             ; After
ORA  A          ;  4cc, 1B           ORA  A          ;  4cc, 1B
JZ   .Lskip     ; 12cc, 3B           CNZ  foo        ; 18cc taken / 12cc not, 3B
CALL foo        ; 18cc, 3B
.Lskip:
```

Savings: **3 bytes**, **12cc when call taken** (or equivalently
30cc → 18cc taken / 16cc → 12cc not-taken; identical not-taken cost).

### Example 2 — `if (x == 0) reset();` (Z path)

`JNZ .Lskip; CALL reset; .Lskip:` → `CZ reset`.

Saves the 3-byte JNZ branch unconditionally; saves 12cc on the
taken-call path.

### Example 3 — Negative: result used

`int v = c ? foo() : 0;` lowers (post-RA) to a CALL block that
also contains `MOV r, A` to capture the result. Our fold rejects
this case because the call block has more than one non-debug
instruction. Output unchanged.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Lost IPRA RegMask after fold | Forward all operands of original `CALL` onto new `Cxx` (preserves RegMask + implicit reg uses/defs). Verified by `V6ClangCallRegMaskVerifier` in debug builds (already present, would assert if a CALL-class instr lacked a mask). |
| Folding when result is used | Only fold when `bb.call` contains exactly one non-debug, non-terminator instruction. A result COPY would disqualify the block. |
| Folding when call block has multiple predecessors | Require `pred_size() == 1` so deleting the block is safe. |
| Folding tail call (`V6CLANG_TAILJMP`) by mistake | Match `V6CLANG::CALL` opcode specifically; tail calls have a different opcode. |
| Branch-target operand types other than MBB | Reject when `Jcc.getOperand(0).isMBB()` is false; threading already redirected those. |
| Stale CFG edges left after delete | Remove edge MBB→bb.call before deleting; bb.call's outgoing edge (to skip) is detached during dead-block cleanup. |

---

## 6. Relationship to Other Improvements

- **O14 / O23** (tail call & cross-block tail call): handle
  `CALL; RET` and `CALL` → RET-only successor; complementary —
  O15 handles non-tail conditional calls.
- **O35** (conditional return over RET): mirror pattern for RET.
- **O39** (IPRA): O15 must preserve the RegMask operand or it
  silently regresses IPRA spill behavior at the rewritten call
  site. Forwarded explicitly in step 3.2.
- **`V6ClangBranchOpt`** order: runs after `invertConditionalBranch`
  so that `Jcc; JMP` patterns are normalized first, ensuring our
  fold sees the canonical `Jcc skip; (CALL block)` shape.

## 7. Future Enhancements

- **Allow trailing copies as cost-bound**: extend the fold to also
  match call blocks with a single COPY of `A`/`HL`/`DE` to a
  callee-clobbered register, rewriting both as conditional. Modest
  added complexity; useful for `int v = c ? foo() : v;` patterns.
- **Cost-model gating**: when the conditional path is *cold* (e.g.
  `__builtin_expect`), the not-taken cost reduction (Cxx 12cc vs
  Jcc+nothing 12cc) is neutral; the byte savings still help. No
  gating needed today, but worth revisiting once `MBFI` is wired
  into `V6ClangBranchOpt`.

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O15 Feature Description](design\future_plans\O15_conditional_call_optimization.md)
* [O23 Plan (mirror pattern for tail calls)](design\plan_conditional_tail_call.md)
* [O35 Plan (mirror pattern for RET)](design\plan_conditional_return_over_ret.md)
* [O39 IPRA Integration](design\plan_ipra_integration.md)
