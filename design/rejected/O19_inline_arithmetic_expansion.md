# O19. Inline Arithmetic Expansion (Mul/Div)

*Inspired by llvm-z80 `Z80ExpandPseudo` inline multiply and divide.*
*Detailed analysis: [llvm_z80_analysis.md](llvm_z80_analysis.md) §S9.*

## Rejected
Inlining mul funcs doesn't justify the extra memory usage.

## Problem

V6CLANG uses library calls (`__mulqi3`, `__divqi3`, etc.) for all multiply and
divide operations. Each library call incurs:
- CALL/RET overhead: ~30cc
- Register save/restore in the callee: ~40-80cc (PUSH/POP pairs)
- Function body execution
- Total: ~150-300cc+ per invocation

For 8-bit multiply (the most common case), an inline shift-add loop takes
only ~100-120cc with no call overhead and no register save/restore beyond
what the caller already manages.

## How the Z80 Does It

Expand pseudo instructions into inline loops:

**8-bit multiply** (SM83 variant = 8080-compatible):
```asm
  LD   D, A           ; D = multiplier
  XOR  A              ; A = 0 (accumulator)
  LD   B, 8           ; counter
loop:
  ADD  A, A           ; A <<= 1
  RL   D              ; D <<= 1, MSB → carry
  JR   NC, skip
  ADD  A, E           ; A += multiplicand
skip:
  DJNZ loop
; Result in A (low 8 bits)
```

8080 equivalent:
```asm
  MOV  D, A           ; D = multiplier
  XRA  A              ; A = 0
  MVI  B, 8
loop:
  ADD  A              ; A <<= 1
  MOV  A, D           ; (need to rotate D via A on 8080)
  RAL                 ; carry into D's MSB position
  MOV  D, A
  JNC  skip
  ADD  E              ; A += multiplicand
skip:
  DCR  B
  JNZ  loop
```

**16-bit multiply** and **8/16-bit divide** follow similar shift-loop patterns
with the SM83 variants (no DJNZ, no EX DE,HL) mapping directly to 8080.

## Implementation

Expand arithmetic pseudo instructions in a post-RA pass:
1. **8-bit multiply**: ~12-15 instructions inline (vs CALL + library)
2. **8-bit divide/mod**: ~20 instructions inline (restoring division)
3. **Signed variants**: Absolute value + unsigned op + sign correction
4. Selection: Always inline for 8-bit; use size threshold for 16-bit

Could be controlled by `-O` level: inline at `-O2`/`-O3`, keep library calls
at `-Os`/`-Oz`.

## Benefit

- **8-bit multiply**: ~100-120cc inline vs ~200-300cc library = **2-3× faster**
- **8-bit divide**: ~150-200cc inline vs ~300-400cc library = **1.5-2× faster**
- **Code size tradeoff**: Each inline expansion is ~12-20 bytes vs 3-byte CALL,
  but eliminates the library function from the linked binary

## Complexity

Medium. ~200-400 lines for all variants (8/16 bit, unsigned/signed, mul/div/mod).
The algorithms are well-known and the Z80 SM83 variants provide tested templates.

## Risk

Low. The algorithms are standard binary multiply/divide. Correctness can be
exhaustively tested for 8-bit operands (256×256 = 65536 cases).
