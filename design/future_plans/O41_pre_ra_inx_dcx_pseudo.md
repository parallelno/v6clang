# O41. Pre-RA INX/DCX Pseudo for Small-Constant Pointer Arithmetic

*Identified during O20 implementation. After removing `Defs = [HL]` from*
*store/load pseudos, the register allocator freely uses HL for pointers.*
*But `ptr + 1` still lowers as `LXI rp, 1` + `DAD rp`, occupying a register*
*pair for the constant before RA even runs. The post-RA INX peephole removes*
*the constant too late — RA already reserved a register pair.*

## Problem

Pointer increment `gep ptr, 1` lowers through the standard i16 add path:

1. **ISel**: `add i16 ptr, 1` → `V6ClangISD::DAD` (since result is used as
   store/load pointer) → `V6CLANG_DAD HL, HL, <vreg>`
2. **RA**: `<vreg>` holds constant 1 → allocates a physical register pair
   (e.g. BC) → `LXI BC, 1` materialized in the preheader
3. **Post-RA peephole**: Detects `LXI BC, 1` + `DAD BC` → converts to
   `INX HL`, but the dead `LXI BC, 1` from a predecessor block can't
   always be erased, and **BC was already reserved by RA**.

The same applies to `V6CLANG_ADD16` and `V6CLANG_SUB16` for ±1..±3 constants.

### Example: fill_array after O20

```asm
fill_array:
    MOV     L, A                ; save start_val
    LXI     DE, array1          ; pointer
    LXI     BC, 1               ; ← dead constant, BC wasted
.loop:
    MOV     A, L
    STAX    DE
    INX     DE                  ; ← peephole converted DAD BC → INX DE
    INR     L
    ...
```

BC is occupied by a constant that the peephole eliminated. If BC were free,
RA could use it for another live value, potentially avoiding a spill.

## Solution

### Approach: ISel-level INX/DCX pseudos (Option A)

Add new single-operand pseudos that represent `rp ± N` without a constant
register:

```tablegen
def V6CLANG_INX16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$count),
    "# INX16 $dst, $src, $count", []> {
  let Constraints = "$dst = $src";
}

def V6CLANG_DCX16 : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i8imm:$count),
    "# DCX16 $dst, $src, $count", []> {
  let Constraints = "$dst = $src";
}
```

The `$count` is an immediate (1..3), not a register. RA sees only one
register operand — no constant pair is allocated.

### DAG Combine changes

In `PerformDAGCombine` for `ISD::ADD`, before the existing DAD conversion:

1. Check if one operand is `ConstantSDNode` with value ±1..±3
2. If so, emit `V6ClangISD::INX16` or `V6ClangISD::DCX16` instead of `V6ClangISD::DAD`
3. This applies both when the result is used as a pointer (currently goes
   to DAD) and for general i16 add (currently goes to ADD16)

For the DAD path (pointer arithmetic):
```cpp
if (auto *C = dyn_cast<ConstantSDNode>(N->getOperand(1))) {
  int64_t Val = C->getSExtValue();
  if (Val >= 1 && Val <= 3)
    return DAG.getNode(V6ClangISD::INX16, DL, MVT::i16,
                       N->getOperand(0), DAG.getTargetConstant(Val, DL, MVT::i8));
  if (Val >= -3 && Val <= -1)
    return DAG.getNode(V6ClangISD::DCX16, DL, MVT::i16,
                       N->getOperand(0), DAG.getTargetConstant(-Val, DL, MVT::i8));
}
// Check operand(0) too (commutative)
```

### Post-RA expansion

Trivial — emit N copies of `INX rp` or `DCX rp`:

```cpp
case V6CLANG::V6CLANG_INX16: {
  Register Rp = MI.getOperand(0).getReg();
  unsigned Count = MI.getOperand(2).getImm();
  for (unsigned I = 0; I < Count; ++I)
    BuildMI(MBB, MI, DL, get(V6CLANG::INX), Rp).addReg(Rp);
  MI.eraseFromParent();
  return true;
}
```

### Interaction with existing INX peephole

The existing `findDefiningLXI` + INX conversion in V6CLANG_DAD / V6CLANG_ADD16 /
V6CLANG_SUB16 expansion remains as a **fallback** for larger constants (±4+)
where the cost model allows INX chains. For ±1..±3, the new pseudo
intercepts earlier in the pipeline and avoids register allocation entirely.

## Before → After

```asm
; Before (O20, post-RA peephole converts DAD→INX but BC wasted):
    LXI     DE, array1          ; pointer
    LXI     BC, 1               ; dead constant — BC occupied
.loop:
    STAX    DE
    INX     DE                  ; was DAD BC → INX DE
    ...

; After (O41, no constant register needed):
    LXI     DE, array1          ; pointer
.loop:                          ; BC is FREE for RA
    STAX    DE
    INX     DE                  ; directly from V6CLANG_INX16 pseudo
    ...
```

## Benefit

- **Savings per instance**: Frees one register pair (BC or DE) that was
  holding a ±1..±3 constant. Indirect benefit: fewer spills.
- **Direct savings**: Eliminates dead `LXI rp, N` (12cc, 3B) from preheaders
- **Frequency**: Very high — every pointer loop with step ±1 (the common case)
- **Threshold**: ±3 (3× INX = 24cc vs LXI+DAD = 24cc — equal cost but
  saves a register pair, so INX is strictly better)

## Complexity

Low. ~40 lines total:
- 2 TableGen pseudo definitions (~8 lines)
- 2 ISD node definitions (~4 lines)
- DAG combine check for small constants (~15 lines)
- Post-RA expansion cases (~10 lines)
- ISel patterns or custom lowering (~5 lines)

## Risk

Very low.
- INX/DCX don't set flags — must verify FLAGS isn't expected live after
  the add. The DAD path already requires `isFlagsDefDead()` for the INX
  conversion; same check applies here.
- Correctness: INX ×N is semantically identical to ADD rp, N — no edge cases.
- The existing post-RA INX peephole handles N>3; this handles N≤3 earlier.

## Dependencies

- **O20** (done): Honest store/load defs — motivates this optimization by
  making HL available for pointers, which shifts pointer increments to
  non-HL pairs where the wasted constant register is most visible.
- **O40** (done): ADD16 DAD expansion — the existing post-RA fallback that
  this optimization partially supersedes for small constants.

## Test cases

1. **fill_array** (tests/features/23): Single-pointer store loop — BC should
   no longer be allocated for constant 1
2. **copy_loop** (loop-pointer-induction.ll): Dual-pointer loop — constant
   pair freed
3. **clear_buf** (loop-pointer-inx.ll): Simple memset — should use INX
   without any dead LXI
