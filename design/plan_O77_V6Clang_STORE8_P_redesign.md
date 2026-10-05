# Plan: V6CLANG_STORE8_P Per-Shape Redesign — SpareR-A + XCHG Bypass

Source design: [O77 V6CLANG_STORE8_P Redesign](future_plans/O77_V6CLANG_STORE8_P_redesign.md)

## 1. Problem

### Current behavior

`V6CLANG_STORE8_P` is the 8-bit store-through-pointer pseudo:

```tablegen
let mayStore = 1 in
def V6CLANG_STORE8_P : V6ClangPseudo<(outs), (ins GR8:$src, GR16:$addr),
    "# STORE8P ($addr), $src",
    [(store i8:$src, i16:$addr)]>;
```

The post-RA expander in `V6ClangInstrInfo::expandPostRAPseudo()`
(`case V6CLANG::V6CLANG_STORE8_P:`, currently line ~2325) implements a
4-priority chain (timings against
[V6ClangInstructionTimings.md](../docs/V6ClangInstructionTimings.md)):

| # | addr | src   | A-liveness | expansion                                   | size | cycles |
|---|------|-------|------------|---------------------------------------------|------|--------|
| 1 | HL   | any   | any        | `MOV M, src`                                | 1B   |  8cc   |
| 2 | BC   | A     | any        | `STAX B`                                    | 1B   |  8cc   |
| 3 | DE   | A     | any        | `STAX D`                                    | 1B   |  8cc   |
| 4 | BC   | non-A | A dead     | `MOV A, src; STAX B`                        | 2B   | 16cc   |
| 5 | DE   | non-A | A dead     | `MOV A, src; STAX D`                        | 2B   | 16cc   |
| 6 | BC   | non-A | A live     | `PUSH PSW; MOV A, src; STAX B; POP PSW`     | 4B   | 44cc   |
| 7 | DE   | non-A | A live     | `PUSH PSW; MOV A, src; STAX D; POP PSW`     | 4B   | 44cc   |

Cases 6 and 7 always pay the `PUSH PSW` / `POP PSW` envelope (28cc)
to preserve `A`, even when (a) a free GR8 is dead at the store (a
2× MOV pair would be 16cc instead of 28cc) or (b) `addr=DE`, where
an `XCHG; MOV M,partner(src); XCHG` bypass skips `STAX` entirely
without ever touching `A`.

### Desired behavior

For case 6 (`addr=BC, src≠A, A live`), dispatch on the availability
of a dead non-A GR8 (`SpareR`):

| Predicate          | Shape                                            | Bytes / Cycles |
|--------------------|--------------------------------------------------|----------------|
| SpareR available   | `MOV spareR,A; MOV A,src; STAX B; MOV A,spareR`  | 4B / 32cc      |
| no SpareR          | `PUSH PSW; MOV A,src; STAX B; POP PSW` (today)   | 4B / 44cc      |

For case 7 (`addr=DE, src≠A, A live`), always emit the XCHG bypass:

| Predicate          | Shape                                            | Bytes / Cycles |
|--------------------|--------------------------------------------------|----------------|
| (any non-A src)    | `XCHG; MOV M, partner(src); XCHG`                | 3B / 16cc      |

