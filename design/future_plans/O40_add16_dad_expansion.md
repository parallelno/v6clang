# O40. ADD16 DAD-Based Expansion (Post-RA Pseudo Lowering)

*Identified from analysis of `nested_calls` in the O10 feature test.*
*The register allocator assigns non-HL destinations for ADD16, missing the*
*DAD instruction which only operates on HL.*

## Problem

`V6CLANG_ADD16` is a pseudo-instruction for 16-bit addition. It accepts any
register pair (BC, DE, HL) for all three operands (dst, lhs, rhs). The
existing expansion in `expandPostRAPseudo()` has two paths:

1. **DAD path** (12cc, 1B): Used when `DstReg == HL` AND one operand is HL.
2. **Byte chain** (40cc, 6B): Used for everything else — 6 MOV/ADD/ADC
   instructions through the accumulator.

The problem: when the register allocator assigns a non-HL destination but
one operand IS HL, the byte chain is used even though a DAD-based sequence
would be cheaper. Similarly, when dst==HL but neither operand is HL, a
MOV pair + DAD is cheaper than the byte chain.

### Post-RA MIR for `nested_calls`

```
$bc = V6CLANG_ADD16 $hl, $bc    ; Case 1: HL is an operand, dst=BC
$hl = V6CLANG_ADD16 $bc, $de    ; Case 2: dst=HL, neither operand is HL
```

**Case 1** currently expands to:
```asm
MOV  A, L       ; 8cc  1B
ADD  C           ; 4cc  1B
MOV  C, A        ; 8cc  1B
MOV  A, H        ; 8cc  1B
ADC  B           ; 4cc  1B
MOV  B, A        ; 8cc  1B
; total: 40cc, 6B
```

Optimal expansion using DAD:
```asm
DAD  BC          ; 12cc 1B  — HL = HL + BC
MOV  B, H        ; 8cc  1B  — copy result to BC
MOV  C, L        ; 8cc  1B
; total: 28cc, 3B  (saves 12cc, 3B)
```

**Case 2** currently expands to:
```asm
MOV  A, C        ; 8cc  1B
ADD  E           ; 4cc  1B
MOV  L, A        ; 8cc  1B
MOV  A, B        ; 8cc  1B
ADC  D           ; 4cc  1B
MOV  H, A        ; 8cc  1B
; total: 40cc, 6B
```

Optimal expansion using DAD:
```asm
MOV  H, B        ; 8cc  1B  — copy one operand to HL
MOV  L, C        ; 8cc  1B
DAD  DE          ; 12cc 1B  — HL = HL + DE
; total: 28cc, 3B  (saves 12cc, 3B)
```

Or, if BC is dead after:
```asm
DAD  DE          ;  — but wait, HL has the wrong value here
```
No — since neither operand is HL, we must copy one in first.

However, the special sub-case where `DstReg == HL` and one operand equals
the other operand's pair (commutative) can pick the cheaper copy direction.
When `DstReg == HL`: copy one operand into HL, DAD the other.

## Solution

Enhance the `V6CLANG_ADD16` expansion in `V6ClangInstrInfo::expandPostRAPseudo()`
with two new DAD-based paths, inserted between the existing DAD check and
the general byte-chain fallback.

### New Path 1: `rp = ADD16 HL, rp` or `rp = ADD16 rp, HL`

One operand is HL, destination is a different pair. HL is available as the
implicit DAD accumulator.

**Precondition**: HL must be dead after the ADD16 (since DAD clobbers HL
with the sum, and we need the result in a different pair). Check via the
existing `isRegDeadAfter()` utility.

**Expansion:**
```
; rp = HL + rp  (HL dead after)
DAD  rp              ; 12cc 1B — HL = HL + rp (clobbers HL)
MOV  rp_hi, H        ;  8cc 1B — copy result to dst pair
MOV  rp_lo, L        ;  8cc 1B
; total: 28cc, 3B
```

Both commutative orderings are handled — `$rp = ADD16 $hl, $rp` and
`$rp = ADD16 $rp, $hl`.

**If HL is live after**: Cannot use this path — fall through to byte chain.
The byte chain is still correct and only 12cc worse.

### New Path 2: `HL = ADD16 rp1, rp2` (neither operand is HL)

Destination is HL but neither source operand is HL.

**Expansion:**
```
; HL = rp1 + rp2
MOV  H, rp1_hi       ;  8cc 1B — copy rp1 into HL
MOV  L, rp1_lo       ;  8cc 1B
DAD  rp2              ; 12cc 1B — HL = HL + rp2
; total: 28cc, 3B
```

No liveness precondition needed — HL is the destination, so HL's old value
is dead by definition (the ADD16 defines it).

