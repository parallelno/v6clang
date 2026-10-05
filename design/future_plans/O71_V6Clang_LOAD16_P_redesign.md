# O71: V6CLANG_LOAD16_P Redesign

## Status

Implemented. See [../plan_O71_V6CLANG_LOAD16_P_redesign.md](../plan_O71_V6CLANG_LOAD16_P_redesign.md).

## Background

`V6CLANG_LOAD16_P` is the generic 16-bit load-through-pointer pseudo:

```tablegen
let mayLoad = 1 in
def V6CLANG_LOAD16_P : V6ClangPseudo<(outs GR16:$dst), (ins GR16:$addr),
    "# LOAD16P $dst, ($addr)",
    [(set i16:$dst, (load i16:$addr))]>;
```

It declares **no `Defs`**. The intent is that the pseudo behaves as a
pure 16-bit load: it produces `$dst` and preserves every other
register the caller cares about. The post-RA expander is responsible
for emitting whatever address-shuffling and preservation code is
needed to honour that contract for the chosen `(addr, dst)` physreg
pair.

The current expander does not always honour the contract. Some shapes
emit code that genuinely clobbers `A` or leaves `HL` pointing at
`orig + 1`, while the pseudo continues to claim everything is
preserved. RA and downstream passes trust the pseudo and miscompile.

## Problem

### Concrete correctness bugs

1. **`addr=HL, dst=HL` silently corrupts `A`.**
   Expansion: `MOV A,M; INX H; MOV H,M; MOV L,A`. `A` is destroyed
   and not reflected in `Defs`.

2. **`addr=HL, dst∈{BC,DE}` lies about `HL`.**
   Expansion: `MOV lo,M; INX H; MOV hi,M`. After it runs,
   `HL = orig_HL + 1`. RA is told HL is unchanged.

3. **`addr=DE, dst=DE` produces wrong values in HL and DE.**
   Expansion: `XCHG; MOV E,M; INX H; MOV D,M; XCHG`. Trace:
   - `XCHG` → HL=ptr, DE=old_HL
   - inner load deposits result in DE (= old_HL after first XCHG)
   - trailing `XCHG` swaps that result into HL while pushing old_HL
     out into DE — both registers end up wrong.

   Observed in `temp\asm_inline\custom_cc.s`:

   ```asm
   ;--- V6CLANG_ADD16 ---       HL = sum
   DAD     B
   ;--- V6CLANG_LOAD16_P ---    addr=DE, dst=DE
   XCHG
   MOV     E, M
   INX     H
   MOV     D, M
   XCHG                     ; HL = loaded (wrong), DE = ptr+1 (wrong)
   ;--- V6CLANG_ADD16 ---
   DAD     D                ; HL = loaded + (ptr+1)  -- WRONG
   ```

4. **`addr=BC` with `HLDead` skips PUSH/POP and leaks
   `HL = orig_BC + 1`.** Benign while `HLDead` truly means dead, but
   fragile — any later liveness recompute that re-reads the pseudo's
   declared `Defs` (none) will not see the HL clobber.

5. **`addr=BC, dst=HL` silently corrupts `A`** for the same reason as
   bug 1.

### Why a single blanket `Defs` is not the answer

This backend's dominant cost is register pressure: spills account for
a large fraction of generated code. `A` lives in a 1-element pressure
class. Marking the pseudo `Defs = [HL, A]` (or worse, `Defs = [HL, A,
FLAGS]`) would close the correctness holes but force RA to spill `A`
across *every* 16-bit pointer load, even shapes like
`addr=HL, dst=BC/DE` whose actual code is `MOV r,M; INX H; MOV r,M`
and preserves `A` perfectly.

Per-shape pseudos with honest pre-RA `Defs` would be more precise
than one union, but still worse than the design below: RA cannot
emit `DCX rp` to undo an increment, and cannot pick a dead GR8 as a
temp at expansion time. Both of those are key cost levers on this
ISA.

