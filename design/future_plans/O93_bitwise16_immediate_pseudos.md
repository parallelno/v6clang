# Plan: O93 — V6CLANG_AND16_IMM / V6CLANG_OR16_IMM / V6CLANG_XOR16_IMM (Immediate Bitwise 16)

> **Status: ✅ COMPLETE.** Implemented in `V6ClangInstrInfo.td` (3 pseudos +
> patterns) and `V6ClangInstrInfo.cpp` (`expandPostRAPseudo` constant-in-A
> expansion with per-byte identity folding + dead-hi guard). Lit:
> `bitwise16-imm.ll`. Feature test: `tests/features/77/`. lfsr16 benchmark:
> 121 B → 90 B (−25.6%), 1,344,784 cc → 730,452 cc (−45.7%). All regression
> suites pass.

## 1. Problem

### Current behavior

A 16-bit bitwise op against a **compile-time constant** is lowered as a
register/register `V6CLANG_AND16` / `V6CLANG_OR16` / `V6CLANG_XOR16`. ISel must first
materialise the constant into a scratch register **pair** with `LXI`, then run
the 6-instruction pair-wise sequence.

Example — `lfsr ^= 0xb400` from `tests/benchmarks_c/asm/v6clang_lfsr16_O2.s`:

```asm
LXI   B, 0xb400        ; 12cc  3B   materialise constant into BC
;--- V6CLANG_XOR16 ---
MOV   A, L             ;  8cc  1B
XRA   C                ;  4cc  1B
MOV   C, A             ;  8cc  1B   (writes lo)
MOV   A, H             ;  8cc  1B
XRA   B                ;  4cc  1B
MOV   B, A             ;  8cc  1B   (writes hi)
; op = 40cc / 6B, + 12cc/3B LXI = 52cc total
```

The `LXI` does two bad things:

1. **Costs 12cc / 3B** of pure constant-materialisation overhead per use.
2. **Burns a whole register pair** (BC here) for the duration. On a machine
   with only HL / BC / DE this is the difference between fitting in registers
   and spilling. In the `lfsr16` hot loop this constant pair is exactly what
   forces the surrounding `V6CLANG_SPILL16` / `V6CLANG_RELOAD16` pair.

### Desired behavior

```asm
;--- V6CLANG_XOR16_IMM  (dst = src ^ 0xb400) ---
MVI   A, 0x00          ;  8cc  2B   lo byte of constant   (← see §2 folding)
XRA   L                ;  4cc  1B   A = lo(src) ^ 0x00
MOV   L, A             ;  8cc  1B
MVI   A, 0xb4          ;  8cc  2B   hi byte of constant
XRA   H                ;  4cc  1B   A = hi(src) ^ 0xb4
MOV   H, A             ;  8cc  1B
; 40cc / 8B, NO LXI, NO scratch pair
```

No constant pair is materialised, so **no extra register pair is consumed** and
the spill/reload that the `LXI` provoked disappears. With the per-byte folding
in §2, the `0x00` lo byte is an XOR identity and drops out entirely, giving
**20cc / 4B** for this exact site (52 → 20).

### Root cause / the commutativity trick

The naïve immediate lowering would be `MOV A,reg; <op>I imm; MOV reg,A` using
the immediate ALU forms (`ANI`/`ORI`/`XRI`, all 8cc). That is `8+8+8 = 24cc`
per byte — *worse* than the register form's `8+4+8 = 20cc`.

The win comes from loading the **constant** into `A` and applying the **cheaper
4cc register ALU** form against the source register:

```
MVI A, imm_byte   ; 8cc   (constant → A)
XRA reg_byte      ; 4cc   (register operand, NOT immediate)
MOV reg_byte, A   ; 8cc
```

This is only legal because AND/OR/XOR are **commutative**:
`A & r == r & A`, `A | r == r | A`, `A ^ r == r ^ A`. So putting the constant in
`A` and the variable in the ALU operand produces the identical result while
using the 4cc register form instead of the 8cc immediate form.

> **`CMP` is explicitly excluded.** `A - r ≠ r - A`, so the trick cannot be
> applied to a hypothetical `CMP16_IMM`, and the ordered-flag semantics of a
> 16-bit compare are a separate problem. CMP16-against-immediate is out of
> scope for this plan (track separately as an EQ/NE-only variant if ever
> wanted).

---

## 2. Strategy

### Approach

