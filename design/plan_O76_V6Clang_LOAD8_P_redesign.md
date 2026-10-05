# Plan: V6CLANG_LOAD8_P Per-Shape Redesign — SpareR-A + XCHG Bypass

Source design: [O76 V6CLANG_LOAD8_P Redesign](future_plans/O76_V6CLANG_LOAD8_P_redesign.md)

## 1. Problem

### Current behavior

`V6CLANG_LOAD8_P` is the 8-bit load-through-pointer pseudo:

```tablegen
let mayLoad = 1 in
def V6CLANG_LOAD8_P : V6ClangPseudo<(outs GR8:$dst), (ins GR16:$addr),
    "# LOAD8P $dst, ($addr)",
    [(set i8:$dst, (load i16:$addr))]>;
```

The post-RA expander in `V6ClangInstrInfo::expandPostRAPseudo()`
(`case V6CLANG::V6CLANG_LOAD8_P:`, currently line ~2231) implements a
4-priority chain (timings against
[V6ClangInstructionTimings.md](../docs/V6ClangInstructionTimings.md)):

| # | addr | dst   | A-liveness | expansion                                  | size | cycles |
|---|------|-------|------------|--------------------------------------------|------|--------|
| 1 | HL   | any   | any        | `MOV dst,M`                                | 1B   |  8cc   |
| 2 | BC   | A     | any        | `LDAX B`                                   | 1B   |  8cc   |
| 3 | DE   | A     | any        | `LDAX D`                                   | 1B   |  8cc   |
| 4 | BC   | non-A | A dead     | `LDAX B; MOV dst,A`                        | 2B   | 16cc   |
| 5 | DE   | non-A | A dead     | `LDAX D; MOV dst,A`                        | 2B   | 16cc   |
| 6 | BC   | non-A | A live     | `PUSH PSW; LDAX B; MOV dst,A; POP PSW`     | 4B   | 44cc   |
| 7 | DE   | non-A | A live     | `PUSH PSW; LDAX D; MOV dst,A; POP PSW`     | 4B   | 44cc   |

Cases 6 and 7 always pay the `PUSH PSW` / `POP PSW` envelope (28cc)
to preserve `A`, even when (a) a free GR8 is dead at the load (the
spill could be a 8cc+8cc MOV pair instead of 12cc+10cc PUSH/POP) or
(b) `addr=DE`, in which case an `XCHG; MOV r,M; XCHG` bypass skips
`LDAX` entirely without ever touching `A`.

### Desired behavior

For case 6 (`addr=BC, dst≠A, A live`), dispatch on the availability
of a dead non-A GR8 (`SpareR`):

| Predicate          | Shape                                            | Bytes / Cycles |
|--------------------|--------------------------------------------------|----------------|
| SpareR available   | `MOV spareR,A; LDAX B; MOV dst,A; MOV A,spareR`  | 4B / 32cc      |
| no SpareR          | `PUSH PSW; LDAX B; MOV dst,A; POP PSW` (today)   | 4B / 44cc      |

For case 7 (`addr=DE, dst≠A, A live`), always emit the XCHG bypass:

| Predicate          | Shape                                            | Bytes / Cycles |
|--------------------|--------------------------------------------------|----------------|
| (any non-A dst)    | `XCHG; MOV partner(dst),M; XCHG`                 | 3B / 16cc      |

`partner(dst)` maps `B→B, C→C, H→D, L→E, D→H, E→L`. The trick: after
`XCHG`, `HL` holds `addr`, so a `MOV r,M` reads `mem[addr]` into `r`;
the second `XCHG` lands the loaded byte in the requested register
(see design doc table for full trace).

Per-fire savings vs current:
- Case 6 → 6a: −12cc, =B (28cc PSW envelope → 16cc 2× MOV).
- Case 7 → 7: −28cc, −1B (44cc/4B → 16cc/3B).

### Root cause

