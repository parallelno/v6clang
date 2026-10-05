# O85 — TypeNarrowing: Narrow i16 Up-Counter When IV Has Arithmetic Users

**Source:** V6CLANG — discovered while investigating O52 (Index IV Rewriting); O52 turned out to be
superseded by `V6ClangLoopPointerInduction`, but the counter itself may survive as i16 when used in
direct arithmetic in addition to GEP indexing.
**Savings:** 2 cc/iter (INX rp → INR r); minor register-pressure reduction from splitting
the pair live range
**Frequency:** Moderate — any counted loop `for (int i = 0; i < N; i++)` where `i` appears
in both array indexing and inline arithmetic (e.g., weighted sums, index-keyed computes)
**Complexity:** Medium — SCEV analysis for the LPI-rewrite case; zext insertion for extra uses;
structural icmp path is straightforward
**Risk:** Low — narrowing is only performed when the unsigned range is provably ⊆ [0, 255];
all non-AddOp uses of the old i16 IV are replaced with `zext(i8 narrow_iv)`, which is
bit-for-bit identical to the original i16 value within that range
**Dependencies:** `V6ClangLoopPointerInduction` (runs first, may eliminate the exit icmp); existing
`tryNarrowLoopIV` in `V6ClangTypeNarrowing.cpp` (this optimization extends it)
**Status:** [x] complete

---

## Problem

`V6ClangLoopPointerInduction` (LPI) converts GEP-indexed loop bodies to running-pointer form.
When it fires, it:

1. Replaces `gep base, %i` with an incrementing pointer PHI.
2. Optionally rewrites the loop exit from `icmp eq i16 %i.next, N` to
   `icmp eq ptr %ptr.next, arr_end`.

After step 2 the counter PHI `%i` may still be live because it appears in body arithmetic
(`sum += i`, `out[i] = weight * i`, etc.).  `V6ClangTypeNarrowing::tryNarrowLoopIV` then has the
opportunity to narrow it from i16 to i8 — but it refuses because of an overly conservative
guard:

```cpp
// PN's only user (besides the backedge from AddOp) must be... well, AddOp.
for (User *U : PN->users()) {
    if (U != AddOp)
        return false;  // <-- rejects any arithmetic user of %i
}
```

The same restriction blocks narrowing in loops that have no GEP at all but where the counter
is used in both the exit comparison and body arithmetic (e.g., `for (int i=0; i<100; i++) s+=i`).

### Concrete Example

```c
// Clang -O2 → i16 counter survives as-is
int weighted_sum(uint8_t *arr) {
    int s = 0;
    for (int i = 0; i < 100; i++)
        s += arr[i] + i;   // 'i' used in arithmetic, not just as GEP index
    return s;
}
```

After LPI, the loop IR looks like (simplified):

```llvm
; PHI nodes in loop header:
%ptr    = phi ptr   [ arr,     %preheader ], [ %ptr.next,    %latch ]
%i      = phi i16   [ 0,       %preheader ], [ %i.next,      %latch ]  ; still i16!
%s      = phi i16   [ 0,       %preheader ], [ %s.next,      %latch ]

; Body:
%v      = load i8, ptr %ptr
%v16    = zext i8 %v to i16
%sum_i  = add i16 %v16, %i        ; <-- %i used directly as i16
%s.next = add i16 %s, %sum_i

; Latch:
%ptr.next = getelementptr i8, ptr %ptr, i32 1
%i.next   = add i16 %i, 1
%exit     = icmp eq ptr %ptr.next, %arr_end  ; pointer-based exit (LPI rewrote it)
br i1 %exit, label %out, label %header
```

Because `%i` has the arithmetic user `%sum_i`, `tryNarrowLoopIV` returns early and the counter
stays i16.

---

## Assembly Impact

### Before (i16 counter, after LPI)