Choice of which operand to copy: copy rp1 (lhs) into HL and DAD rp2 (rhs).
The choice is arbitrary since add is commutative; prefer whichever is cheaper
(both are 2 MOVs so it doesn't matter, but if one operand == dst in a
future three-operand form, prefer the other).

### Case Matrix

All possible `$dst = V6CLANG_ADD16 $lhs, $rhs` register pair assignments:

| dst | lhs | rhs | Path | Expansion | Cost |
|-----|-----|-----|------|-----------|------|
| HL | HL | rp | existing | `DAD rp` | 12cc, 1B |
| HL | rp | HL | existing | `DAD rp` | 12cc, 1B |
| HL | rp1 | rp2 | **new path 2** | `MOV H,rp1_hi; MOV L,rp1_lo; DAD rp2` | 28cc, 3B |
| rp | HL | rp | **new path 1** | `DAD rp; MOV rp_hi,H; MOV rp_lo,L` (HL dead) | 28cc, 3B |
| rp | rp | HL | **new path 1** | `DAD rp; MOV rp_hi,H; MOV rp_lo,L` (HL dead) | 28cc, 3B |
| rp | HL | HL | **new path 1** | `DAD HL; MOV rp_hi,H; MOV rp_lo,L` (HL dead) | 28cc, 3B |
| rp1 | rp2 | rp3 | byte chain | 6-instr through A | 40cc, 6B |

Notes:
- `rp = HL + rp` when HL is **live** after → falls to byte chain (40cc, 6B)
- `rp1 = rp2 + rp3` (no HL involved at all) → byte chain (only option)
- New path 1 requires `isRegDeadAfter(MBB, MI, V6CLANG::HL, TRI)` check
- New path 2 requires no liveness check (HL is the destination)

### Cost comparison

| Case | Old | New | Saving |
|------|-----|-----|--------|
| `rp = HL + rp` (HL dead) | 40cc, 6B | 28cc, 3B | **12cc, 3B** |
| `HL = rp1 + rp2` | 40cc, 6B | 28cc, 3B | **12cc, 3B** |
| `rp = HL + rp` (HL live) | 40cc, 6B | 40cc, 6B | 0 (unchanged) |

## Implementation

### Location

`V6ClangInstrInfo::expandPostRAPseudo()`, case `V6CLANG::V6CLANG_ADD16`, between the
existing `DstReg == HL` DAD check (line ~521) and the general byte-chain
fallback (line ~536).

### Pseudocode

```cpp
// --- New path 1: rp = ADD16 (HL, rp) or (rp, HL), HL dead after ---
// One operand is HL, dst != HL. Use DAD + copy out.
if (DstReg != V6CLANG::HL) {
  Register OtherReg = Register();
  if (LhsReg == V6CLANG::HL || RhsReg == V6CLANG::HL) {
    OtherReg = (LhsReg == V6CLANG::HL) ? RhsReg : LhsReg;
  }
  if (OtherReg && isRegDeadAfter(MBB, MI.getIterator(), V6CLANG::HL, &RI)) {
    // DAD OtherReg (or DAD DstReg if OtherReg == DstReg)
    // Note: DAD adds HL + rp → HL. We need HL + OtherReg.
    // If OtherReg == DstReg, we can DAD DstReg directly.
    BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(OtherReg);
    MCRegister DstHi = RI.getSubReg(DstReg, V6CLANG::sub_hi);
    MCRegister DstLo = RI.getSubReg(DstReg, V6CLANG::sub_lo);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstHi).addReg(V6CLANG::H);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), DstLo).addReg(V6CLANG::L);
    MI.eraseFromParent();
    return true;
  }
}

// --- New path 2: HL = ADD16 (rp1, rp2), neither is HL ---
// Copy one operand to HL, DAD the other.
if (DstReg == V6CLANG::HL && LhsReg != V6CLANG::HL && RhsReg != V6CLANG::HL) {
  // Copy LhsReg into HL, DAD RhsReg.
  MCRegister LhsHi = RI.getSubReg(LhsReg, V6CLANG::sub_hi);
  MCRegister LhsLo = RI.getSubReg(LhsReg, V6CLANG::sub_lo);
  BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::H).addReg(LhsHi);
  BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::L).addReg(LhsLo);
  BuildMI(MBB, MI, DL, get(V6CLANG::DAD)).addReg(RhsReg);
  MI.eraseFromParent();
  return true;
}
```

### Edge cases

1. **`rp = ADD16 HL, HL`** (doubling HL): OtherReg = HL, but
   `DAD HL` is valid (HL = HL + HL). Then copy HL to rp. Works correctly
   with path 1 if HL is dead after.