The existing expander considers only one A-preservation lever
(`PUSH PSW`/`POP PSW`) and ignores the `XCHG` swap available when
`addr=DE`. Both improvements require post-RA liveness knowledge
(SpareR availability, `A` liveness), which the register allocator
cannot encode in a fixed `Defs` set without forcing pessimistic
spills on every load.

For the `dst ∈ {D, E}` rows of the new XCHG bypass, the apparent
`DE` clobber is unobservable because of the LLVM RA invariant
**a def of a sub-register ends the live range of its containing
super-register**. Verified empirically with probes
[temp/load8p_de_d3.c](../temp/load8p_de_d3.c) /
[temp/load8p_de_e3.c](../temp/load8p_de_e3.c): when `DE` is live
across the load, RA refuses to allocate `dst ∈ {D, E}` and routes
through a scratch GR8 instead. So the expander only ever observes
`(addr=DE, dst ∈ {D,E})` when `DE` is dead-after, and the bypass's
`DE`-clobber side-effect is never observable.

---

## 2. Strategy

### Approach: per-shape expansion with cheap-first preservation

Keep `V6CLANG_LOAD8_P` exactly as declared today (`(outs GR8:$dst),
(ins GR16:$addr)`, no `Defs`). Replace the `else` body of priority 4
with a three-way dispatch on `(AddrReg, ALive, SpareR-available)`:

1. `addr=DE && A live` → **XCHG bypass** (3B/16cc, unconditional for
   any non-A `dst`).
