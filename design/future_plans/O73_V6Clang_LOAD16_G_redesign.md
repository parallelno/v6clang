# O73: V6CLANG_LOAD16_G Redesign

## Status

Planned. Companion to
[O71_V6CLANG_LOAD16_P_redesign.md](O71_V6CLANG_LOAD16_P_redesign.md) (which
covers the through-pointer variant). This plan covers the
global-address (immediate-address) variant.

## Background

`V6CLANG_LOAD16_G` is the 16-bit load-from-global-address pseudo:

```tablegen
let mayLoad = 1 in
def V6CLANG_LOAD16_G : V6ClangPseudo<(outs GR16:$dst), (ins imm16:$addr),
    "# LOAD16G $dst, $addr", []>;

def : Pat<(i16 (load (V6Clangwrapper tglobaladdr:$addr))),
          (V6CLANG_LOAD16_G tglobaladdr:$addr)>;
```

It declares **no `Defs`**. The intent is that the pseudo behaves as a
pure 16-bit load: it produces `$dst` and preserves every other
register the caller cares about. The post-RA expander is responsible
for emitting whatever code is needed to honour that contract for the
chosen `$dst` physreg.

Unlike `V6CLANG_LOAD16_P`, the address operand is an immediate (a
`tglobaladdr` or `MCSymbol`), so `LHLD addr` / `LDA addr` / `LDA
addr+1` are all directly available without any address-pair
materialisation.

The current expander honours the contract for `dst=HL` (`LHLD`,
optimal) and for `dst=DE` (`XCHG; LHLD; XCHG`, preserves HL via the
swap, even when HL is dead and the leading `XCHG` could be skipped),
but the `dst=BC` path is one-size-fits-all:

```asm
PUSH H              ; 16cc / 1B
LHLD addr           ; 20cc / 3B
MOV  B, H           ;  8cc / 1B
MOV  C, L           ;  8cc / 1B
POP  H              ; 12cc / 1B
                    ; ----------
                    ; 64cc / 7B
```

The PUSH/POP HL pair is paid unconditionally whenever HL is live
across the pseudo (O42 already skips it when HL is dead, but does not
consider any cheaper alternative when HL is live).

V6CLANG has cheaper options that can be selected from observable post-RA
liveness:

- When **HL is dead** across the pseudo, `LHLD` may write HL freely.
  No preservation is needed at all.
- When **A is dead** across the pseudo, the two halves of the
  16-bit load can be sourced via `LDA addr` / `LDA addr+1` directly
  into BC through A, without ever touching HL.
- Only when both HL and A are live does the existing PUSH/POP HL
  wrap remain optimal among non-`A`-using shapes.

## Problem

`V6CLANG_LOAD16_G` with `dst=BC` always emits the PUSH/POP HL wrap
whenever HL is live, even when:

- `A` is dead at the pseudo, in which case an `LDA`-pair shape would
  cost 48cc / 8B and leave HL untouched (saves 16cc, costs +1B).
- `HL` is dead at the pseudo (already handled by O42 — skip the
  PUSH/POP — but we should make this part of the unified table).

The issue is structurally identical to the one solved by O71:
selecting the cheapest preservation/clobber strategy requires
post-RA liveness knowledge that the register allocator does not
have. RA cannot insert "save A through PSW" or "skip the HL wrap"
selectively; it would have to mark A and HL as clobbered globally,
which would force every `V6CLANG_LOAD16_G` to spill A across the call —
unacceptable on a 1-element pressure class.

## Solution

Keep `V6CLANG_LOAD16_G` as a single pseudo with **no `Defs` declared**,
and extend the post-RA expander to pick a cheapest-first shape for
the `dst=BC` case based on observable liveness of HL and A at the
pseudo's location.

### Design rules

1. **No `Defs`.** The pseudo defines only `$dst`. Pre-RA passes
   (CSE, LICM, scheduling, RA) see the load as preserving every
   other register. This matches the actual post-expansion behaviour
   in the cheapest path and avoids forcing spills on the common
   case.

