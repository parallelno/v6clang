# O47 — Sub-Register Liveness Tracking

## Problem

The register allocator tracks liveness at the full 16-bit register pair level
(HL, BC, DE). When only one half is needed (e.g. L for `ADD L`), the RA
considers the entire pair live and emits unnecessary save/restore sequences
for the other half.

### Example: `multi_live` function

```asm
; After CALL use8, need to reload spilled 'a' from static stack:
LDA   __v6clang_ss.multi_live+1   ; A = b (reloaded)
MOV   D, H                    ; save H — RA thinks HL is live
LXI   HL, __v6clang_ss.multi_live ; load address (clobbers both H and L)
MOV   L, M                    ; L = *HL = a (the value we need)
MOV   H, D                    ; restore H — DEAD, never read again
ADD   L                       ; only L is used
ADI   3
RET                           ; return in A, H is irrelevant
```

`MOV D, H` and `MOV H, D` are both unnecessary — 8cc + 2B wasted. The RA
can't see that H is dead because it tracks liveness of the HL pair, not H
individually.

### Same pattern in `interleaved_add` loop body

```asm
PUSH  DE
MOV   D, H                    ; save H (RA thinks HL pair is live)
LXI   HL, __v6clang_ss...+6       ; clobbers HL
MOV   L, M                    ; only L needed
MOV   H, D                    ; restore H — used later by INX HL, SHLD
```

In this case `MOV H, D` is **needed** because the loop continues to use HL
as a pair (INX HL, SHLD). Sub-register liveness tracking would correctly
distinguish the two cases: dead H in `multi_live`, live H in the loop.

## Source of the pattern

```c
unsigned char multi_live(unsigned char a, unsigned char b, unsigned char c) {
    unsigned char x = a + 1;
    unsigned char y = b + 2;
    use8(c);          // call clobbers all regs
    return x + y;     // = a + b + 3, only 8-bit result
}
```

The RA spills `a` before the call. After the call it needs to reload `a` from
a static stack slot. Loading the slot address requires LXI HL which clobbers
the pair, so RA saves H around it — even though H is dead post-reload.

## Solution

### Approach: `enableSubRegLiveness()` (RA-level, global)

Override in `V6ClangSubtarget`:

```cpp
bool enableSubRegLiveness() const override { return true; }
```

This tells LLVM's register allocator to track liveness at the sub-register
level (sub_hi = H, sub_lo = L for HL pair, etc.). The RA would see that H
is dead after the reload and skip the save/restore pair entirely.

**Prerequisites:**
- Every instruction in `V6ClangInstrInfo.td` that partially writes a register
  pair must correctly declare sub-register defs and uses via implicit-def /
  implicit-use operands.
- Instructions like `LXI`, `LHLD`, `MVI` that write sub-registers must have
  correct lane masks.
- `SHLD`, `DAD`, `PUSH`, `POP`, and other pair-level instructions must
  declare both sub-register uses.

**Risks:**
- Global change affecting all register allocation decisions.
- May expose latent bugs where instruction definitions have incorrect or
  missing sub-register def/use declarations.
- Slightly increased compile time (more intervals to track).
- Needs thorough testing across the full test suite — regressions could be
  subtle (wrong code from stale sub-register liveness).

**Validation:**
- Run all 102+ lit tests + 15 golden tests.
- Compare generated code for all tests/features/ assemblies before/after.
- Manually audit functions with known save/restore patterns.


## Savings

- **Per instance:** 8cc, 2B (one save + one restore MOV eliminated)
- **Frequency:** Medium — occurs in functions with 8-bit results that
  reload from static stack slots via LXI, especially after calls.
- **Where visible:** `multi_live` style functions (8-bit arithmetic across
  calls), and any post-call reload path where only one sub-register is used.

## Complexity

- **Approach:** High — requires full audit of every instruction definition
  for correct sub-register lane masks, then extensive testing.

## Dependencies

- O10 (static stack) — patterns are most visible with static stack slots.
- O20 (honest store/load defs) — correct HL defs make liveness analysis
  more precise.

## Resolution

Rejected because O47 was superseded by O61.