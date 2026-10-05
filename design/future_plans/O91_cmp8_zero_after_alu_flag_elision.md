# O91 — Elide V6CLANG_CMP8_ZERO After Flag-Setting ALU Op (MOV R,A bridge)

**Source:** `temp/cmp8_zero_after_aluflag.c`; triggered by O89 dead-hi-byte sequences
**Savings:** 16cc, 3B per `(u8)(a OP b) == 0` comparison (OP = `^`, `&`, `|`)
**Frequency:** Every lo-byte-truncated bitwise result fed into a boolean zero-test
**Complexity:** Low — extend `V6ClangRedundantFlagElim` with a one-register value set
**Risk:** Low — conservative: only fires when exact sequence is proven
**Dependencies:** O89 (dead-hi-byte elision creates the pattern); O80 (V6CLANG_CMP8_ZERO)
**Status:** [ ] not started

---

## Problem

After O89 (dead high-byte elision), `V6CLANG_XOR16 / V6CLANG_AND16 / V6CLANG_OR16` with
DstHi dead expand to:

```asm
;--- V6CLANG_XOR16 (DstHi dead, O89 active) ---
MOV  A, E          ; A = lhs_lo              8cc  1B
XRA  L             ; A = lo result, Z set ←  4cc  1B   ← Z ALREADY VALID
MOV  L, A          ; DstLo = A               8cc  1B   ← flags untouched
;--- V6CLANG_CMP8_ZERO L (shape 2: XRA A; CMP L) ---
XRA  A             ; ← Z already valid!      4cc  1B   ← REDUNDANT
CMP  L             ; ← Z already valid!      4cc  1B   ← REDUNDANT
JZ   .zero         ;                        12cc  3B
```

`XRA L` sets Z = (lo result == 0).  `MOV L, A` writes a register without
touching FLAGS.  The `V6CLANG_CMP8_ZERO L` expansion (`XRA A; CMP L`) is
therefore provably redundant: Z is already the correct answer.

### Confirmed current output (clang -O2, 2026-06-01)

```asm
xor16_cmp_zero:            ; u8 xor16_cmp_zero(u16 a, u16 b) { return (u8)(a^b)==0; }
    MOV  A, E              ;  8cc  1B
    XRA  L                 ;  4cc  1B   ← Z set here
    MOV  L, A              ;  8cc  1B
    XRA  A                 ;  4cc  1B   ← redundant (CMP8_ZERO shape 2)
    CMP  L                 ;  4cc  1B   ← redundant
    JZ   .LBB15_2          ; 12cc  3B  (worst path)
    XRA  A                 ;  4cc  1B
    RET                    ; 12cc  1B
.LBB15_2:
    INR  A                 ;  8cc  1B
    RET                    ; 12cc  1B   ← worst 60cc, 11B
```

### Target output after O91

```asm
xor16_cmp_zero:
    MOV  A, E              ;  8cc  1B
    XRA  L                 ;  4cc  1B   ← Z used directly
    JZ   .zero             ; 12cc  3B  (worst path)
    XRA  A                 ;  4cc  1B
    RET                    ; 12cc  1B
.zero:
    INR  A                 ;  8cc  1B
    RET                    ; 12cc  1B   ← worst 44cc, 8B  (save 16cc, 3B)
```

---

## Why Existing Passes Miss This

`V6ClangRedundantFlagElim` tracks `ZFlagValid` (true after any `isAluWritesAAndFlags`
op) and erases `ORA A` / `ANA A` when it is true.

For the pattern above:

| Instruction | ZFlagValid | Action |
|---|---|---|
| `MOV A, E`  | false | `isWritesANoFlags` → false |
| `XRA L`     | **true** | `isAluWritesAAndFlags` |
| `MOV L, A`  | true | neither A-write nor FLAGS-write → unchanged |
| `XRA A`     | true | **not** `ORA A` / `ANA A` → passes through; treated as ALU |
| `CMP L`     | false | `isWritesFlagsNoA` → false |

The pass has no concept of "register R holds the same value A had when Z was
set", so it cannot recognize that `XRA A; CMP L` restates the flag redundantly.

---

## Root Cause

`V6CLANG_CMP8_ZERO R` (shape 2: `XRA A; CMP R`) is emitted by `expandPostRAPseudo`
when A is dead and src ≠ A.  After O89 the typical pre-cursor is:

```
<ALU writes A, sets Z>   ; A = result; Z = (result == 0)
MOV R, A                 ; R = result; A, FLAGS untouched
XRA A                    ; ← starts CMP8_ZERO shape 2
CMP R
```

