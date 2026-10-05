# V6CLANG_STORE16_P Design Redesign

`V6CLANG_STORE16_P` is the generic 16-bit store-through-pointer pseudo:

## Problem

It has a problem - a single blanket `Defs = [HL, A]` that is over-declared in
several shapes. One coarse `Defs` set cannot simultaneously be
truthful and tight across 9 different code shapes. The fix is to drop `Defs`
entirely, and have the post-RA expander emit truthful preservation per shape
using the cheapest mechanism available at the expansion site (`SpareR`, `DCX rp`,
`XCHG`, or `PUSH`/`POP`).

## Full picture of `V6CLANG_STORE16_P` today

### TableGen declaration

```tablegen
let mayStore = 1, Defs = [HL, A] in
def V6CLANG_STORE16_P : V6ClangPseudo<(outs), (ins GR16:$val, GR16:$addr),
    "# STORE16P $val, ($addr)",
    [(store i16:$val, i16:$addr)]>;
```

- Two GR16 inputs: `$val`, `$addr`. Each is independently in `{HL, BC, DE}`,
  giving 9 shapes total.
- `Defs = [HL, A]` is a coarse blanket that over-declares: most val≠HL
  shapes never touch `A`, and `val=HL, addr ∈ {BC, DE}` shapes never
  touch `HL`.
- No `FLAGS` in `Defs`; none of the shapes touch flags, which is correct.

### Current expander structure (`V6ClangInstrInfo.cpp::expandPostRAPseudo`)

```
if val == HL:
    if addr == HL:        MOV A,H; MOV M,L; INX H; MOV M,A
    elif addr == DE:      [PUSH D];  MOV A,L; STAX D; INX D; MOV A,H; STAX D; [POP D]
    elif addr == BC:      [PUSH B];  MOV A,L; STAX B; INX B; MOV A,H; STAX B; [POP B]
                          (PUSH/POP elided when addr-pair is dead at MI — O42)
else  # val ∈ {BC, DE}
    if addr != HL:        MOV H,addrHi; MOV L,addrLo
    MOV M,valLo; INX H; MOV M,valHi
```

### Per-shape expansion table (current behaviour vs. truthful clobbers)

| #  | addr| val | current expansion | declared `Defs` | actual clobbers | over / under-decl |
|----|-----|------|-------------------|-----------------|-----------------|-------------------|
| 1  | HL  | HL   | `MOV A,H; MOV M,L; INX H; MOV M,A`  | HL, A    | A; HL = orig+1 | exact |
| 2  | HL  | DE   | `MOV M,E; INX H; MOV M,D` | HL, A | HL = orig+1; A preserved | over: A |
| 3  | HL  | BC   | `MOV M,C; INX H; MOV M,B`  | HL, A | HL = orig+1; A preserved | over: A |
| 4  | DE  | HL   | `[PUSH D]; MOV A,L; STAX D; INX D; MOV A,H; STAX D; [POP D]` | HL, A | A; HL preserved; DE preserved (PUSH/POP elided iff DE dead) | over: HL |
| 5  | DE  | DE   | `MOV H,D; MOV L,E; MOV M,E; INX H; MOV M,D` | HL, A | HL fully overwritten; A preserved | over: A |
| 6  | DE  | BC   | `MOV H,D; MOV L,E; MOV M,C; INX H; MOV M,B` | HL, A | HL fully overwritten; A preserved | over: A |
| 7  | BC  | HL   | `[PUSH B]; MOV A,L; STAX B; INX B; MOV A,H; STAX B; [POP B]` | HL, A | A; HL preserved; BC preserved (PUSH/POP elided iff BC dead) | over: HL |
| 8  | BC  | DE   | `MOV H,B; MOV L,C; MOV M,E; INX H; MOV M,D` | HL, A | HL fully overwritten; A preserved | over: A |
| 9  | BC  | BC   | `MOV H,B; MOV L,C; MOV M,C; INX H; MOV M,B` | HL, A | HL fully overwritten; A preserved | over: A |

Notes:
- Cases 2, 3, 5, 6, 8, 9 never write `A`, but the blanket `Defs=[HL,A]`
  forces RA to treat `A` as clobbered across **every** 16-bit pointer
  store. On a 1-element pressure class this is the single most expensive
  part of the current declaration.
- Cases 5, 6, 8, 9 fully overwrite HL (both bytes via `MOV H,addrHi;
  MOV L,addrLo`), so DCX-recovery is impossible — these are the only
  cases where HL truly cannot be cheaply recovered without
  PUSH/POP HL.
- Cases 2 and 3 mutate HL only via `INX H`, so a single `DCX H`
  recovers the original pointer cheaply (1B / 5cc).
