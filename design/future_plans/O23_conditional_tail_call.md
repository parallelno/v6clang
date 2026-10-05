# O23. Conditional Tail Call Optimization

*From plan_tail_call_optimization.md Future Enhancements.*
*Extension of O14 (CALL+RET → JMP tail call peephole).*

## Problem

O14 handles the simple `CALL target; RET` → `JMP target` pattern.
However, conditional patterns around tail calls remain unoptimized:

### Pattern A: Conditional skip over tail call
```asm
; if (cond) return foo();
    JZ   .Lskip           ; 12cc, 3B
    CALL target            ; 18cc, 3B
.Lskip:
    RET                    ; 12cc, 1B
; Total: 42cc worst-case, 7B
```

Can become:
```asm
    JZ   .Lskip           ; 12cc, 3B
    JMP  target            ;  4cc, 3B
.Lskip:
    RET                    ; 12cc, 1B
; Total: 28cc worst-case, 7B (same size, 14cc faster)
```

This is just O14 applied within a conditional block — the `CALL` before
`RET` (or before a jump to `RET`) is still a tail call.

### Pattern B: Conditional return with fallthrough to tail call
```asm
; if (cond) return; else return foo();
    JNZ  .Learly_ret       ; 12cc, 3B
    CALL target             ; 18cc, 3B
    RET                     ; 12cc, 1B
.Learly_ret:
    RET                     ; 12cc, 1B
; Total: ~42cc, 8B
```

Can become:
```asm
    JNZ  .Learly_ret       ; 12cc, 3B
    JMP  target             ;  4cc, 3B
.Learly_ret:
    RET                     ; 12cc, 1B
; Total: 28cc, 7B (saves 14cc + 1B)
```

### Pattern C: ISel-level tail call recognition

The post-RA peephole can only catch cases where CALL+RET appear in the
final machine code. ISel-level tail call support (`LowerTailCall` in
`V6ClangISelLowering.cpp`) can catch tail calls earlier, enabling:
- Tail calls where argument registers need minimal shuffling
- Tail calls to functions with identical argument signatures (sibling calls)
- The DAG optimizer to skip unnecessary stack frame setup

## Implementation

### Phase 1: Extend O14 peephole (V6ClangBranchOpt.cpp or V6ClangPeephole.cpp)

The existing O14 pattern matches `CALL; RET`. Extend to match:
- `CALL; JMP .Lret` where `.Lret:` contains only `RET`
- `CALL` at end of block where the sole successor is a block ending in `RET`

This catches Patterns A and B above with minimal code change.

### Phase 2: ISel-level (future)

Add `LowerTailCall()` in `V6ClangISelLowering.cpp`:
- Check: callee's stack frame ≤ caller's stack frame
- Check: return value register matches (HL for i16, A for i8)
- Emit `V6ClangISD::TAIL_CALL` node instead of `V6ClangISD::CALL` + `V6ClangISD::RET`
- Expand to `JMP target` in ISel

## Benefit

- **Phase 1**: 14cc per conditional tail call, occasional 1B savings
- **Phase 2**: Enables tail call in more cases (argument shuffling), reduces
  stack depth for recursive functions
- **Frequency**: Medium — tail calls in if/else returns are common

## Complexity

Phase 1: Low. ~20 lines extending existing O14 peephole.
Phase 2: Medium. ~60-80 lines for ISel lowering + new pseudo.

## Risk

Low. Phase 1 is a straightforward extension of proven O14 pattern.
Phase 2 requires careful stack frame size comparison.

## Dependencies

O14 (tail call peephole) — already complete.

## Testing

1. New lit test: `conditional-tail-call.ll` — patterns A, B, C
2. Golden test regression check
