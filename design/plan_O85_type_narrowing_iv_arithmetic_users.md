# Plan: O85 — TypeNarrowing: Narrow i16 Up-Counter When IV Has Arithmetic Users

## 1. Problem

### Current behavior

`V6ClangTypeNarrowing::tryNarrowLoopIV` contains an overly conservative guard:

```cpp
// PN's only user (besides the backedge from AddOp) must be... well, AddOp.
for (User *U : PN->users()) {
    if (U != AddOp)
        return false;
}
```

This check rejects narrowing any loop counter PHI that has uses beyond the
increment instruction (`AddOp`).  The most common such case is a counted loop
where the counter appears directly in body arithmetic:

```c
uint16_t sum_indices(void) {
    uint16_t s = 0;
    for (uint16_t i = 0; i < 100; i++)
        s += i;  // <-- 'i' is a second user of the i16 PHI
    return s;
}
```

A symmetric restriction exists for `AddOp->users()`: any user that is not the
PHI back-edge, an `icmp`, or (for step −1 only) an `inttoptr` causes an
immediate `return false`, so `s += (i + 1)` patterns are also blocked.

IR after Clang -O2 (simplified):
```llvm
%i     = phi i16 [0, %pre], [%i.next, %latch]
%i.next = add i16 %i, 1
%cond  = icmp eq i16 %i.next, 100
; body:
%s.next = add i16 %s, %i   ; <-- second user of %i → tryNarrowLoopIV bails
```

### Desired behavior

The counter `%i` is provably in [0, 99] (init = 0 < 256, bound = 100 < 256,
step = +1, no wrap).  It should be narrowed to i8, and every arithmetic use of
the old i16 IV should be replaced by `zext(i8 narrow_i)` — a transformation
that is bit-for-bit identical within the proven range.

The narrowed IR should be:
```llvm
%i.narrow  = phi i8 [0, %pre], [%i.narrow.next, %latch]
%i.wide    = zext i8 %i.narrow to i16          ; replaces all %i arithmetic uses
%i.narrow.next = add i8 %i.narrow, 1
%cond      = icmp eq i8 %i.narrow.next, 100    ; narrowed exit check
; body:
%s.next = add i16 %s, %i.wide                  ; uses wide value, unchanged semantics
```

### Root cause

The `PN->users()` guard was written conservatively to handle only the
"pure counter" case (counter used only as next-value source and exit
comparison).  It never gained the zext-substitution logic needed to safely
allow additional uses.

The parallel guard on `AddOp->users()` has the same origin.

---

## 2. Strategy

### Approach: Collect-then-Substitute in `tryNarrowLoopIV`

Replace the strict bail-out loops with *collectors*:

1. Walk `PN->uses()` — collect non-`AddOp`, non-PHI uses into `ExtraPNUses`.
2. Walk `AddOp->uses()` — collect non-PHI-backedge, non-icmp, non-inttoptr,
   non-PHI uses into `ExtraAddUses`.
3. After range verification via the exit `icmp` (unchanged logic), and after
   constructing `NewPN` (i8) and `NewAdd` (i8):
   - Insert `Wide_PN = zext i8 NewPN to i16` at `Header->getFirstNonPHI()`.
   - Replace every use in `ExtraPNUses` with `Wide_PN`.
   - Insert `Wide_Add = zext i8 NewAdd to i16` immediately after `NewAdd`.
   - Replace every use in `ExtraAddUses` with `Wide_Add`.
4. Guard: if extra uses exist but `CmpsDirect` and `CmpsViaPtr` are both empty
   (no icmp bound visible — the exit was pointer-replaced by LPI), return false
   to avoid unsafe narrowing.  This defers "Case A" to a future SCEV pass.

PHI users of the old i16 IV are rejected (both `PN` and `AddOp` user loops
bail on `isa<PHINode>`).  Such uses would require per-edge zext placement
across basic-block boundaries; the single-insertion-point approach is
insufficient and the case is rare in practice.

### Why this works

