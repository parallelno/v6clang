# Plan: O83 — POP/PUSH Pair Elimination for Dead Register Pairs

## 1. Problem

### Current behavior

The spill/reload pseudo lowering and the O43 (SHLD/LHLD→PUSH/POP) peephole
together sometimes produce a `POP rp; ...; PUSH rp` sequence in a basic block
where:

- `rp` is not read or modified by any instruction between `POP` and `PUSH`,
- `rp` is dead (not read) after the `PUSH`, and
- no instruction between them alters the stack pointer.

In this situation both instructions are dead: the `POP` loads a value that is
immediately discarded, and the `PUSH` stores a value that is never consumed.
The net effect on the stack and on every register is zero, yet they remain in
the output, wasting 22 cycles and 2 bytes per occurrence.

### Concrete evidence (`tests/benchmarks_c/asm/v6clang_sieve_O2.s`, block `.LBB15_8`)

```asm
; Case 1 — trivially adjacent (ELIMINABLE):
        PUSH H               ; V6CLANG_ADD16 preamble: save HL
        DAD  B               ; HL += BC
        MOV  B, H
        MOV  C, L
        POP  H               ; ADD16 epilogue: restore HL       ← POP
        ;--- V6CLANG_SPILL16 ---
        PUSH H               ; spill HL to stack slot            ← PUSH (redundant)
        MOV  L, C            ; HL immediately overwritten
        MOV  H, B
        SHLD .LLo61_3+1
        POP  H               ; end-of-spill restore

; Case 2 — invalid: rp used between (NOT eliminable):
        POP  H
        INX  H               ; ← reads and writes HL  ✗
        INX  H               ; ← reads and writes HL  ✗
        PUSH H

; Case 3 — valid: intervening instruction does not touch rp (ELIMINABLE):
        POP  H               ; reload preamble: save outer HL   ← POP
        INX  B               ; modifies BC, not HL  ✓
        ;--- V6CLANG_SPILL16 ---
        PUSH H               ; spill HL (immediately overwritten)← PUSH (redundant)
        MOV  L, C
        MOV  H, B
        SHLD .LLo61_5+1
        POP  H
```

### Desired behavior

After O83, cases 1 and 3 are removed: `POP H` and the matching `PUSH H` are
erased; the instructions between them (if any) are kept intact.

### Root cause

The `V6ClangPeephole` pass has no pattern for this class of redundancy. The POP
comes from one pseudo expansion (ADD16 epilogue or RELOAD16 epilogue), and the
PUSH comes from the next pseudo expansion (SPILL16 prologue). Neither expansion
has visibility into the other's intent, so both instructions survive.

---

## 2. Strategy

### Approach: New `eliminateDeadPopPush()` method in `V6ClangPeephole`

Add a single forward-scan method to the existing `V6ClangPeephole` pass. The scan
is O(n) per basic block and requires no new passes or infrastructure.

For each `POP rp` found:
1. Walk forward, skipping debug instructions.
2. If an instruction reads or writes any sub-register of `rp` → stop.
3. If an instruction alters the stack (PUSH, POP, CALL, branch, XTHL, SPHL)
   → stop.
4. If a `PUSH rp` is found (same pair) → candidate found.
5. Check `isRegDeadAfter(MBB, PushIt, rp, TRI)` — if rp is dead, erase both.

Skip the PSW pair (`A`+`FLAGS`) entirely because `FLAGS` is an implicit input
to nearly every ALU instruction, making condition 2 almost never satisfiable.

### Why this works

- **Stack neutrality**: `POP` increments SP by 2; `PUSH` decrements by 2.
  No intervening instruction changes SP (condition 3 ensures this).
  Removing both leaves SP unchanged. ✓
- **Register value**: Since no instruction between them reads or writes `rp`
  (condition 2), the value that `POP` loaded is the same value that `PUSH`
  would store. Since `rp` is dead after `PUSH` (condition 5), nobody reads
  the loaded value either. Erasing both is safe. ✓