2. **`HL = ADD16 BC, DE`**: Path 2 copies BC→HL, then DAD DE. Order
   doesn't matter (commutative), but we must not clobber an operand before
   reading it. Since we copy Lhs first and DAD Rhs, and Rhs is not HL,
   the Rhs is never clobbered.

3. **`BC = ADD16 HL, BC`**: Path 1 does `DAD BC; MOV B,H; MOV C,L`.
   But wait — DAD reads BC, then we overwrite BC with the result. This is
   safe because DAD executes atomically (single instruction), reading BC
   before producing the result in HL.

4. **`DE = ADD16 HL, DE`**: Same as above with DE. `DAD DE; MOV D,H; MOV E,L`.

5. **`BC = ADD16 HL, DE`**: OtherReg = DE. `DAD DE; MOV B,H; MOV C,L`.
   BC's old value (lhs? no — lhs is HL). Wait, lhs=HL, rhs=DE, dst=BC.
   So we do DAD DE (HL = HL + DE), then copy HL→BC. This is correct
   because BC is only the destination (not an input operand in this case).

6. **Interaction with XCHG optimization**: The MOV pair in path 1 output
   (`MOV D,H; MOV E,L`) will be caught by V6ClangXchgOpt and converted to XCHG
   when DE is the destination. This would further optimize to `DAD rp; XCHG`
   (16cc, 2B). This interaction is free — no special handling needed.

## Test Cases

### Lit test

File: `tests/lit/CodeGen/V6Clang/add16-dad-expansion.ll`

```llvm
; RUN: llc -march=v6clang -O2 < %s | FileCheck %s

; Case 1: rp = ADD16 HL, rp — should use DAD + copy out
; nested_calls puts a+b into BC via ADD16 where one operand is HL.
define i16 @test_dad_copy_out(i16 %n) nounwind {
  %a = call i16 @get_val()
  %b = call i16 @get_val()
  %sum1 = add i16 %a, %b
  %sum2 = add i16 %sum1, %n
  call void @use_val(i16 %sum2)
  ret i16 %sum1
}
; CHECK-LABEL: test_dad_copy_out:
; CHECK: DAD
; CHECK-NOT: ADC

; Case 2: HL = ADD16 rp1, rp2 — should use MOV pair + DAD
define i16 @test_dad_copy_in(i16 %a, i16 %b) nounwind {
  call void @use_val(i16 %a)       ; force a into non-HL
  call void @use_val(i16 %b)       ; force b into non-HL
  %sum = add i16 %a, %b
  ret i16 %sum                     ; result in HL
}
; CHECK-LABEL: test_dad_copy_in:
; CHECK: DAD
; CHECK-NOT: ADC

declare void @use_val(i16)
declare i16 @get_val()
```

### Feature test

Reuse `tests/features/21/v6clang.c` — the `nested_calls` function is the
primary beneficiary. After the fix, expected output:

```asm
nested_calls:
    MOV  D, H
    MOV  E, L
    CALL get_val
    MOV  B, H
    MOV  C, L
    CALL get_val
    DAD  BC            ; ← was 6 MOV/ADD/ADC instructions
    MOV  B, H          ; ← copy result to BC
    MOV  C, L
    DAD  DE            ; ← was 6 MOV/ADD/ADC instructions
    CALL use_val
    MOV  H, B
    MOV  L, C
    RET
```

Current: 21 instructions, 196cc (for `nested_calls` body).
Expected: 14 instructions. Saving: ~24cc, 6B in `nested_calls` alone.

## Savings

| Per instance | Cycles saved | Bytes saved |
|-------------|-------------|-------------|
| Path 1 (HL dead) | 12cc | 3B |
| Path 2 (dst=HL) | 12cc | 3B |

**Frequency**: Medium-High. Any function with 16-bit additions where HL
is not the primary accumulator pair — common when multiple additions feed
different destinations, or when the RA assigns results to non-HL pairs
due to pressure from calls (calls clobber HL for return values).

**Frequency boost from O10**: With static stack allocation, functions
that previously spilled (consuming ADD16 instructions for stack offset
computation) now have more register pressure freed up, leading to more
ADD16 instances in non-HL pairs.

## Risk

**Very Low**. Pure improvement to pseudo-instruction expansion:
- No new instructions or pseudos
- No changes to ISel, RA, or other passes
- Falls back to existing byte chain when preconditions aren't met
- Liveness check uses proven `isRegDeadAfter()` utility

## Dependencies

- None. Standalone enhancement to `expandPostRAPseudo()`.
- V6ClangXchgOpt (existing pass) will further optimize `MOV D,H; MOV E,L`
  to `XCHG` when applicable, turning `DAD rp; MOV D,H; MOV E,L` into
  `DAD rp; XCHG` (16cc, 2B) — a free bonus.