- **Correctness**: the range check on `CmpsDirect` already proves
  `PN ∈ [Init, Bound)` ⊆ `[0, 255]` for step +1 (and `[Bound, Init]` ⊆
  `[0, 255]` for step −1).  Within that range `zext(trunc(x)) == x` for any
  i16 value, so replacing `%i` with `zext(i8 narrow_i)` is semantically
  identical.
- **Dominator safety**: `Wide_PN` is inserted at `Header->getFirstNonPHI()`,
  which dominates every loop-body block.  All non-PHI loop-body users of `%i`
  are therefore dominated by the insertion point.  `Wide_Add` is inserted
  immediately after `NewAdd` (in the latch), which dominates any user of
  `AddOp` in the latch or blocks dominated by the latch.
- **Use-list safety**: all extra uses are collected before any modification;
  `U->set(Wide)` only rewrites collected uses, so there is no iterator
  invalidation.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6CLANG/V6ClangTypeNarrowing.cpp` | Extend `tryNarrowLoopIV`: add `ExtraPNUses`/`ExtraAddUses` collectors; add range guard; add zext substitution block |
| `tests/features/67/v6clang.c` | New feature test (sum_indices, weighted_sum) |
| `tests/features/67/c8080.c` | Reference implementation |

---

## 3. Implementation Steps

### Step 3.1 — Create test folder and baseline assembly [x]

Create `tests/features/67/` with `v6clang.c`, `c8080.c`, and baseline assembly:

```
tools\c8080\c8080.exe tests\features\67\c8080.c -a tests\features\67\c8080.asm
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\67\v6clang.c -o tests\features\67\v6clang_old.asm
```

> **Design Notes**: Test focuses on `sum_indices` (pure arithmetic, no GEP) as
> the canonical Case B pattern. Also includes `weighted_sum` which still shows
> the register-pressure benefit.

> **Implementation Notes**:

### Step 3.2 — Extend `tryNarrowLoopIV`: PN extra-use collector [x]

In `V6ClangTypeNarrowing.cpp`, replace the strict PN-user guard block:

```cpp
// OLD — bail on any non-AddOp user of PN:
for (User *U : PN->users()) {
    if (U != AddOp)
        return false;
}
```

with:

```cpp
// NEW — collect non-AddOp users for zext substitution.
// PHI users are rejected: per-edge insertion is not implemented.
SmallVector<Use *, 4> ExtraPNUses;
for (Use &U : PN->uses()) {
    if (U.getUser() == AddOp)
        continue;
    if (isa<PHINode>(U.getUser()))
        return false;
    ExtraPNUses.push_back(&U);
}
```

> **Implementation Notes**:

### Step 3.3 — Extend `tryNarrowLoopIV`: AddOp extra-use collector [x]

Before the AddOp user scan loop, declare `ExtraAddUses`:

```cpp
SmallVector<Use *, 4> ExtraAddUses;
```

Change the loop from iterating over `AddOp->users()` to `AddOp->uses()` so
that `Use *` pointers are available for rewriting.  Change inner variable
names from `U` (`User *`) to `U.getUser()` where needed, and replace the
final `return false;` (which rejected unrecognized users) with:

```cpp
    // Any other user: collect for zext rewrite.
    // PHI users would require per-edge insertion — reject.
    if (isa<PHINode>(U.getUser()))
        return false;
    ExtraAddUses.push_back(&U);
    continue;
```

> **Design Notes**: The existing `inttoptr` path already has `if (Step != -1) return false`,
> which properly restricts the inttoptr shape to down-counters.  No change
> needed there.

> **Implementation Notes**:

### Step 3.4 — Add range guard before rewrite [x]

After the AddOp user scan loop and before the "All clear — rewrite." comment,
add:

```cpp
// If extra IV uses exist but no icmp provides the loop bound, we cannot
// prove the range ⊆ [0, 255] without SCEV.  Defer these (Case A) to a
// future SCEV-driven extension.
if ((!ExtraPNUses.empty() || !ExtraAddUses.empty()) &&
    CmpsDirect.empty() && CmpsViaPtr.empty())
    return false;