## Solution

Keep `V6CLANG_LOAD16_P` as a single pseudo with **no `Defs` declared**,
and fix the expander to truthfully preserve every register that is
live across the pseudo, using whichever cheapest mechanism is
available at the expansion point.

### Design rules

1. **No `Defs`.** The pseudo defines only `$dst`. Pre-RA passes
   (CSE, LICM, scheduling) and RA itself see the load as preserving
   every other register. This is what they want for the pressure
   model.

2. **Honest preservation in the expander.** After RA, the expander
   computes post-RA liveness for both 8-bit and 16-bit registers at
   the pseudo's location. For each register that the chosen shape
   would otherwise clobber and that is live across the pseudo, the
   expander emits cheap recovery code.

3. **Cheap-first preservation policy.** Preference order, cheapest
   first:
   1. **Pick a dead spare GR8** for the low-byte temporary instead
      of `A`. Any GR8 dead at the pseudo works (there are seven to
      choose from). This avoids clobbering `A` entirely.
   2. **`DCX rp` to undo `INX rp`** when the address pointer is live
      across the pseudo. 1 byte / 5 cc, no flag effects.
   3. **`PUSH PSW` / `POP PSW`** wrap when the temp must be `A` and
      `A` is live across the pseudo. 2 bytes / 23 cc, last resort
      for the temp.
   4. **`PUSH H` / `POP H`** wrap when HL must hold the address
      mid-pseudo and HL is live across the pseudo and cannot be
      recovered by `DCX` (i.e. `addr=BC` cases, where HL was
      overwritten rather than incremented). 2 bytes / 22 cc.

### Per-shape expansion table

`SpareR` denotes a GR8 that is dead at the pseudo location; `A` is
the fallback if no GR8 is dead.

| Case | addr | dst   | expansion | preservation knobs |
|------|------|-------|-----------|--------------------|
| 1    | HL   | HL    | `MOV SpareR,M; INX H; MOV H,M; MOV L,SpareR` | if no SpareR, wrap `PUSH PSW` / `POP PSW` and use `SpareR=A` |
| 2    | HL   | BC/DE | `MOV lo,M; INX H; MOV hi,M`                  | optional `DCX H` if HL live                         |
| 3a   | DE   | BC    | `XCHG; MOV C,M; INX H; MOV B,M; XCHG`        | optional `DCX D` if DE live                         |
| 3b   | DE   | HL    | `XCHG; MOV E,M; INX H; MOV D,M; XCHG`        | optional `DCX D` if DE live (old HL was dead — it is the dst) |
| 4    | DE   | DE    | `XCHG; MOV SpareR,M; INX H; MOV H,M; MOV L,SpareR; XCHG`| if no SpareR, wrap `PUSH PSW` / `POP PSW` and use `SpareR=A` |
| 5a   | BC   | DE    | HL dead: `MOV H,B; MOV L,C; MOV E,M; INX H; MOV D,M`. HL live + A dead: `LDAX B; MOV E,A; INX B; LDAX B; MOV D,A`. HL live + A live + spare in {H,L} dead: same wrapped with `MOV S,A` / `MOV A,S`. Else: `PUSH H` wraps the M-staging form. | `DCX B` after the LDAX shape iff BC live; never needed for the M-staging form |
| 5b   | BC   | BC    | Tier 1 (HL fully dead): `MOV H,B; MOV L,C; MOV C,M; INX H; MOV B,M`. Tier 2 (A dead AND a non-{B,C} GR8 spare dead): `LDAX B; MOV S,A; INX B; LDAX B; MOV B,A; MOV C,S`. Tier 3: `PUSH H; tier-1; POP H`. | no DCX (BC is the destination) |
| 6    | BC   | HL    | Shape A (A live AND a GR8 spare excluding {HL,BC} is dead): `MOV H,B; MOV L,C; MOV S,M; INX H; MOV H,M; MOV L,S`. Shape B (otherwise): `[PUSH PSW] LDAX B; MOV L,A; INX B; LDAX B; MOV H,A [POP PSW]`. | `DCX B` after shape B iff BC live; never needed for shape A |


