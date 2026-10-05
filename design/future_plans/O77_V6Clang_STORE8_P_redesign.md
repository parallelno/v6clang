# O77 — V6CLANG_STORE8_P Per-Shape Redesign

`V6CLANG_STORE8_P` is the generic 8-bit store-through-pointer pseudo, the
companion of `V6CLANG_LOAD8_P` (O76):

```tablegen
let mayStore = 1 in
def V6CLANG_STORE8_P : V6ClangPseudo<(outs), (ins GR8:$src, GR16:$addr),
    "# STORE8P ($addr), $src",
    [(store i8:$src, i16:$addr)]>;
```

- One `GR16` input `$addr` ∈ {HL, BC, DE}.
- One `GR8` input `$src` ∈ {A, B, C, D, E, H, L}.
- No declared `Defs` (already correct per O20 / honest-clobber model).

The current expander has 4 priorities and is correct and `HL`-preserving on
every path. Like O76, **it leaves cycles on the table on the most expensive
shape** (`addr ∈ {BC, DE}, src ≠ A, A live`) where it pays
`PUSH PSW` / `POP PSW` framing even when (a) a dead GR8 is available, or
(b) `addr=DE` (where an `XCHG` bypass entirely sidesteps `A`).

This is the direct port of O76's two new sub-priorities to the store side.
The XCHG bypass is in fact **cleaner** for the store than for the load — it
modifies no register at all, so the partner-MOV trick is unconditionally
correctness-safe for every `src ∈ {B, C, D, E, H, L}` with no RA-invariance
argument required.

## Problem

Current 4-priority expansion (timings using the O76 model:
`MOVrr/MOVMr/STAX = 8cc`, `PUSH PSW = 14cc`, `POP PSW = 14cc`, `XCHG = 4cc`):

| #  | addr | src    | A-liveness | expansion                                   | size | cycles |
|----|------|--------|------------|---------------------------------------------|------|--------|
| 1  | HL   | any    | any        | `MOV M, src`                                | 1B   |  8cc   |
| 2  | BC   | A      | any        | `STAX B`                                    | 1B   |  8cc   |
| 3  | DE   | A      | any        | `STAX D`                                    | 1B   |  8cc   |
| 4  | BC   | non-A  | A dead     | `MOV A, src; STAX B`                        | 2B   | 16cc   |
| 5  | DE   | non-A  | A dead     | `MOV A, src; STAX D`                        | 2B   | 16cc   |
| 6  | BC   | non-A  | A live     | `PUSH PSW; MOV A, src; STAX B; POP PSW`     | 4B   | 44cc   |
| 7  | DE   | non-A  | A live     | `PUSH PSW; MOV A, src; STAX D; POP PSW`     | 4B   | 44cc   |

(Prior to the 2026-05-07 fix the fallback used a `PUSH HL; LXI HL, addr; …;
POP HL` shape that miscompiled when `src ∈ {H, L}`. The current PSW-wrap
shape is correct on every src; see notes in
`/memories/repo/v6clang-backend.md`.)

Cases 6 and 7 are again the only sub-optimal shapes. Two mechanisms drop the
PSW envelope:

1. **SpareR-A.** Save `A` into a dead GR8 instead of the stack:
   `MOV spareR,A; MOV A,src; STAX rp; MOV A,spareR`. Two MOVs (8cc each)
   replace `PUSH PSW` (14cc) + `POP PSW` (14cc), shaving 12cc at the same
   4-byte width. Applies for **either** `addr=BC` or `addr=DE`.
2. **XCHG bypass** for `addr=DE` only. `XCHG; MOV M, partner(src); XCHG`
   stores `mem[old DE] := src` without touching `A`. **3B / 16cc**, same
   cycle count as the A-dead path of case 5.

### Why XCHG bypass is universally safe for the store

Unlike the load (`MOV r, M`), the body instruction here is `MOV M, r` — a
**read-only** register access. No register value is modified between
XCHG1 and XCHG2, so XCHG2 is the exact inverse of XCHG1: every GPR is
restored to its pre-`XCHG` value. There is **no DE-clobber edge case**
to argue about; the bypass is correctness-safe for every legal
`src ∈ {B, C, D, E, H, L}` regardless of post-pseudo liveness of any
register.

The partner mapping mirrors the load. Let `addr=DE = (addrHi,addrLo)`,
`HL = (h₀,l₀)`. After `XCHG`:

```
H = addrHi, L = addrLo, D = h₀, E = l₀
```

We need to write `src`'s **original value** into `mem[HL]` (= `mem[old DE]`).
Whichever register held `src` before the XCHG now holds the partner of `src`:

