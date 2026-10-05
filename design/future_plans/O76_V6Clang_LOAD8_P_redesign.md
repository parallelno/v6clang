# O76 — V6CLANG_LOAD8_P Per-Shape Redesign

`V6CLANG_LOAD8_P` is the generic 8-bit load-through-pointer pseudo:

```tablegen
let mayLoad = 1 in
def V6CLANG_LOAD8_P : V6ClangPseudo<(outs GR8:$dst), (ins GR16:$addr),
    "# LOAD8P $dst, ($addr)",
    [(set i8:$dst, (load i16:$addr))]>;
```

- One `GR16` input `$addr` ∈ {HL, BC, DE}.
- One `GR8` output `$dst` ∈ {A, B, C, D, E, H, L}.
- No declared `Defs`. Already correct per O71/O72-style truthful clobber model
  (resolved on 2026-05-07; see `/memories/repo/v6clang-backend.md`).

The current expander has 4 priorities and is already correct and `HL`-preserving
on all paths. **It is, however, leaving cycles on the table on the most
expensive path** (`addr ∈ {BC, DE}, dst ≠ A, A live`) where we pay
`PUSH PSW`/`POP PSW` framing even when a dead GR8 is available, and we ignore
`XCHG` as an A-preserving bypass for `addr=DE`.

## Problem

Current 4-priority expansion (timings restated against
[V6ClangInstructionTimings.md](../../docs/V6ClangInstructionTimings.md)):

| #  | addr | dst        | A-liveness | expansion                                  | size | cycles |
|----|------|------------|------------|--------------------------------------------|------|--------|
| 1  | HL   | any        | any        | `MOV dst,M`                                | 1B   |  8cc   |
| 2  | BC   | A          | any        | `LDAX B`                                   | 1B   |  8cc   |
| 3  | DE   | A          | any        | `LDAX D`                                   | 1B   |  8cc   |
| 4  | BC   | non-A      | A dead     | `LDAX B; MOV dst,A`                        | 2B   | 16cc   |
| 5  | DE   | non-A      | A dead     | `LDAX D; MOV dst,A`                        | 2B   | 16cc   |
| 6  | BC   | non-A      | A live     | `PUSH PSW; LDAX B; MOV dst,A; POP PSW`     | 4B   | 44cc   |
| 7  | DE   | non-A      | A live     | `PUSH PSW; LDAX D; MOV dst,A; POP PSW`     | 4B   | 44cc   |

Cases 6 and 7 are the only sub-optimal shapes. Two mechanisms can replace the
`PUSH PSW`/`POP PSW` envelope:

1. **A dead-GR8 spare** (`SpareR`). Save `A` into a dead GR8 instead of the
   stack: `MOV spareR,A; <body>; MOV A,spareR`. Two MOVs (8cc each) cost
   16cc total, vs `PUSH PSW`/`POP PSW` at 28cc. **Saves 12cc per fire**, same
   byte count.
2. **`XCHG` bypass** for `addr=DE` only. `XCHG; MOV r,M; XCHG` skips `LDAX`
   entirely and never touches `A`. The trick: write to the **XCHG-partner**
   of `dst` (B↔B, C↔C, H↔D, L↔E) so that the second XCHG drops the loaded
   byte into the requested register. The bypass is **3B / 16cc** for every
   non-A `dst`. The only side-effect axis is `DE` (=addr): preserved for
   `dst ∈ {B, C, H, L}`, clobbered for `dst ∈ {D, E}` — but the clobber is
   never observable (see next section).

### Why `DE` clobber for `dst ∈ {D, E}` is never observable

LLVM's register allocator enforces the invariant that **a def of a
subregister ends the live range of its containing superregister**. The
pseudo `V6CLANG_LOAD8_P` has `uses=$addr (GR16), defs=$dst (GR8)`. When `addr=DE`
and `dst ∈ {D, E}`, the def of `D` (or `E`) terminates the live range of
`DE`. Therefore RA can pick `dst ∈ {D, E}` for `addr=DE` **only if `DE` is
dead immediately after the pseudo**. If anything downstream needs `DE`
live-across, RA must allocate a different `dst` (typically a scratch GR8)
and emit the `MOV {D|E}, scratch` later, after `DE`'s last use.

