# O31. Dead PHI-Constant Elimination for Zero-Tested Branches

*Identified from analysis of O27 (i16 zero-test) codegen.*
*When a branch tests `reg == 0` and the PHI on the taken path uses constant 0
for the same register, the constant materialization is provably dead.*

## Problem

When LLVM lowers `if (x) { ... } else { /* use 0 */ }`, SimplifyCFG merges
the else block into the merge block, creating a PHI:

```llvm
entry:
  %cmp = icmp eq i16 %x, 0
  br i1 %cmp, label %merge, label %then

then:
  %y = call i16 @bar(i16 %x)
  br label %merge

merge:
  %result = phi i16 [ %y, %then ], [ 0, %entry ]  ; ← constant 0 from entry
  ret i16 %result
```

ISel materializes the constant in the entry block (the PHI predecessor):
```
bb.0 (entry):
  %arg = COPY $hl              ; x arrives in HL
  %zero = LXI 0                ; ← constant for PHI
  V6CLANG_BR_CC16_IMM %arg, 0, 1, %bb.2  ; test x == 0
  JMP %bb.1                    ; fallthrough to call

bb.2 (merge):
  %result = PHI %zero, %bb.0, %callresult, %bb.1
  RET
```

This forces RA to keep both `%arg` (HL) and `%zero` alive simultaneously,
causing a register shuffle: `%arg` gets evicted to DE, `%zero` takes HL.

### The insight

When `V6CLANG_BR_CC16_IMM %arg, 0, COND_Z` branches to bb.2, we **know** that
`%arg == 0`. The PHI takes the value `0` from this edge. But `%arg` is already
0! The `LXI 0` is redundant — the PHI could use `%arg` directly.

### Current output (11 instructions, 17 bytes)
```asm
test_ne_zero:
    MOV  D, H          ; 1B  save x to DE (HL clobbered by LXI)
    MOV  E, L          ; 1B
    LXI  HL, 0         ; 3B  ← REDUNDANT constant
    MOV  A, D          ; 1B  zero-test on DE (should be HL)
    ORA  E             ; 1B
    JZ   .LBB0_2       ; 3B
    MOV  H, D          ; 1B  restore x from DE
    MOV  L, E          ; 1B
    JMP  bar           ; 3B
.LBB0_2:
    RET                ; 1B
```

### Ideal output (4-5 instructions, 6-8 bytes)
```asm
test_ne_zero:
    MOV  A, H          ; 1B  zero-test directly on HL
    ORA  L             ; 1B
    RZ                 ; 1B  (with O30) or JZ .ret (3B without)
    JMP  bar           ; 3B  HL still has x
```

Savings: **7-9 instructions, 9-11 bytes, ~40-60 cycles** per instance.

## Root Cause Analysis

The problem chain:
1. **SimplifyCFG** merges `else { return 0; }` into the merge block → PHI
2. **ISel** materializes `LXI 0` in entry block for PHI incoming value
3. **Machine-sink** can't sink it (PHI source must dominate end of predecessor)
4. **PHI elimination** places copy in entry block (critical edge, not split)
5. **RA** sees two live values in entry block → evicts arg to DE
6. **O27** expands zero-test on DE instead of HL → register shuffle preserved

No single existing pass has the combined knowledge:
"The PHI's constant 0 equals the branch comparison's RHS, and the source
register (%arg) is proven to be 0 on that path → constant is dead."

## Implementation Options

### Option A: Pre-RA MachineIR pass (recommended)

A pre-RA pass running after ISel that recognizes the pattern:

```
%const = LXI <imm>
V6CLANG_BR_CC16_IMM %reg, <imm>, <cc>, %target
...
%target:
  PHI %const, %pred, ...
```

When `<imm>` matches the PHI's incoming value for the same edge AND the
branch condition proves `%reg == <imm>` on the taken path, replace
the PHI operand with `%reg`:

```
; %const = LXI 0        ← becomes dead, DCE removes it
V6CLANG_BR_CC16_IMM %reg, 0, COND_Z, %target
...
%target:
  PHI %reg, %pred, ...  ← uses %reg (proven == 0 on this edge)
```

This eliminates the constant, removes HL pressure, and RA naturally
keeps `%arg` in HL.

**Where to run**: After ISel, before machine-sink. Can be a small
`MachineFunctionPass` in `V6ClangDeadPhiConst.cpp`, or added as a
method in `V6ClangISelDAGToDAG.cpp` post-selection cleanup.

**Complexity**: Medium. Need to:
- Walk PHI nodes looking for constant incoming values on branch edges
- Match the constant with the branch comparison RHS
- Verify the branch condition proves the register equals the constant
- Handle EQ (zero on taken path) vs NE (zero on fallthrough path)

### Option B: ISel-level (DAG combine)

Teach the DAG combiner to not materialize the constant when it can prove
the source register already holds that value on the relevant path. This is
harder because DAG-level doesn't have MBB/PHI information.

### Option C: Critical edge splitting

Insert a new basic block on the entry→merge edge and place `LXI 0` there.
This moves the constant off the critical path but still materializes it —
less effective than Option A but simpler and might help other patterns too.

## Applicability

This optimization fires when ALL of:
1. A `V6CLANG_BR_CC16_IMM` (or future `V6CLANG_BR_CC8_IMM`) compares against an immediate
2. The branch targets (directly or via the fallthrough) a PHI node
3. The PHI's incoming value on that edge is the same constant as the comparison RHS
4. The comparison condition proves the register equals that constant on that edge
   (EQ on taken path, or NE on fallthrough path)

The zero case (`== 0`) is by far the most common due to null checks, boolean
tests, and loop termination, but the optimization is general for any constant.

### Patterns covered

| C pattern | IR | Fires? |
|-----------|------|--------|
| `if (x) bar(x); return 0;` | `phi [0, entry]` + `icmp eq x, 0` | Yes |
| `if (!x) return 0; return bar(x);` | `phi [0, entry]` + `icmp ne x, 0` | Yes (fallthrough) |
| `if (p == NULL) return NULL;` | `phi [null, entry]` + `icmp eq p, 0` | Yes |
| `while (n) { ...n--; } return 0;` | `phi [0, entry]` + `icmp eq n, 0` | Yes |
| `if (x == 42) return 42;` | `phi [42, entry]` + `icmp eq x, 42` | Yes (general case) |

## Complexity: Medium

~60-80 lines new pass. Requires pattern matching PHI incoming values against
branch comparison operands, and understanding which condition proves which
value on which edge.

## Risk: Low

- Pure dead-code elimination — replacing a constant with a register that
  provably holds the same value
- Worst case: the pattern doesn't match and nothing changes (no regression)
- Only affects V6CLANG_BR_CC16_IMM patterns (well-understood pseudo)

## Dependencies

- **O27** (done): Provides the MOV+ORA zero-test that this builds on
- **O30** (conditional return): Combines with this for maximum savings
  (4 instructions total instead of 11)

## Testing

### Lit tests
- `phi [0, entry]` + `br eq 0` → constant eliminated
- `phi [0, entry]` + `br ne 0` → constant eliminated (fallthrough case)
- `phi [42, entry]` + `br eq 42` → general constant case
- `phi [0, entry]` + `br eq 1` → NO elimination (different constant)
- `phi [0, entry]` from different edge → NO elimination

### Golden tests
- Recompile `tests/features/08/` — `LXI HL, 0` and `MOV D,H; MOV E,L`
  should disappear from `test_ne_zero`