2. `A live && SpareR available` → **SpareR-A** envelope (4B/32cc).
3. `A live && no SpareR` → **PSW-wrap** (4B/44cc, today's path).

Priority 3 (`A dead`) is unchanged.

### Why this works

- **Pressure-friendly.** RA still sees the pseudo as preserving every
  non-`$dst` register, so it does not insert spills around 8-bit
  loads. The expander's choices are entirely post-RA.
- **Honest at expansion time.** Each shape is selected only when its
  side-effects are demonstrably absent: SpareR-A clobbers a GR8 that
  was already dead; XCHG bypass clobbers `DE` only when RA's subreg
  invariant guarantees `DE` is dead-after.
- **Reuses existing helpers.** `findDeadGR8AtMI` (added by O71/O72)
  already provides the SpareR search. `isRegDeadAtMI` already
  provides `A`-liveness. No new helpers needed.

### Summary of changes

| Step | What                                                      | Where                                          |
|------|-----------------------------------------------------------|------------------------------------------------|
| Rewrite expander | Three-way dispatch in priority-4 arm           | V6ClangInstrInfo.cpp `case V6CLANG::V6CLANG_LOAD8_P:`      |
| (No change) | `V6CLANG_LOAD8_P` td declaration unchanged              | V6ClangInstrInfo.td                                |
| Test coverage | Lit test pinning each new shape + feature test    | tests/lit/CodeGen/V6CLANG/, tests/features/58/     |
| Doc updates | Mark O76 done in `design/future_plans/README.md`    | design/future_plans/                           |

---

## 3. Implementation Steps

### Step 3.1 — Rewrite expander: priority-4 three-way dispatch [ ]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`,
`case V6CLANG::V6CLANG_LOAD8_P:` (currently line ~2231).

Replace the existing `else` (priority-4) branch with:

```cpp
} else {
  // AddrReg ∈ {BC, DE}, DstReg != A.
  bool ALive = !isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI);

  // 7 — addr=DE, A live: XCHG bypass via partner(dst). No A-spill,
  // no flag-spill, 3B/16cc. Correct for every non-A dst:
  //   - dst ∈ {B, C, H, L}: bypass preserves DE.
  //   - dst ∈ {D, E}      : bypass clobbers DE, but RA's
  //     subreg-def-kills-superreg-use invariant guarantees DE is
  //     dead after the pseudo whenever it allocates dst ∈ {D, E}
  //     for addr=DE (verified empirically; see plan §1).
  auto partnerOf = [](Register R) -> Register {
    switch (R) {
    case V6CLANG::B: return V6CLANG::B;
    case V6CLANG::C: return V6CLANG::C;
    case V6CLANG::H: return V6CLANG::D;
    case V6CLANG::L: return V6CLANG::E;
    case V6CLANG::D: return V6CLANG::H;
    case V6CLANG::E: return V6CLANG::L;
    default:     return Register();
    }
  };

  if (ALive && AddrReg == V6CLANG::DE) {
    Register Partner = partnerOf(DstReg);
    BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrM))
        .addReg(Partner, RegState::Define);
    BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
  } else if (ALive) {
    // 6a — addr=BC, A live, SpareR available: dead-GR8 envelope.
    // Saves 12cc vs PUSH PSW / POP PSW. Same byte count.
    Register SpareR = findDeadGR8AtMI(MI, MBB, &RI,
                                      /*Exclude1=*/V6CLANG::A,
                                      /*Exclude2=*/DstReg);
    if (SpareR) {
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), SpareR).addReg(V6CLANG::A);
      BuildMI(MBB, MI, DL, get(V6CLANG::LDAX))
          .addReg(V6CLANG::A, RegState::Define).addReg(AddrReg);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(DstReg, RegState::Define).addReg(V6CLANG::A);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(SpareR);
    } else {
      // 6b — A live, no spare: PSW envelope (today's path).
      BuildMI(MBB, MI, DL, get(V6CLANG::PUSH)).addReg(V6CLANG::PSW);
      BuildMI(MBB, MI, DL, get(V6CLANG::LDAX))
          .addReg(V6CLANG::A, RegState::Define).addReg(AddrReg);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(DstReg, RegState::Define).addReg(V6CLANG::A);
      BuildMI(MBB, MI, DL, get(V6CLANG::POP), V6CLANG::PSW);
    }
  } else {
    // Priority 3 — A dead, current behavior.
    BuildMI(MBB, MI, DL, get(V6CLANG::LDAX))
        .addReg(V6CLANG::A, RegState::Define).addReg(AddrReg);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
        .addReg(DstReg, RegState::Define).addReg(V6CLANG::A);
  }
}
```

> **Design Notes**: `findDeadGR8AtMI` already exists at
> [V6ClangInstrInfo.cpp:506](../llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp#L506).
> It excludes `A` and accepts up-to-two extra exclude registers.
> The `Exclude2=DstReg` argument is essential: SpareR must survive
> the entire envelope including the post-LDAX `MOV dst,A`, so it
> cannot alias `DstReg`. The XCHG bypass uses partner-of-dst so it
> writes the loaded byte to `partnerOf(DstReg)` (which equals
> `DstReg` for `dst ∈ {B,C,H,L}` and equals the XCHG-image of
> `DstReg` for `dst ∈ {D,E}`).

> **Implementation Notes**: <empty>

### Step 3.2 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Fix any compile errors, then proceed.

> **Implementation Notes**: <empty>

### Step 3.3 — Lit test: load8p-shape-redesign.ll [ ]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/load8p-shape-redesign.ll`

Pin each priority-4 sub-shape with IR + register-asm constraints.
Coverage matrix:

| label                | addr | dst    | A live | SpareR | expected emission                              |
|----------------------|------|--------|--------|--------|------------------------------------------------|
| `case4_bc_a_dead`    | BC   | non-A  | dead   | n/a    | `LDAX B; MOV dst, A` (priority 4, unchanged)   |
| `case5_de_a_dead`    | DE   | non-A  | dead   | n/a    | `LDAX D; MOV dst, A` (priority 5, unchanged)   |
| `case6a_bc_spareR`   | BC   | non-A  | live   | yes    | `MOV r,A; LDAX B; MOV dst,A; MOV A,r`          |
| `case6b_bc_no_spare` | BC   | non-A  | live   | no     | `PUSH PSW; LDAX B; MOV dst,A; POP PSW`         |
| `case7_de_b`         | DE   | B      | live   | n/a    | `XCHG; MOV B, M; XCHG`                         |
| `case7_de_h`         | DE   | H      | live   | n/a    | `XCHG; MOV D, M; XCHG` (partner-MOV trick)     |
| `case7_de_l`         | DE   | L      | live   | n/a    | `XCHG; MOV E, M; XCHG` (partner-MOV trick)     |

The `dst ∈ {D, E}` rows of case 7 need not be lit-tested because RA
will not allocate them when `DE` is live-after; if `DE` is dead-after
they reduce to case 5 already covered. (Already verified
empirically — see plan §1 root cause.)

> **Design Notes**: Use `register uint8_t v asm("X")` pinning + a
> trailing inline-asm sink with `"a"`, `"r"` constraints to force
> A and HL/BC/DE liveness. To deny SpareR for case6b, hammer **all**
> non-A non-dst GR8s with `"r"` clobbers across the load.

> **Implementation Notes**: <empty>

### Step 3.4 — Run lit tests [ ]

```
cd llvm-project
llvm-build\bin\llvm-lit -v llvm/test/CodeGen/V6CLANG
```

Diagnose and fix any failure. Pre-existing tests that pin
`(addr=DE, A live)` or `(addr=BC, A live)` shapes may need
FileCheck pattern updates to match the new emission.

> **Implementation Notes**: <empty>

### Step 3.5 — Run regression tests [ ]

```
python tests\run_all.py
```

Diagnose and fix any regression. Re-run until clean. Pay attention
to benchmark checksums (bsort 0x98, sieve 0xEC, fib_crc 0x2B,
fannkuch 0x10, lfsr16 0x1D) — they must remain unchanged.

> **Implementation Notes**: <empty>

### Step 3.6 — Verification assembly steps from `tests\features\README.md` [ ]

Compile `tests\features\58\v6clang.c` to `v6clang_new01.asm` and
analyze the priority-4 sub-shapes:

- Function pinning `addr=DE, dst=B, A/HL live` should now emit
  `XCHG; MOV B,M; XCHG` (3B/16cc) instead of
  `PUSH PSW; LDAX D; MOV B,A; POP PSW` (4B/44cc). Net: −1B, −28cc.
- Function pinning `addr=BC, dst=B, A live, SpareR=D` should now
  emit `MOV D,A; LDAX B; MOV B,A; MOV A,D` (4B/32cc) instead of
  the PSW envelope (4B/44cc). Net: =B, −12cc.

Iterate to `v6clang_new02.asm`, … if needed.

> **Implementation Notes**: <empty>

### Step 3.7 — Make sure `result.txt` is created (`tests\features\README.md`) [ ]

Document c8080 vs v6clang cycles/bytes per function, plus the
shape-by-shape dispatch matrix.

> **Implementation Notes**: <empty>

### Step 3.8 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: <empty>

### Step 3.9 — Mark O76 complete in `design/future_plans/README.md` [ ]

Add the **DONE** marker on the O76 row in both the Optimization
Plans table and the Implementation order section.

> **Implementation Notes**: <empty>

---

## 4. Expected Results

### Example 1 — `addr=DE, dst=B, A live` (case 7)

**Before**:
```asm
PUSH    PSW          ; 12cc / 1B
LDAX    D            ;  8cc / 1B
MOV     B, A         ;  8cc / 1B
POP     PSW          ; 12cc / 1B
                     ; -----------
                     ; 40cc / 4B   (timings doc has POP PSW at 12cc — see §timings)
```

**After**:
```asm
XCHG                 ;  4cc / 1B
MOV     B, M         ;  8cc / 1B
XCHG                 ;  4cc / 1B
                     ; -----------
                     ; 16cc / 3B
```

Net: −1B, −28cc per fire.

### Example 2 — `addr=BC, dst=B, A live, SpareR=D` (case 6a)

**Before** (case 6, unchanged today):
```asm
PUSH    PSW          ; 16cc / 1B
LDAX    B            ;  8cc / 1B
MOV     B, A         ;  8cc / 1B
POP     PSW          ; 12cc / 1B
                     ; -----------
                     ; 44cc / 4B
```

**After** (case 6a):
```asm
MOV     D, A         ;  8cc / 1B   (SpareR = D)
LDAX    B            ;  8cc / 1B
MOV     B, A         ;  8cc / 1B
MOV     A, D         ;  8cc / 1B
                     ; -----------
                     ; 32cc / 4B
```

Net: =B, −12cc per fire.

### Example 3 — Hot-path benchmark impact

Pointer-walk loops with DE pointer + A accumulator (e.g.
fib_crc, fannkuch shift loop) currently pay the full 44cc/4B PSW
envelope on each `*p` load. After O76, those loads cost 16cc/3B —
a 28cc/byte saving per iteration in the inner loop.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **`MOV partner(dst),M` reads mem[HL] post-XCHG**: a wrong partner mapping silently miscompiles. | Unit-test all 6 partner mappings via lit (cases 7 dst=B, dst=H, dst=L pinned; D and E reachable only when DE-dead-after, where they reduce to case 5). Trace table in design doc §"Why XCHG is universally cheap". |
| **`findDeadGR8AtMI` returns a register that is in fact live across the LDAX/MOV envelope**: would clobber it. | The helper already checks dead-at-MI via forward scan + successor live-in. Same helper used by O71/O72 in production for ~3 weeks without issue. Excludes `A` and `DstReg` explicitly. |
| **RA allocates `(addr=DE, dst ∈ {D,E})` with `DE` live-after** → XCHG bypass would clobber DE. | LLVM RA invariant prohibits this (subreg def kills super-register live range). Verified empirically with `temp/load8p_de_{d,e}3.c` — RA routed through scratch C in both cases. Plan §1 references the probes. |
| **Pre-existing lit tests pinning case 6/7 break**: FileCheck patterns expect `PUSH PSW`. | Anticipated. Step 3.4 updates affected tests; the new emission is strictly cheaper, so updates are lossless. |
| **Benchmark checksums change**: indicates correctness regression. | Step 3.5 runs `tests/run_all.py` which validates 5 benchmark checksums. Any divergence triggers diagnose-and-fix. |

---

## 6. Relationship to Other Improvements

- **O71** (V6CLANG_LOAD16_P redesign): introduced `findDeadGR8AtMI`. O76
  reuses it directly.
- **O72** (V6CLANG_STORE16_P redesign): same helper reuse pattern. O76's
  store companion (`V6CLANG_STORE8_P`) is a future enhancement listed
  in the design doc §Out-of-scope.
- **O42** (Liveness-aware pseudo expansion): introduced
  `isRegDeadAtMI`. O76 reuses it for `A`-liveness.
- **O44** (Adjacent XCHG cancellation): may fold the trailing XCHG
  in case 7 when followed by another DE-using op. Composes
  naturally — O76 emits the canonical XCHG pair, O44 folds when
  legal.

---

## 7. Future Enhancements

- **O76-store**: parallel redesign for `V6CLANG_STORE8_P`. Same
  4-priority structure today; SpareR-A and (less obviously) XCHG
  bypass apply. Deferred to a follow-up plan.

---

## 8. References

* [O76 Design Doc](future_plans/O76_V6CLANG_LOAD8_P_redesign.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c Instruction Timings](../docs/V6ClangInstructionTimings.md)
* [Future Improvements](future_plans/README.md)
* [O71 Plan (helper precedent)](plan_O71_V6CLANG_LOAD16_P_redesign.md)
* [Probe: addr=DE, dst=B](../temp/load8p_de_b.c)
* [Probe: addr=DE, dst=D, DE live](../temp/load8p_de_d3.c)
* [Probe: addr=DE, dst=E, DE live](../temp/load8p_de_e3.c)