`partner(src)` maps `B→B, C→C, D→H, E→L, H→D, L→E`. The trick: after
`XCHG`, `HL` holds `addr`, so a `MOV M,r` writes the value originally
held in `partnerOf(src)` (= `src` itself before XCHG, since XCHG
swapped `src`'s old register into its partner) into `mem[addr]`. The
second `XCHG` restores every GPR (the body `MOV M,r` is read-only on
registers, so XCHG2 is the exact inverse of XCHG1).

Per-fire savings vs current:
- Case 6 → 6a: −12cc, =B (28cc PSW envelope → 16cc 2× MOV).
- Case 7 → 7: −28cc, −1B (44cc/4B → 16cc/3B).

### Root cause

The existing expander considers only one A-preservation lever
(`PUSH PSW` / `POP PSW`) and ignores the `XCHG` swap available when
`addr=DE`. Both improvements require post-RA liveness knowledge
(SpareR availability, `A` liveness), which the register allocator
cannot encode in a fixed `Defs` set without forcing pessimistic
spills on every store.

Unlike the load companion (O76), the store has **no DE-clobber edge
case**: the body `MOV M, r` is read-only on registers, so XCHG2 is
the exact inverse of XCHG1 — every GPR (including DE) returns to its
pre-pseudo value unconditionally. The XCHG bypass is correctness-safe
for every legal `src ∈ {B, C, D, E, H, L}` regardless of post-pseudo
liveness of any register.

---

## 2. Strategy

### Approach: per-shape expansion with cheap-first preservation

Keep `V6CLANG_STORE8_P` exactly as declared today (`(outs),
(ins GR8:$src, GR16:$addr)`, no `Defs`). Replace the `else` body of
priority 4 with a three-way dispatch on
`(AddrReg, ALive, SpareR-available)`:

1. `addr=DE && A live` → **XCHG bypass** (3B/16cc, unconditional for
   any non-A `src`).
2. `addr=BC && A live && SpareR available` → **SpareR-A** envelope
   (4B/32cc).
3. `addr=BC && A live && no SpareR` → **PSW-wrap** (4B/44cc, today's
   path).

Priority 3 (`A dead`) is unchanged.

### Why this works

- **Pressure-friendly.** RA still sees the pseudo as preserving every
  non-`$src`/`$addr` register, so it does not insert spills around
  8-bit stores. The expander's choices are entirely post-RA.
- **Honest at expansion time.** Each shape is selected only when its
  side-effects are demonstrably absent: SpareR-A clobbers a GR8 that
  was already dead; XCHG bypass clobbers nothing observable
  (XCHG2 inverts XCHG1 because the body writes only memory).
- **Reuses existing helpers.** `findDeadGR8AtMI` (added by O71/O72,
  reused by O76) already provides the SpareR search. `isRegDeadAtMI`
  already provides `A`-liveness. No new helpers needed.

### Summary of changes

| Step | What                                                      | Where                                          |
|------|-----------------------------------------------------------|------------------------------------------------|
| Rewrite expander | Three-way dispatch in priority-4 arm           | V6ClangInstrInfo.cpp `case V6CLANG::V6CLANG_STORE8_P:`     |
| (No change) | `V6CLANG_STORE8_P` td declaration unchanged             | V6ClangInstrInfo.td                                |
| Test coverage | Lit test pinning each new shape + feature test    | tests/lit/CodeGen/V6CLANG/, tests/features/59/     |
| Doc updates | Mark O77 done in `design/future_plans/README.md`    | design/future_plans/                           |

---

## 3. Implementation Steps

### Step 3.1 — Rewrite expander: priority-4 three-way dispatch [ ]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp`,
`case V6CLANG::V6CLANG_STORE8_P:` (currently line ~2325).

Replace the existing `else` (priority-4) branch with:

```cpp
} else {
  // AddrReg ∈ {BC, DE}, SrcReg != A, A live. Three-way dispatch:
  //   7  : addr=DE                 → XCHG bypass        (3B/16cc)
  //   6a : addr=BC, SpareR exists  → SpareR-A envelope  (4B/32cc)
  //   6b : addr=BC, no spare       → PSW-wrap fallback  (4B/44cc)
  //
  // Note: unlike V6CLANG_LOAD8_P (O76), the store body MOV M,r modifies
  // no register, so XCHG2 is the exact inverse of XCHG1 — every GPR
  // (incl. DE) returns to its pre-pseudo value. The partner-MOV
  // trick is therefore universally safe for every non-A src; no
  // RA-invariant argument is needed.
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
    // 7: XCHG bypass. 3B / 16cc, unconditional.
    BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVMr)).addReg(partnerOf(SrcReg));
    BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
  } else {
    // addr=BC. SpareR must survive the body unchanged — exclude
    // A and SrcReg.
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
      // 6b: PSW envelope (today's path).
      BuildMI(MBB, MI, DL, get(V6CLANG::PUSH)).addReg(V6CLANG::PSW);
      BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
          .addReg(V6CLANG::A, RegState::Define).addReg(SrcReg);
      BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
          .addReg(V6CLANG::A).addReg(AddrReg);
      BuildMI(MBB, MI, DL, get(V6CLANG::POP), V6CLANG::PSW);
    }
  }
}
```

> **Design Notes**: The current expander unconditionally branches on
> `bool ALive = !isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI);` and emits
> PUSH/POP around `MOV A,src; STAX rp`. The new branch keeps the same
> outer `else` (priority 4 after HL, A-as-src, A-dead checks) and
> replaces only the body. The `A live` predicate is implicit (the
> outer chain already excluded `A dead` in priority 3).
>
> `findDeadGR8AtMI` already exists at
> [V6ClangInstrInfo.cpp:506](../llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.cpp#L506).
> It excludes `A` automatically and accepts up-to-two extra exclude
> registers. The `Exclude2=SrcReg` argument is essential: SpareR must
> survive the entire envelope including the `MOV A,src` step, so it
> cannot alias `SrcReg`. The XCHG bypass uses partner-of-src so it
> writes the byte originally held in `src` into `mem[addr]` —
> equal to `src` itself for `src ∈ {B,C}` and equal to the XCHG
> image for `src ∈ {D,E,H,L}`.

> **Implementation Notes**: <empty>

### Step 3.2 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Fix any compile errors, then proceed.

> **Implementation Notes**: <empty>

### Step 3.3 — Lit test: store8p-shape-redesign.ll [ ]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/store8p-shape-redesign.ll`

Pin each priority-4 sub-shape with IR + register-asm constraints.
Coverage matrix:

| label                | addr | src    | A live | SpareR | expected emission                              |
|----------------------|------|--------|--------|--------|------------------------------------------------|
| `case4_bc_a_dead`    | BC   | non-A  | dead   | n/a    | `MOV A,src; STAX B` (priority 4, unchanged)    |
| `case5_de_a_dead`    | DE   | non-A  | dead   | n/a    | `MOV A,src; STAX D` (priority 5, unchanged)    |
| `case6a_bc_spareR`   | BC   | non-A  | live   | yes    | `MOV r,A; MOV A,src; STAX B; MOV A,r`          |
| `case6b_bc_no_spare` | BC   | non-A  | live   | no     | `PUSH PSW; MOV A,src; STAX B; POP PSW`         |
| `case7_de_b`         | DE   | B      | live   | n/a    | `XCHG; MOV M,B; XCHG`                          |
| `case7_de_c`         | DE   | C      | live   | n/a    | `XCHG; MOV M,C; XCHG`                          |
| `case7_de_h`         | DE   | H      | live   | n/a    | `XCHG; MOV M,D; XCHG` (partner-MOV trick)      |
| `case7_de_l`         | DE   | L      | live   | n/a    | `XCHG; MOV M,E; XCHG` (partner-MOV trick)      |

Unlike O76, the `src ∈ {D, E}` rows of case 7 ARE testable here —
the XCHG bypass for the store is universally safe regardless of
`DE` post-liveness. Add at least one such row (e.g. `case7_de_d`
expecting `XCHG; MOV M,H; XCHG`) to exercise the partner mapping
fully.

> **Design Notes**: Use `register uint8_t v asm("X") = ...;` pinning
> + a trailing inline-asm sink with `"a"`, `"r"` constraints to
> force A and HL/BC/DE liveness across the store. To deny SpareR
> for case6b, hammer **all** non-A non-src GR8s with `"r"` clobbers
> across the store.

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

Compile `tests\features\59\v6clang.c` to `v6clang_new01.asm` and
analyze the priority-4 sub-shapes:

- Function pinning `addr=DE, src=B, A/HL live` should now emit
  `XCHG; MOV M,B; XCHG` (3B/16cc) instead of
  `PUSH PSW; MOV A,B; STAX D; POP PSW` (4B/44cc). Net: −1B, −28cc.
- Function pinning `addr=BC, src=B, A live, SpareR=D` should now
  emit `MOV D,A; MOV A,B; STAX B; MOV A,D` (4B/32cc) instead of
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

### Step 3.9 — Mark O77 complete in `design/future_plans/README.md` [ ]

Add the **DONE** marker on the O77 row in both the Optimization
Plans table and the Implementation order section.

> **Implementation Notes**: <empty>

---

## 4. Expected Results

### Example 1 — `addr=DE, src=B, A live` (case 7)

**Before**:
```asm
PUSH    PSW          ; 12cc / 1B
MOV     A, B         ;  8cc / 1B
STAX    D            ;  8cc / 1B
POP     PSW          ; 12cc / 1B
                     ; -----------
                     ; 40cc / 4B
```

**After**:
```asm
XCHG                 ;  4cc / 1B
MOV     M, B         ;  8cc / 1B
XCHG                 ;  4cc / 1B
                     ; -----------
                     ; 16cc / 3B
```

Net: −1B, −28cc per fire.

### Example 2 — `addr=BC, src=B, A live, SpareR=D` (case 6a)

**Before** (case 6, unchanged today):
```asm
PUSH    PSW          ; 16cc / 1B
MOV     A, B         ;  8cc / 1B
STAX    B            ;  8cc / 1B
POP     PSW          ; 12cc / 1B
                     ; -----------
                     ; 44cc / 4B
```

**After** (case 6a):
```asm
MOV     D, A         ;  8cc / 1B   (SpareR = D)
MOV     A, B         ;  8cc / 1B
STAX    B            ;  8cc / 1B
MOV     A, D         ;  8cc / 1B
                     ; -----------
                     ; 32cc / 4B
```

Net: =B, −12cc per fire.

### Example 3 — Hot-path benchmark impact

Pointer-walk loops with DE destination pointer + A accumulator
(e.g. `*p++ = a` in a buffer-fill, fannkuch perm shift) currently
pay the full 44cc/4B PSW envelope on each `*p = src` store. After
O77, those stores cost 16cc/3B — a 28cc/byte saving per iteration
in the inner loop.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **Wrong partner mapping** silently miscompiles. | Unit-test all 6 partner mappings via lit (`case7_de_b/c/d/e/h/l`). Trace table in design doc §"Why XCHG is universally safe". |
| **`findDeadGR8AtMI` returns a register live across the envelope** → clobber. | Helper checks dead-at-MI via forward scan + successor live-in. Used by O71/O72/O76 in production. Excludes `A` and `SrcReg` explicitly. |
| **XCHG body modifies a register** (it doesn't — `MOV M,r` is read-only on regs). Were that ever to change, XCHG2 would no longer invert XCHG1. | Body is fixed `MOV M, partner(src)`. Encoding-level invariant. |
| **Pre-existing lit tests pinning case 6/7 break**: FileCheck patterns expect `PUSH PSW`. | Anticipated. Step 3.4 updates affected tests; new emission is strictly cheaper, updates are lossless. |
| **Benchmark checksums change**: indicates correctness regression. | Step 3.5 runs `tests/run_all.py` validating 5 benchmark checksums. Any divergence triggers diagnose-and-fix. |

---

## 6. Relationship to Other Improvements

- **O71/O72** (V6CLANG_LOAD16_P / V6CLANG_STORE16_P redesigns): introduced
  `findDeadGR8AtMI`. O77 reuses it directly.
- **O76** (V6CLANG_LOAD8_P redesign): the load companion. Same dispatch
  structure; O76 needed an RA-invariant argument for `dst ∈ {D,E}`
  XCHG-bypass safety, O77 does not (read-only register access).
- **O42** (Liveness-aware pseudo expansion): introduced
  `isRegDeadAtMI`. O77 reuses it for `A`-liveness.
- **O44** (Adjacent XCHG cancellation): may fold the trailing XCHG
  in case 7 when followed by another DE-using op. Composes
  naturally — O77 emits the canonical XCHG pair, O44 folds when
  legal.
- **O49** (Direct memory ALU/store ISel): `V6CLANG_STORE8_IMM_P` and the
  M-operand RMW pseudos have separate expanders (`expandMemOpM`);
  O77 leaves them alone.

---

## 7. Future Enhancements

- **`addr=BC` XCHG-via-DE alternative.** A path of the form
  `XCHG; MOV H,B; MOV L,C; MOV M,src; XCHG` would preserve `A` for
  `addr=BC` too, but it costs 5B / 36cc (worse than 6a's 4B / 32cc)
  and unconditionally clobbers DE. Not pursued.

---

## 8. References

* [O77 Design Doc](future_plans/O77_V6CLANG_STORE8_P_redesign.md)
* [O76 Plan (load companion)](plan_O76_V6CLANG_LOAD8_P_redesign.md)
* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c Instruction Timings](../docs/Vector_06c_instruction_timings.md)
* [Future Improvements](future_plans/README.md)