1. Add three new pseudos `V6CLANG_AND16_IMM` / `V6CLANG_OR16_IMM` / `V6CLANG_XOR16_IMM`,
   each `(outs GR16:$dst), (ins GR16:$src, i16imm:$imm)`, `Defs = [A, FLAGS]`,
   `Constraints = "$dst = $src"`.
2. ISel patterns match `(and/or/xor GR16:$src, imm:$imm)`. DAGCombine already
   canonicalises the constant to the RHS of commutative nodes, so a single
   RHS-immediate pattern per op suffices.
3. Expand in `expandPostRAPseudo` (sibling to the existing
   `V6CLANG_AND16/OR16/XOR16` case) using the **constant-in-A** shape above, with
   per-byte specialisation:

   | Op  | Byte == 0x00            | Byte == 0xFF            | else                         |
   |-----|-------------------------|-------------------------|------------------------------|
   | AND | `MVI reg,0` (→ O55 XRA) | identity — skip byte     | `MVI A,b; ANA reg; MOV reg,A`|
   | OR  | identity — skip byte    | `MVI reg,0xFF`          | `MVI A,b; ORA reg; MOV reg,A`|
   | XOR | identity — skip byte    | (no special) `b=0xFF`   | `MVI A,b; XRA reg; MOV reg,A`|

   - **XOR `0x00`** and **OR `0x00`** and **AND `0xFF`** are identities → emit
     nothing for that byte.
   - **AND `0x00`** → `MVI reg,0` (O55 may further fold to `XRA reg` if A dead).
   - **OR `0xFF`** → `MVI reg,0xFF`.
   - This reuses and generalises the O89 dead-hi-byte idea: a dead `DstHi` is
     also folded away via `isRegDeadAfter` exactly as in the reg/reg case.

### Why this works

- Constant operands of 16-bit bitwise ops are common (masks, flag toggles,
  LFSR taps) and currently pay full `LXI` + reg-pair cost.
- Removing the scratch pair is the dominant win: it directly relieves the RA
  pressure that drives spills in tight loops (the motivating `lfsr16` case).
- The constant-in-A trick keeps per-byte cost at the cheaper 20cc, and per-byte
  identity folding frequently makes one or both bytes free.

### Cost / register-pressure trade-off (when reg/reg can still win)

Code size per use is up to `MVI A,lo`(2B)+`MVI A,hi`(2B) = 4B vs reg/reg's
`MOV A,r`+`MOV A,r` = 2B (plus one-time `LXI` 3B). If a constant is
**loop-invariant, reused ≥ 2×, AND a register pair is genuinely free**, hoisting
one `LXI` via LICM and reusing a resident pair is smaller and equal-cc.