Notes on case 3b (`addr=DE, dst=HL`): `dst=HL` means the old HL value
is dead at the pseudo by construction. The first `XCHG` parks old HL
in DE, the inner load overwrites DE with the loaded bytes, and the
trailing `XCHG` delivers the loaded value into HL. The trailing XCHG
is mandatory — it is the delivery, not just preservation. DE
recovery via `DCX D` is needed only when the original `addr=DE`
value is live across the pseudo. No `A` is ever needed here.

Notes on case 4 (`addr=DE, dst=DE`): `dst=DE` means DE is being
redefined, so the address pair is by construction not preserved —
The inner load must use a non-HL temp because the high byte must
be sourced via `M` *after* `INX H`, while the low byte must already
have been written. Trailing XCHG places the loaded value into DE and
restores HL to its original.

SpareR selection in this case is **per-byte**, not per-pair. After
the leading `XCHG`, `HL` holds the address (so `H` and `L` are
never candidates) and `DE` physically holds the original HL bytes
(`D = H_orig`, `E = L_orig`). The trailing `XCHG` swaps `DE↔HL`
again, so whatever value sits in `D` (resp. `E`) at that moment
ends up in `H` (resp. `L`) post-load. Therefore:

- `B` is a candidate iff `B` is dead across the pseudo.
- `C` is a candidate iff `C` is dead across the pseudo.
- `D` is a candidate iff **`H`** is dead across the pseudo
  (using `D` would otherwise destroy `H_orig`).
- `E` is a candidate iff **`L`** is dead across the pseudo
  (using `E` would otherwise destroy `L_orig`).
- `H`, `L` are never candidates.

When `HL` is fully dead (e.g. tail position), `D` and `E` become valid
spares and the `PUSH PSW` fallback is avoided.

Notes on case 6 (`addr=BC, dst=HL`): two shapes compete. Shape A
(`MOV H,B; MOV L,C; MOV S,M; INX H; MOV H,M; MOV L,S`, 6B/48cc) does
not touch A and preserves BC, but burns 4 instructions on
`MOV H,B; MOV L,C; ... MOV L,S` staging. Shape B
(`LDAX B; MOV L,A; INX B; LDAX B; MOV H,A`, 5B/40cc) is shorter and
faster but clobbers A and increments BC. Cost crossover:
when A is dead, shape B is unconditionally cheaper (5B/40cc plus a
1B/8cc DCX B if BC live). When A is live and a spare exists, shape
A wins (6B/48cc with no wrap) over wrapped shape B
(`MOV S,A; LDAX B; ...; MOV A,S` = 7B/56cc + DCX). When A is live
and no spare exists, shape B with `PUSH PSW`/`POP PSW` (7B/68cc)
beats the legacy A-as-spare shape A (8B/76cc).

Notes on case 5a (`addr=BC, dst=DE`): four-way dispatch by
(HL liveness, A liveness, spare availability). The M-staging form
(`MOV H,B; MOV L,C; MOV E,M; INX H; MOV D,M`) wins whenever HL is
dead — 5B/40cc with no preservation overhead. When HL is live, the
LDAX form (5B/40cc + DCX-if-BC-live) avoids the PUSH H/POP H pair
(saving 22cc) at the cost of going through A. Spare for the cheap
`MOV S,A` wrap can only come from {H,L} (S must avoid A,B,C,D,E)
under the case-4 per-byte rule: H is candidate iff H is dead; L is
candidate iff L is dead. PUSH H / POP H around the M-staging form
remains the worst-case fallback (7B/68cc).