- **Correctness for other registers**: The intervening instructions are
  unchanged. Their register and memory effects are identical with or without
  the POP/PUSH frame. ✓

### Summary of changes

| File | Change |
|------|--------|
| `V6ClangPeephole.cpp` | Add `DisablePopPushElim` flag, `eliminateDeadPopPush()` method, call site in `runOnMachineFunction()` |
| `tests/lit/CodeGen/V6Clang/peephole-pop-push-elim.ll` | New lit test (positive + negative + disabled-flag cases) |

---

## 3. Implementation Steps

### Step 3.1 — Create test folder and baseline assembly [ ]

Create `tests/features/64/` with `v6clang.c`, `c8080.c`, and baseline assembly.

See **Preparation steps** from `tests/features/README.md`.

> **Design Notes**: The sieve-of-Eratosthenes kernel (SIZE=200) is used as the
> test function because it is the known source of the pattern. The `c8080`
> compiler eliminates the redundancy naturally through tighter register
> tracking, so the comparison shows a direct improvement.

> **Implementation Notes**: <empty — filled after completion>

---

### Step 3.2 — Add `DisablePopPushElim` command-line flag [ ]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

After the existing `DisableMviAluFold` flag (around line 47), add:

```cpp
static cl::opt<bool> DisablePopPushElim(
    "v6clang-disable-pop-push-elim",
    cl::desc("Disable POP/PUSH pair elimination (O83)"),
    cl::init(false), cl::Hidden);
```

> **Design Notes**: Consistent naming with existing disable flags.
> **Implementation Notes**: <empty>

---

### Step 3.3 — Add method declaration to `V6ClangPeephole` class [ ]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

In the `V6ClangPeephole` class private section (around line 88), add:

```cpp
bool eliminateDeadPopPush(MachineBasicBlock &MBB);
```

> **Implementation Notes**: <empty>

---

### Step 3.4 — Implement `eliminateDeadPopPush()` [ ]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

Add the method before `runOnMachineFunction`. Full body:

```cpp
/// Eliminate a redundant POP rp; ...; PUSH rp sequence (O83).
///
/// Conditions for elimination:
///   1. Both instructions are in the same MBB.
///   2. rp (and all sub-registers) is not read or written between POP and PUSH.
///   3. No stack-affecting instruction (PUSH, POP, CALL, branch, return,
///      XTHL, SPHL) occurs between them.
///   4. rp is dead after the PUSH (verified via isRegDeadAfter).
///
/// PSW (A+FLAGS) is excluded because FLAGS is an implicit operand of almost
/// every ALU instruction, making condition 2 virtually unsatisfiable.
bool V6ClangPeephole::eliminateDeadPopPush(MachineBasicBlock &MBB) {
  if (DisablePopPushElim)
    return false;
  bool Changed = false;
  const TargetRegisterInfo *TRI =
      MBB.getParent()->getSubtarget().getRegisterInfo();

  for (auto I = MBB.begin(), E = MBB.end(); I != E; ) {
    if (I->getOpcode() != V6CLANG::POP) {
      ++I;
      continue;
    }
    Register Rp = I->getOperand(0).getReg();

    // Skip PSW: FLAGS is implicitly live through most instructions.
    if (TRI->regsOverlap(Rp, V6CLANG::PSW)) {
      ++I;
      continue;
    }

    // Scan forward for a matching PUSH rp.
    bool CanElim = true;
    MachineBasicBlock::iterator PushIt = E;

    for (auto J = std::next(I); J != E; ++J) {
      if (J->isDebugInstr())
        continue;

      // Found matching PUSH rp — candidate.
      if (J->getOpcode() == V6CLANG::PUSH &&
          J->getOperand(0).getReg() == Rp) {
        PushIt = J;
        break;
      }

      // Abort if any operand touches rp (explicit or implicit).
      bool TouchesRp = false;
      for (const MachineOperand &MO : J->operands()) {
        if (MO.isReg() && MO.getReg().isValid() &&
            TRI->regsOverlap(MO.getReg(), Rp)) {
          TouchesRp = true;
          break;
        }
      }
      if (TouchesRp) {
        CanElim = false;
        break;
      }

      // Abort on any instruction that changes the stack pointer, has
      // side-effects on control flow, or alters SP indirectly.
      if (J->isCall() || J->isBranch() || J->isReturn() || J->isBarrier()) {
        CanElim = false;
        break;
      }
      unsigned Opc = J->getOpcode();
      if (Opc == V6CLANG::PUSH || Opc == V6CLANG::POP ||
          Opc == V6CLANG::XTHL || Opc == V6CLANG::SPHL) {
        CanElim = false;
        break;
      }
      // Catch any other SP-def (LXI SP, INX SP, DCX SP, ...).
      if (J->modifiesRegister(V6CLANG::SP, TRI)) {
        CanElim = false;
        break;
      }
    }

    if (!CanElim || PushIt == E) {
      ++I;
      continue;
    }

    // rp must be dead after the PUSH.
    if (!isRegDeadAfter(MBB, PushIt, Rp, TRI)) {
      ++I;
      continue;
    }

    // All conditions met. Erase POP rp and PUSH rp.
    PushIt->eraseFromParent();
    I = MBB.erase(I); // erase POP; I now points to next instruction
    Changed = true;
    // Don't advance I: a new POP may now start at I (exposed by erasure).
  }
  return Changed;
}
```