- Cases 4 and 7 mutate DE/BC only via `INX D`/`INX B`, so a single
  `DCX D`/`DCX B` recovers the address pair cheaply — strictly
  better than the current `PUSH/POP` (1B/5cc vs 2B/22–23cc).
- Cases 1, 4, 7 use `A` as the high-byte staging register. In case 1
  this is just to get past the `INX H` carry; any dead GR8 works
  (mirrors O71 case 1). In cases 4 and 7 `A` is **mandatory**: `STAX rp`
  only accepts `A` as the source register. There is no GR8-spare
  substitution available for cases 4 and 7.

### Proposed truthful clobber model (mirror of O71)

Drop `Defs` from the pseudo entirely; have the expander emit
preservation in cheap-first order. The `addr` register selects the
preservation strategy (`XCHG` for DE, `STAX` or `PUSH H`/`POP H`
for BC, nothing for HL); `val` only affects details inside that
strategy.

`SpareR` denotes a GR8 dead at the pseudo location; `A` is the
fallback if no GR8 spare is available, with `PUSH PSW`/`POP PSW`
wrap if `A` is also live.

| # | addr | val   | expansion | preservation knobs |
|-|---|---|-----------------------------------|--------------------------|
| 1 | HL | HL    | `MOV SpareR,H; MOV M,L; INX H; MOV M,SpareR` | if no SpareR, wrap `PUSH PSW`/`POP PSW` and use `SpareR=A`; emit `DCX H` if HL live after |
| 2 | HL | BC/DE | `MOV M,lo; INX H; MOV M,hi`                  | emit `DCX H` if HL live after |
| 3 | DE | HL/BC | `XCHG; MOV M,lo; INX H; MOV M,hi; XCHG`      | emit `DCX D` if DE live after |
| 4 | DE | DE    | `XCHG; MOV SpareR,H; MOV M,L; INX H; MOV M,SpareR; XCHG` | per-byte SpareR (see notes); if no SpareR, wrap inner body in `PUSH PSW`/`POP PSW` and use `SpareR=A`; emit `DCX D` if DE live after |
| 5 | BC | HL/DE | `MOV A,lo; STAX B; INX B; MOV A,hi; STAX B`    | preserve `A` if live: prefer `MOV SpareR,A; <body>; MOV A,SpareR`, else wrap `PUSH PSW`/`POP PSW`. Emit `DCX B` if BC live after. |
| 6 | BC | BC    | if HL dead: `MOV H,B; MOV L,C; MOV M,C; INX H; MOV M,B` (5B/40cc); else if SpareR: `MOV SpareR,A; MOV A,C; STAX B; INX B; MOV A,B; STAX B; MOV A,SpareR` (7B/56cc); else wrap `PUSH H` / `POP H` (7B/68cc) | emit `DCX B` if BC live after |


#### Notes on case 1 (`addr=HL, val=HL`)

`INX H` can carry from `L` into `H`, so the high byte of the value
must be parked in a GR8 before `INX H`. Any GR8 dead at the pseudo
works; `H` and `L` are not candidates because both halves are live
across the relevant window.

#### Notes on case 3 (`addr=DE, val ∈ {HL, BC}`) — major win vs. today

The current expander uses `STAX D` for `val=HL` and clobbers `A`.
The XCHG path preserves both `A` and `HL`:

```
XCHG          ; HL=address, DE=value (or HL=address, DE=DE-orig if val=BC)
MOV M,lo      ; mem[address]   = lo(value)
INX H         ; HL = address+1
MOV M,hi      ; mem[address+1] = hi(value)
XCHG          ; HL restored, DE = address+1
[DCX D]       ; only if DE live after — recovers DE = address
```

5B / 32cc + opt `DCX D` (1B/8cc) — vs current `STAX D` path (7–9B and
`A` clobber) for `val=HL`, and current `MOV H,D; MOV L,E; ...` path
(5B / 40cc but unconditional HL clobber) for `val=BC`.

#### Notes on case 4 (`addr=DE, val=DE`)

Same structure as case 1 but wrapped in `XCHG`/`XCHG`. The leading
`XCHG` parks original `HL` in `DE`, the body stores the value
(which is now in `HL` after the swap), and the trailing `XCHG`
restores both pairs. A GR8 temp is needed because `INX H` can
carry from L into H.

`SpareR` selection mirrors O71 case 4 (per-byte, not per-pair):
after the leading `XCHG`, `HL` holds the address (so `H`, `L` are
never candidates), and `DE` physically holds the original `HL`
bytes that the trailing `XCHG` will restore. Therefore:

- `B` is a candidate iff `B` is dead across the pseudo.
- `C` is a candidate iff `C` is dead across the pseudo.
- `D` is a candidate iff **`H`** is dead across the pseudo
  (using `D` would otherwise destroy `H_orig`).