Notes on case 5b (`addr=BC, dst=BC`): the destination IS the
address pair, so we can never write a loaded byte into B or C
before completing both reads. The M-staging form sidesteps this by
copying BC→HL first and using the HL alias as the address pair,
freeing B and C to receive the loaded bytes. The LDAX-based tier 2
buffers the low byte in a non-{B,C} spare across `INX B` so the
second LDAX still reads from the (now incremented) original
address. No DCX BC is ever emitted since BC is intentionally
redefined.

### Why this is faster than honest pre-RA `Defs`

| Scenario                              | Pre-RA `Defs` (RA must spill / re-route)          | Expander preservation (this design)         |
|---------------------------------------|---------------------------------------------------|----------------------------------------------|
| HL load, original HL pointer live     | Copy HL→other GR16 or spill: ≥+2B/+8cc, often ~6B/+44cc when both BC and DE taken | `DCX H`: **+1B / +5cc**                      |
| `_HL_HL` load, A live                 | Spill A to memory: ~6B / ~26cc                    | Use any dead GR8: **+0B / +0cc**; else `PUSH PSW`/`POP PSW`: +2B / +23cc |
| DE load, DE pointer live              | Spill DE: ≥+2B/+8cc, often memory: ~6B/+44cc      | `DCX D`: **+1B / +5cc**                      |
| BC load, HL live                      | RA cannot rename HL (only one GR16Ptr); forced to memory: ~6B / +44cc | LDAX-based shape (`LDAX B; MOV r,A; INX B; LDAX B; MOV r,A`): **+0B / +0cc** when A dead and BC dead, +1B/+8cc DCX B when BC live, +2B/+16cc MOV-wrap when A live + spare. Worst case `PUSH H`/`POP H`: +2B / +22cc |

The expander wins in every preservation case. The reason is
structural:

- `DCX rp`-after-`INX rp` is unavailable to RA. RA operates at vreg
  granularity and cannot insert "undo the increment" code; it must
  arrange for the value to live somewhere else across the def. On a
  3-element GR16 set, "somewhere else" usually means memory.
- A dead GR8 chosen at expansion time is unavailable to RA. RA
  commits before the pseudo splits into individual ops, so it must
  reserve a worst-case clobber slot per declared `Defs` whether or
  not the particular instance needs it.


## Correctness Conditions

- Expander must compute post-RA liveness of GR8 and GR16 registers
  at the pseudo's location.
- For every register the chosen expansion would otherwise clobber
  (other than `$dst` itself), if the register is live across the
  pseudo, the expander must emit preservation code.
- Cases 1, 4 and 6 need a GR8 temp because `INX rp` can carry from
  the low byte into the high byte, so the high byte must be
  sourced after `INX` while the low byte must already be saved
  somewhere outside the address pair.
- `addr=BC` cases (5, 6) destroy HL while computing the address.
  HL preservation in case 5 requires `PUSH H`/`POP H`.
- The `DCX` recovery is conditioned on the *address-pair* being
  live after the pseudo, **and** on the destination not already
  redefining that pair. Specifically: case 2 conditions on "HL
  live"; case 3 (a/b) conditions on "DE live";
- Case 4 SpareR selection is per-byte: `D` is safe iff `H` is dead;
  `E` is safe iff `L` is dead; `B`/`C` use their own liveness;
  `H`/`L` are never safe.

## Implementation Sketch

In `V6ClangInstrInfo::expandPostRAPseudo` for `V6CLANG::V6CLANG_LOAD16_P`:

1. Read `DstReg`, `AddrReg`, then their lo/hi sub-regs.
2. Compute `AddrPairLiveAfter` and `HLLiveAfter` using the existing
   `isRegDeadAtMI` helper (or a lightweight forward scan inside the
   block) for the relevant GR16s.
3. For shapes that need a GR8 temp (cases 1, 4, 6), find a dead GR8
   at the pseudo by scanning live regs at MI. If none, set
   `SpareR = A` and remember to wrap `PUSH PSW; POP PSW` only if
   `A` is itself live.
4. Emit the body for the matched `(AddrReg, DstReg)` row from the
   table.
