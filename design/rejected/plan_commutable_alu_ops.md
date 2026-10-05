# Plan: Commutable ALU Operand Selection (O60)

## Resolution
Implemented, tested, shown no stable perf improvements, perf regression in some
caces. Rejected.

## 1. Problem

### Current behavior

Trivial commutative 8-bit adds produce a 3-instruction shuffle when the
incoming operand placement does not match the `Acc` (A) register the
pattern requires as LHS:

```asm
; char sum(char arg0, char arg1)   ; arg0=A, arg1=E
sum:
    MOV   L, A      ; save arg0
    MOV   A, E      ; move arg1 into A (the LHS)
    ADD   L         ; ADD with the saved arg0
    RET
```

The shuffle costs **2 extra `MOV`s (8cc, 2B)** for every commutative
ALU op whose operand assignment got flipped. In hotter code this
cascades — see the inner loop in `interleaved_add`:

```asm
    ;--- V6CLANG_RELOAD8 ---
    PUSH  DE
    MOV   D, H
    LXI   HL, __v6clang_ss.interleaved_add+6
    MOV   L, M
    MOV   H, D
    POP   DE
    ADD   L           ; ← the *only* real work; everything above is shuffle
```

### Desired behavior

The compiler should recognize that `+`, `&`, `|`, `^` are commutative
and pick whichever operand ordering requires fewer copies:

```asm
sum:
    ADD   E           ; arg0 already in A; arg1 in E — commute and use directly
    RET
```

### Root cause

Three independent gaps in the backend combine to produce the shuffles:

1. **TableGen defs lack `isCommutable = 1`.** All 8-bit register ALU ops
   (`ADDr`, `ADCr`, `ANAr`, `ORAr`, `XRAr`) and all 16-bit commutative
   pseudos (`V6CLANG_ADD16`, `V6CLANG_AND16`, `V6CLANG_OR16`, `V6CLANG_XOR16`) are
   missing the flag. Without it, `TwoAddressInstructionPass` never
   swaps operands to avoid a tied-operand copy; the register coalescer
   never retries coalescing through a commuted form; and MachineCSE
   cannot canonicalize operand order across uses. See
   [V6ClangInstrInfo.td#L259](llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L259) (8-bit)
   and [V6ClangInstrInfo.td#L721](llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L721) (16-bit).

2. **ISel does not prefer A-aligned LHS.** When a function argument or
   the result of a prior ALU op already sits in `A`, ISel still emits
   the DAG in whichever operand order the SelectionDAG happens to
   produce. For commutative ops this is essentially random; when the
   "wrong" operand is picked as LHS, a pre-RA commute cannot always
   recover (both operands live past the op).

3. **No post-RA residual cleanup.** Spill reshaping and late
   scheduling can flip which operand ended up in `A` at the use site.
   `V6ClangAccumulatorPlanning` already tracks A-contents but does not
   rewrite a commutative ALU op to read from whichever side currently
   matches `A`.

---

## 2. Strategy

### Approach: Three-layer operand-selection improvement

**Layer 1 — TableGen `isCommutable = 1` (pre-RA, primary win)**

Add `let isCommutable = 1 in` around the five 8-bit register ALU defs
and the four 16-bit pseudo defs. This is consumed by:

- `TwoAddressInstructionPass`: before inserting a tied-operand copy,
  tries swapping; keeps the swap iff it avoids the copy.
- Register coalescer: retries coalescing the tied def against the
  commuted source operand.
- MachineCSE / scheduler: hashes operand-order-insensitively.

Because `$dst` is tied to `$lhs = Acc` (fixed A), the legal commute
swaps the meaning of `$lhs` and `$rs`; the tied pair still lands in
`A` (the non-`Acc` operand just keeps its GR8 allocation). This is
the case LLVM's default `commuteInstructionImpl` handles correctly.

**Layer 2 — ISel operand-order preference (pre-RA, secondary)**

In `V6ClangDAGToDAGISel::Select` (or via a pattern predicate), for the
commutative ALU opcodes, inspect the two operands. When one operand
is demonstrably "already in A" at that SelectionDAG point — e.g. it is
an incoming physreg copy from `$A`, or it is the result of a prior
node that writes `A` (`LDA`, previous ALU, `LDAX`) — prefer it as
LHS. This fixes cases where pre-RA commute (Layer 1) cannot fire
because both operands are live past the op (TwoAddressPass can only
eliminate one of the two possible copies).

**Layer 3 — Post-RA commute in `V6ClangAccumulatorPlanning`**

Add a new method `commuteMatchingAccALU()` to
[V6ClangAccumulatorPlanning.cpp](llvm/lib/Target/V6Clang/V6ClangAccumulatorPlanning.cpp)
that walks each MBB post-RA, maintains `A`-value tracking (already
present), and when it encounters a commutative ALU op whose current
LHS is NOT what `A` holds but whose RHS IS, swaps them by rewriting
operand 2. Handles residual cases introduced by the spiller and
scheduler that Layers 1 and 2 cannot reach.

### Why this works

- **Layer 1 is sound by construction.** LLVM's tied-operand commute
  rewriter respects reg-class constraints. `Acc` is a single-reg class;
  the tied result class is unchanged. If the commute would violate
  constraints, the pass simply skips it.
- **Layer 2 is a pure ISel preference.** No correctness change — just
  pick between two semantically equivalent DAG selections.
- **Layer 3 only rewrites operand positions of a single commutative
  ALU op.** Preserves flag semantics (commutative ops produce the same
  flags regardless of operand order: ADD/ADC Z/S/P/CY all symmetric;
  logicals clear CY unconditionally). No live-range extension.

### Summary of changes

| File | Layer | Change |
|------|-------|--------|
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td` | 1 | Add `isCommutable = 1` to `ADDr`, `ADCr`, `ANAr`, `ORAr`, `XRAr` |
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td` | 1 | Add `isCommutable = 1` to `V6CLANG_ADD16`, `V6CLANG_AND16`, `V6CLANG_OR16`, `V6CLANG_XOR16` |
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangISelDAGToDAG.cpp` | 2 | Prefer A-aligned LHS when selecting commutative ALU ops |
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangAccumulatorPlanning.cpp` | 3 | Add `commuteMatchingAccALU()` walker using existing A-value tracking |
| `llvm/...` (mirror) | — | Run `scripts\sync_llvm_mirror.ps1` |
| `design/future_plans/README.md` | — | Add O60 row |

No new pass. No new pseudo. No CC/flag semantic change. `ADCr` and
`SBBr` behaviors are preserved (only `ADCr` is commutative and only
when the carry-in is considered invariant — which it is, as the carry
operand is implicit in FLAGS and unaffected by operand swap).

Note: `SBBr` is NOT commutative (`a - b - C ≠ b - a - C`). Only `ADCr`
is. `SUBr`/`SBBr`/`CMPr` must remain non-commutable.

---

## 3. Implementation Steps

### Step 3.1 — Read reference documents [ ]

- [V6ClangArchitecture.md](docs/V6ClangArchitecture.md) — calling convention
  (arg0 in A, arg1 in E)
- [V6ClangOptimization.md](docs/V6ClangOptimization.md) — existing ALU patterns
- [V6ClangCallingConvention.md](docs/V6ClangCallingConvention.md) — physreg
  argument assignment
- [V6ClangBuildGuide.md](docs/V6ClangBuildGuide.md) — build commands
- [Vector_06c_instruction_timings.md](docs/Vector_06c_instruction_timings.md)
  — verify `MOV r,r'` = 4cc, 1B

> **Design Notes**: Confirm that `ADCr` semantics are invariant under
> commute (carry is read from FLAGS, not a source operand) — it is.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.2 — Layer 1a: Mark 8-bit ALU regs commutable [ABANDONED]

**Abandoned — the change regressed codegen.**

In [V6ClangInstrInfo.td](llvm/lib/Target/V6Clang/V6ClangInstrInfo.td), wrap
`ADDr`, `ADCr`, `ANAr`, `ORAr`, `XRAr` in an additional
`let isCommutable = 1 in { ... }` scope. `SUBr`, `SBBr`, and `CMPr`
must NOT receive the flag.

> **Design Notes**: The existing `let Defs = [FLAGS] in { let
> Constraints = "$dst = $lhs" in { ... } }` block already covers all
> eight ops. Split into two inner scopes: commutable (add/adc/and/or/xor)
> and non-commutable (sub/sbb). `CMPr` is outside the `Constraints`
> block (no `$dst`) and stays as-is.

> **Implementation Notes**: Tried as described. Build succeeds, lit +
> golden still 102/102 green, **but feature-test codegen regresses**:
>
> | Function | Old | New (isCommutable) |
> |---|---|---|
> | `sum_add` | 3 insns (MOV L,A; MOV A,E; ADD L) | 4 insns + static spill of E |
> | `both_live` | 5 insns, ends `ADD L` | 6 insns, ends `MOV A,L; ADD E` |
> | `spill_pressure` | 11 insns, reload `LDA mem; ADD B` | 14 insns, reload `MOV A,B; LXI; MOV L,M; ADD L` |
>
> **Root cause** (from post-TwoAddrPass MIR):
> ```
> %1:acc = COPY killed $e                    ; RHS vreg forced to Acc class
> %2:acc = COPY killed %0:gr8                ; LHS vreg in Acc
> %2:acc = ADDr %2:acc(tied), killed %1:acc  ; BOTH in Acc simultaneously!
> ```
> LLVM's default `commuteInstructionImpl` swaps operand contents but
> leaves per-position register-class constraints from the InstrDesc
> unchanged. Since `$lhs` is class `Acc` (single physreg A) and `$rs`
> is class `GR8`, after commute the vreg that held the free GR8 RHS
> inherits the Acc constraint of position 1. The allocator now has
> two vregs both requiring physreg A at the same program point and
> spills one to static stack. The resulting spill costs far more than
> the shuffle it was trying to avoid.
>
> **Conclusion**: isCommutable cannot be applied to 8-bit ALU while
> operand classes are asymmetric (Acc vs GR8). Fixing this would
> require either (a) writing a custom `commuteInstructionImpl` that
> also swaps register-class constraints, or (b) redefining ADDr et al.
> to take GR8 for both operands and model the A-physreg pinning via
> implicit operands — both far larger changes than this plan intends.
> The A-aligned operand selection problem is better handled by
> Layer 2 (ISel) and Layer 3 (post-RA AccPlanning). Revert applied;
> the 8-bit defs are kept non-commutable with a comment explaining
> why.

### Step 3.3 — Layer 1b: Mark 16-bit ALU pseudos commutable [x]

In [V6ClangInstrInfo.td](llvm/lib/Target/V6Clang/V6ClangInstrInfo.td), add
`isCommutable = 1` to `V6CLANG_ADD16`, `V6CLANG_AND16`, `V6CLANG_OR16`,
`V6CLANG_XOR16`. `V6CLANG_SUB16` stays non-commutable.

> **Design Notes**: These pseudos do NOT have `$dst = $lhs`
> constraints (unlike the 8-bit physical ops). Commute still helps by
> letting the coalescer choose the cheaper of two copy insertions
> when expanding to `V6CLANG_ADD16`'s 8-bit chain.

> **Implementation Notes**: Applied inside a nested
> `let isCommutable = 1 in { ... }` scope covering ADD16/AND16/OR16/XOR16.
> Both input operands are class `GR16` (symmetric), so the class-
> asymmetry problem seen in Layer 1a does not apply. `sum16` output
> unchanged (`DAD DE; RET` — already optimal in baseline). Full
> regression 102/102 green. No adverse effect observed.

### Step 3.4 — Layer 1: Build & sanity check [ ]

```
cd c:\Work\Programming\v6clang
cmd /c """C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc FileCheck not"
```

Run existing full test suite to catch any unexpected commute-induced
changes before proceeding to Layers 2/3.

> **Design Notes**: Expect small MIR diffs from the commuter picking
> different operand orders. Golden test numeric output must be
> unchanged.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.5 — Layer 1 lit test: `commute-alu-tied.ll` [ ]

Create `tests/lit/CodeGen/V6Clang/commute-alu-tied.ll` asserting the
`sum`-style case:

```
define i8 @add_a_e(i8 %a, i8 %b) {
  %r = add i8 %a, %b
  ret i8 %r
}
; CHECK-LABEL: add_a_e:
; CHECK-NEXT:  ADD E
; CHECK-NEXT:  RET
; CHECK-NOT:   MOV L, A
```

Add parallel cases for `and`, `or`, `xor` (all 8-bit commutative ops).

> **Design Notes**: Use `-O2` — `-O0` will keep spills.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.6 — Layer 2: A-aligned LHS preference in ISel [x]

In [V6ClangISelDAGToDAG.cpp](llvm/lib/Target/V6Clang/V6ClangISelDAGToDAG.cpp),
add a `preferAccLHS()` helper used in `Select()` before falling
through to the TableGen-generated selector. For commutative 8-bit
ALU nodes (`ISD::ADD`/`AND`/`OR`/`XOR` with i8 result), if operand 1
is a `CopyFromReg(A)` or a node known to produce its result in `A`,
swap operands 0 and 1 on the DAG before selection.

> **Design Notes**: Keep the helper conservative — only rewrite when
> the match is certain (explicit `CopyFromReg` of `A`, or a V6CLANG
> opcode whose TableGen def has `Acc:$dst`). Do not attempt full
> value-tracking here; that's Layer 3's job.

> **Implementation Notes**: Two surprises during implementation:
>
> 1. **DAG operands reference virtual registers, not physregs.** The
>    natural check `CopyFromReg($A)` never fires for formal arguments
>    because `LowerFormalArguments` emits `CopyFromReg(vreg)` where
>    `vreg` is separately mapped to the physreg `$A` via the
>    `MachineFunction`'s live-in list. Fix: resolve a-alignment by
>    looking up `MRI.liveins()` for a matching `{physreg, vreg}` pair.
>
> 2. **A DAG-level operand swap has no effect.** The TableGen-
>    generated matcher for the commutative `ISD::ADD` pattern re-picks
>    operand ordering internally. `CurDAG->UpdateNodeOperands(N, Op1,
>    Op0)` updates the DAG but the emitted machine node's operand
>    order is still chosen by the matcher. Fix: bypass the matcher
>    entirely — emit the `ADDr`/`ANAr`/`ORAr`/`XRAr` `MachineSDNode`
>    directly via `CurDAG->getMachineNode()` with operands in the
>    desired (LHS=A-aligned, RHS=other) order and `ReplaceNode(N,
>    MN)`.
>
> Feature test 31 output after Layer 2:
>
> | Function | Old | New | Δ |
> |---|---|---|---|
> | `sum_add` | `MOV L,A; MOV A,E; ADD L; RET` | `ADD E; RET` | −2 |
> | `sum_and` | `MOV L,A; MOV A,E; ANA L; RET` | `ANA E; RET` | −2 |
> | `sum_or`  | `MOV L,A; MOV A,E; ORA L; RET` | `ORA E; RET` | −2 |
> | `sum_xor` | `MOV L,A; MOV A,E; XRA L; RET` | `XRA E; RET` | −2 |
> | `both_live` | 6 insns | 7 insns | +1 |
> | `spill_pressure` | 11 insns | 14 insns | +3 |
> | `sum16` | `DAD DE; RET` | `DAD DE; RET` | 0 |
>
> The `both_live` and `spill_pressure` regressions arise because
> Layer 2 is pre-RA and cannot see spill costs: it forces the
> A-aligned operand to be LHS even when the RHS operand could have
> been cheaply reloaded directly into A via `LDA` (yielding the
> commuted form `b+a`). These residual cases are exactly what
> Layer 3 (post-RA `V6ClangAccumulatorPlanning` commute) is designed to
> recover. Net impact on the feature test: −4 insns. Full 102/102
> lit + golden regression green.
>
> **Guard refinement (post-baselining).** The initial unconditional
> Layer 2 regressed `both_live` (+1) and `spill_pressure` (+3). Root
> cause: the helper pinned LHS=A-aligned without checking whether
> that operand would actually still be in `A` at the ALU point. Two
> guards restore correctness while preserving every win:
>
> - **Guard 1 — A-aligned operand has exactly one use.** If the
>   `CopyFromReg(A)` operand has more than one user, RA must copy
>   it out of `A` for the other use, so pinning LHS forces a
>   re-materialization (`MOV A,<saved>` before the ALU). Catches
>   `both_live`, where `a` feeds the ADD *and* a store.
>
> - **Guard 2 — in multi-ALU DAGs, fire only for ALUs pinned early
>   in the schedule.** When at least one other i8 ALU is already a
>   `MachineSDNode` in the same DAG (SelectionDAG is per-BB), the
>   current ALU must have a user that is not `ISD::CopyToReg`.
>   Rationale: `CopyToReg`-only users indicate the ALU is free-
>   floating at the BB tail — the scheduler places it last, other
>   chain-pinned ALUs clobber `A` first, and RA is then forced to
>   preserve the A-aligned operand across them. A non-`CopyToReg`
>   user (store, call, other machine ALU) pins this ALU early so
>   firing is safe. Catches `spill_pressure` while still winning
>   `chain4`, `sibling2`, and `two_args_two_ops`.
>
> Final feature-test deltas (both sides with `--enable-deferred-
> spilling`, LEA_FI fix applied):
>
> | Function | Old | New | Δ |
> |---|---:|---:|---:|
> | `sum_add`/`_and`/`_or`/`_xor` | 3 each | 1 each | −2 × 4 = **−8** |
> | `both_live` | 5 | 5 | 0 |
> | `spill_pressure` | 11 | 11 | 0 |
> | `chain4` (`a+b+c+d`) | 12 | 10 | **−2** |
> | `sibling2` (`(a+b)\|(c^d)`) | 11 | 9 | **−2** |
> | `mixed_imm` (`(a+b)+7`) | 3 | 3 | 0 |
> | `two_args_two_ops` | 10 | 8 | **−2** |
> | `sum16` | 1 | 1 | 0 |
>
> Net **−14 insns** across the feature test, zero regressions.
>
> **Coverage limits of Layer 2 (measured).** Layer 2's win surface
> is narrow and deliberately so:
>
> 1. It fires **only when one of the ALU operands is
>    `CopyFromReg(V6CLANG::A)`** at the point of selection. In practice
>    that means:
>    - function arguments whose ABI slot is `A` (`arg0` of a
>      u8-taking function), or
>    - 8-bit return values flowing directly into a commutative op.
> 2. Values produced by in-BB loads, reloads, or prior computed
>    results never look A-aligned to ISel, even if RA will end up
>    placing them in `A`. Layer 2 therefore contributes nothing to
>    loop bodies where `A` is ping-ponged through the static-stack
>    spill slot (see the `arr_sum` loop in feature test 31 — 0
>    insn delta between Layer 2 ON and OFF).
> 3. Equivalently, the post-RA peephole
>
>     ```
>     MOV  r1, A         ; A moved out into r1
>     MOV  A, r2         ; A overwritten with r2
>     <OP> r1            ; commutative OP reading r1; r1 dead after
>     ```
>
>    → `<OP> r2` (with `OP ∈ {ADD,ADC,ANA,ORA,XRA}`) would cover
>    the exact same set of functions on this test file. Layer 2's
>    only genuine pre-RA advantage is that it can influence RA's
>    spill choices in larger functions where the shuffle never
>    materialises — we have not yet measured a case where this
>    matters in isolation. If the ISel complexity ever becomes a
>    maintenance burden, replacing Layer 2 with the peephole
>    described above is a defensible simplification.
>
> Remaining inefficiencies in `arr_sum`-style loops are register-
> allocator / spill-scheduling problems (multiple values contending
> for `A` across a long live range), not commutativity problems;
> they are out of scope for this plan.

### Step 3.7 — Layer 2: Build [x]

Same command as Step 3.4.

> **Implementation Notes**: Clean build, only pre-existing C4062
> warnings. No TableGen changes needed beyond Step 3.3.
### Step 3.8 — Layer 2 lit test: `commute-alu-isel.ll` [ ]

Create `tests/lit/CodeGen/V6Clang/commute-alu-isel.ll` targeting cases
Layer 1 cannot reach — both operands live past the ALU op, but one
is already in A from a prior use. Example: `r = a + b; use(a);
use(b); use(r)`.

> **Design Notes**: If the output is already optimal after Layer 1
> alone for a given case, drop it from this test and document why.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.9 — Layer 3: `commuteMatchingAccALU()` in AccumulatorPlanning [ ]

In [V6ClangAccumulatorPlanning.cpp](llvm/lib/Target/V6Clang/V6ClangAccumulatorPlanning.cpp),
add a new method that walks MBBs post-RA. Maintain the existing
`A`-value tracking (pass already has this for `eliminateRedundantAccMoves`).

When the scanner hits one of `ADDr`/`ADCr`/`ANAr`/`ORAr`/`XRAr`:

- If current tracked `A`-value == RHS physreg (`$rs`) AND
- LHS physreg is currently live and not equal to A,

swap operand 2 so that the now-correct RHS is the physreg that is
NOT in A, and the preceding `MOV A, <lhs>` becomes dead (to be
cleaned up by the existing redundant-MOV elimination in the same
pass).

> **Design Notes**: Keep the rewrite confined to the operand at index
> 2 (the `$rs` input). The tied `$dst`/`$lhs` input stays as `A`.
> Flag semantics: all five ops set Z/S/P identically under commute;
> ADD/ADC set CY identically; AND/OR/XOR clear CY regardless. Safe.

> **Design Notes**: Guard with `-v6clang-disable-acc-planning` (existing
> toggle) and add a sub-toggle `-v6clang-disable-commute-acc-alu` for
> isolation testing.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.10 — Layer 3: Build [ ]

Same command as Step 3.4.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.11 — Layer 3 lit test: `commute-alu-post-ra.ll` [ ]

Create `tests/lit/CodeGen/V6Clang/commute-alu-post-ra.ll` targeting
spill-induced residuals. Construct a function with enough register
pressure that the spiller introduces a late `MOV A, X` where `A`
already held the correct RHS pre-spill.

Toggle test: `-v6clang-disable-commute-acc-alu` reverts to the
Layer-1/2 output.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.12 — Lit test: `commute-alu-disabled.ll` [ ]

Sanity-check that disabling Layer 3 only (keeping Layers 1 and 2
live) still produces Layer-1 optimal output. Ensures layers are
independent and the toggle is correct.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.13 — Run regression tests [ ]

```
python tests/run_all.py
```

Must pass:
- All lit tests (CodeGen + MC + Clang)
- All 15 golden tests
- M7 round-trip (13)
- M10 link round-trip (2)
- M12 validation sweep
- Runtime tests (4)
- `-verify-machineinstrs` sweep

> **Design Notes**: Expect MIR diffs across the suite. Verify that
> cycle-count-sensitive golden tests either improve or stay flat;
> any regression is a bug.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.14 — Verification assembly steps from `tests\features\README.md` [ ]

Create `tests/features/<next-id>/` following the template. Include
at minimum:

- `sum` (arg0+arg1, both scalar)
- `multi_live` (commutative op with liveness pressure)
- An i16 variant exercising `V6CLANG_ADD16` commute
- A loop body containing `ADD` where commute fires inside the hot path

> **Implementation Notes**: <empty. filled after completion>

### Step 3.15 — Make sure `result.txt` is created [ ]

Per [tests/features/README.md](tests/features/README.md), run the
feature verification script and confirm `result.txt` is generated
and matches the expected commuted output.

> **Implementation Notes**: <empty. filled after completion>

### Step 3.16 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: <empty. filled after completion>

### Step 3.17 — Documentation updates [ ]

- `design/future_plans/README.md`: add O60 table row and summary row
- `design/future_plans/O60_commutable_alu_ops.md`: short cross-ref
  stub pointing to this plan
- `docs/V6ClangOptimization.md`: add "Commutable operand selection"
  subsection describing the three layers

> **Implementation Notes**: <empty. filled after completion>

---

## 4. Expected Results

### Example 1: `sum(char, char)` — the canonical case

Before (current output, from
[tests/features/20/v6clang_xchg.asm#L119](tests/features/20/v6clang_xchg.asm#L119)):

```asm
sum:
    MOV   L, A      ; 4cc 1B
    MOV   A, E      ; 4cc 1B
    ADD   L         ; 4cc 1B
    RET
```

After Layer 1 alone:

```asm
sum:
    ADD   E         ; 4cc 1B
    RET
```

**Savings: 8cc, 2B per function.**

### Example 2: `multi_live` — inline commute avoids reload

Before:

```asm
multi_live:
    MOV   L, A      ; save arg0
    MOV   A, C      ; set up OUT
    OUT   0xde
    MOV   A, L      ; reload arg0
    ADD   E
    ADI   3
    RET
```

After (Layer 1 + Layer 2): `A` is clobbered by `OUT`, so Layer 1
alone still spills. Layer 2 cannot help because the A-clobber is
unavoidable. Layer 3 cannot help either. This case remains
unchanged — correctly demonstrating where the boundary of the
optimization lies. (A further enhancement would lift `ADD E` ahead
of the `OUT`; that is outside this plan's scope.)

### Example 3: i16 commute reducing copies before expansion

A function containing `i16 c = a + b;` where `a` is in DE and `b`
in HL. Pre-Layer-1, ISel may produce `V6CLANG_ADD16 dst=HL, lhs=DE, rhs=HL`
requiring a DE→HL copy before expansion. With Layer 1, the coalescer
commutes to `V6CLANG_ADD16 dst=HL, lhs=HL, rhs=DE`, eliminating the
`XCHG` / `MOV H,D; MOV L,E` pair.

**Savings: 4cc, 1B per i16 commute (XCHG) or 8cc, 2B (MOV pair).**

### Example 4: inner loop from `interleaved_add`

Within `.LBB0_2`, any of the 4+ ALU ops that currently shuffle `A`
back into place will benefit from combined Layer 1+3. Exact savings
depend on RA output, but even one eliminated shuffle per iteration
over a typical loop trip count of 256 = **2048cc, 512B** saved over
the program.

### Aggregate expectation across golden tests

Anticipated reduction: 1-3% in code size, 1-2% in cycle counts for
arithmetic-dominated golden tests (`arith`, `fib`, `sieve`). Flat
for data-movement-dominated ones (`memcpy`, `sprintf`-style).

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `isCommutable` on `ADCr` violates carry semantics | `ADCr` IS commutative: `a + b + C == b + a + C`. Carry read from FLAGS unaffected by operand order. Covered by existing ADC lit tests + new commute-alu-tied.ll. |
| TwoAddressPass commute breaks `Acc` class constraint | LLVM checks reg-class legality inside `commuteInstructionImpl`; if illegal, it skips. Tested via `-verify-machineinstrs` sweep in Step 3.13. |
| Layer 2 ISel rewrite produces different DAG shape breaking existing patterns | Gate Layer 2 on a `-v6clang-disable-isel-commute-pref` hidden toggle. Any test regression → disable Layer 2 and investigate. |
| Layer 3 swap leaves stale A-value tracking | Post-swap, refresh the tracked A-value to the result of the commuted op. Identical to existing write-through logic for non-commuted ALU ops — reuse the same hook. |
| Flag differences in CY for ADD vs SUB swap | Only commutative ops receive the flag; SUB/SBB/CMP explicitly excluded. Covered by code review + encoding lit tests. |
| Interaction with O36 (branch-implied value propagation) | Commute preserves both result value and Z flag; O36 observes only those. No interaction. |
| Interaction with O38 (XRA+CMP zero-test) | O38 rewrites `XRA A` (identity); commute doesn't apply (both operands are A). No interaction. |
| Layer 3 creates new adjacent redundant MOVs | Existing V6ClangPeephole pass (self-MOV + redundant-MOV) runs after AccPlanning and will clean them up. |

---

## 6. Relationship to Other Improvements

- **O13 Load-Immediate Combining**: Commute exposes more
  opportunities for O13 by freeing registers. After commute, an
  immediate that was loaded into the original LHS may be reusable.
- **O32 XCHG in copyPhysReg**: 16-bit commute (Layer 1b) reduces the
  need for O32's XCHG insertions by letting the coalescer pick the
  pair that doesn't need swapping.
- **O20 Honest Store/Load Defs**: Orthogonal — operates at a
  different level (pseudo expansion correctness, not operand order).
- **O39 IPRA Integration**: IPRA narrows per-call clobbers; commute
  reduces the cost of the clobbers that remain. Composes cleanly.
- **O12 Global Copy Optimization**: Targets cross-BB copy elimination;
  commute (Layer 1) targets intra-BB copy elimination at tied-operand
  boundaries. Non-overlapping coverage.
- **Supersedes**: parts of O01 (redundant MOV after BUILD_PAIR + ADD16)
  for the common `a = a + b` pattern.

---

## 7. Future Enhancements

- **Layer 4 — Inter-BB commute**: Extend Layer 3 to track A-value
  across BB boundaries for single-predecessor successors. Rarely
  applicable given the 8080's short BB lifetimes, but could help
  short loops.
- **Commute-aware scheduler hooks**: Integrate with
  `MachineScheduler` to prefer schedules that align A-value with
  commutative ALU LHS operands. Depends on O11 cost model.
- **Immediate-form commute**: Already subsumed by DAG canonicalization
  for `ADI`/`ANI`/`ORI`/`XRI` (constant → RHS → immediate form). No
  action needed.
- **Memory-form commute (`ADDM`/`ANAM`/...)**: Impossible — the M
  operand is implicit-HL. Excluded by ISA.
- **Commute across V6CLANG_BUILD_PAIR**: When building an i16 from two
  bytes to feed into a commutative i16 op, sometimes the pair order
  can be swapped to align with the coalescer's preferred DE/HL. Out
  of scope here; worth an O6x follow-up.

---

## 8. References

* [V6CLANG Build Guide](docs/V6ClangBuildGuide.md)
* [V6CLANG Architecture](docs/V6ClangArchitecture.md)
* [V6CLANG Calling Convention](docs/V6ClangCallingConvention.md)
* [V6CLANG Optimization](docs/V6ClangOptimization.md)
* [Vector 06c CPU Timings](docs/Vector_06c_instruction_timings.md)
* [Future Improvements](design/future_plans/README.md)
* [V6ClangInstrInfo.td — 8-bit ALU defs](llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L243)
* [V6ClangInstrInfo.td — 16-bit ALU pseudos](llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L720)
* [V6ClangAccumulatorPlanning.cpp](llvm/lib/Target/V6Clang/V6ClangAccumulatorPlanning.cpp)
* [V6ClangISelDAGToDAG.cpp](llvm/lib/Target/V6Clang/V6ClangISelDAGToDAG.cpp)
* LLVM `TwoAddressInstructionPass` — consumes `isCommutable`
* LLVM `TargetInstrInfo::commuteInstructionImpl` — default commute impl