```asm
; LXI D, 0          ; preheader: i = 0
; LXI H, arr        ; preheader: ptr = arr
.loop:
    MOV  A, M       ; load *ptr                      (8cc)
    MOV  L, E       ; zext: L = i_lo                 (4cc)
    MOV  H, D       ; zext: H = i_hi                 (4cc)   ← i16 zero-extend
    ADD  L          ; A = *ptr + i_lo                (4cc)
    MOV  L, A
    MVI  H, 0
    DAD  BC         ; s += (A : 0)                   (10cc)
    INX  H          ; ptr++                          (6cc)
    INX  D          ; i++  ← i16 increment           (6cc)
    MOV  A, L
    CMP  E          ; ptr_lo == end_lo?              (4cc)
    JNZ  .loop      ; (10cc) + rare hi-byte check
```

**Counter increment: `INX D` = 6 cc**

### After (i8 counter, O85 applied)

```asm
; LXI H, arr        ; preheader: ptr = arr
; MVI E, 0          ; preheader: i (i8) = 0  [H=D=0 invariant handled below]
.loop:
    MOV  A, M       ; load *ptr                      (8cc)
    MOV  L, E       ; zext(i8 E) → L                 (4cc)
    MVI  H, 0       ; zext: H = 0                    (7cc)   ← materialised once if HL free
    ADD  L          ; A = *ptr + i                   (4cc)
    MOV  L, A
    MVI  H, 0
    DAD  BC         ; s += (A : 0)                   (10cc)
    INX  H          ; ptr++                          (6cc)
    INR  E          ; i++  ← i8 increment            (4cc)   ← saves 2cc
    MOV  A, L
    CMP  E          ; ptr_lo == end_lo?              (4cc)
    JNZ  .loop
```

**Counter increment: `INR E` = 4 cc → saves 2 cc/iter**

For 100 iterations that is 200 cc ≈ 80 µs at 2.5 MHz — small but free.  The real benefit shows
when the exit comparison was NOT already pointer-based (see Case B below), where the exit check
itself also shrinks.

---

## Two Sub-Cases

### Case A — LPI rewrote the exit condition to a pointer comparison

The `icmp eq i16 %i.next, N` no longer exists; the loop exits on a pointer comparison.
`tryNarrowLoopIV` cannot find a numeric bound from the IR alone.

**Required analysis:** `ScalarEvolution`.  Use `SE.getBackedgeTakenCount(L)` to obtain the
trip count.  If it is a constant ≤ 255, the IV is in [0, BTC − 1] ⊆ [0, 255] and narrowing
is safe.  If the trip count is not a constant but `SE.getUnsignedRange(PN)` proves the range
fits in 8 bits, that is also sufficient.

### Case B — Exit icmp is still present on `%i.next`

The original `icmp eq i16 %i.next, N` remains (LPI did not fire, or fired but did not rewrite
the exit).  `tryNarrowLoopIV` already extracts the bound from the icmp and checks `Bound ≤ 255`.
Only the over-restrictive PN-user guard stands in the way.

**Required change:** Relax the user loop — allow non-`AddOp` users of `PN` (and non-icmp / non-
PHI users of `AddOp`), then replace each such use with `zext(i8 NewPN)` / `zext(i8 NewAdd)`.

---

## Implementation

### Step 1 — Enable SCEV in `V6ClangTypeNarrowing`

```cpp
void V6ClangTypeNarrowing::getAnalysisUsage(AnalysisUsage &AU) const {
    AU.addRequired<ScalarEvolutionWrapperPass>();
    AU.setPreservesAll();  // remove if we need to invalidate
}
```

Add `SE = &getAnalysis<ScalarEvolutionWrapperPass>().getSE();` at the top of `runOnFunction`.

### Step 2 — Extend `tryNarrowLoopIV`

Replace the strict PN-user guard with a two-pass approach:

```cpp
// Pass 1: collect non-AddOp users of PN; they will be rewritten with zext later.
SmallVector<Use *, 4> ExtraUsesPHI;
for (Use &U : PN->uses()) {
    if (U.getUser() != AddOp)
        ExtraUsesPHI.push_back(&U);
}

// Pass 2: collect non-PHI, non-icmp users of AddOp; same treatment.
SmallVector<Use *, 4> ExtraUsesAdd;
for (Use &U : AddOp->uses()) {
    User *Usr = U.getUser();
    if (Usr == PN) continue;
    if (isa<ICmpInst>(Usr)) continue;  // handled separately
    ExtraUsesAdd.push_back(&U);
}
```

After verifying the range (icmp bound or SCEV), perform the rewrite as today, then:

```cpp
// Insert zext(i8 NewPN) at the start of the loop header for all extra PN uses.
if (!ExtraUsesPHI.empty()) {
    IRBuilder<> B(PN->getParent()->getFirstNonPHI());
    Value *Wide = B.CreateZExt(NewPN, PN->getType(), NewPN->getName() + ".zext");
    for (Use *U : ExtraUsesPHI)
        U->set(Wide);
}
// Insert zext(i8 NewAdd) just after NewAdd for all extra AddOp uses.
if (!ExtraUsesAdd.empty()) {
    IRBuilder<> B(cast<Instruction>(NewAdd)->getNextNode());
    Value *Wide = B.CreateZExt(NewAdd, AddOp->getType(), NewAdd->getName() + ".zext");
    for (Use *U : ExtraUsesAdd)
        U->set(Wide);
}
```

### Step 3 — Range proof when icmp is absent (Case A)

When `CmpsDirect` is empty after the user scan (LPI replaced the icmp), fall back to SCEV:

```cpp
if (CmpsDirect.empty() && CmpsViaPtr.empty()) {
    if (!SE) return false;  // SCEV not available
    Loop *L = LI->getLoopFor(PN->getParent());
    if (!L) return false;
    auto BTC = SE->getBackedgeTakenCount(L);
    auto *CBTC = dyn_cast<SCEVConstant>(BTC);
    if (!CBTC || CBTC->getValue()->getValue().getActiveBits() > 8)
        return false;  // trip count unknown or > 255
    // Range is [Init, Init + BTC]; check Init + BTC ≤ 255.
    if ((Init + CBTC->getValue()->getZExtValue()) > 255)
        return false;
    // Safe — proceed with no icmp to rewrite.
}
```

---

## Scope and Limitations

- Only handles **constant** upper bounds (or SCEV-constant trip counts).  Variable bounds
  (e.g., `for (int i = 0; i < n; i++)`) require a SCEV range that proves `[0, max_n − 1] ⊆ [0, 255]`
  which in practice only fires if `n` is derived from an i8 source.
- Only handles **step ±1**.  Larger steps are already rejected by the existing guard.
- Does NOT replace the GEP index — that is `V6ClangLoopPointerInduction`'s job.  O85 is purely
  about the loop counter's data type, not about pointer form.
- The inserted `zext(i8 narrow_iv)` increases the live range of `narrow_iv`.  In a tight
  register-pressure loop this could cause a spill; guard with a heuristic similar to the
  existing i16-PHI sibling check in `tryNarrowAndConst` if regressions appear.

---

## Estimated Savings

| Loop structure | Iters | Savings source | cc saved |
|---|---|---|---|
| `for i=0; i<N; i++) s += i` (N≤255) | N | INX rp → INR r (2cc) | 2N cc |
| Same, exit icmp survives | N | Counter increment + exit check shrinks | ~6N cc |
| Nested inner (N=16) | 16 | 2cc/iter | 32 cc/outer |

The exit-check improvement in the second row: if the icmp is still on `%i.next`, after
narrowing it becomes `CPI r, N; JZ` (4+10=14cc) instead of the i16 two-byte check
`MVI A, N_lo; CMP E; JNZ; XRA A; CMP D; JNZ` (7+4+10+4+4+10=39cc common path ≈ 21cc amortised).
The actual improvement depends heavily on how the ISel lowers the narrowed icmp.