5. Emit the conditional preservation code (`DCX rp`,
   `PUSH H`/`POP H`, `PUSH PSW`/`POP PSW`) per the table's
   "preservation knobs" column.
6. Erase the pseudo.

A small helper, e.g. `findDeadGR8AtMI(MI, MBB, &RI)`, is the only
new machinery required.

## Expected Effects

- Bug 1 fixed: `addr=HL, dst=HL` no longer leaks `A` because the
  expander uses a dead GR8 (or wraps with `PUSH PSW`).
- Bug 2 fixed: `addr=HL, dst∈{BC,DE}` now emits `DCX H` whenever HL
  is live across the pseudo.
- Bug 3 fixed: `addr=DE, dst=DE` is implemented via the case-4 row,
  not the broken `MOV E,M; …; MOV D,M; XCHG` pattern.
- Bug 4 fixed: `addr=BC, *` honours HL liveness — case 5a falls
  back to `PUSH H`/`POP H` when HL is live and no cheaper LDAX-shape
  variant is applicable; case 5b uses tier 3's `PUSH H` wrap; case 6
  never needs HL preservation (HL is the dst).
- Bug 5 fixed: `addr=BC, dst=HL` uses a dead GR8 (shape A), the
  cheap LDAX shape (shape B with A dead), or `PUSH PSW`/`POP PSW`
  (shape B with A live and no spare) instead of silently clobbering
  `A`.
- Pressure unchanged in the common path. RA continues to see
  `V6CLANG_LOAD16_P` as preserving everything except `$dst`, so it
  does not insert spills around pointer loads.

## Tests

- Lit test exercising each row of the table, with both
  "address-pair live after" and "address-pair dead after"
  variants. Verify the expected asm: `DCX rp` present iff pointer
  live, `PUSH H`/`POP H` present iff case 5/6 with HL live,
  `PUSH PSW`/`POP PSW` present iff GR8 spare unavailable and `A`
  live.
- Regression test for bug 3 derived from
  `temp\asm_inline\custom_cc.c`: `DAD B; <16-bit load via DE
  pointer to DE>; DAD D` must compute `sum + loaded`, not
  `loaded + (ptr + 1)`.
- Regression test for bug 1: a value live in `A` across an
  `addr=HL, dst=HL` load must be preserved.
- Regression test for bug 2: the original pointer in HL must be
  recoverable across an `addr=HL, dst=BC` load.
- Regression test for bug 5: a value live in `A` across an
  `addr=BC, dst=HL` load must be preserved.
- End-to-end runtime guard: `temp\asm_inline\custom_cc.c`.

## Risk

Low-medium. The change is local to the post-RA expansion of one
pseudo plus a small `findDeadGR8AtMI` helper. The pseudo's td
declaration does not change, so isel patterns and pre-RA passes are
untouched. Main risk is missing a live-reg case in the
preservation logic — guarded by per-shape lit and runtime tests.

## Dependencies

- Existing `V6CLANG_LOAD16_P` post-RA expansion entry point.
- Existing `isRegDeadAtMI` helper from O42.
- New `findDeadGR8AtMI` helper (this plan).

## Out of Scope

The nominal preservation overhead is paid only on *unbroken
chains*. Two existing or planned peepholes cancel it when chains
are unbroken:

- **`XCHG; XCHG` cancellation.** Two adjacent `XCHG` instructions
  are identity. When two `addr=DE` loads abut, the trailing `XCHG`
  of the first cancels the leading `XCHG` of the second.
- **`DCX rp; INX rp` cancellation.** `DCX rp` immediately before
  `INX rp` on the same pair is identity. When an address is loaded
  and immediately re-incremented (e.g. struct field walks), the
  preservation `DCX` of the first load cancels the next walker
  step.
- `V6CLANG_STORE16_P` redesign. Same structural problem, parallel fix.
- `V6CLANG_LOAD16_G` / `V6CLANG_STORE16_G` global-address variants. Same
  shape-conflation pattern, follow-up.