Recommended bias: **default to `_IMM`** (register pressure almost always
dominates on V6CLANG), and only keep the reg/reg form when the constant pair is
loop-hoistable and there is provable free register pressure. For the first cut,
emit `_IMM` unconditionally for constant RHS; revisit a cost heuristic only if a
benchmark regresses on size.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td` | 3 new `_IMM` pseudos + ISel patterns |
| `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp` | New `expandPostRAPseudo` case: constant-in-A expansion + per-byte folding + dead-hi guard |
| `llvm-project/llvm/test/CodeGen/V6CLANG/bitwise16-imm.ll` | New lit test: all 3 ops × {generic, 0x00 byte, 0xFF byte, dead-hi} |
| `tests/features/NN/` | Feature test: C source, baseline, new asm, result.txt |
| `design/future_plans/O93_bitwise16_immediate_pseudos.md` | This plan; mark complete when done |
| `design/future_plans/README.md` | Add ✅ O93 entry |

---

## 3. Implementation Steps

### Step 3.1 — Add the three `_IMM` pseudos + patterns in V6ClangInstrInfo.td [ ]

In the `let Defs = [A, FLAGS]` block that holds `V6CLANG_AND16/OR16/XOR16`, add
their immediate siblings:

```tablegen
def V6CLANG_AND16_IMM : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i16imm:$imm),
    "# AND16_IMM $dst, $src, $imm",
    [(set i16:$dst, (and i16:$src, imm:$imm))]> {
  let Constraints = "$dst = $src";
}
def V6CLANG_OR16_IMM : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i16imm:$imm),
    "# OR16_IMM $dst, $src, $imm",
    [(set i16:$dst, (or i16:$src, imm:$imm))]> {
  let Constraints = "$dst = $src";
}
def V6CLANG_XOR16_IMM : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$src, i16imm:$imm),
    "# XOR16_IMM $dst, $src, $imm",
    [(set i16:$dst, (xor i16:$src, imm:$imm))]> {
  let Constraints = "$dst = $src";
}
```

> **Design Notes**: Give the `_IMM` pattern a higher `AddedComplexity` than the
> reg/reg `V6CLANG_AND16` etc. so a constant RHS prefers `_IMM`. Confirm the reg/reg
> patterns still match when RHS is a non-constant register. Check that no
> existing pattern (e.g. an i8-narrowing fast path from O90) already captures
> the small-constant case before it reaches here — O90 handles `C ≤ 0xFF`
> zero-test-only narrowing; this plan targets full-width constants and
> register-persistent results that O90 deliberately leaves at i16.

### Step 3.2 — Expansion in V6ClangInstrInfo.cpp [ ]

Add a case next to `V6CLANG_AND16/OR16/XOR16`. Reuse `DstLo/DstHi/SrcLo/SrcHi`
sub-register extraction. Pull the constant via `MI.getOperand(2).getImm()`,
split into `Lo = Imm & 0xFF`, `Hi = (Imm >> 8) & 0xFF`. Pick `OpOpc`
(`ANAr`/`ORAr`/`XRAr`). For each byte, apply the §2 folding table; emit the
`MVI A,b; <op> reg; MOV reg,A` triple only in the generic case. Guard the hi
byte with `bool HiDead = isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI)` as
in O89.

> **Design Notes**: When the lo byte is an identity AND the hi byte is also
> identity/dead, the pseudo collapses to a plain pair copy (`$dst = $src`
> constraint already makes this a no-op). Make sure the no-op case still erases
> the pseudo cleanly. Verify `A`/`FLAGS` are only marked clobbered on paths that
> actually emit an ALU op (an all-identity expansion clobbers neither — but the
> pseudo's `Defs = [A,FLAGS]` over-approximates, which is safe).

### Step 3.3 — Build [ ]

```
cmd /c "call ""...VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```
(or `pwsh scripts\build.ps1 -SkipTests`)

### Step 3.4 — Lit test: bitwise16-imm.ll [ ]

Cover, per op:
- generic constant (both bytes non-trivial) → expect `MVI A,lo; <op> reglo; MOV reglo,A; MVI A,hi; <op> reghi; MOV reghi,A`, **no `LXI`**.
- XOR/OR `0x00` byte → that byte's triple absent.
- AND `0xFF` byte → that byte's triple absent; AND `0x00` byte → `MVI reg,0` / `XRA`.
- OR `0xFF` byte → `MVI reg,0xFF`.
- dead-hi (`(u8)(x op C)`) → hi block absent.

### Step 3.5 — Feature test tests/features/NN/ [ ]

Use an `lfsr`-style hot loop with a constant tap so the before/after shows the
removed `LXI` + removed spill/reload. Record cc/byte deltas in `result.txt`.

### Step 3.6 — Run full suite [ ]

`python tests/run_all.py` (after `scripts/sync_llvm_mirror.ps1`). Check the
`lfsr16` benchmark cc/size dropped and nothing else regressed.

---

## 4. Risks & Notes

- **Interaction with O90 i8 narrowing**: O90 narrows `C ≤ 0xFF` bitwise ops to
  i8 *only when all users are zero-tests*. O93 targets the complementary set
  (full-width constants, or results that must persist in a register). Ensure
  the two do not both fire — O90 runs pre-ISel and rewrites the node, so by the
  time ISel sees a surviving i16 bitwise-with-constant, O93's pattern is the
  correct owner. Add a feature/lit check that a narrowable zero-test case still
  goes through O90 (ANI/ORI/XRI), not O93.
- **O55 dependency**: AND-`0x00` → `MVI reg,0` relies on the existing O55
  `MVI A,0 → XRA A` peephole only for the *accumulator*; for a non-A `reg` the
  `MVI reg,0` stays (8cc/2B). That is still strictly better than the reg/reg
  path. Do not hand-roll an `XRA reg` here (would clobber the wrong reg / need A
  dead) — leave byte-zeroing as `MVI reg,0`.
- **Patched-imm (O61) safety**: these `MVI A,imm` are ordinary immediates with
  no `MO_PATCH_IMM` flag, so later passes treat them normally. No special
  guarding needed, but do **not** let any future MVI-fold peephole collapse the
  `MVI A,b; <op> reg` pair incorrectly (the constant-in-A is the whole point).
- **CMP16 immediate**: out of scope (see §1). Track separately if needed.
```
