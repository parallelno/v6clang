# O78 — V6CLANG_STORE8_IMM_P Per-Shape Redesign

`V6CLANG_STORE8_IMM_P` is the immediate-source 8-bit store-through-pointer
pseudo introduced by O46/O49:

```tablegen
def V6CLANG_STORE8_IMM_P : V6ClangPseudo<(outs), (ins imm8:$imm, GR16:$addr),
    "# STORE8IMMP ($addr), $imm",
    [(store (i8 imm:$imm), i16:$addr)]>;
```

- One `imm8` `$imm` (the value being stored).
- One `GR16` input `$addr` ∈ {HL, BC, DE}.
- No declared `Defs`.

Today the expander is a one-liner that delegates to the generic
`expandMemOpM` helper (used by all O49 M-operand pseudos):

```cpp
case V6CLANG::V6CLANG_STORE8_IMM_P: {
  int64_t Imm     = MI.getOperand(0).getImm();
  Register AddrReg = MI.getOperand(1).getReg();
  expandMemOpM(MBB, MI, *this, RI, AddrReg,
      [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
        BuildMI(B, Ip, DL, get(V6CLANG::MVIM)).addImm(Imm);
      });
  MI.eraseFromParent();
  return true;
}
```

`expandMemOpM` is correct for every O49 M-operand pseudo, but it's
sub-optimal for `STORE8_IMM_P` specifically because — unlike ADDM/CMPM/INRM
etc. — `MVI M` has a 1-byte alternative path through A (`MVI A, imm; STAX
rp`) that uses BC or DE directly without HL staging.

## Problem

Current 4-priority expansion (timings from `docs/V6ClangInstructionTimings.md`:
`MVI M, d8 = 12cc/2B`, `MVI r, d8 = 8cc/2B`, `STAX = 8cc/1B`,
`MOVrr = 8cc/1B`, `XCHG = 4cc/1B`, `PUSH rp = 16cc/1B`, `POP rp = 12cc/1B`):

| # | addr | HL-liveness | expansion                                              | size | cycles |
|---|------|-------------|--------------------------------------------------------|------|--------|
| 1 | HL   | n/a         | `MVI M, imm`                                           | 2B   | 12cc   |
| 2 | DE   | n/a         | `XCHG; MVI M, imm; XCHG`                               | 4B   | 20cc   |
| 3 | BC   | HL dead     | `MOV L,C; MOV H,B; MVI M, imm`                         | 4B   | 28cc   |
| 4 | BC   | HL live     | `PUSH HL; MOV L,C; MOV H,B; MVI M, imm; POP HL`        | 6B   | 56cc   |

Note A-liveness is ignored entirely: `MVI M` doesn't read or write A, so
the existing path never considered using A as a staging register. This is
exactly where the wins are.

## The two missing tricks

### Trick 1 — go through A for `addr ∈ {BC, DE}, A dead`

`MVI A, imm; STAX rp` materialises the immediate into A and writes through
the BC/DE pair directly. Same end-state for the store, no HL touched, no
swap, no envelope.

- Cost: **3B / 16cc** (`MVI A` 8cc + `STAX` 8cc).
- Strictly cheaper than today's `addr=DE` path (4B/20cc) and **far** cheaper
  than today's `addr=BC, HL live` path (6B/56cc).
- Correctness: A is dead at the pseudo by precondition, so destroying it
  is harmless. BC/DE is unchanged. HL is unchanged.

### Trick 2 — DE-routing for `addr=BC, A live, HL live, DE dead`

When HL is live but DE is dead, today's path pays the full PUSH/POP HL
envelope (16+12=28cc just for save/restore, on top of 28cc for the body).
A cheaper alternative exists: **copy BC into DE first, then use the
cheap DE path**.

```
MOV D, B
MOV E, C   ; DE := BC = addr (DE was dead)
XCHG       ; HL := addr, DE := old HL
MVI M, imm ; mem[addr] := imm
XCHG       ; HL := old HL (restored), DE := addr
```