**Empirical confirmation** (probes `temp/load8p_de_d3.c`,
`temp/load8p_de_e3.c` with `addr=DE`, `A`/`HL`/`DE` all live across the
load, and the output `register asm("D")` / `register asm("E")`):

```asm
; addr=DE, named-out=E, with de_ptr live after
PUSH PSW
LDAX D
MOV  C, A          ; <-- RA chose dst=C (scratch), not dst=E
POP  PSW
... uses of A, HL, DE ...
MOV  E, C          ; <-- copy to named E only after DE is dead
```

RA refused `dst=E` and routed through scratch `C`, exactly as the invariant
predicts. Symmetric result for `dst=D`.

**Consequence for the expander**: when we observe `(addr=DE, dst ∈ {D, E})`
at post-RA expansion time, `DE` is provably dead-after. The XCHG bypass can
fire unconditionally for all six non-A `dst` values; no `DE`-liveness query
is needed and no SpareR/PSW fallback for `dst ∈ {D, E}` is reachable.

### Why XCHG is universally cheap for addr=DE

Trace each candidate `dst` through `XCHG; MOV partner(dst),M; XCHG` with
initial `HL = h₀:l₀`, `DE = addrHi:addrLo`. After XCHG1 we have
`H=addrHi, L=addrLo, D=h₀, E=l₀`; the `MOV r,M` reads `mem[HL]` (=`mem[addr]`)
into `r`; XCHG2 swaps H↔D and L↔E.

The partner mapping that lands the loaded byte in `dst` after XCHG2:

| dst | mid-instr | After XCHG2 (H, L, D, E)            | dst correct | HL preserved | DE preserved |
|-----|-----------|--------------------------------------|-------------|--------------|--------------|
| B   | `MOV B,M` | `(h₀, l₀, addrHi, addrLo)`, B=loaded | ✓ | ✓ (both halves) | ✓ |
| C   | `MOV C,M` | same, C=loaded                       | ✓ | ✓ (both halves) | ✓ |
| H   | `MOV D,M` | `(loaded, l₀, addrHi, addrLo)`       | ✓ (in H)  | partial (L=l₀) | ✓ |
| L   | `MOV E,M` | `(h₀, loaded, addrHi, addrLo)`       | ✓ (in L)  | partial (H=h₀) | ✓ |
| D   | `MOV H,M` | `(h₀, l₀, loaded, addrLo)`           | ✓ (in D)  | ✓ (both halves) | DE-clobber, RA-unreachable† |
| E   | `MOV L,M` | `(h₀, l₀, addrHi, loaded)`           | ✓ (in E)  | ✓ (both halves) | DE-clobber, RA-unreachable† |

`partial` for `dst ∈ {H, L}` means "the half that is `dst` is overwritten with
`loaded` — which is exactly what the load is supposed to do; the other half is
untouched." So `HL` is correctly post-load for all six rows.

† As established in the previous section, `(addr=DE, dst ∈ {D, E})` only
reaches the post-RA expander when `DE` is dead immediately after the
pseudo; the apparent clobber is therefore never observable.

**Conclusion**: XCHG bypass is correct and optimal for **all six** non-A
`dst` values when `addr=DE` and `A` is live. The only gating predicates are:

- `addr == DE` (XCHG operates on DE↔HL).
- `A` is live (otherwise the 2B/16cc `LDAX D; MOV dst,A` path of case 5 wins
  on bytes at the same cycle count).

`A` and flags are never touched by `XCHG`/`MOV r,M`/`XCHG`.

## Proposed expansion table

`SpareR` = a GR8 dead at the pseudo location. Eligibility:

- Not `A` (trivially — `A` is what we're saving).
- Not `dst` (the spareR must survive the body unchanged so we can restore `A`).
- Not a half of the live `addr` pair (LDAX needs `addr` intact;
  in practice the `addr` halves are not "dead at MI" anyway because `addr` is
  read by the pseudo — they're excluded automatically by the dead-GR8 check).

Concretely:
- `addr=BC, dst=R`: spareR ∈ {D, E, H, L} \ {R}, restricted to GR8s dead at MI.
- `addr=DE, dst=R`: spareR ∈ {B, C, H, L} \ {R}, restricted to GR8s dead at MI.

| #  | addr | dst         | A-liveness | path                | expansion                                        | size | cycles | Δ vs today |
|----|------|-------------|------------|---------------------|--------------------------------------------------|------|--------|------------|
| 1  | HL   | any         | any        | direct              | `MOV dst,M`                                      | 1B   |  8cc   | unchanged  |
| 2  | BC   | A           | any        | LDAX                | `LDAX B`                                         | 1B   |  8cc   | unchanged  |
| 3  | DE   | A           | any        | LDAX                | `LDAX D`                                         | 1B   |  8cc   | unchanged  |
| 4  | BC   | non-A       | A dead     | LDAX+MOV            | `LDAX B; MOV dst,A`                              | 2B   | 16cc   | unchanged  |
| 5  | DE   | non-A       | A dead     | LDAX+MOV            | `LDAX D; MOV dst,A`                              | 2B   | 16cc   | unchanged  |
| 6a | BC   | non-A   | A live, SpareR   | SpareR-A    | `MOV spareR,A; LDAX B; MOV dst,A; MOV A,spareR`  | 4B   | 32cc   | −12cc, =B   |
| 6b | BC   | non-A   | A live, no spare | PSW-wrap    | `PUSH PSW; LDAX B; MOV dst,A; POP PSW`           | 4B   | 44cc   | unchanged    |
| 7  | DE   | non-A   | A live           | XCHG bypass | `XCHG; MOV partner(dst),M; XCHG`                 | 3B   | 16cc   | −1B, −28cc  |

`partner(dst)`: `B→B, C→C, H→D, L→E, D→H, E→L` (XCHG-partner of `dst`).

### Priority order inside each shape group

For `addr=BC, dst≠A, A live` (case 6): try **6a** (SpareR) first; fall back to
**6b** (PSW).

For `addr=DE, dst≠A, A live` (case 7): always emit XCHG bypass — the RA
invariant guarantees the partner-MOV trick is correctness-safe for every
`dst ∈ {B, C, D, E, H, L}` that RA actually selects. No fallback path
needed.

XCHG bypass at 3B/16cc dominates SpareR-A (4B/32cc) and PSW-wrap (4B/44cc) on
both axes.

## Per-fire impact

Cycle savings vs current expander, conditional on RA actually producing the
matching shape:

- **Case 6 → 6a**: −12cc per fire when a GR8 is dead at the load.
  Common when the load is the only live-A consumer in its block.
- **Case 7**: −28cc and −1B per fire whenever `addr=DE`, `A` is live, and
  `dst ≠ A`. This is the headline win — XCHG bypass costs the same as the
  A-dead path (case 5) but works in the A-live window for every non-A `dst`
  RA can legally pick. Covers all six non-A `dst` values unconditionally;
  the apparent edge case `dst ∈ {D, E}` is correctness-safe because RA
  cannot allocate it when `DE` is live-after.

No regressions: every new path is strictly cheaper than the shape it replaces;
6b remains as the unchanged worst-case fallback for `addr=BC` with no spare.

## Implementation sketch

Single change to `V6ClangInstrInfo.cpp::expandPostRAPseudo`, case `V6CLANG_LOAD8_P`:

```cpp
} else {
    // Priority 4: addr ∈ {BC, DE}, dst != A.
    bool ALive = !isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI);

    // Sub-priority 4a (DE only): XCHG bypass via partner(dst).
    // Correct for every non-A dst: for dst ∈ {B, C, H, L} the bypass
    // preserves DE; for dst ∈ {D, E} the bypass clobbers DE, but RA's
    // subreg-def-kills-superreg-use invariant guarantees DE is dead after
    // the pseudo whenever it allocates dst ∈ {D, E} for addr=DE.
    auto partnerOf = [](Register R) -> Register {
        switch (R) {
        case V6CLANG::B: return V6CLANG::B;
        case V6CLANG::C: return V6CLANG::C;
        case V6CLANG::H: return V6CLANG::D;
        case V6CLANG::L: return V6CLANG::E;
        case V6CLANG::D: return V6CLANG::H;
        case V6CLANG::E: return V6CLANG::L;
        default: return Register();
        }
    };
    bool XchgOK = ALive && AddrReg == V6CLANG::DE;
    if (XchgOK) {
        BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrM))
            .addReg(partnerOf(DstReg), RegState::Define);
        BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    } else if (ALive) {
        // Sub-priority 4b: SpareR — save A into a dead GR8, do LDAX+MOV,
        // restore A.
        Register SpareR = pickDeadGR8For(MI, MBB, &RI, /*Exclude=*/{V6CLANG::A,
                                                                    DstReg});
        if (SpareR) {
            BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), SpareR).addReg(V6CLANG::A);
            BuildMI(MBB, MI, DL, get(V6CLANG::LDAX))
                .addReg(V6CLANG::A, RegState::Define).addReg(AddrReg);
            BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
                .addReg(DstReg, RegState::Define).addReg(V6CLANG::A);
            BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(SpareR);
        } else {
            // Sub-priority 4c: PSW-wrap (today's path).
            BuildMI(MBB, MI, DL, get(V6CLANG::PUSH)).addReg(V6CLANG::PSW);
            BuildMI(MBB, MI, DL, get(V6CLANG::LDAX))
                .addReg(V6CLANG::A, RegState::Define).addReg(AddrReg);
            BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
                .addReg(DstReg, RegState::Define).addReg(V6CLANG::A);
            BuildMI(MBB, MI, DL, get(V6CLANG::POP), V6CLANG::PSW);
        }
    } else {
        // Priority 3: A dead — today's path.
        BuildMI(MBB, MI, DL, get(V6CLANG::LDAX))
            .addReg(V6CLANG::A, RegState::Define).addReg(AddrReg);
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
            .addReg(DstReg, RegState::Define).addReg(V6CLANG::A);
    }
}
```

`pickDeadGR8For(MI, MBB, RI, Exclude)` is a new helper (or factored shared
helper if O71/O72 already provides one — likely
`V6ClangInstrInfo.cpp::pickDeadSpareGR8` or similar) returning a `Register`
in `{B, C, D, E, H, L}` that is dead across `MI` and not in `Exclude`,
or `Register()` if none exists.

## Verification plan

- Lit test `tests/lit/CodeGen/V6CLANG/load8p-shape-redesign.ll` covering all 7
  sub-shapes (1, 2, 3, 4, 5, 6a, 6b, 7). Use IR + inline-asm
  `register asm` pinning to materialise each
  `(addr, dst, A-liveness, spareR)` tuple. Pattern after
  `temp/load8p_de_b.c`. The `dst ∈ {H, L}` rows of case 7 are particularly
  important to encode: the partner-MOV trick (`MOV D,M` for `dst=H`,
  `MOV E,M` for `dst=L`) is non-obvious and must be exercised. The
  `dst ∈ {D, E}` rows of case 7 should be checked too — confirm via probe
  (already done: `temp/load8p_de_d3.c`, `temp/load8p_de_e3.c`) that RA
  never produces `(addr=DE, dst ∈ {D,E})` with `DE` live-after, so the
  bypass's DE-clobber is unobservable.
- Existing benchmarks (bsort, sieve, fib_crc, fannkuch, lfsr16) for net
  cycle/byte impact. Case 7 (DE-bypass) is expected to fire in any
  pointer-walk loop where DE holds the pointer and A is in use as an
  accumulator (e.g. fib_crc, fannkuch).
- 133/133 lit + golden + benchmark checksums must remain green.

## Open questions / non-goals

- **Flag-only PSW save.** `LDAX` and `MOV` don't touch flags, so the only
  reason `PUSH PSW`/`POP PSW` appears in 6b is to save `A`. If the spare-
  search ever finds **no `A` source to preserve** (i.e. RA actually killed
  `A` here but liveness analysis missed it), we'd already be in case 4/5.
  No "flags-only" variant is needed.
- **Shape symmetry with `V6CLANG_STORE8_P`.** The store pseudo has the same
  4-priority chain today. The two new sub-priorities (SpareR-A, XCHG bypass)
  port to the store with the same constraints; the XCHG bypass for stores
  applies to `addr=DE, src ∈ {B, C}`. Tracked separately as O77 / part of
  this plan as a follow-up — flagged here for visibility, not in scope.