> **Design Notes**:
> - `J->modifiesRegister(V6CLANG::SP, TRI)` catches `LXI SP`, `INX SP`, `DCX SP`
>   (all of which have `Defs = [SP]`). The explicit opcode checks for PUSH/POP
>   are still needed first because `modifiesRegister` could be slow on a full
>   scan.
> - `isRegDeadAfter` is already defined in this file and handles successor
>   live-in analysis, artifact implicit-kills, and super/sub-register aliasing.
> - The early-exit iterator pattern (`I = MBB.erase(I)`, no `++I`) allows
>   chained eliminations: if removing a POP/PUSH exposes another POP at the
>   same position, it is processed on the next iteration.
>
> **Implementation Notes**: <empty>

---

### Step 3.5 — Call from `runOnMachineFunction()` [ ]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

In `runOnMachineFunction`, add the call after `foldShldLhldToPushPop` (O43
produces the PUSH/POP pairs that O83 then eliminates):

```cpp
Changed |= foldShldLhldToPushPop(MBB);
Changed |= eliminateDeadPopPush(MBB);   // O83
```

The ordering `foldShldLhldToPushPop` → `eliminateDeadPopPush` is important:
O43 converts SHLD/LHLD pairs into PUSH/POP, potentially creating new O83
candidates in the same pass invocation.

> **Implementation Notes**: <empty>

---

### Step 3.6 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: <empty>

---

### Step 3.7 — Lit test: `peephole-pop-push-elim.ll` [ ]

Create `tests/lit/CodeGen/V6Clang/peephole-pop-push-elim.ll`.

The test uses a register-pressure-heavy loop (sieve inner kernel) and checks:
- **Positive (enabled)**: the output contains no adjacent `POP H` + `PUSH H`
  of the same register pair where the pair is clearly dead.
- **Negative (disabled flag)**: the output still compiles and the flag is
  accepted.

Run the lit test:
```
llvm-build\bin\llvm-lit tests\lit\CodeGen\V6Clang\peephole-pop-push-elim.ll -v
```

> **Implementation Notes**: <empty>

---

### Step 3.8 — Run regression tests [ ]

```
python tests\run_all.py
```

Verify all existing tests pass.

> **Implementation Notes**: <empty>

---

### Step 3.9 — Verification assembly [ ]

