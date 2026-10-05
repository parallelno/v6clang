# O38. XRA+CMP i8 Zero-Test Peephole

*Identified from analysis of temp/test_o28.asm `test_two_cond_tailcall`.*
*Fits into V6ClangPeephole — replaces MOV A,r + ORA A with XRA A + CMP r.*

## Problem

When testing an 8-bit register for zero before a conditional branch,
the compiler emits `MOV A, r; ORA A`. This is correct but suboptimal:
it costs 12cc and leaves A = r. On the i8080, `XRA A; CMP r` achieves
the same zero-test in 8cc and leaves A = 0, which often eliminates a
subsequent `MVI A, 0`.

### Primary Example

```c
extern unsigned char bar(unsigned char x);
unsigned char test_two_cond_tailcall(unsigned char x, unsigned char y) {
    if (x) return bar(x);
    if (y) return bar(x);
    return 0;
}
```

Current output:
```asm
.LBB1_1:
    MOV  A, E        ; 1B, 8cc — copy y into A
    ORA  A           ; 1B, 4cc — test y == 0 (A = y)
    JZ   .LBB1_4
; %bb.2:             ; fallthrough: y != 0
    MVI  A, 0        ; 2B, 8cc — need A = 0 for bar(x=0)
    JMP  bar
.LBB1_4:             ; taken: y == 0
    MVI  A, 0        ; 2B, 8cc — need A = 0 for return 0
    RET
```

### Desired output

```asm
.LBB1_1:
    XRA  A           ; 1B, 4cc — A = 0
    CMP  E           ; 1B, 4cc — test E == 0 (Z = (0 - E == 0))
    JZ   .LBB1_4
; %bb.2:             ; fallthrough: A already 0
    JMP  bar         ; MVI A,0 eliminated by O13
.LBB1_4:             ; taken: A already 0
    RET              ; MVI A,0 eliminated by O13
```

### Savings

**Direct:** 4cc per instance (8cc vs 12cc), same code size (2B).

**Cascading:** A = 0 from XRA enables O13 (LoadImmCombine) to eliminate
downstream `MVI A, 0` on both paths. In the primary example, this
eliminates 2 × `MVI A, 0` = **4B + 16cc** additional savings.

**Total for primary example: 4B, 20cc.**

## Pattern

### Match (post-RA, forward scan in V6ClangPeephole)

```
MOV  A, r       ; r ∈ {B, C, D, E, H, L} (not A)
ORA  A           ; flags = (A | A), i.e. test A for zero
Jcc  target      ; conditional branch on Z or NZ
```

### Transform

```
XRA  A           ; A = 0, flags set
CMP  r           ; flags = (0 - r), Z iff r == 0
Jcc  target      ; same condition
```

### Correctness

| Flag | MOV A,r + ORA A | XRA A + CMP r | Match? |
|------|-----------------|---------------|--------|
| Z | r == 0 | r == 0 | Yes |
| S | bit7(r) | bit7(-r) | Different (but irrelevant — only Z/NZ used by Jcc) |
| CY | 0 | (r != 0) | Different (but irrelevant — only Z/NZ used by Jcc) |
| P | parity(r) | parity(-r) | Different (but irrelevant) |
| AC | 0 | depends | Different (but irrelevant) |

The transform is **valid only when the branch tests Z or NZ**.
If any code between ORA A and the branch uses CY, S, P, or AC, the
transform is invalid. In practice, the ORA → Jcc sequence is always
adjacent with no intervening flag consumers.

### Safety constraint

The transform replaces A = r with A = 0. This is valid when:

1. **A is dead** on the fallthrough (non-taken) path before its next
   def, OR
2. **A = 0 is needed** on the fallthrough path — i.e., the next use
   of A (before any redef) reads A expecting 0 (e.g., `MVI A, 0`
   which would become redundant).

On the **taken path** (branch target when testing Z): if taken means
r == 0, then the old code had A = r = 0 anyway, so A = 0 is unchanged.
If taken means r != 0 (NZ branch), then old had A = r ≠ 0 and new has
A = 0 — must verify A dead/zero-needed on the target block too.

**Conservative first implementation:** require A dead on the fallthrough
path. Use `computeRegisterLiveness()` which is already available in
V6ClangPeephole. O13 will cascade-eliminate `MVI A, 0` automatically.

**Enhanced (future):** also check if the first A-consuming instruction
in the fallthrough block is `MVI A, 0` — if so, consider A-zero as
acceptable and mark the MVI for elimination.

## Implementation

### Approach: Extend V6ClangPeephole

Add a new pattern match in the existing peephole forward scan loop
(`V6ClangPeephole.cpp`). ~40-50 lines.

```
For each MBB:
  For each MI in MBB:
    if MI is MOV A, r (r != A):
      NextMI = next non-debug instruction
      if NextMI is ORA A:
        BrMI = next non-debug after NextMI
        if BrMI is Jcc on Z or NZ:
          if A is dead on fallthrough path (computeRegisterLiveness):
            Replace MOV A,r with XRA A
            Replace ORA A with CMP r
            Changed = true
```

### Pass ordering

V6ClangPeephole already runs in the post-RA pipeline before LoadImmCombine.
The XRA A seeds A = 0 in the value tracker, and O13 eliminates
downstream `MVI A, 0`. No pass ordering change needed.

Pipeline: AccPlanning → **LoadImmCombine** → **Peephole** → …

Wait — LoadImmCombine runs *before* Peephole currently. For O13 to
see the XRA A seeding, either:
- (a) LoadImmCombine runs after Peephole, or
- (b) The peephole itself eliminates the MVI A, 0.

Check actual pipeline order and adjust if needed during implementation.

## Complexity & Risk

- **Complexity:** Low (~40-50 lines in V6ClangPeephole)
- **Risk:** Very Low — conservative A-dead check prevents miscompiles;
  pattern is narrow (MOV A,r → ORA A → Jcc Z/NZ)
- **Dependencies:** None required. Benefits from O13 (cascade elimination).
  Benefits from O36 (branch-implied seeding on taken path).