2. **Honest preservation in the expander.** After RA, the expander
   computes post-RA liveness for `HL` and `A` at the pseudo's
   location. For each register the chosen shape would otherwise
   clobber and that is live across the pseudo, the expander emits
   the cheapest available recovery.

3. **Cheapest-first dispatch for `dst=DE` and `dst=BC`.**
   For `dst=DE`:
   1. `HL` dead → `LHLD addr; XCHG` (HL is scratch).
   2. else → `XCHG; LHLD addr; XCHG`.

   For `dst=BC`:
   1. `HL` dead → `LHLD addr; MOV B,H; MOV C,L`.
   2. else `A` dead → `LDA addr; MOV C,A; LDA addr+1; MOV B,A`.
   3. else → `PUSH H; LHLD addr; MOV B,H; MOV C,L; POP H`.

   `dst=HL` is unchanged from the current expander (already
   optimal — see table below).

### Per-shape expansion table

|# |dst|Predicate          |Expansion                                   |Bytes/CCs|
|--|---|-------------------|--------------------------------------------|---------|
|1 |HL |(always)           |`LHLD addr`                                 |3B / 20cc|
|2a|DE |`HL` dead at pseudo|`LHLD addr; XCHG`                           |4B / 24cc|
|2b|DE |otherwise          |`XCHG; LHLD addr; XCHG`                     |5B / 28cc|
|3a|BC |`HL` dead at pseudo|`LHLD addr; MOV B,H; MOV C,L`               |5B / 36cc|
|3b|BC |`A` dead at pseudo |`LDA addr; MOV C,A; LDA addr+1; MOV B,A`    |8B / 48cc|
|3c|BC |otherwise          |`PUSH H; LHLD addr; MOV B,H; MOV C,L; POP H`|7B / 64cc|

Cycle counts use the V6CLANG-specific timings from
[`docs/Vector_06c_instruction_timings.md`](../../docs/Vector_06c_instruction_timings.md):
`LHLD`=20cc, `LDA`=16cc, `MOV r,r`=8cc, `XCHG`=4cc, `PUSH`=16cc,
`POP`=12cc.

### Dispatch precedence (`dst=BC`)

```
if HL is dead at MI:
    use case 3a  # 5B / 36cc, never touches A
elif A is dead at MI:
    use case 3b  # 8B / 48cc, never touches HL
else:
    use case 3c  # 7B / 64cc, preserves HL via PUSH/POP
```

Case 3a is preferred over 3b when HL is dead even if A is also dead:
3a is shorter (5B vs 8B) and faster (36cc vs 48cc).

### Why cycle-cheapest is also pressure-correct

| Case | Touches HL?              | Touches A? |
|------|--------------------------|------------|
| 3a   | yes (overwrites; HL dead)| no         |
| 3b   | no                       | yes (A dead) |
| 3c   | yes, restored            | no         |

Each shape is selected only when its clobber set is provably empty
(register dead at MI) or recoverable (PUSH/POP). The pseudo's
declared "no Defs" remains truthful in every dispatch outcome.

## Correctness Conditions

- Expander must compute post-RA liveness of `HL` and `A` at the
  pseudo's location using `isRegDeadAtMI` (the same helper used by
  O42 and O71).
- The two `LDA` operands in case 3b are `addr` and `addr+1`. For a
  `tglobaladdr` operand, `addr+1` is encoded as `MachineOperand`
  with the same `GlobalValue` and an offset incremented by 1. For
  an `MCSymbol`/`imm` operand, the second `LDA` carries the
  numerically-incremented immediate (or a symbol-plus-1 expression
  via `MCSymbolRefExpr` when the operand is a symbol reference).
- Case 3b never executes when `A` is live across the pseudo, so no
  preservation of `A` is ever required.
- Case 3c is unchanged from the current expander modulo the
  predicate — it remains the universal fallback.