Follow **Verification assembly steps** from `tests/features/README.md`:

```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
    tests\features\64\v6clang.c -o tests\features\64\v6clang_new01.asm
```

Analyze the output: the three evidence cases from Case 1 and Case 3 in the
sieve kernel (`.LBB15_8`) should no longer contain the redundant POP/PUSH
pairs.

Expected savings per sieve invocation: ≥ 2 pairs × 22cc = 44cc per outer
loop iteration.

> **Implementation Notes**: <empty>

---

### Step 3.10 — Create `result.txt` [ ]

Follow `tests/features/result.md` to create `tests/features/64/result.txt`
containing: C source, c8080 main-func ASM (i8080 form), c8080 stats,
v6clang old ASM, v6clang new ASM, comparison table.

> **Implementation Notes**: <empty>

---

### Step 3.11 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: <empty>

---

## 4. Expected Results

### Sieve benchmark (.LBB15_8 outer loop body)

Case 1 (trivially adjacent):
```asm
; Before O83:
        POP  H        ; 10cc, 1B  ← REMOVED
        PUSH H        ; 12cc, 1B  ← REMOVED
; After O83: both gone
```

Case 3 (INX B between):
```asm
; Before O83:
        POP  H        ; 10cc, 1B  ← REMOVED
        INX  B        ; 6cc, 1B   kept
        PUSH H        ; 12cc, 1B  ← REMOVED
; After O83:
        INX  B        ; only this remains
```

Per outer loop iteration: **-4 instructions, -4B, -44cc** (2 pairs eliminated).

### Code size

For a function with ~10 outer-loop iterations executing the hot path,
elimination reduces the hot block size by 4 bytes and saves 44 cycles per
iteration.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Liveness misdetection — isRegDeadAfter returns wrong result | Use existing `isRegDeadAfter` with its artifact-kill filtering; covered by pair-deadness regression |
| PSW false positive — FLAGS treated as dead when it is not | Explicitly skip PSW pair; FLAGS is an implicit operand of nearly all instructions |
| Stack corruption — another PUSH/POP between POP and PUSH causes wrong SP | Abort on any PUSH/POP/CALL/branch between them (condition 3); new regression test |
| Cascade elimination creates incorrect state | Early-exit iterator: re-check from new I after erasure; covered by test case 3 |
| O43 PUSH/POP pairs not yet created when O83 runs | O83 is called immediately after O43 in runOnMachineFunction; same-pass ordering guarantees pairs are visible |

---

## 6. Relationship to Other Improvements

- **O43** (`foldShldLhldToPushPop`): converts SHLD/LHLD pairs to PUSH/POP,
  producing many of the candidate pairs that O83 eliminates.
- **O61** (spill-in-reload-immediate patching): uses `.LLo61_N` labels on
  LXI instructions. O83 does not touch LXI, so no conflict.
- **O64** (liveness-aware i8 spill lowering): also uses `isRegDeadAfter`;
  O83 is a parallel consumer, no ordering dependency.
- **O82** (`eliminateDeadMVI`): also eliminates dead stores; O83 is the
  analog for the PUSH/POP class of dead stores.

---

## 7. Future Enhancements

- Extend to multi-BB liveness: if `rp` is dead across all successors and there
  are no cross-BB POP consumers, the pattern could be eliminated even when it
  spans a block boundary (very rare; low priority).
- Handle `PUSH PSW`/`POP PSW` when both A and FLAGS are provably dead (requires
  full FLAGS liveness; low frequency in practice).

---

## 8. References

* [Feature Description](design/future_plans/O83_pop_push_pair_elimination.md)
* [V6CLANG Build Guide](docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs/Vector_06c_instruction_timings.md)
* [Future Improvements](design/future_plans/README.md)
* [Plan Format Reference](design/plan_cmp_based_comparison.md)
* [Feature Test Cases](tests/features/README.md)