| src | partner(src) | mid-instr  | what gets stored | DE/HL preservation |
|-----|--------------|------------|------------------|--------------------|
|  B  |  B           | `MOV M, B` | original src     | both fully preserved |
|  C  |  C           | `MOV M, C` | original src     | both fully preserved |
|  D  |  H           | `MOV M, H` | original src (D was swapped into H) | both fully preserved |
|  E  |  L           | `MOV M, L` | original src     | both fully preserved |
|  H  |  D           | `MOV M, D` | original src (H was swapped into D) | both fully preserved |
|  L  |  E           | `MOV M, E` | original src     | both fully preserved |

After XCHG2 every GPR returns to its pre-XCHG1 value. Same `partnerOf`
function as O76:

```
B↔B,  C↔C,  D↔H,  E↔L
```

`A` and flags are never touched.

### Why XCHG bypass dominates SpareR-A for `addr=DE`

XCHG bypass: 3B / 16cc, no spare needed.
SpareR-A:    4B / 32cc, needs a dead GR8.

XCHG bypass is strictly better on both axes whenever `addr=DE`, so the
priority chain emits XCHG bypass unconditionally for that shape and never
falls through to SpareR-A or PSW-wrap when `addr=DE`.

## Proposed expansion table

`SpareR` = a GR8 dead at the pseudo location. Eligibility:

