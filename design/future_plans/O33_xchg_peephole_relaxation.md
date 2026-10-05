# O33. XCHG Peephole Relaxation (Drop isRegLiveBefore Guard)

*Identified from investigation of missed XCHG in test_null_guard (O30 feature test).*
*The existing V6ClangXchgOpt pass is overly conservative.*

## Problem

The existing V6ClangXchgOpt post-RA peephole detects `MOV D,H; MOV E,L` (and
reverse) patterns and replaces them with `XCHG`. However, it requires **two**
conditions to both hold:

1. `isRegLiveBefore()` — the "other" register pair must be live before the
   MOV pair (to avoid XCHG reading an undefined register)
2. `isRegDeadAfter()` — the "other" register pair must be dead after the
   MOV pair (to ensure the swap side-effect doesn't corrupt a needed value)

Condition 1 is **unnecessarily conservative**. If condition 2 already proves
the "other" pair is dead after the swap, it doesn't matter what value XCHG
puts into it — nobody reads it. Reading an undefined register into a dead
destination is harmless.

### Example: `test_null_guard` bb.2

MIR before V6ClangXchgOpt:
```
bb.2:
  liveins: $de            ; ← HL is NOT a livein
  $h = MOVrr killed $d   ; Pattern 2: MOV H,D; MOV L,E
  $l = MOVrr killed $e
  RET implicit $hl        ; ← only HL is read, DE is dead
```

V6ClangXchgOpt checks:
- `isRegLiveBefore(HL)` → **false** (HL not in liveins, not defined before) → **BAIL**
- `isRegDeadAfter(DE)` → true (RET only reads HL)

XCHG is safe here: it would put garbage into DE, but DE is dead. The pass
misses this optimization because of the unnecessary `isRegLiveBefore` check.

### What O32 doesn't cover

O32 (XCHG in copyPhysReg) handles RA-inserted copies where `KillSrc=true`.
O33 catches remaining cases:

- **MOV pairs from `expandPostRAPseudos()`**: Pseudo-instruction expansion
  (e.g., `V6CLANG_LOAD16_P`, `V6CLANG_STORE16_P`) emits MOV pairs to copy addresses
  to/from HL. These bypass `copyPhysReg` entirely.
- **Late-dead sources**: RA copies where `KillSrc=false` at allocation time,
  but later post-RA passes remove the last use of the source, making it dead.
- **MOV pairs from other passes**: Any pass that manually emits DE↔HL MOV
  pairs (peephole, load-store opt, etc.).

### Frequency

Low after O32 is implemented (O32 handles the majority). Occasional hits
from pseudo-expansion and late-dead scenarios. Estimated: 0-1 per function.

## Implementation

### Location

`V6ClangXchgOpt::tryXchg()` in `V6ClangXchgOpt.cpp` (lines 113-182).

### Change

For each of the 4 patterns, change the logic from:

```cpp
// Current: require BOTH conditions
if (!isRegLiveBefore(MBB, I, V6CLANG::DE, TRI))
  return false;
if (!isRegDeadAfter(MBB, Next, V6CLANG::HL, TRI))
  return false;
```

To:

```cpp
// Relaxed: only require the "other" pair to be dead after.
// If it's dead after, the swap side-effect is harmless regardless of
// whether the source was defined.
if (!isRegDeadAfter(MBB, Next, V6CLANG::HL, TRI))
  return false;
```

Apply symmetrically to all 4 patterns:
- Pattern 1 (MOV D,H; MOV E,L): drop `isRegLiveBefore(DE)`, keep `isRegDeadAfter(HL)`
- Pattern 2 (MOV H,D; MOV L,E): drop `isRegLiveBefore(HL)`, keep `isRegDeadAfter(DE)`
- Pattern 3 (MOV E,L; MOV D,H): drop `isRegLiveBefore(DE)`, keep `isRegDeadAfter(HL)`
- Pattern 4 (MOV L,E; MOV H,D): drop `isRegLiveBefore(HL)`, keep `isRegDeadAfter(DE)`

After the change, `isRegLiveBefore()` can also be removed entirely if no
other code references it.

### Testing

- Compile `test_null_guard` without O32 and verify XCHG appears
- With both O32 and O33 enabled, verify no regressions
- Run full lit + golden regression suite
- Verify V6ClangXchgOpt still does NOT apply XCHG when the "other" pair is
  live after (negative test case)

### Risks

- **Very Low**: The only change is removing an unnecessary guard. The
  essential safety check (`isRegDeadAfter`) remains.
- XCHG may read an undefined register — but the result goes into a dead
  register, so no observable effect.
- No interaction with FLAGS (XCHG does not affect flags).

### Dependencies

- None. Standalone relaxation of existing pass.
- O32 reduces the number of cases this pass sees, but O33 is independently
  correct and useful even without O32.
- Can be implemented before or after O32.