## Implementation Sketch

In `V6ClangInstrInfo::expandPostRAPseudo` for `V6CLANG::V6CLANG_LOAD16_G`,
`dst=BC` arm:

1. Read `DstReg`, `AddrOp`. Compute `DstLo`, `DstHi`.
2. Compute `HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI)` (already
   done today for the O42 PUSH/POP skip).
3. Compute `ADead = isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI)`.
4. Emit:
   - **HLDead:** `LHLD addr; MOV B,H; MOV C,L`.
   - **else ADead:** `LDA addr; MOV C,A; LDA addr+1; MOV B,A`,
     where the second `LDA` uses `AddrOp` cloned with `getOffset()
     += 1` (global) or `getImm() += 1` (immediate).
   - **else:** unchanged PUSH/POP HL wrap around `LHLD; MOV B,H;
     MOV C,L`.
5. Erase the pseudo.

`dst=HL` and `dst=DE` arms are unchanged.

A small helper, e.g. `cloneAddrOpPlus(AddrOp, 1)`, simplifies the
case-3b second-LDA operand construction.

## Expected Effects

- **Hot path improvement.** Functions that load a 16-bit global
  while HL is live and A is dead (a common pattern: i8 producer
  followed by i16 global load into a non-HL register) drop from
  64cc/7B to 48cc/8B (–16cc, +1B). The cycle saving is significant
  in inner loops at the cost of one byte.
- **Already-cold-path preservation.** When both HL and A are live,
  fall back to today's PUSH/POP shape — no regression.
- **HL-dead path tightened.** When HL is dead, drop from 64cc/7B
  (with O42-skipped PUSH/POP that's already 36cc/5B) to a clearly
  unified 36cc/5B path with the same cost.
- **Pressure unchanged.** RA continues to see `V6CLANG_LOAD16_G` as
  preserving everything except `$dst`, so it does not insert
  spills around the load.

## Tests

- Lit test exercising each row of the dispatch table:
  - `dst=HL` (case 1).
  - `dst=DE` (case 2).
  - `dst=BC, HL dead` (case 3a).
  - `dst=BC, HL live, A dead` (case 3b) — verify two `LDA` with
    the second carrying offset `+1`.
  - `dst=BC, HL live, A live` (case 3c) — verify PUSH/POP HL.
- Regression test: a value in `A` live across `V6CLANG_LOAD16_G` with
  `dst=BC` (case 3c) must survive — confirm no `LDA` is emitted.
- Regression test: the global pointer load result must equal the
  in-memory bytes regardless of dispatch outcome (golden test
  with the same C source, verifying byte-level equivalence
  across all three BC dispatch paths).

## Risk

Low. The change is local to one `case` arm in
`expandPostRAPseudo`. The pseudo's `.td` declaration does not
change, so isel patterns and pre-RA passes are untouched. The
existing `dst=HL` and `dst=DE` arms are unchanged. Main risk is
the symbol-plus-1 operand construction for case 3b — guarded by
lit checks on the emitted assembly.

## Dependencies

- Existing `V6CLANG_LOAD16_G` post-RA expansion entry point in
  [`V6ClangInstrInfo.cpp`](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp)
  (around line 1883).
- Existing `isRegDeadAtMI` helper from O42.

## Out of Scope

- `V6CLANG_STORE16_G` global-address-store variant. Same shape-conflation
  pattern, follow-up plan (parallel to O72 for the through-pointer
  variant).
- `V6CLANG_LOAD16_P` / `V6CLANG_STORE16_P` through-pointer variants. Already
  covered by [O71](O71_V6CLANG_LOAD16_P_redesign.md) and
  [O72](O72_V6CLANG_STORE16_P_redesign.md).
- Sequential `V6CLANG_LOAD16_G` peepholes (e.g. two adjacent BC-loads
  from `addr` / `addr+2` reusing the LDA-pair shape). The unified
  table here is a prerequisite, but the peephole itself is a
  separate plan.