- Not `A` (we're saving it).
- Not `src` (mustn't overwrite the value we're about to store).
- Not a half of the live `addr` pair (excluded automatically — `addr` is
  read by the pseudo, so its halves aren't dead at MI).

Concretely:
- `addr=BC, src=R`: spareR ∈ {D, E, H, L} \ {R}, restricted to GR8s dead at MI.
- `addr=DE`: never reached for SpareR (XCHG always wins).

| #  | addr | src      | A-liveness         | path         | expansion                                                | size | cycles | Δ vs today |
|----|------|----------|--------------------|--------------|----------------------------------------------------------|------|--------|------------|
| 1  | HL   | any      | any                | direct       | `MOV M, src`                                             | 1B   |  8cc   | unchanged   |
| 2  | BC   | A        | any                | STAX         | `STAX B`                                                 | 1B   |  8cc   | unchanged   |
| 3  | DE   | A        | any                | STAX         | `STAX D`                                                 | 1B   |  8cc   | unchanged   |
| 4  | BC   | non-A    | A dead             | MOV+STAX     | `MOV A, src; STAX B`                                     | 2B   | 16cc   | unchanged   |
| 5  | DE   | non-A    | A dead             | MOV+STAX     | `MOV A, src; STAX D`                                     | 2B   | 16cc   | unchanged   |
| 6a | BC   | non-A    | A live, SpareR     | SpareR-A     | `MOV sR,A; MOV A,src; STAX B; MOV A,sR`                  | 4B   | 32cc   | −12cc, =B    |
| 6b | BC   | non-A    | A live, no spare   | PSW-wrap     | `PUSH PSW; MOV A,src; STAX B; POP PSW`                   | 4B   | 44cc   | unchanged   |
| 7  | DE   | non-A    | A live             | XCHG bypass  | `XCHG; MOV M, partner(src); XCHG`                        | 3B   | 16cc   | −1B, −28cc  |

`partner(src)`: `B→B, C→C, D→H, E→L, H→D, L→E`.

### Priority order inside each shape group

For `addr=BC, src≠A, A live` (case 6): try **6a** (SpareR) first; fall back
to **6b** (PSW).

For `addr=DE, src≠A, A live` (case 7): always emit XCHG bypass — strictly
dominates both 6a and 6b on size and cycles, with no liveness or RA
preconditions.

## Per-fire impact

Cycle savings vs current expander, conditional on RA producing the matching
shape:

- **Case 6 → 6a**: −12cc per fire when a GR8 is dead at the store. Common
  in pointer-walk loops where `A` holds a running accumulator and one of
  `D/E/H/L` is dead at the store.
- **Case 7**: −28cc and −1B per fire whenever `addr=DE`, `A` is live, and
  `src ≠ A`. Symmetric headline win to O76 case 7. Universally applicable
  to every non-A `src` (no edge case unlike the load — the body
  `MOV M, r` doesn't modify any register).

No regressions: every new path is strictly cheaper than the shape it
replaces; 6b remains as the unchanged worst-case fallback for `addr=BC`
with no spare.

## Implementation sketch

Single change to `V6ClangInstrInfo.cpp::expandPostRAPseudo`, case
`V6CLANG_STORE8_P`. Reuses the `findDeadGR8AtMI` helper introduced by O76
(currently in `V6ClangInstrInfo.cpp`).

```cpp
case V6CLANG::V6CLANG_STORE8_P: {
  Register SrcReg  = MI.getOperand(0).getReg();
  Register AddrReg = MI.getOperand(1).getReg();

  if (AddrReg == V6CLANG::HL) {
    // Priority 1: addr is HL.
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVMr)).addReg(SrcReg);
  } else if (SrcReg == V6CLANG::A &&
             (AddrReg == V6CLANG::BC || AddrReg == V6CLANG::DE)) {
    // Priority 2: STAX — src already in A.
    BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
        .addReg(SrcReg).addReg(AddrReg);
  } else if ((AddrReg == V6CLANG::BC || AddrReg == V6CLANG::DE) &&
             isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI)) {
    // Priority 3: A dead — MOV A,src; STAX.
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
        .addReg(V6CLANG::A, RegState::Define).addReg(SrcReg);
    BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
        .addReg(V6CLANG::A).addReg(AddrReg);
  } else {
    // Priority 4: addr ∈ {BC, DE}, src ≠ A, A live. Three-way dispatch:
    //   7  : addr=DE                 → XCHG bypass        (3B/16cc)
    //   6a : addr=BC, SpareR exists  → SpareR-A envelope  (4B/32cc)
    //   6b : addr=BC, no spare       → PSW-wrap fallback  (4B/44cc)
    auto partnerOf = [](Register R) -> Register {
      switch (R) {
      case V6CLANG::B: return V6CLANG::B;
      case V6CLANG::C: return V6CLANG::C;
      case V6CLANG::D: return V6CLANG::H;
      case V6CLANG::E: return V6CLANG::L;
      case V6CLANG::H: return V6CLANG::D;
      case V6CLANG::L: return V6CLANG::E;
      default:     return Register();
      }
    };

    if (AddrReg == V6CLANG::DE) {
      // 7: XCHG bypass. The body MOV M, r modifies no register, so XCHG2
      //    is the exact inverse of XCHG1 — every GPR (incl. DE) returns
      //    to its pre-pseudo value. Universally safe for every non-A src.
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVMr)).addReg(partnerOf(SrcReg));
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    } else {
      // addr=BC. Try SpareR-A first; fall back to PSW-wrap.
      // SpareR must survive the body unchanged — exclude A and SrcReg.
      Register SpareR = findDeadGR8AtMI(MI, MBB, &RI,
                                        /*Exclude1=*/V6CLANG::A,
                                        /*Exclude2=*/SrcReg);
      if (SpareR) {
        // 6a: MOV sR,A; MOV A,src; STAX B; MOV A,sR.
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), SpareR).addReg(V6CLANG::A);
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
            .addReg(V6CLANG::A, RegState::Define).addReg(SrcReg);
        BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
            .addReg(V6CLANG::A).addReg(AddrReg);
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(SpareR);
      } else {
        // 6b: PSW-wrap (legacy fallback).
        BuildMI(MBB, MI, DL, get(V6CLANG::PUSH)).addReg(V6CLANG::PSW);
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
            .addReg(V6CLANG::A, RegState::Define).addReg(SrcReg);
        BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
            .addReg(V6CLANG::A).addReg(AddrReg);
        BuildMI(MBB, MI, DL, get(V6CLANG::POP), V6CLANG::PSW);
      }
    }
  }
  MI.eraseFromParent();
  return true;
}
```

Note one subtlety vs the load expander: the load only consults `partnerOf`
inside the XCHG branch, but for the load case `dst ∈ {D, E}` is correctness-
safe by RA invariant. Here no such argument is needed — the partner mapping
is universal because the body does not write to any register.

## Verification plan

- Lit test `tests/lit/CodeGen/V6CLANG/store8p-shape-redesign.ll` covering all
  sub-shapes (1, 2, 3, 4, 5, 6a, 6b, 7). Use IR + inline-asm
  `register asm` pinning to materialise each `(addr, src, A-liveness,
  spareR)` tuple. Pattern after `temp/load8p_de_b.c` from O76 — invert
  load to store. The `src ∈ {H, L}` and `src ∈ {D, E}` rows of case 7 are
  particularly important: the partner-MOV trick uses non-obvious targets
  (`MOV M, D` for `src=H`, `MOV M, E` for `src=L`, `MOV M, H` for `src=D`,
  `MOV M, L` for `src=E`).
- Existing benchmarks (bsort, sieve, fib_crc, fannkuch, lfsr16) for net
  cycle/byte impact. Case 7 (DE-bypass) is expected to fire wherever DE
  holds a destination pointer in an A-live store loop — fannkuch's
  `perm1[i] = …` shift and any byte-output buffer write fits.
- 133/133 lit + golden + benchmark checksums must remain green.

## Open questions / non-goals

- **Composing with O49 direct memory ALU.** O49 already short-circuits
  most `mem[p] = mem[p] OP …` shapes that previously went through
  `LOAD8_P + ALU + STORE8_P`. O77 only affects pure stores that survive
  O49; no interaction.
- **Composing with O46 / `V6CLANG_STORE8_IMM_P`.** The immediate-store pseudo
  has its own expander (`expandMemOpM`); O77 leaves it alone.
- **Symmetry with O76.** O76 (load) and O77 (store) together close the
  book on the "A-live, addr ∈ {BC, DE}, R ≠ A" cluster of pseudos. Both
  use the same `findDeadGR8AtMI` helper and the same `partnerOf` table.