- Cost: **5B / 36cc** (8 + 8 + 4 + 12 + 4 = 36cc).
- vs today's BC/HL-live path: 6B/56cc → **−1B, −20cc per fire.**
- DE is clobbered, but it was dead by precondition.
- HL is preserved exactly (XCHG2 is the inverse of XCHG1; the body
  `MVI M, imm` doesn't touch any register).

### Why XCHG bypass alone (without the BC→DE copy) doesn't apply here

The plain DE bypass shape (`XCHG; MVI M; XCHG`) requires the address to
already be in DE — that's row 2. For BC, we need an explicit BC→DE
materialisation first, paying 2 MOVs (16cc) up front. That extra cost is
why this path only beats today's row 4 (HL save/restore is even more
expensive: 28cc PUSH+POP), not today's rows 2/3.

## Liveness facts about `STORE8_IMM_P`

- **A**: not read, not written by any path today. A's liveness was
  irrelevant before; it becomes a *precondition* for trick 1.
- **HL**: read on rows 1, 3, 4; not on row 2. Preserved on every row.
- **DE**: read on row 2 (XCHG side). Preserved on every row today.
  Becomes a *precondition* (must be dead) for trick 2.
- **BC**: read on rows 3, 4. Preserved on every row.

The redesign adds A-dead and DE-dead as new dispatch axes that weren't
relevant before.

## Proposed expansion table

Order matters — earlier rows are strictly cheaper, so try them first.

| addr | A | HL | DE | path                                          | size | cycles | Δ vs today |
|------|---|----|----|-----------------------------------------------|------|--------|------------|
| HL   | * | *  | *  | `MVI M, imm`                                  | 2B   | 12cc   | unchanged  |
| BC   | dead | * | * | `MVI A, imm; STAX B`                          | 3B   | 16cc   | **−3B, −12cc to −40cc** |
| DE   | dead | * | * | `MVI A, imm; STAX D`                          | 3B   | 16cc   | **−1B, −4cc** |
| DE   | live | * | * | `XCHG; MVI M, imm; XCHG`                      | 4B   | 20cc   | unchanged  |
| BC   | live | dead | * | `MOV L,C; MOV H,B; MVI M, imm`                | 4B   | 28cc   | unchanged  |
| BC   | live | live | dead | `MOV D,B; MOV E,C; XCHG; MVI M; XCHG`     | 5B   | 36cc   | **−1B, −20cc** |
| BC   | live | live | live | `PUSH HL; MOV L,C; MOV H,B; MVI M; POP HL` | 6B   | 56cc   | unchanged  |

`*` = don't care.

### Δ breakdown for the new BC/A-dead row

- vs today's `BC, HL dead`: −1B, **−12cc**.
- vs today's `BC, HL live`: −3B, **−40cc** — by far the biggest win.

## Per-fire impact

- **BC + A dead**: −12cc to −40cc per fire, depending on HL. Common
  in initialisation loops (`*p++ = 0` over a buffer when A is otherwise
  unused), tag stores in pointer-chasing loops, etc.
- **DE + A dead**: −4cc per fire. Smaller win but free.
- **BC + A live + HL live + DE dead**: −20cc per fire. Hits when HL
  holds an unrelated long-lived pointer/value and DE happens to be free.

No regressions: every new path is strictly cheaper than the row it
replaces; the worst-case `BC, all live` path remains as the unchanged
fallback.

## Implementation sketch

The expander stops sharing `expandMemOpM` (which is generic for ADDM/INRM/
DCRM/CMPM where `M` is mandatory). Specialised case in
`V6ClangInstrInfo.cpp::expandPostRAPseudo`:

