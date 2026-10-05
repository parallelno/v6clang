# Plan: O51 — LSR Cost Tuning (`isLSRCostLess` Insns-First Ordering)

Source: [O51_lsr_cost_tuning.md](future_plans/O51_lsr_cost_tuning.md) ·
Inspiration: llvm-z80 `Z80TargetTransformInfo::isLSRCostLess()` ·
Prerequisite: O7 (done — `isLSRCostLess` already overridden).

## 1. Problem

### Current behavior

`V6ClangTTIImpl::isLSRCostLess` ranks LSR formulas register-pressure first:

```cpp
return std::tie(C1.NumRegs, C1.Insns, C1.NumBaseAdds, C1.NumIVMuls,
                C1.AddRecCost, C1.ImmCost, C1.SetupCost, C1.ScaleCost) <
       std::tie(C2.NumRegs, C2.Insns, ...);
```
([V6ClangTargetTransformInfo.cpp](../llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp#L50))

For loops with three or more live pointers (≥4 IVs counting the
counter, against 3 GP pairs BC/DE/HL), LSR collapses the per-pointer
IVs into a single base+index IV to minimize `NumRegs`. Because the
i8080 has no base+index addressing, every in-loop access then
re-materializes the address with `LXI HL, slot` + `LHLD` + `DAD` —
~30cc per access — and the inner loop is dominated by spill traffic.

Demonstrated in [temp/o51_lsr_test_baseline.asm](../temp/o51_lsr_test_baseline.asm)
(generated from [temp/o51_lsr_test.c](../temp/o51_lsr_test.c)). The
`axpy3` inner loop body shows ~6 `LXI __v6clang_ss.axpy3+N` /
`MOV M,C; INX HL; MOV M,B` ping-pong sequences plus 4 `SHLD`/`LHLD`
per iteration just to swap pointers in and out of HL.

### Desired behavior

For pressure-sensitive loops, prefer LSR formulas with fewer in-loop
**instructions** even at the cost of one additional pointer IV. Pay a
single one-time spill (or accept higher prologue setup) outside the
loop in exchange for `INX rp` (8cc) per access in the loop body
instead of `LXI`+`LHLD`+`DAD`+`STAX` (~30cc).

### Root cause

The Z80 backend uses an instruction-first ordering on the same generic
LSR cost vector:

```cpp
return std::tie(C1.Insns, C1.NumRegs, C1.AddRecCost, C1.NumIVMuls,
                C1.NumBaseAdds, C1.ScaleCost, C1.ImmCost, C1.SetupCost) <
       std::tie(C2.Insns, C2.NumRegs, ...);
```

The V6CLANG ordering was chosen at O7 time on the assumption that 3 GP
pairs make register pressure absolute. Since O7, several pressure-
relief features have landed (static stack, IPRA, store/load forwarding,
deferred zero-load, spill-in-reload, liveness-aware i8 spill lowering,
O64), so the empirical balance between "register-first" and
"instruction-first" needs re-evaluation. The plan adds the alternative
ordering behind a flag so it can be A/B-tested on the regression suite,
then promoted to default if the data supports it.

## 2. Strategy

### Approach: `V6ClangOptMode`-keyed ordering with `cl::opt` override

> **Status (post-implementation)**: The original V6ClangOptMode-keyed dispatch
> was wired up and validated end-to-end, then rolled back to
> `auto = regs-first` after Step 3.7 A/B measurement showed `insns-first`
> regressing 3 of 42 regression tests on bytes (test 20: +235 B,
> test 29: +315 B, test 43: +53 B) with 0 wins. The `cl::opt` plumbing
> and both orderings stay in place; `insns-first` is now opt-in only.
> See Step 3.7 Implementation Notes for the data and the rationale.

1. Reuse the existing `V6ClangOptMode` enum from
   [V6ClangInstrCost.h](../llvm/lib/Target/V6CLANG/V6ClangInstrCost.h#L26)
   (Speed / Size / Balanced) — it already derives the mode from
   `Function::hasMinSize()/hasOptSize()` plus
   `TargetMachine::getOptLevel()`.
2. In `V6ClangTTIImpl::isLSRCostLess`, dispatch on the mode:
   * **Speed** (`-O2`/`-O3`) → Z80-style **Insns-first** ordering.
     Each in-loop instruction costs 4–12 cc with certainty; an extra
     register *may* spill, but on i8080 even a worst-case SHLD/LHLD
     pair (32 cc) still loses to the multi-instruction `LXI`+`LHLD`+
     `DAD`+`STAX` ping-pong (~30+ cc) when the latter fires once
     per loop iteration.
   * **Size** (`-Os`/`-Oz`) → keep the current **NumRegs-first**
     ordering. Each spill is also bytes in the prologue / per
     access, so register count is the better proxy for code size on
     this target.
   * **Balanced** (`-O1` / fall-through) → also **Insns-first**.
     Insns reduction typically reduces bytes too, and Balanced
     averages the two anyway.
3. Add a `cl::opt<v6clang::LSRStrategy>` named `-v6clang-lsr-strategy=` with
   values `auto` (default — use the mode-keyed dispatch),
   `insns-first`, `regs-first` so the experiment can be A/B-tested
   on the regression suite without recompiling clang for `-Os`/`-O2`.
4. Run the existing regression suite, the golden tests, and the new
   feature test (`tests/features/43`) with all three strategy values
   to confirm the dispatch matches expectations and no test regresses
   under its declared optimization mode.

### Why this works

`isLSRCostLess` is the single hook the generic LoopStrengthReduce pass
asks per-target to break ties between candidate formulas. The two
orderings differ only in field priority — both are total orders over
the same `LSRCost` fields, so neither can introduce illegal formulas;
only the tie-breaking outcome changes.

Keying on `V6ClangOptMode` is consistent with the rest of the backend
([V6ClangInstrInfo.cpp lines 603, 652, 799](../llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp#L600)
already use the same hook for DAD/INX expansion), so a `-Os` build
stays code-size-oriented end-to-end (LSR through post-RA peepholes)
and a `-O2` build stays cycle-oriented end-to-end. The `cl::opt`
override preserves the A/B-test workflow from the original plan and
lets us pin both shapes in lit. The new feature test (multi-stream
`axpy`) exercises the exact pressure shape that should benefit at
`-O2`, and the regression suite catches any case where Insns-first
regresses for Speed mode.

### Summary of changes

* `llvm-project/llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.h` — add
  `const Function &F` member so `isLSRCostLess` can derive the opt
  mode (TM is already accessible via `BaseT`).
* `llvm-project/llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp` —
  include `V6ClangInstrCost.h`, add `LSRStrategy` `cl::opt`,
  mode-keyed `isLSRCostLess` body. Update the docstring.
* `llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.{h,cpp}` — synced via
  `scripts/sync_llvm_mirror.ps1`.
* `tests/lit/CodeGen/V6CLANG/lsr-strategy-speed.ll` — lit test that the
  Insns-first shape is emitted at `-O2` (and with
  `-v6clang-lsr-strategy=insns-first`).
* `tests/lit/CodeGen/V6CLANG/lsr-strategy-size.ll` — lit test that the
  NumRegs-first shape is emitted with `optsize`/`minsize` attribute
  (and with `-v6clang-lsr-strategy=regs-first`).
* `tests/features/43/` — feature test (multi-stream axpy) with
  baseline / new asm and `result.txt`.
* `design/plan_O51_lsr_cost_tuning.md` — this file.
* `design/future_plans/README.md` — mark O51 `[x]` (after Phase 5).

No `.td`, no pass pipeline, no codegen lowering changes.

## 3. Implementation Steps

### Step 3.1 — Add `cl::opt` and the two field orderings [x]

Edit `llvm-project/llvm/lib/Target/V6CLANG/V6ClangTargetTransformInfo.cpp`:

* Add includes:
  ```cpp
  #include "V6ClangInstrCost.h"
  #include "llvm/IR/Function.h"
  #include "llvm/Support/CommandLine.h"
  ```
* Add the strategy enum and `cl::opt`:
  ```cpp
  namespace {
  enum class LSRStrategy { Auto, InsnsFirst, RegsFirst };
  } // namespace

  static llvm::cl::opt<LSRStrategy> LSRStrategyOpt(
      "v6clang-lsr-strategy",
      llvm::cl::desc("LSR formula tie-breaker ordering on V6CLANG."),
      llvm::cl::init(LSRStrategy::Auto),
      llvm::cl::values(
          clEnumValN(LSRStrategy::Auto, "auto",
                     "derive from V6ClangOptMode (default)"),
          clEnumValN(LSRStrategy::InsnsFirst, "insns-first",
                     "Z80-style: instruction count first"),
          clEnumValN(LSRStrategy::RegsFirst, "regs-first",
                     "V6CLANG historical: register count first")),
      llvm::cl::Hidden);
  ```
* Add two static helpers (file-scope) so the body of
  `isLSRCostLess` reads cleanly:
  ```cpp
  static bool insnsFirstLess(const TTI::LSRCost &C1,
                             const TTI::LSRCost &C2) {
    return std::tie(C1.Insns, C1.NumRegs, C1.AddRecCost, C1.NumIVMuls,
                    C1.NumBaseAdds, C1.ScaleCost, C1.ImmCost, C1.SetupCost) <
           std::tie(C2.Insns, C2.NumRegs, C2.AddRecCost, C2.NumIVMuls,
                    C2.NumBaseAdds, C2.ScaleCost, C2.ImmCost, C2.SetupCost);
  }

  static bool regsFirstLess(const TTI::LSRCost &C1,
                            const TTI::LSRCost &C2) {
    return std::tie(C1.NumRegs, C1.Insns, C1.NumBaseAdds, C1.NumIVMuls,
                    C1.AddRecCost, C1.ImmCost, C1.SetupCost, C1.ScaleCost) <
           std::tie(C2.NumRegs, C2.Insns, C2.NumBaseAdds, C2.NumIVMuls,
                    C2.AddRecCost, C2.ImmCost, C2.SetupCost, C2.ScaleCost);
  }
  ```
* Update the docstring above `isLSRCostLess` to explain both
  orderings, the mode-keyed dispatch, and the override flag.

> **Design Notes**: Helpers (not lambdas) so they can be reused from
> the lit-only path that calls `isLSRCostLess` directly. Keeping the
> two `std::tie` literals in one place simplifies any future field
> reorder when tracking upstream LLVM.
>
> **Implementation Notes**: Implemented as written. The `cl::opt` is
> hidden (`cl::Hidden`) and parsed via `clEnumValN`. The two helpers
> live in anonymous file-scope.

### Step 3.1b — Mode-keyed dispatch in `isLSRCostLess` [x]

The TTI ctor already takes `const Function &F`. Capture it as a
member (`const Function *F` — pointer because TTI must be
copy-assignable in some upstream paths) so `isLSRCostLess` can
derive the mode without re-querying.

Edit the header:
```cpp
// V6ClangTargetTransformInfo.h
public:
  explicit V6ClangTTIImpl(const V6ClangTargetMachine *TM, const Function &F)
      : BaseT(TM, F.getParent()->getDataLayout()),
        ST(TM->getSubtargetImpl(F)),
        TLI(ST->getTargetLowering()),
        Func(&F) {}
private:
  const Function *Func;
```

Replace the body of `isLSRCostLess`:
```cpp
bool V6ClangTTIImpl::isLSRCostLess(const TTI::LSRCost &C1,
                                const TTI::LSRCost &C2) const {
  // Explicit override.
  switch (LSRStrategyOpt) {
  case LSRStrategy::InsnsFirst: return insnsFirstLess(C1, C2);
  case LSRStrategy::RegsFirst:  return regsFirstLess(C1, C2);
  case LSRStrategy::Auto: break;
  }

  // Auto: derive from optimization mode.
  // Speed/Balanced -> Insns-first (each in-loop reload is ~30cc,
  //   far worse than +1 GP pair pressure).
  // Size           -> NumRegs-first (each spill is also bytes).
  if (Func && (Func->hasMinSize() || Func->hasOptSize()))
    return regsFirstLess(C1, C2);
  return insnsFirstLess(C1, C2);
}
```

> **Design Notes**: We use `Function::hasMinSize/hasOptSize` directly
> instead of constructing a `MachineFunction` to call `getV6ClangOptMode`
> — TTI runs at IR time, before `MachineFunction` exists. The
> resulting decision is identical (same predicate the IR-level
> attributes feed) for the Size case. For the Speed/Balanced
> distinction we fold both into Insns-first; the Balanced (-O1)
> path is secondary and the bytes-vs-cycles trade still favors
> fewer in-loop instructions on i8080.
>
> **Note on default change**: Auto mode flips the default for
> `-O2`/`-O3` builds from regs-first to insns-first. This is the
> intended behavior — Step 3.6/3.7 must validate it on the
> regression corpus before merging. If a `-O2` test regresses, the
> fix is to either (a) pin that test with
> `-v6clang-lsr-strategy=regs-first` while we investigate, or (b) revert
> Auto to regs-first and require explicit `-v6clang-lsr-strategy=
> insns-first` for opt-in.
>
> **Implementation Notes**: First wired the V6ClangOptMode-keyed dispatch
> (Speed/Balanced → insns-first, Size → regs-first) using
> `Func->hasMinSize()/hasOptSize()`. After Step 3.7 (A/B measurement)
> showed insns-first regressing 3 of 42 tests on bytes with zero
> wins, took rollback option (b): Auto now returns `regsFirstLess`
> unconditionally. The captured `Func` member stays in place because
> a future, attribute-driven dispatch is plausible (see §7).

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Two builds: one after the initial
> Auto=insns-first wiring, one after the rollback to Auto=regs-first.
> Both succeeded with no warnings.

### Step 3.3 — Sanity rebuild of the demo loop [x]

Recompile the standalone demo at `-O2` and `-Os` and with each
explicit strategy override. Expected matrix:

| Build | Expected ordering | Expected asm shape (`axpy3` inner) |
|-------|-------------------|------------------------------------|
| `-O2` (auto)              | Insns-first | per-IV `INX rp`, no in-loop `LXI __v6clang_ss.*` |
| `-O2 -v6clang-lsr-strategy=regs-first` | Regs-first  | matches current `temp/o51_lsr_test_baseline.asm` |
| `-Os` (auto)              | Regs-first  | matches current baseline |
| `-Os -v6clang-lsr-strategy=insns-first` | Insns-first | same as `-O2` auto |

```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S temp\o51_lsr_test.c -o temp\o51_lsr_test_O2_auto.asm
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S temp\o51_lsr_test.c -o temp\o51_lsr_test_O2_regs.asm  -mllvm -v6clang-lsr-strategy=regs-first
llvm-build\bin\clang -target i8080-unknown-v6clang -Os -S temp\o51_lsr_test.c -o temp\o51_lsr_test_Os_auto.asm
llvm-build\bin\clang -target i8080-unknown-v6clang -Os -S temp\o51_lsr_test.c -o temp\o51_lsr_test_Os_insns.asm -mllvm -v6clang-lsr-strategy=insns-first
fc temp\o51_lsr_test_O2_regs.asm  temp\o51_lsr_test_baseline.asm
fc temp\o51_lsr_test_Os_auto.asm  temp\o51_lsr_test_baseline.asm
fc temp\o51_lsr_test_O2_auto.asm  temp\o51_lsr_test_Os_insns.asm
```

The last three `fc`s must each report "no differences encountered"
— the first two confirm regs-first is the same as the historical
baseline regardless of how it's selected, the last confirms
Insns-first is consistent across the two paths that select it.

> **Implementation Notes**: All three `fc` checks reported
> "no differences encountered" with `-mllvm -mv6clang-annotate-pseudos`
> consistently applied. `O2_auto` (insns-first under the original
> dispatch) byte-matched `Os_insns`; `O2_regs` byte-matched
> `o51_lsr_test_baseline.asm`; `Os_auto` byte-matched the baseline.
> The Auto rollback is verified separately by Step 3.7 (re-run
> after rollback shows `auto == regs` across the corpus).

### Step 3.4 — Lit test: `lsr-strategy-speed.ll` [x]

Create `tests/lit/CodeGen/V6CLANG/lsr-strategy-speed.ll`. Source is the
IR of the multi-pointer `axpy3` loop. Two RUN lines:

```
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s --check-prefix=AUTO
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -v6clang-lsr-strategy=insns-first < %s | FileCheck %s --check-prefix=EXPLICIT
```

Both check prefixes assert the Insns-first shape — `; CHECK-NOT: LXI
HL, __v6clang_ss` between the inner loop label and its `JNZ` back edge,
plus a positive `; CHECK: INX` count on the IV pairs.

> **Design Notes**: Outside-loop spills are fine — the contract is
> "no in-loop reloads for the reachable pointer IVs". Both RUN
> lines exist so a future change to the Auto dispatch is caught
> by the AUTO prefix while the EXPLICIT prefix still enforces the
> shape independently of mode plumbing.
>
> **Implementation Notes**: After the Auto rollback the AUTO check
> moved to `lsr-strategy-size.ll` and the speed test now has only
> a single `EXPLICIT` (insns-first) RUN line; the lit signature is
> `__v6clang_ss.axpy3+10` plus `.comm   __v6clang_ss.axpy3,12,1` (a 12-byte
> static spill area, vs 10 B for regs-first).

### Step 3.5 — Lit test: `lsr-strategy-size.ll` [x]

Create `tests/lit/CodeGen/V6CLANG/lsr-strategy-size.ll`. Same IR but the
function carries `optsize` IR attribute, plus an explicit
`-v6clang-lsr-strategy=regs-first` RUN line:

```
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s --check-prefix=AUTO
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -v6clang-lsr-strategy=regs-first < %s | FileCheck %s --check-prefix=EXPLICIT
```

CHECK lines pin the current NumRegs-first spilling shape (positive
`; CHECK: LXI HL, __v6clang_ss` inside the inner loop) so the Size mode
dispatch is locked in.

> **Implementation Notes**: Pinned via `.comm   __v6clang_ss.axpy3,10,1`
> (10-byte spill area, no `+10` slot). Both AUTO (default after
> rollback) and EXPLICIT regs-first paths produce the same shape.

### Step 3.6 — Run regression tests [x]

```
python tests\run_all.py
```

The Auto dispatch flips the default for `-O2` builds. Treat any
failure as a real signal:

* If the failing test asserts asm shape that has flipped to
  Insns-first — update the CHECK lines (this is the intended
  outcome for the multi-pointer loops).
* If the failing test is a runtime/golden test — runtime semantics
  must not change. Investigate; if isolated, narrow the failing
  function with `-v6clang-lsr-strategy=regs-first` while diagnosing.
* If the failure rate is high or runtime tests fail — back out
  the Auto flip (Step 3.1b: change the trailing
  `return insnsFirstLess(...)` to `return regsFirstLess(...)`),
  rerun, document, and degrade O51 to opt-in via
  `-v6clang-lsr-strategy=insns-first`.

> **Implementation Notes**: With Auto = insns-first the lit suite
> (91/91) and the V6CLANG regression suite (`tests/run_all.py` = 2/2
> suites: golden + lit) both passed. With Auto = regs-first
> (post-rollback) both still pass. No runtime regressions observed
> in either configuration.

### Step 3.7 — A/B measurement on regression corpus [x]

For every `.c` under `tests/features/*/v6clang.c`, compile three
times at `-O2`:

```
clang ... v6clang.c -o /tmp/<n>_auto.asm
clang ... v6clang.c -o /tmp/<n>_insns.asm -mllvm -v6clang-lsr-strategy=insns-first
clang ... v6clang.c -o /tmp/<n>_regs.asm  -mllvm -v6clang-lsr-strategy=regs-first
```

For each triple, count cycles of the inner-loop bodies (use the
existing `tools\v6asm` + `docs\Vector_06c_instruction_timings.md`
references already used by `result.txt` accounting). Tabulate
regs-first-vs-insns-first cycle deltas. **Decision rule**:

* `auto` matches `insns` for every test (after Step 3.6) → the
  Auto dispatch is correct as-implemented. Document the regs-first
  workloads where Insns-first regresses and either widen the Size
  branch to catch them by attribute, or accept the regression as
  small and document it.
* `auto` matches `insns` but Insns-first regresses some test by
  >5% → either narrow Auto's Insns-first branch (e.g. require not
  just "not Size" but also "function has loop with ≥4 IVs" — see
  §7) or revert Auto to regs-first as in Step 3.6.

> **Design Notes**: This is a measurement step. The deliverable is
> a short table appended to this plan and a recommendation in
> `tests/features/43/result.txt`.
>
> **Implementation Notes**: A/B harness lives at
> [scripts/o51_ab_measure.py](../scripts/o51_ab_measure.py); raw
> output at `temp/o51_ab_summary.txt`. Across all 42 feature tests
> at -O2:
>
> | bucket | count |
> |--------|-------|
> | `insns < regs` (insns-first wins on bytes) | 0 |
> | `insns > regs` (insns-first regresses on bytes) | 3 |
> | identical | 39 |
>
> The 3 regressions:
>
> | test | regs-first | insns-first | delta |
> |------|-----------:|------------:|------:|
> | 20   | 2300 B | 2535 B | +235 B |
> | 29   | 1343 B | 1658 B | +315 B |
> | 43   | 6078 B | 6131 B |  +53 B |
>
> Decision: revert Auto to regs-first; keep `insns-first` as opt-in.
> Reasoning: LSR's `Insns` field counts pre-RA instructions; on a
> 3-pair GP target it does not see the heavy `LXI`+`MOV`+`INX HL`+
> `MOV`+`POP` reload sequences emitted when the chosen formula's
> IV count exceeds 3. The smaller `Insns` estimate therefore picks
> formulas that grow the inner loop after RA. axpy3 inner body
> measured 71 instr (regs-first) vs 80 instr (insns-first), +12.7 %.

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [x]

In `tests/features/43/`:

* `v6clang_old.asm` already captured in Phase 1 (regs-first, before
  the Auto-flip).
* Compile with `-O2` → `v6clang_new01.asm` (Auto = Insns-first
  after this plan).
* Compile with `-Os` → `v6clang_new02.asm` (Auto = Regs-first;
  expected byte-identical to `v6clang_old.asm` modulo size-driven
  changes elsewhere).
* Compile with `-O2 -mllvm -v6clang-lsr-strategy=regs-first` →
  `v6clang_new03.asm` (rollback / parity check vs `v6clang_old.asm`).

Diff the inner loop of `axpy3` between `_new01` and the others.
Confirm `LXI __v6clang_ss.*` / `LHLD __v6clang_ss.*` ping-pong is gone in
`_new01`, replaced by per-IV `INX rp`. Iterate with `_new04.asm`,
`_new05.asm` if the shape is not yet what the plan predicts.

> **Implementation Notes**: After the Auto rollback the file naming
> reflects post-rollback semantics:
> * `_new01.asm` (-O2 auto = regs-first) — **byte-identical to
>   `_old.asm`** (6078 B). No regression on the default path.
> * `_new02.asm` (-Os auto = regs-first) — 8783 B (Os has unrelated
>   size-mode codegen differences).
> * `_new03.asm` (-O2 -mllvm -v6clang-lsr-strategy=insns-first) —
>   6131 B; the +53 B is the extra `__v6clang_ss.axpy3+10` spill slot
>   plus the in-loop reload sequence the insns-first formula
>   demands.

### Step 3.9 — Make sure `result.txt` is created [x]

Per `tests/features/README.md`. Include:

* The C test case.
* c8080 `main`-and-friends asm (translated to i8080 syntax) and per-
  function worst-case cycle / byte stats.
* v6clang asm at `-O2` (auto = Insns-first), `-Os` (auto =
  Regs-first), and `-O2 -v6clang-lsr-strategy=regs-first` side-by-side,
  per-function stats for each, and the aggregate decision
  recommendation from Step 3.7.

> **Implementation Notes**: Written to
> [tests/features/43/result.txt](../tests/features/43/result.txt).
> Contents now reflect the post-rollback decision (auto = regs-first,
> insns-first as opt-in only) plus the A/B numbers from Step 3.7.

### Step 3.10 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror sync completed cleanly.

### Step 3.11 — Documentation [x]

* Update `docs/V6ClangOptimization.md` with a paragraph on the LSR
  strategy: the `V6ClangOptMode`-keyed Auto dispatch (Speed/Balanced →
  Insns-first, Size → Regs-first), the override
  `-v6clang-lsr-strategy={auto,insns-first,regs-first}`, and the
  empirical decision from Step 3.7.
* Mark O51 complete in
  [design/future_plans/README.md](future_plans/README.md) and tick
  the table-row checkbox.

> **Implementation Notes**: Added an `LSR Strategy` section to
> [docs/V6ClangOptimization.md](../docs/V6ClangOptimization.md) describing
> the two orderings, the `-v6clang-lsr-strategy` flag, and the empirical
> finding that `insns-first` does not win on this target. Marked
> O51 complete in `design/future_plans/README.md` (both the index
> table and the summary table).

## 4. Expected Results

### Example 1 — `axpy3` (3 input streams, 1 output stream) at `-O2`

Baseline today (regs-first):
* Inner loop body ≈ 35+ instructions, dominated by 4 `SHLD`/`LHLD`
  pairs and 6 `LXI __v6clang_ss.axpy3+N`+`MOV M,C; INX HL; MOV M,B`
  pointer-swap sequences per iteration.

After Auto = Insns-first:
* LSR keeps separate `BC`/`DE`/`HL` pointer IVs for three of the four
  arrays plus a counter, paying 1 spill setup *outside* the loop and
  2× `INX rp` per IV per iteration. Net per-iteration cycle reduction
  expected in the 80–150 cc range.

The same function compiled with `-Os` falls back to the regs-first
shape, on the assumption that minimizing in-loop spill bytes is
worth the cycle hit when the user has already opted into size.

### Example 2 — `dot` (2 streams + accumulator + counter)

Default emits `__v6clang_ss.dot`/`__v6clang_ss.dot+2`/`__v6clang_ss.dot+4`
ping-pong because the accumulator forces the same collapse. Insns-
first should keep both pointers in registers and spill only the
accumulator across the `__mulhi3` call site, where it has to spill
anyway.

### Example 3 — `scale_copy` (2 pointers + counter, fits in 3 pairs)

No change either way — there is no pressure to relieve and both
orderings pick the same single-IV-per-pointer formula. This is the
control case demonstrating the flag does not regress already-clean
loops.

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Auto = Insns-first at `-O2` regresses a pressure-light loop that happened to be tuned for the old shape | Two lit tests pin both shapes; Step 3.6 catches it; per-test rollback via `-v6clang-lsr-strategy=regs-first`; whole-mode rollback via 1-line edit in Step 3.1b. |
| Regression suite has loops where `Insns` reduction comes from extra hoisted setup that the rest of the backend (e.g. constant sinking) then re-introduces, masking the gain | Step 3.7 measures end-to-end cycles after all post-RA passes, not LSR-output IR. |
| Generic LSR cost field semantics drift between LLVM versions | Mirror the Z80 ordering verbatim; both backends sit on the same generic `LSRCost`, so any drift affects both equally and is caught by upstream-merge regression. |
| `isNumRegsMajorCostOfLSR()=true` interacts non-trivially with `Insns`-first ordering and yields a non-monotone choice | Out of scope of this experiment — recorded in §7 as a follow-up to evaluate flipping that hook too. |
| `-Os` users want the cycle win on one hot kernel without giving up size elsewhere | Per-function attribute override deferred to §7; meanwhile a single TU can be split or compiled with `-O2 -v6clang-lsr-strategy=insns-first` for the kernel and `-Os` for the rest. |

---

## 6. Relationship to Other Improvements

* **O7 (done)** — installed the `isLSRCostLess` hook; O51 only retunes
  the field order.
* **O10 (done — static stack)** and **O16 (done — store-to-load
  forwarding)** reduce the per-spill cost. They lower the penalty of
  an extra in-loop reload that Insns-first would tolerate, weakening
  the original "regs-first because pressure dominates" argument.
* **O39 (done — IPRA)** can leave more registers free across calls
  inside loops, again favoring formulas with more pointer IVs.
* **O41 / O64** target the per-pointer increment expansion. They are
  what makes the Insns-first formula cheap enough to win — every
  `INX rp` that Insns-first prefers is the cheapest possible form
  thanks to those passes.
* **O52 (Index IV Rewriting, future)** would make the Insns-first
  ordering more attractive still, by promoting some pointer IVs to
  i8 indices that don't consume a register pair.

## 7. Future Enhancements

* If Step 3.7 confirms Insns-first wins for Speed, evaluate flipping
  `isNumRegsMajorCostOfLSR()` to `false` so the upstream LSR scorer
  agrees with the local tie-breaker.
* Refine the Auto dispatch with loop-shape data: extend the Insns-
  first branch to require "loop has ≥4 induction variables and ≥3
  pointer IVs" so simple counted loops at `-O2` keep regs-first
  (which is harmless there but smaller).
* Investigate per-function override via attribute (e.g.
  `__attribute__((v6clang_lsr_strategy("insns")))`) for hot functions
  that disagree with the global default — useful when a `-Os`
  build has one inner kernel that should still use Insns-first.

## 8. References

* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
* [O51 description](future_plans/O51_lsr_cost_tuning.md)
* [O7 — Loop Strength Reduction (TTI)](future_plans/O07_loop_strength_reduction.md)
* [llvm-z80 analysis §S11](future_plans/llvm_z80_analysis.md)
* Standalone demo (Phase 0): [temp/o51_lsr_test.c](../temp/o51_lsr_test.c) ·
  [temp/o51_lsr_test_baseline.asm](../temp/o51_lsr_test_baseline.asm)
