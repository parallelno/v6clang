# Plan: O88 — MVI-through-MOV Collapse

## 1. Problem

### Current behavior

`V6CLANG_BUILD_PAIR` expands hi-first, lo-second. When the hi source register was
materialised by an immediately preceding `MVI reg, imm`, the expansion emits a
dead copy through that intermediate:

```asm
MVI   L, 0          ; 8cc, 2B — zero hi via intermediate L
;--- V6CLANG_BUILD_PAIR ---
MOV   H, L          ; 8cc, 1B — redundant: just copies the known-zero L to H
MOV   L, A          ; 8cc, 1B
```

Three instructions / 4 bytes / 24cc where two instructions / 3 bytes / 16cc
are sufficient.

### Desired behavior

```asm
MVI   H, 0          ; 8cc, 2B — zero written directly to the destination half
;--- V6CLANG_BUILD_PAIR ---
MOV   L, A          ; 8cc, 1B
```

### Root cause

`collapseMovChain` in `V6ClangPeephole.cpp` only scans for `MOVrr` producers:

```cpp
if (ProducerMI.getOpcode() != V6CLANG::MOVrr)
    continue;  // ← MVIr producers are skipped entirely
```

`eliminateDeadMVI` cannot help either: it erases `MVI r, imm` only when `r` is
dead *immediately after* the MVI, but here `r` (e.g. L) is still live at the
next instruction `MOV H, L`.

---

## 2. Strategy

### Approach: extend `collapseMovChain` with an `MVIr`-producer loop

Add a second forward-scan loop in `V6ClangPeephole::collapseMovChain` that handles
`MVIr` producers. When the sole consumer `MOV Z, X` is reached and `X` is dead
after that consumer, emit `MVI Z, Imm` in place of the `MOV` and erase the
original `MVI X, Imm`.

### Why this works

- `X` is an intermediate register that holds `Imm` from the MVI until the MOV.
- If nothing else reads `X` between producer and consumer, and `X` is dead
  after the consumer, then the consumer is the sole use.
- Replacing `MOV Z, X` with `MVI Z, Imm` is semantically identical and
  eliminates both the intermediate load and the copy.
- The O61 patch guard prevents touching MVIs that carry a pre-instr symbol,
  which would orphan spill-patched imm references.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp` | Add `MVIr`-producer loop in `collapseMovChain` |
| `llvm-project/llvm/test/CodeGen/V6Clang/peephole-mvi-through-mov.ll` | New lit test |
| `tests/features/70/` | New feature test with C source and baseline/new asm |

---

## 3. Implementation Steps

### Step 3.1 — Extend `collapseMovChain` with `MVIr`-producer case [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

After the existing `MOVrr`-producer loop (ends before the `return Changed;`
statement), add a second loop:

```cpp
  // O88: MVIr-producer variant.
  // Pattern: MVI X, Imm  ; [window, no read/clobber of X] ; MOV Z, X
  //          where X is dead after the MOV.
  // Transform: erase both, emit MVI Z, Imm before the old MOV position.
  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    MachineInstr &ProducerMI = *I;
    if (ProducerMI.getOpcode() != V6CLANG::MVIr)
      continue;
    if (isO61PatchedImm(ProducerMI))
      continue;

    Register X   = ProducerMI.getOperand(0).getReg();
    int64_t  Imm = ProducerMI.getOperand(1).getImm();

    unsigned Steps = 0;
    for (auto J = std::next(I); J != E && Steps < kChainWindow; ++J) {
      if (J->isDebugInstr())
        continue;
      ++Steps;

      bool IsConsumer = J->getOpcode() == V6CLANG::MOVrr &&
                        TRI->regsOverlap(J->getOperand(1).getReg(), X);

      bool ReadsX = false, ClobbersX = false;
      for (const MachineOperand &MO : J->operands()) {
        if (!MO.isReg() || !MO.getReg())
          continue;
        if (!TRI->regsOverlap(MO.getReg(), X))
          continue;
        if (MO.isUse() && !MO.isUndef() && !(IsConsumer && &MO == &J->getOperand(1)))
          ReadsX = true;
        if (MO.isDef())
          ClobbersX = true;
      }

      if (IsConsumer) {
        if (!ClobbersX && isRegDeadAfter(MBB, J, X, TRI)) {
          Register Z = J->getOperand(0).getReg();
          const TargetInstrInfo &TII =
              *MBB.getParent()->getSubtarget().getInstrInfo();
          BuildMI(MBB, J, J->getDebugLoc(), TII.get(V6CLANG::MVIr), Z)
              .addImm(Imm);
          auto Next = std::next(I);
          J->eraseFromParent();
          ProducerMI.eraseFromParent();
          I = std::prev(Next);
          Changed = true;
        }
        break;  // stop scan regardless (only fold single-consumer case)
      }

      if (ReadsX || ClobbersX)
        break;
    }
  }