- `E` is a candidate iff **`L`** is dead across the pseudo
  (using `E` would otherwise destroy `L_orig`).
- `A` is a candidate iff `A` is dead across the pseudo.
- `H`, `L` are never candidates.

When no SpareR is available, fall back to `SpareR=A` wrapped in
`PUSH PSW`/`POP PSW` (inside the XCHG pair). The same FLAGS-dead
trick from case 1 is unavailable for the same reason.

#### Notes on cases 5 and 6 (`addr=BC`)

No XCHG-equivalent for BC, so HL must either be left untouched
(`val=HL`, via `STAX B`) or used as scratch and restored
(`val=BC/DE`, via `MOV H,B; MOV L,C` + body). Both subcases share
the same cheap-first preservation policy: use a GR8 spare when
available, otherwise PUSH/POP.

**Case 5 (`val ∈ {HL, DE}`).** `STAX rp` only accepts `A` as
source, so `A` is mandatory. When `A` is live across the pseudo:

1. **GR8 spare available** — save `A` into a dead GR8:

   ```
   MOV SpareR,A          ; 8cc
   MOV A,lo; STAX B; INX B; MOV A,hi; STAX B   ; body, 40cc
   MOV A,SpareR          ; 8cc
   ```

   Total 7B / 56cc. Candidates: any GR8 dead across the pseudo,
   except `H` and `L` when `val=HL` (the body reads both halves
   of HL, so the save target must survive the body unchanged);
   for `val=DE` the candidate set excludes `D` and `E` for the
   same reason.

2. **No GR8 spare** — wrap the body in `PUSH PSW`/`POP PSW`:

   ```
   PUSH PSW              ; 16cc
   <body>                ; 40cc
   POP PSW               ; 12cc
   ```

   Total 7B / 68cc — 12cc more expensive than the SpareR path,
   same byte count.

A would-be XCHG alternative — `XCHG; MOV H,B; MOV L,C; MOV M,E;
INX H; MOV M,D; XCHG` — preserves `A` but trades it for an
unconditional DE clobber. For most inputs the `STAX` path (5B /
40cc + optional `DCX B` / SpareR / `PUSH PSW`) is cheaper than the
XCHG-via-DE path (7B / 48cc + the same opt knobs + DE preservation
if DE live).

**Case 6 (`val=BC`).** Strategy depends on whether `HL` is live
across the pseudo. Three sub-cases ordered cheap-first:

1. **HL dead at the pseudo** — use HL as scratch and don't
   bother restoring:

   ```
   MOV H,B; MOV L,C; MOV M,C; INX H; MOV M,B   ; 40cc
   ```

   Total 5B / 40cc. This is the cheapest shape and the typical
   case after RA has scheduled HL away.

2. **HL live, GR8 spare available** — switch to the case-5 STAX
   body (which never touches HL) and save `A` into the spare:

   ```
   MOV SpareR,A                                ; 8cc
   MOV A,C; STAX B; INX B; MOV A,B; STAX B     ; body, 40cc
   MOV A,SpareR                                ; 8cc
   ```

   Total 7B / 56cc. Candidates: any GR8 dead across the pseudo;
   `B` and `C` are excluded (the body reads both halves of BC).

3. **HL live, no GR8 spare** — wrap the scratch body in
   `PUSH H`/`POP H`:

   ```
   PUSH H                                         ; 16cc
   MOV H,B; MOV L,C; MOV M,C; INX H; MOV M,B      ; 40cc
   POP H                                          ; 12cc
   ```

   Total 7B / 68cc — same cost as wrapping the STAX body in
   `PUSH PSW`/`POP PSW`, picked here because the scratch body is
   strictly simpler and avoids the `A` shuffle.

### Key wins vs. today

- **`A` preserved on every shape except case 5** (`addr=BC,
  val=HL`), which unconditionally clobbers `A` because `STAX rp`
  only accepts `A`. Cases 1 and 4 preserve `A` on the common
  SpareR path and only touch it in the no-spare fallback. RA no
  longer spills `A` across pointer stores in the common case.
- **`HL` preserved on cases 3, 4, 5** — the `addr ∈ {BC, DE}`
  shapes either never touch HL (`STAX` for case 5) or recover it
  via XCHG (cases 3, 4).
- **`DCX D`/`DCX B` replaces `PUSH/POP D`/`PUSH/POP B`** in cases
  3, 4, 5, 6 whenever the address pair is live (1B/8cc vs
  2B/28cc).
- **`PUSH H`/`POP H` is needed only on case 6** when HL is live
  *and* no GR8 spare is available — the only shape where HL is
  unavoidably scratched and there is no `A`-preserving STAX
  detour.