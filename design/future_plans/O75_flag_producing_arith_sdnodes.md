# O75. Flag-Producing Arithmetic SDNodes (Fold `setcc(arith, 0)` at ISel)

*V6CLANG-native optimization. Inspired by X86's `X86ISD::ADD/SUB/DEC` family
returning `(value, EFLAGS)` and ARM's `ARMISD::ADDC/SUBC` flag-producing
nodes.*

## Problem

V6CLANG's ISel models flags via a single SDNode — `V6ClangISD::CMP` (and its sibling
`V6ClangISD::CMP_ZERO` for i16 zero tests). Only this node carries
`SDNPOutGlue`; every flag-setting arithmetic op (DCR, INR, ADD, ADC, SUB,
SBB, ANA, ORA, XRA, RLC, RRC, RAL, RAR, …) is matched from a plain
arithmetic SDAG pattern that produces only an `i8`/`i16` value and discards
its FLAGS at the SDAG level.

`LowerBR_CC` ([V6ClangISelLowering.cpp:471](../../llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp#L471))
unconditionally creates a fresh `V6ClangISD::CMP` node from the icmp's LHS/RHS,
even when LHS is itself an arithmetic result that already set the right
flags:

```cpp
// For i8: emit CMP (produces glue with FLAGS) then BRCOND.
SDValue Glue = DAG.getNode(V6ClangISD::CMP, DL, MVT::Glue, LHS, RHS);
SDValue CCVal = DAG.getConstant(V6ClangC, DL, MVT::i8);
return DAG.getNode(V6ClangISD::BRCOND, DL, MVT::Other, Chain, Dest, CCVal, Glue);
```

For C source like `while (--n) { ... }` the result is:

```mir
%8:gr8  = DCRr %1:gr8(tied-def 0), implicit-def dead $flags
%19:acc = COPY %8:gr8                 ; <-- forced because CPI's operand class is Acc
CPI %19:acc, 0, implicit-def $flags
V6CLANG_BRCOND %bb.2, 1, implicit $flags
```

After register allocation this becomes:

```asm
MOV  A, C        ;  8cc   (forced by Acc-class operand of CPI)
DCR  A           ;  4cc
MOV  C, A        ;  8cc   (write back; A is still pinned)
CPI  0           ;  7cc   (redundant — DCR A already set Z)
JNZ  loop        ; 12cc
; Total: 39cc, 7B
```

The hand-written / `golden/16_bsort.asm` reference is just:

```asm
DCR  C           ;  4cc
JNZ  loop        ; 12cc
; Total: 16cc, 2B
```

### Why the existing post-RA mitigations are not enough

* **O17 `RedundantFlagElim`** removes the `CPI 0` / `ORA A` after a
  flag-setting ALU op, but only after the damage to register allocation
  is done. The accumulator pinning (`MOV A,r ; … ; MOV r,A`) is already
  baked in.
* **O18 `foldCounterBranch`** can collapse the full 5-instruction
  template back to `DCR r; JNZ`, but it requires **strict adjacency** of
  the five instructions. Any spill-related code O61 inserts between
  `MOV r,A` and `JNZ` (e.g. `STA .LLo61_3+1`, patched `MVI A,0`) breaks
  the pattern and the peephole bails out.

In other words, the late peephole has to undo a decision (route value
through A) that should never have been made — and frequently can't, in
the very loops where it matters most.

## Goal

The **primary** goal is to eliminate the upstream **Acc-class pinning** of
loop counters and mask-test inputs. The redundant `CPI 0` is a *symptom*
— removing it is what O17 / O18 already do post-RA, but they cannot undo
the `MOV A,r ; … ; MOV r,A` round-trip that `CPI`'s `Acc` operand class
forces at register allocation time. That round-trip is the real cost,
both directly (16cc + 4B per iteration) and indirectly (it pins A across
the loop body and biases every spill decision around it).


> **Peepholes are not the solution.** O17 and O18 remain as defensive
> backstops for shapes the combine doesn't cover (e.g. flag producers
> separated from their consumer by code the combine cannot see across),
> but the value of O75 is measured by what register allocation does, not
> by what the post-RA peeps clean up.

## Design

### Step ...

## Before → After

### Loop counter (`while (--n)`)

```asm
; Before                          ; After
MOV  A, C        ;  8cc           DCR  C           ;  4cc
DCR  A           ;  4cc           JNZ  loop        ; 12cc
MOV  C, A        ;  8cc           ; Total: 16cc, 2B
CPI  0           ;  7cc
JNZ  loop        ; 12cc
; Total: 39cc, 7B
```

### Mask zero test (`if ((x & MASK) == 0)`)

```asm
; Before                          ; After
MOV  A, B        ;  8cc           MOV  A, B        ;  8cc
ANI  0x0F        ;  7cc           ANI  0x0F        ;  7cc
CPI  0           ;  7cc  ←gone    JZ   .lab        ; 12cc
JZ   .lab        ; 12cc           ; Total: 27cc, 5B
; Total: 34cc, 6B
```

(The first `MOV A,B` survives because `ANI` is an A-only instruction;
that allocation cost is real, not a redundancy. The CPI is the redundancy
this plan removes.)

## Complexity

## Risk

## Tests

## Dependencies

* **None hard.** O17 and O18 remain in place as backstops.
* **Composes with** O27 (i16 zero test) — see Future Improvements.
* **Composes with** O61 / O64 by reducing pressure they have to handle.

## Future Improvements