```cpp
case V6CLANG::V6CLANG_STORE8_IMM_P: {
  int64_t Imm     = MI.getOperand(0).getImm();
  Register AddrReg = MI.getOperand(1).getReg();
  bool ADead  = isRegDeadAtMI(V6CLANG::A,  MI, MBB, &RI);
  bool HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI);
  bool DEDead = isRegDeadAtMI(V6CLANG::DE, MI, MBB, &RI);

  if (AddrReg == V6CLANG::HL) {
    // Row 1 — direct.
    BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
  } else if (ADead) {
    // Rows 2/3 of new table — A dead, route via STAX.
    // Works for AddrReg ∈ {BC, DE}.
    BuildMI(MBB, MI, DL, get(V6CLANG::MVIr), V6CLANG::A).addImm(Imm);
    BuildMI(MBB, MI, DL, get(V6CLANG::STAX)).addReg(V6CLANG::A).addReg(AddrReg);
  } else if (AddrReg == V6CLANG::DE) {
    // A live, addr=DE — XCHG bypass.
    BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
    BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
  } else {
    // A live, addr=BC. Three sub-cases by HL/DE liveness.
    if (HLDead) {
      // BC + HL dead: copy BC→HL, store. (Today's row 3.)
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::C);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::H).addReg(V6CLANG::B);
      BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
    } else if (DEDead) {
      // BC + HL live + DE dead: route via DE-then-XCHG.
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::D).addReg(V6CLANG::B);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::E).addReg(V6CLANG::C);
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    } else {
      // BC + HL live + DE live: today's row 4 fallback.
      BuildMI(MBB, MI, DL, get(V6CLANG::PUSH))
          .addReg(V6CLANG::HL, RegState::Kill)
          .addReg(V6CLANG::SP, RegState::ImplicitDefine);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::C);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::H).addReg(V6CLANG::B);
      BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
      BuildMI(MBB, MI, DL, get(V6CLANG::POP), V6CLANG::HL)
          .addReg(V6CLANG::SP, RegState::ImplicitDefine);
    }
  }
  MI.eraseFromParent();
  return true;
}
```

Notes:

- `expandMemOpM` is unchanged and still used by all other O49 M-operand
  pseudos (ADDM/SUBM/.../CMPM/INRM/DCRM). They have no STAX-equivalent
  shortcut and genuinely require `M`.
- Reuses `isRegDeadAtMI` already used by O76/O77.
- No new helper needed (no SpareR / partner-MOV table — the immediate is
  not a register, so the XCHG bypass body is register-free and partner
  remapping is unnecessary).

## Verification plan

- Lit test `tests/lit/CodeGen/V6CLANG/store8imm-shape-redesign.ll` covering all
  seven sub-shapes. Pattern after the four `temp/store8imm_case*.c`
  probes already in the workspace; add three more for the new (A dead +
  BC), (A dead + DE), (BC + HL live + DE dead) shapes. Use the free-list
  CC pinning trick (1st i16 arg → HL, 2nd → DE, 3rd → BC) plus
  inline-asm `OUT 0xde` consumers to control liveness.
- Regression: 133/133 lit + golden + benchmark checksums must remain
  green.
- Benchmarks (bsort, sieve, fib_crc, fannkuch, lfsr16): expected fires in
  any byte-init / tag-store / null-terminator-write site where the
  destination pointer ends up in BC or DE. The biggest practical fire is
  zero-init loops written as `*p = 0;` where O55's `XRA A` peephole is
  not applicable because A is otherwise live.

## Composition with other plans

- **O46 / O49** (where this pseudo originated): unchanged. O78 only
  refines the expander, not the ISel pattern or the .td definition.
- **O55 (`MVI A, 0` → `XRA A`)**: composes naturally. After O78 emits
  `MVI A, imm` on the A-dead paths, if `imm == 0` and FLAGS is also dead,
  O55 rewrites it to `XRA A` (1B/4cc instead of 2B/8cc). That gives an
  additional −1B/−4cc on top of O78's win for the common `*p = 0` case.
- **O76 / O77** (LOAD8_P / STORE8_P redesigns): orthogonal — those
  handle register-source/destination stores, this one handles
  immediate-source stores.
- **No interaction with `findDeadGR8AtMI`**: O78 only checks A/HL/DE
  liveness, not generic GR8s, so it doesn't need O71/O76's helper.

## Open questions / non-goals

- **Could RA pick A for us if we deleted the pseudo?** Investigated in
  the design discussion: yes for the `addr=BC, A dead` shape (RA does
  pick A when the value goes through a vreg), but no overall — the
  HL row would degrade from `MVI M, imm` (2B/12cc) to `MVI vreg, imm;
  MOV M, vreg` (3B/16cc), and the DE+A-live row would degrade from
  4B/20cc to 5B/24cc. Keeping the dedicated pseudo is strictly cheaper.
- **Cycle threshold for dual cost model**: not needed — every new path
  is both smaller and faster than the row it replaces. No size/speed
  trade-off to gate on `getV6ClangOptMode`.