At the point of `XRA A`: Z is already valid AND R holds the value A had when
Z was set, so `A == R` is a proven identity and `XRA A; CMP R` is a no-op
w.r.t. flags.

---

## Solution

### Extend `V6ClangRedundantFlagElim` (single additional tracker)

Add `SmallSet<Register, 4> AValueRegs` alongside `ZFlagValid`:

> `AValueRegs` = the set of registers that are known to hold A's value as of
> the last `isAluWritesAAndFlags` instruction.

**State transition rules:**

| Event | ZFlagValid | AValueRegs |
|---|---|---|
| `isAluWritesAAndFlags(MI)` | → true | clear; insert A |
| `MOV R, A` (isWritesANoFlags, dst=R≠A, src=A) while ZFlagValid | unchanged | insert R |
| `isWritesANoFlags` (dst=A) | → false | clear |
| `isWritesFlagsNoA` or control flow | → false | clear |
| anything else | unchanged | unchanged |

**Elimination rule (new):**

When `ZFlagValid == true` and the current instruction is `XRA A`, peek at the
immediately following instruction.  If that next instruction is `CMP R` and
`R ∈ AValueRegs`:

1. Erase `XRA A`.
2. Erase `CMP R`.
3. Erase the `MOV R, A` that put R into `AValueRegs` (dead store, R no longer
   read by CMP R).  If that instruction has already been processed and removed
   from the iterator, skip step 3 — a subsequent DCE pass will remove it.
4. Continue scan; `ZFlagValid` and `AValueRegs` are unchanged (Z is still
   valid from the same prior ALU op).

### Handling `MOV R, A` erasure

The `MOV R, A` that bridges ALU → `CMP R` is a dead store once `CMP R` is
eliminated.  It can be erased in the same forward scan if we keep a pointer to
the last `MOV R, A` instruction that extended `AValueRegs`.

Simplest implementation: store a `std::map<Register, MachineInstr*> AValueSrc`
that maps each `R ∈ AValueRegs` to the `MOV R, A` that produced it.  On
successful elimination of `XRA A; CMP R`, erase `AValueSrc[R]` first, then
erase `XRA A` and `CMP R`.

---

## Affected patterns

| C expression | ALU op | Current | After O91 |
|---|---|---|---|
| `(u8)(a ^ b) == 0` | `XRA L` | MOV L,A + XRA A + CMP L | drop all 3 |
| `(u8)(a & b) == 0` | `ANA E` | MOV L,A + XRA A + CMP L | drop all 3 |
| `(u8)(a \| b) == 0` | `ORA L` | MOV L,A + XRA A + CMP L | drop all 3 |
| `(u8)(a ^ b) != 0` | `XRA L` | same + JNZ | same saving |

### Non-applicable cases (must not fire)

- `XRA A` not preceded by `ZFlagValid=true` — normal zero-clear, must keep.
- `CMP R` where R ∉ `AValueRegs` — genuine comparison, must keep.
- Multi-use of `DstLo` (R used again after the CMP) — `MOV R, A` erasure would
  break correctness; guard by checking R is dead after `CMP R` (or that the only
  intervening use is the CMP itself).

---

## Savings estimate

Per `(u8)(a OP b) == 0` site with O89 active:

| Removed instruction | Cycles | Bytes |
|---|---|---|
| `MOV L, A` (dead DstLo store) | 8 | 1 |
| `XRA A` (CMP8_ZERO part 1) | 4 | 1 |
| `CMP L` (CMP8_ZERO part 2) | 4 | 1 |
| **Total** | **16** | **3** |

---

## Test program

`temp/cmp8_zero_after_aluflag.c` — functions `xor16_cmp_zero`, `and16_cmp_zero`,
`or16_cmp_zero`.  Control (must be unaffected): `xor_bytes`, `xor8_cmp_zero`,
`xor16_full`.

Compile:
```
clang -target i8080-unknown-v6clang -O2 -S -o temp/cmp8_zero_after_aluflag.s \
      temp/cmp8_zero_after_aluflag.c
```

Expected after O91:

```asm
xor16_cmp_zero:
    MOV  A, E
    XRA  L
    JZ   .LBBx_2
    XRA  A
    RET
.LBBx_2:
    INR  A
    RET
```

---

## Implementation location

**File:** `llvm-project/llvm/lib/Target/V6Clang/V6ClangRedundantFlagElim.cpp`

Add `AValueRegs` + `AValueSrc` alongside `ZFlagValid` in `runOnMachineFunction`.
Extend the four state-transition branches.  Add one new elimination branch for
the `XRA A` + peek-at-next-`CMP R` pattern.

No new TableGen, no new pseudo, no new pass.
