# O90 — Pre-ISel i8 Narrowing (Undo InstCombine Widening)

**Source:** `tests/benchmarks_c/src/lfsr16.c` — `u8 lsb = (u8)(lfsr & 1)`
**Savings:** ~20cc per narrowable bitwise op in a hot loop
**Frequency:** Every `(u8)(i16_val OP const8)` where InstCombine erased the cast
**Complexity:** Medium — new IR pass registered in `addPreISel()`
**Risk:** Low — pure IR narrowing, guarded by constant-fits-in-i8 check
**Dependencies:** none
**Status:** [x] done

---

## Problem

The C programmer wrote an explicit `u8` cast:

```c
u8 lsb = (u8)(lfsr & 1);
if (lsb) ...
```

At `-O0` the IR preserves this faithfully:

```llvm
%18 = and i16 %lfsr, 1
%19 = trunc i16 %18 to i8     ; the user's (u8) cast
%23 = icmp ne i8 %19, 0       ; if (lsb)
```

At `-O2`, InstCombine's `computeKnownBits` analysis observes that `and i16 X, 1`
produces a value in {0, 1} — all bits above bit 0 are provably zero — so the
`trunc` is a mathematical no-op for the zero-test.  It folds:

```llvm
icmp ne (trunc i16 X to i8), 0   →   icmp ne i16 X, 0
```

The `trunc` is eliminated and the comparison is widened to i16:

```llvm
%10 = and i16 %lfsr, 1
%11 = icmp eq i16 %10, 0        ; full i16 compare — no trunc
```

This is **correct on every target** (the math is identical).  But on the 8080
it is catastrophic: the i16 `and` expands to `V6CLANG_AND16` (6 instructions, 36cc),
the i16 compare expands to `V6CLANG_CMP16_ZERO` (2 instructions, 8cc), and a spill
is needed to hold the AND result across the SRL.  The total per-iteration cost
for this single C expression is ~44cc + spill overhead.

The optimal 8080 code needs only 2 instructions:

```asm
MOV  A, L       ; 8cc — lo byte of lfsr
ANI  1          ; 8cc — AND immediate
; Z flag set; JZ/JNZ follows directly
```

### Why TTI cannot fix this

The InstCombine fold is a **pure algebraic identity**, not a cost decision.
No `TargetTransformInfo` hook is consulted.  The fold fires unconditionally
whenever `computeKnownBits` proves the trunc is a no-op, regardless of any
target cost model.  It cannot be suppressed via TTI.

### Why DAGCombine is insufficient

A DAGCombine rule can patch specific patterns (e.g. `setcc (and i16 X, K), 0`)
but requires a separate rule for every opcode × use-pattern combination:
`and`, `or`, `xor`; used in `icmp`, `select`, `trunc`, `store`, etc.
This is a remedy to the symptom, not the root cause.

---

## Solution: Pre-ISel Narrowing Pass

Add a new IR pass that runs at the end of `addPreISel()` (after all standard
IR optimizations, before SelectionDAG construction).  The pass re-narrows
widened bitwise operations whose constant operand fits in i8, restoring the
`trunc` nodes that InstCombine removed.

### Pattern matched

```
%r = and i16 %x, C          (or or, xor)
     where C ≤ 0xFF (constant fits in i8)
     and %r has at least one use that is i8-compatible:
         - icmp %r, 0  / icmp 0, %r
         - trunc %r to i8
         - select (icmp %r, ...), ...
```

### Transformation

```llvm
; Before (what InstCombine left):
%r   = and i16 %x, 1
%cmp = icmp eq i16 %r, 0

; After (pass re-inserts trunc):
%lo  = trunc i16 %x to i8
%r8  = and i8 %lo, 1          ; ANI 1 on 8080 → 8cc, 2B
%cmp = icmp eq i8 %r8, 0
```

The `trunc i16 to i8` is free on V6CLANG — it is the lo sub-register of a pair.
ISel sees a pure i8 `and` with a constant and emits `ANI K` directly (no
`V6CLANG_AND16`, no `LXI rp, K`, no spill).

### Scope

All three bitwise ops: `and`, `or`, `xor`.

All i8-compatible use patterns:
- `icmp eq/ne %r, 0`
- `trunc %r to i8` (explicit cast already present)
- `select i1 (icmp %r, 0), ...`
- Any use where all consumers already trunc to i8

Guarded by:
- Constant must be `≤ 0xFF`
- All uses of `%r` must be narrowable (no use needs the full i16 value)

### lfsr16 before / after

**Before (V6CLANG_AND16 + V6CLANG_CMP16_ZERO path, per loop iteration)**:

```asm
LXI   B, 1              ; 12cc, 3B — materialise constant 1
; --- V6CLANG_AND16 (6 insn) ---
MOV   A, L              ;  8cc, 1B
ANA   C                 ;  4cc, 1B
MOV   C, A              ;  8cc, 1B
MOV   A, H              ;  8cc, 1B  ← wasted (result = 0)
ANA   B                 ;  4cc, 1B  ← wasted (AND with 0)
; spill hi/lo to memory  ~20cc, 6B
; --- V6CLANG_CMP16_ZERO ---
MOV   A, H              ;  8cc, 1B  ← wasted (H = 0 always)
ORA   L                 ;  4cc, 1B
JNZ   ...               ; 12cc, 3B
; Subtotal: ~88cc (excluding spill) per iteration
```

**After (ANI path)**:

```asm
MOV   A, L              ;  8cc, 1B — lo byte of lfsr
ANI   1                 ;  8cc, 2B — AND immediate; sets Z flag
JNZ   ...               ; 12cc, 3B
; Subtotal: 28cc per iteration
```

Savings: **~60cc per loop iteration × 4096 = ~245,760cc** on the lfsr16 benchmark.

---

## Implementation Location

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangTargetMachine.cpp` | Register new pass in `addPreISel()` |
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangNarrowBitwisePass.cpp` (new) | Pass implementation |
| `llvm-project/llvm/lib/Target/V6Clang/CMakeLists.txt` | Add new source file |

The pass is a `FunctionPass` using the standard `runOnFunction` / `InstVisitor`
or explicit `IRBuilder` pattern.  It iterates over all `BinaryOperator`
instructions (`and`/`or`/`xor`) with i16 type and a constant RHS ≤ 0xFF,
checks that all users are narrowable, replaces the instruction with
`trunc → i8 op → (zext if needed)`.

---

## Expected Results

| Expression | Before | After |
|------------|--------|-------|
| `(u8)(x & 1)` used as branch | V6CLANG_AND16 + CMP16_ZERO + spill (~88cc) | `ANI 1` + `JNZ` (28cc) |
| `(u8)(x & 0xFF)` | V6CLANG_AND16 6 insn (36cc) | `MOV A,L` + `ANI 0xFF` (16cc) |
| `(u8)(x \| 0x80)` used as i8 | V6CLANG_OR16 6 insn (36cc) | `MOV A,L` + `ORI 0x80` (16cc) |
| `(u8)(x ^ 0x55)` used as i8 | V6CLANG_XOR16 6 insn (36cc) | `MOV A,L` + `XRI 0x55` (16cc) |
