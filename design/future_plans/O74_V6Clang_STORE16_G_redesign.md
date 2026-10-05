# O74: V6CLANG_STORE16_G Redesign

## Status

Planned. Companion to
[O73_V6CLANG_LOAD16_G_redesign.md](O73_V6CLANG_LOAD16_G_redesign.md) (which
covers the global-address load). This plan covers the
global-address (immediate-address) **store** variant. Mirrors the
relationship of [O72](O72_V6CLANG_STORE16_P_redesign.md) to
[O71](O71_V6CLANG_LOAD16_P_redesign.md) for the through-pointer pseudos.

## Background

`V6CLANG_STORE16_G` is the 16-bit store-to-global-address pseudo:

```tablegen
let mayStore = 1, Defs = [HL] in
def V6CLANG_STORE16_G : V6ClangPseudo<(outs), (ins GR16:$val, imm16:$addr),
    "# STORE16G $val, $addr", []>;
```

The pseudo declares a **blanket `Defs = [HL]`**. The intent of the
declaration was to model the worst-case shape (val ∈ {DE, BC},
where the current expander uses `LXI H, addr; MOV M, lo; INX H;
MOV M, hi` and unconditionally clobbers HL). The `val=HL` shape
emits `SHLD addr` and never touches anything other than memory,
yet the pseudo still claims to clobber HL — forcing RA to spill
HL across every `V6CLANG_STORE16_G` even when the value to store was
already conveniently in HL.

The current expander (`V6ClangInstrInfo.cpp::expandPostRAPseudo`,
`case V6CLANG::V6CLANG_STORE16_G:`, ~line 1968) has two arms:

| val   | Current expansion                                             | Bytes / Cycles |
|-------|---------------------------------------------------------------|----------------|
| HL    | `SHLD addr`                                                   | 3B / 20cc      |
| DE/BC | `LXI H, addr; MOV M, lo; INX H; MOV M, hi`                    | 5B / 36cc      |

Cycle counts use the V6CLANG-specific timings from
[`docs/Vector_06c_instruction_timings.md`](../../docs/Vector_06c_instruction_timings.md):
`SHLD`=20cc, `LXI`=12cc, `MOV M,r`=8cc, `INX`=8cc, `MOV r,r`=8cc,
`STA`=16cc, `XCHG`=4cc, `PUSH`=16cc, `POP`=12cc.

Two structural problems with the current declaration / expander:

1. **`Defs = [HL]` is a lie for the `val=HL` shape.** `SHLD addr`
   reads HL and writes only memory; HL survives. The blanket
   declaration forces unnecessary HL preservation by RA whenever
   the value to store lands in HL (the most common shape today,
   since the existing isel pattern feeds `SHLD` directly — see
   below).