```

> **Implementation Notes**:

### Step 3.5 — Insert zext substitution block in rewrite section [x]

After `NewPN->addIncoming(NewAdd, LatchBB)` and before the CmpsDirect
rewriting loop, insert:

```cpp
// Rewrite extra PN users: old i16 IV value → zext(i8 NewPN).
// Insert the zext right after the header's PHIs so it dominates all
// loop-body users.
if (!ExtraPNUses.empty()) {
    IRBuilder<> B(PN->getParent()->getFirstNonPHI());
    Value *Wide = B.CreateZExt(NewPN, PN->getType(),
                               NewPN->getName() + ".wide");
    for (Use *U : ExtraPNUses)
        U->set(Wide);
}
// Rewrite extra AddOp users: old i16 i.next → zext(i8 NewAdd).
// Insert immediately after NewAdd (in the latch block).
if (!ExtraAddUses.empty()) {
    IRBuilder<> B(cast<Instruction>(NewAdd)->getNextNode());
    Value *Wide = B.CreateZExt(NewAdd, AddOp->getType(),
                               NewAdd->getName() + ".wide");
    for (Use *U : ExtraAddUses)
        U->set(Wide);
}
```

> **Design Notes**: After this block, `PN->users()` contains only `AddOp` (all
> extra uses replaced) and `AddOp->users()` contains only `PN` (all extra AddOp
> uses replaced, icmps not yet erased).  The existing erasure logic below
> (`setIncomingValueForBlock` + `eraseFromParent`) therefore proceeds unchanged.

> **Implementation Notes**:

### Step 3.6 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**:

### Step 3.7 — Lit test [x]

Create `llvm-project/llvm/test/CodeGen/V6CLANG/type-narrowing-iv-arith-users.ll`
covering:

- **Test A** (up-counter, PN extra use): `phi i16 [0], [add i16 phi, 1]`;
  direct icmp eq, i16 100; `phi` also used in `add i16 sum, phi` → expect
  `phi i8`, `zext i8 to i16` in output.
- **Test B** (AddOp extra use): `phi` used only in AddOp; `i.next` used in
  body `add i16 sum, i.next` → expect narrowing + `zext i8 to i16` on the
  add result.
- **Test C** (down-counter, PN extra use, step −1): same shape but step = −1
  → also narrows.
- **Test D** (PHI user of PN → no narrowing): `phi i16 [%i, latch]` uses the
  counter → expect NO change (guard fires).
- **Test E** (no icmp, extra PN user → no narrowing): after LPI removes icmp,
  extra arithmetic user remains → expect NO change (Case A guard fires).

Run:
```
llvm-build\bin\llvm-lit llvm-project\llvm\test\CodeGen\V6CLANG\type-narrowing-iv-arith-users.ll -v
```

> **Implementation Notes**:

### Step 3.8 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**:

### Step 3.9 — Verification assembly steps from `tests\features\README.md` [x]

```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S tests\features\67\v6clang.c -o tests\features\67\v6clang_new01.asm
```

Verify that:
- `sum_indices`: counter is `INR r` (not `INX rp`); exit uses single-byte
  `CPI`/`CMP` with no hi-byte check; `zext` of counter compiles to `MVI H, 0`
  (hoistable) + `MOV L, r`.
- `weighted_sum`: similar improvement; register D freed.

> **Implementation Notes**:

### Step 3.10 — Make sure result.txt is created. `tests\features\result.md` [x]

> **Implementation Notes**:

### Step 3.11 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1 — `sum_indices` (primary test)

```c
uint16_t sum_indices(void) {
    uint16_t s = 0;
    for (uint16_t i = 0; i < 100; i++)
        s += i;
    return s;
}
```

**Before O85 (i16 counter in register pair, e.g. DE)**:
```asm
; preheader: LXI D, 0; LXI B, 0
.loop:
    ; s += i: zext DE → HL, then DAD B
    MOV H, D        ; 8cc — zext hi byte (= 0 but compiler doesn't know)
    MOV L, E        ; 8cc — zext lo byte
    DAD B           ; 12cc — s += i
    MOV B, H        ; 8cc — store result
    MOV C, L        ; 8cc
    INX D           ; 8cc — i++  (i16 increment)
    MVI A, 100      ; 8cc — load bound
    CMP E           ; 4cc — compare lo byte
    JNZ .loop       ; 12cc — most iterations
    ; exit iteration only: hi-byte check
    XRA A           ; 4cc
    CMP D           ; 4cc
    JNZ .loop       ; 12cc
; per-iter: 8+8+12+8+8 + 8 + 8+4+12 = 76cc
; exit overhead: +20cc once
```

**After O85 (i8 counter in single register)**:
```asm
; preheader: LXI B, 0; MVI E, 0; MVI H, 0  (H=0 hoisted)
.loop:
    ; s += i: H already 0, just MOV L,E
    MOV L, E        ; 8cc — L = i (H=0 hoisted)
    DAD B           ; 12cc — s += i
    MOV B, H        ; 8cc
    MOV C, L        ; 8cc
    INR E           ; 8cc — i++ (same cost as INX D on V6CLANG)
    MVI A, 100      ; 8cc
    CMP E           ; 4cc
    JNZ .loop       ; 12cc
; per-iter: 8+12+8+8 + 8 + 8+4+12 = 68cc  (saves 8cc/iter from hoisted MOV H,D)
; no hi-byte check at exit
```

**Savings**: 8 cc/iter (MOV H, D eliminated by range knowledge + LICM of MVI H, 0) + 20 cc/run (hi-byte check eliminated).

### Example 2 — `weighted_sum` (register pressure)

A loop `for (uint16_t i = 0; i < 64; i++) s += arr[i] + i` keeps the GEP
access (`arr[i]`) alongside the direct index use.  LPI converts `arr[i]` to
a running pointer, but `i` must remain for the `+ i` term.  After O85, `i`
is narrowed to i8, freeing the hi-byte register of the pair.  In a
register-pressure scenario this prevents a spill that costs
`SHLD addr + LHLD addr` = 20+20 = 40 cc per occurrence.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Wrong narrowing when no icmp bound (Case A, loop > 255 iters) | Guard: `ExtraPNUses.empty() \|\| !CmpsDirect.empty()` — explicitly returns false when no icmp proof |
| zext inserted before all users are visible | Collected-before-modified pattern; no iterator invalidation |
| PHI user of PN across loop back-edges | Explicitly rejected (`isa<PHINode>` bail-out) |
| Register pressure increase from new `zext` live range | Observed savings (freed D register) outweigh in all tested cases; lit test covers regression |
| Interaction with `tryNarrowAndConst` phase-2 sibling check | `tryNarrowLoopIV` runs first (phase 1); if it narrows `%i` to i8, it is no longer an i16 PHI sibling and the `tryNarrowAndConst` check is unaffected |

---

## 6. Relationship to Other Improvements

- **V6ClangLoopPointerInduction (LPI)**: runs before TypeNarrowing.  If LPI
  eliminates the exit icmp (pointer comparison), the new guard catches it and
  returns false.  The Case A scenario (LPI replaced icmp, counter has arith
  users) is deferred to a SCEV-based O85b.
- **O03 (narrow-type arithmetic)**: broader i8 chain narrowing at DAG level.
  O85 operates at IR level, upstream of O03, and feeds it narrower types.
- **O52 (index IV rewriting)**: superseded by LPI.  O85 addresses the
  remaining gap that O52 was meant to cover (counter with arithmetic uses).

---

## 7. Future Enhancements

- **O85b — Case A via SCEV**: when the exit icmp has been replaced by a
  pointer comparison (LPI), use `SE->getBackedgeTakenCount(L)` to recover
  the trip count and prove the range ⊆ [0, 255], enabling narrowing even
  without a visible icmp.
- **PHI-user support**: per-edge zext insertion for loop counters used as
  incoming values of other PHIs.
- **Non-unity step**: extend to steps ±2, ±4 when range still fits in i8.

---

## 8. References

* [O85 Design Doc](design/future_plans/O85_type_narrowing_iv_arithmetic_users.md)
* [V6CLANG Build Guide](docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs/Vector_06c_instruction_timings.md)
* [Future Improvements](design/future_plans/README.md)