```

> **Design Notes**:
> - `kChainWindow = 8` is reused from the existing loop; already declared
>   `static constexpr` in the function scope so it's shared.
> - `IsConsumer` is checked before `ReadsX` so that the consumer's own source
>   operand doesn't terminate the scan prematurely.
> - `ClobbersX` inside the consumer test handles the edge case where the
>   consumer MOV writes back to X itself (`MOV X, X` — self-copy, but that
>   is normally eliminated first).
> - We do **not** need a `ClobbersY` guard (no source register to preserve).
> - Multi-consumer case (e.g. `draw_circle`'s `MVI C, 0; MOV H, C; … MOV B, C`):
>   the first consumer `MOV H, C` is found, but C is not dead after it, so we
>   `break` without folding. Acceptable: the single-consumer `sin8` case is
>   the primary beneficiary.
> - `eliminateDeadMVI` (which runs after `collapseMovChain`) will clean up
>   any remaining dead `MVI X, Imm` left by partial multi-consumer folds,
>   once X truly becomes dead.
>
> **Implementation Notes**: <empty>

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

### Step 3.3 — Create and run lit test: `peephole-mvi-through-mov.ll` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/peephole-mvi-through-mov.ll`

Test cases:
1. `sin8`-like: `zext i8 → i16`, pointer lookup — should produce `MVI H, 0`
   not `MVI L, 0; MOV H, L`.
2. Disabled form: with `--v6clang-disable-peephole` both instructions must appear.
3. O61-patched MVI guard: a patched MVI must NOT be folded.
4. Multi-consumer safety: `MVI X, 0; MOV Y, X; MOV Z, X` — must NOT fold when
   X is still live after the first consumer MOV.

Run:
```
llvm-build\bin\llc -march=v6clang llvm-project\llvm\test\CodeGen\V6Clang\peephole-mvi-through-mov.ll | llvm-build\bin\FileCheck llvm-project\llvm\test\CodeGen\V6Clang\peephole-mvi-through-mov.ll
```

Or via lit:
```
llvm-build\bin\llvm-lit llvm-project\llvm\test\CodeGen\V6Clang\peephole-mvi-through-mov.ll -v
```

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

All tests must pass.

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case with the new compiler:
```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\70\v6clang.c -o tests\features\70\v6clang_new01.asm
```

Verify that `sin8` body no longer contains `MVI L, 0; MOV H, L` and instead
shows `MVI H, 0`.

### Step 3.6 — Create `result.txt` [x]

See `tests\features\result.md` for structure. Save as
`tests\features\70\result.txt`.

### Step 3.7 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

---

## 4. Expected Results

### `sin8` improvement

```asm
; Before (4 instructions, 5B, 32cc)
    MVI   L, 0
    MOV   H, L          ← dead copy of zero
    MOV   L, A
    ; + DAD D / MOV A, M / RET ...

; After (3 instructions, 4B, 24cc)
    MVI   H, 0
    MOV   L, A
    ; + DAD D / MOV A, M / RET ...
```

**Net saving per call**: −8cc, −1B.

### `draw_circle` (partial — single-consumer only in loop body)

The `.LLo61_3` block uses `MVI H, 0; MOV A, H` (two instructions). The
`collapseMovChain` MVIr loop will fold `MVI H, 0; MOV A, H → MVI A, 0`
(identical savings: −8cc, −1B) because A is dead-then-redefined after the MOV.
Wait — that is a different variant (MOV A, H where A is produced from H=0). Let
this naturally emerge from the test.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| O61-patched MVI accidentally folded — orphaned spill label | `isO61PatchedImm` guard on producer; lit test case 3 validates |
| Multi-consumer fold produces wrong code | Scan breaks at first consumer; fold only fires when X dead after that consumer |
| `ClobbersX` inside consumer position causes missed fold | `ClobbersX` is checked only for non-consumer instructions in the scan; consumer check precedes the bail |
| `isRegDeadAfter` false-negative for pair sub-registers | Existing infrastructure already handles this (pair-kill artifact fix from 2026-05-30 repo notes) |

---

## 6. Relationship to Other Improvements

- **O82 `collapseMovChain`**: This is a direct extension of the same function;
  shares the window bound and iterator discipline.
- **O82 `eliminateDeadMVI`**: Handles remaining dead MVIs after partial
  multi-consumer folds; both are called in the same `runOnMachineFunction` loop.
- **O61 SpillPatchedReload**: The `isO61PatchedImm` guard is critical to safe
  coexistence with O61's patched-imm spill scheme.

---

## 7. Future Enhancements

- Multi-consumer fold: if all consumers of X are `MOV Zi, X` and X is dead
  after the last, replace every consumer with `MVI Zi, Imm` and erase the
  original MVI. Requires collecting all consumers before rewriting.
- Extend to `MVI_A` producer (MVI A, imm): only needed if RA ever assigns A as
  the zero-extend intermediate; not observed in current output.

---

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\V6ClangInstructionTimings.md)
* [Future Improvements](design\future_plans\README.md)
* [O88 Design](design\future_plans\O88_mvi_through_mov_collapse.md)