2. **The `val=DE/BC` arm is one-size-fits-all.** It always
   materialises HL with `LXI` and walks it via `INX`, even when
   the value is in DE (where a single `XCHG` round-trip is much
   cheaper than `LXI; MOV M; INX H; MOV M`) and even when HL is
   dead (so the round-trip's restoring `XCHG` can be elided).
   For `val=BC` it never considers the cheaper `STA addr; STA
   addr+1` shape that does not touch HL at all when `A` is dead.

### Current isel landscape

Today the isel pattern in `V6ClangInstrInfo.td:912` for stores to a
global goes through `SHLD` directly (with the `(store i16, ...)`
pattern), not through `V6CLANG_STORE16_G`:

```tablegen
def : Pat<(store i16:$val, (V6Clangwrapper tglobaladdr:$addr)),
          (SHLD i16:$val, tglobaladdr:$addr)>;
```

`SHLD` is `GR16Ptr` (HL-only) on the destination side — the
register allocator must always materialise the value in HL,
even when DE or BC already holds it, which costs a copy or
swap.  This redesign **also** repoints the isel pattern to
`V6CLANG_STORE16_G` (mirroring how the load side switched from
`LHLD` to `V6CLANG_LOAD16_G` in O73's predecessor) so that the
register allocator can leave the value in DE or BC when that is
strictly cheaper than forcing a materialisation in HL — and the
new per-shape expander emits the appropriate cheap-first
sequence.

## Problem

Two distinct issues:

1. **Over-declared `Defs`.** `V6CLANG_STORE16_G` claims to clobber
   `HL` for every shape, but the `val=HL` shape preserves HL.
   Pre-RA passes (RA, scheduler, IPRA) see a stricter clobber set
   than the actual lowering, leading to unnecessary HL spills
   around `val=HL` stores.
2. **Single-shape `val=DE/BC` expander.** The expander emits the
   same `LXI; MOV M; INX H; MOV M` sequence regardless of which
   non-HL register holds the value or whether HL or A is dead at
   the pseudo's location. Cheaper alternatives exist:
   - `val=DE` with HL dead: `XCHG; SHLD addr` (4B / 24cc) vs the
     current 5B / 36cc — saves 12cc, **−1B**.
   - `val=DE` with HL live: `XCHG; SHLD addr; XCHG` (5B / 28cc)
     vs the current 5B / 36cc — saves 8cc at no byte cost.
   - `val=BC` with HL dead: `MOV H,B; MOV L,C; SHLD addr` (5B /
     36cc, same byte / cycle as today) — but leaves H/L holding
     the value, occasionally enabling later peepholes; structural
     parity, included for table completeness.
   - `val=BC` with HL live, A dead: `MOV A, C; STA addr; MOV A,
     B; STA addr+1` (8B / 48cc) vs the current 5B / 36cc —
     **slower** in isolation. NOT a useful substitute when HL is
     just live; only useful when HL **must be preserved** (live
     across the pseudo). The relevant comparison is therefore
     against the HL-preserving shape:
     `PUSH H; LXI; MOV M; INX H; MOV M; POP H` (7B / 64cc) vs
     `MOV A,C; STA; MOV A,B; STA addr+1` (8B / 48cc) — saves
     16cc at +1B.
   - `val=BC` with HL live and A live: `PUSH H; MOV H,B; MOV L,C;
     SHLD addr; POP H` (7B / 64cc) — universal fallback.

The structural reason this belongs in the expander (not in
multiple pseudos or in `Defs`) is identical to O71/O73's:
register pressure on HL and A means RA cannot selectively spill
either per-instance; declaring `Defs = [HL, A]` would force
`A` spills on every store even on the `val=HL` shape that does
not touch `A` at all.

## Solution

Drop `Defs = [HL]` from the pseudo (declare **no `Defs`**), and
extend the post-RA expander to pick a cheapest-first shape for
each `val` register class based on observable liveness of `HL`
and `A` at the pseudo's location.

Also repoint the isel pattern from `(SHLD ...)` to
`(V6CLANG_STORE16_G ...)` so the register allocator can leave the
value in DE or BC when that is the cheaper outcome.

### Design rules

1. **No `Defs`.** The pseudo defines nothing visible; it stores
   `$val` to `$addr`. Pre-RA passes see the store as preserving
   every register. This matches the actual post-expansion
   behaviour in every shape of the new expander (each shape
   either does not touch HL/A, or saves and restores them).

2. **Honest preservation in the expander.** After RA, the
   expander computes post-RA liveness for `HL` and `A` at the
   pseudo's location. For each register the chosen shape would
   otherwise clobber and that is live across the pseudo, the
   expander emits the cheapest available recovery (`XCHG` round
   trip for DE-style; `PUSH H`/`POP H` for the BC universal
   fallback).

3. **Cheapest-first dispatch by `val` register class.**
   - `val=HL`: always `SHLD addr` (no preservation needed).
   - `val=DE`:
     1. `HL` dead → `XCHG; SHLD addr`.
     2. else     → `XCHG; SHLD addr; XCHG`.
   - `val=BC`:
     1. `HL` dead → `MOV H,B; MOV L,C; SHLD addr`.
     2. else `A` dead → `MOV A,C; STA addr; MOV A,B; STA addr+1`.
     3. else     → `PUSH H; MOV H,B; MOV L,C; SHLD addr; POP H`.

### Per-shape expansion table

|# |val|Predicate         |Expansion                                   |Bts/CCs|
|--|--|-------------------|--------------------------------------------|-------|
|1 |HL|(always)           |`SHLD addr`                                 |3B/20cc|
|2a|DE|`HL` dead at pseudo|`XCHG; SHLD addr`                           |4B/24cc|
|2b|DE|otherwise          |`XCHG; SHLD addr; XCHG`                     |5B/28cc|
|3a|BC|`HL` dead at pseudo|`MOV H,B; MOV L,C; SHLD addr`               |5B/36cc|
|3b|BC|`HL` live, `A` dead|`MOV A,C; STA addr; MOV A,B; STA addr+1`    |8B/48cc|
|3c|BC|`HL` live, `A` live|`PUSH H; MOV H,B; MOV L,C; SHLD addr; POP H`|7B/64cc|

Comparison vs the current expander:

|# |val| Current shape (cc/B)          | New shape (cc/B)        | Δ        |
|--|--|--------------------------------|-------------------------|----------|
|1 |HL|`SHLD` 20cc/3B                  | `SHLD` 20cc/3B          | 0 / 0    |
|2a|DE|`LXI;MOV;INX;MOV` 36cc/5B       | `XCHG;SHLD` 24cc/4B     | −12 / −1 |
|2b|DE|`LXI;MOV;INX;MOV` 36cc/5B       | `XCHG;SHLD;XCHG` 28cc/5B| −8 / 0   |
|3a|BC|`LXI;MOV;INX;MOV` 36cc/5B       | `MOV H,B;MOV L,C;SHLD` 36cc/5B | 0 / 0 |
|3b|BC|`LXI;MOV;INX;MOV` 36cc/5B (incorrect — HL clobbered) | `MOV A,C;STA;MOV A,B;STA+1` 48cc/8B | preserves HL; useful as alternative to 3c when A dead |
|3c| BC  | (today: clobbers HL — RA forced to spill HL to honour `Defs=[HL]`) | `PUSH H;…;POP H` 64cc/7B | honest preservation |

Rows 3a/3b/3c are *additions*: today the expander does not even
attempt HL preservation for `val=BC`, because `Defs = [HL]`
delegates that to RA (which spills HL across the store).
Dropping `Defs` and adding the dispatch turns those RA-driven
spills into in-place preservation that is **strictly cheaper**
than the typical RA-emitted spill/reload pair (`SHLD slot;
LHLD slot` = 40cc + frame slot, or static-stack equivalent).

### Dispatch precedence (`val=BC`)

```
if HL is dead at MI:
    use case 3a  # 5B / 36cc, never touches A
elif A is dead at MI:
    use case 3b  # 8B / 48cc, never touches HL
else:
    use case 3c  # 7B / 64cc, preserves HL via PUSH/POP
```

Case 3a is preferred over 3b when HL is dead even if A is also
dead: 3a is shorter (5B vs 8B) and faster (36cc vs 48cc).

### Why cycle-cheapest is also pressure-correct

| Case | Touches HL?               | Touches A?    |
|------|---------------------------|---------------|
| 1    | no (reads only)           | no            |
| 2a   | yes (overwrites; HL dead) | no            |
| 2b   | no (XCHG round-trip)      | no            |
| 3a   | yes (overwrites; HL dead) | no            |
| 3b   | no                        | yes (A dead)  |
| 3c   | yes, restored             | no            |

Each shape is selected only when its clobber set is provably
empty (register dead at MI) or recoverable (PUSH/POP). The
pseudo's declared "no Defs" remains truthful in every dispatch
outcome.

## Correctness Conditions

- Expander must compute post-RA liveness of `HL` and `A` at the
  pseudo's location using `isRegDeadAtMI` (the same helper used
  by O42, O71, O72, and O73).
- The two `STA` operands in case 3b are `addr` and `addr+1`. For
  a `tglobaladdr` operand, `addr+1` is encoded as `MachineOperand`
  with the same `GlobalValue` and an offset incremented by 1. For
  an `MCSymbol`/`imm` operand, the second `STA` carries the
  numerically-incremented immediate (or a symbol-plus-1 expression
  via `MCSymbolRefExpr` when the operand is a symbol reference).
  Reuse the helper used by O73 for the analogous LDA pair (refactor
  into a shared `cloneAddrOpPlus(AddrOp, 1)`).
- Case 3b never executes when `A` is live across the pseudo, so
  no preservation of `A` is ever required.
- Case 2a (`XCHG; SHLD`) ends with HL holding the stored value
  and DE holding the original HL contents. Because HL is dead by
  predicate, leaving it dirty is fine. DE now holds the original
  HL contents; the original DE value (the `$val`) is consumed by
  the store and is not required to survive (`$val` is an `ins`
  operand without `kill` semantics, but the store's data-flow
  contract treats it as consumed).
- Case 3c's `MOV H,B; MOV L,C` after `PUSH H` is safe because
  `PUSH H` reads HL (the live value) and pushes it; the
  subsequent `MOV` overwrites a dead HL. `POP H` restores it.
- Repointing the isel pattern from `SHLD` to `V6CLANG_STORE16_G`
  means the register allocator may now choose DE or BC for the
  value register. The new expander handles all three classes
  faithfully, so no shape regresses; cases 2a/2b/3a improve over
  the historical "force into HL" outcome.

## Implementation Sketch

In `V6ClangInstrInfo::expandPostRAPseudo` for `V6CLANG::V6CLANG_STORE16_G`:

1. Read `ValReg`, `AddrOp`. Compute `ValLo`, `ValHi`.
2. If `ValReg == V6CLANG::HL`: emit `SHLD addr` and erase. (Unchanged
   from today.)
3. Else if `ValReg == V6CLANG::DE`:
   - `HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI)`.
   - Emit `XCHG`.
   - Emit `SHLD addr`.
   - If `!HLDead`: emit trailing `XCHG`.
4. Else (`ValReg == V6CLANG::BC`):
   - `HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI)`.
   - `ADead  = isRegDeadAtMI(V6CLANG::A,  MI, MBB, &RI)`.
   - **HLDead:** `MOV H,B; MOV L,C; SHLD addr`.
   - **else ADead:** `MOV A,C; STA addr; MOV A,B; STA addr+1`,
     where the second `STA` uses `cloneAddrOpPlus(AddrOp, 1)`.
   - **else:** `PUSH H; MOV H,B; MOV L,C; SHLD addr; POP H`.
5. Erase the pseudo.

`val=HL` arm is unchanged.

`.td` changes:
- `V6ClangInstrInfo.td:898`: drop `Defs = [HL]` from the
  `let mayStore = 1, Defs = [HL] in` wrapper around
  `V6CLANG_STORE16_G` — keep only `let mayStore = 1 in`.
- `V6ClangInstrInfo.td:912`: replace the `(SHLD ...)` selection
  pattern with `(V6CLANG_STORE16_G ...)`:
  ```tablegen
  def : Pat<(store i16:$val, (V6Clangwrapper tglobaladdr:$addr)),
            (V6CLANG_STORE16_G i16:$val, tglobaladdr:$addr)>;
  ```

## Expected Effects

- **`val=DE` becomes 8–12cc cheaper.** Functions that store a
  16-bit DE-resident value to a global drop from 36cc/5B to
  28cc/5B (HL live) or 24cc/4B (HL dead). With the isel
  repointing, RA can now actively choose DE for the value
  register, which is occasionally one fewer copy than forcing
  HL — additional implicit savings.
- **`val=BC` honest preservation.** Today the `Defs=[HL]`
  forces RA to spill HL across the store; the new in-place
  preservation (PUSH/POP HL or LDA-pair) is strictly cheaper
  than the typical RA spill (40cc + frame slot vs 28cc /
  16cc). With `A` dead, the LDA-pair path saves another 16cc.
- **`val=HL` no longer over-declared.** Dropping `Defs=[HL]`
  removes the false HL-clobber claim from the `val=HL` shape;
  RA is free to keep the same HL value alive across the
  store. This will eliminate trivial spill/reload pairs around
  back-to-back `SHLD addr; …use HL…` patterns.
- **Pressure unchanged.** RA continues to see `V6CLANG_STORE16_G`
  as preserving everything (the new no-`Defs` declaration), so
  it does not insert spills around the store.

## Tests

- Lit test exercising each row of the dispatch table:
  - `val=HL` (case 1).
  - `val=DE, HL dead` (case 2a) — verify `XCHG` then `SHLD`,
    no trailing `XCHG`.
  - `val=DE, HL live` (case 2b) — verify `XCHG; SHLD; XCHG`.
  - `val=BC, HL dead` (case 3a) — verify `MOV H,B; MOV L,C;
    SHLD`.
  - `val=BC, HL live, A dead` (case 3b) — verify two `STA` with
    the second carrying offset `+1`, and no `PUSH H`.
  - `val=BC, HL live, A live` (case 3c) — verify `PUSH H; …;
    POP H` wrap.
- Regression test: a value in `HL` live across `V6CLANG_STORE16_G`
  with `val=HL` must not be spilled — confirm no `SHLD slot;
  LHLD slot` pair is emitted around the store.
- Regression test: a value in `A` live across
  `V6CLANG_STORE16_G` with `val=BC` (case 3c) must survive —
  confirm no `STA` is emitted (PUSH/POP HL path is taken).
- Regression test: the global pointer store must write the
  correct two bytes regardless of dispatch outcome (golden
  test with the same C source, verifying byte-level
  equivalence across all three BC dispatch paths and the
  two DE paths).
- Add `tests/features/56/v6clang.c` (or next free feature
  slot) exercising the same shape matrix as
  `tests/features/55/` does for O73, but for stores.

## Risk

Low–moderate. Changes are local to one `case` arm in
`expandPostRAPseudo`, plus a one-line `.td` declaration tweak
and a one-line isel pattern repoint. The main risks are:

1. **Symbol-plus-1 operand construction for case 3b** — already
   solved by O73 for `LDA addr+1`; the same helper covers
   `STA addr+1`.
2. **Isel pattern repoint changes RA decisions globally for
   16-bit global stores** — RA may now select DE/BC where it
   previously was forced into HL via `SHLD`. The new expander
   handles all three shapes, so no shape regresses. Net effect
   is at worst neutral and at best a 0–12cc speedup per store
   from one fewer i16 copy to materialise into HL. Run the
   regression suite and lit before declaring victory.
3. **Existing lit tests pin the old `LXI; MOV M; INX H; MOV M`
   shape for non-HL stores** — update affected lit tests to
   the new shapes. For tests where the assertion was
   incidental to a different feature, prefer relaxing the
   CHECK to accept either shape.

## Dependencies

- Existing `V6CLANG_STORE16_G` post-RA expansion entry point in
  [`V6ClangInstrInfo.cpp`](../../llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp)
  (around line 1968).
- Existing `isRegDeadAtMI` helper from O42.
- Address-operand-plus-1 helper introduced for O73's case 3b
  (`cloneAddrOpPlus`).

## Out of Scope

- Sequential `V6CLANG_STORE16_G` peepholes (e.g. two adjacent
  global stores at `addr` / `addr+2` reusing a single
  HL-walk via `SHLD addr; LXI H, val2; SHLD addr+2`, or two
  STA-pair stores sharing an A-resident value). The unified
  per-shape table here is a prerequisite, but each peephole
  is a separate plan.
- `dst=BC` LDA-pair sharing across adjacent loads (tracked in
  O73 future enhancements).
