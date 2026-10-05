# Plan: O78 — V6CLANG_STORE8_IMM_P Per-Shape Redesign

## 1. Problem

### Current behavior

`V6CLANG_STORE8_IMM_P` (immediate-source 8-bit store-through-pointer) lowers
through the generic `expandMemOpM` helper in `V6ClangInstrInfo.cpp`:

```cpp
case V6CLANG::V6CLANG_STORE8_IMM_P: {
  int64_t Imm = MI.getOperand(0).getImm();
  Register AddrReg = MI.getOperand(1).getReg();
  expandMemOpM(MBB, MI, *this, RI, AddrReg,
      [&](MachineBasicBlock &B, MachineBasicBlock::iterator Ip) {
        BuildMI(B, Ip, DL, get(V6CLANG::MVIM)).addImm(Imm);
      });
  MI.eraseFromParent();
  return true;
}
```

`expandMemOpM` produces 4 shapes ranked by `AddrReg`/HL-liveness only:

| # | addr | HL-live | code                                           | size | cycles |
|---|------|---------|------------------------------------------------|------|--------|
| 1 | HL   | n/a     | `MVI M, imm`                                   | 2B   | 12cc   |
| 2 | DE   | n/a     | `XCHG; MVI M, imm; XCHG`                       | 4B   | 20cc   |
| 3 | BC   | dead    | `MOV L,C; MOV H,B; MVI M, imm`                 | 4B   | 28cc   |
| 4 | BC   | live    | `PUSH H; MOV L,C; MOV H,B; MVI M; POP H`       | 6B   | 56cc   |

A-liveness is ignored entirely.

### Desired behavior

Add two new shapes that exploit `MVI A, imm; STAX rp` and the DE-routing
trick. Final dispatch (timings from `docs/V6ClangInstructionTimings.md`):

| addr | A    | HL   | DE   | path                                            | size | cycles |
|------|------|------|------|-------------------------------------------------|------|--------|
| HL   | *    | *    | *    | `MVI M, imm`                                    | 2B   | 12cc   |
| BC   | dead | *    | *    | `MVI A, imm; STAX B`                            | 3B   | 16cc   |
| DE   | dead | *    | *    | `MVI A, imm; STAX D`                            | 3B   | 16cc   |
| DE   | live | *    | *    | `XCHG; MVI M, imm; XCHG`                        | 4B   | 20cc   |
| BC   | live | dead | *    | `MOV L,C; MOV H,B; MVI M, imm`                  | 4B   | 28cc   |
| BC   | live | live | dead | `MOV D,B; MOV E,C; XCHG; MVI M; XCHG`           | 5B   | 36cc   |
| BC   | live | live | live | `PUSH H; MOV L,C; MOV H,B; MVI M; POP H`        | 6B   | 56cc   |

Wins:
- BC + A dead: −12 to −40cc/fire, −1 to −3B.
- DE + A dead: −4cc, −1B.
- BC + HL live + DE dead: −20cc, −1B.

Worst-case `BC, all live` row preserved.

### Root cause

`expandMemOpM` is generic for every M-operand pseudo (ADDM/INRM/DCRM/MVIM
etc.). Those siblings have no STAX-equivalent and genuinely need `M`.
For `V6CLANG_STORE8_IMM_P` specifically, `MVI A, imm; STAX rp` is the
strictly-cheaper alternative when A is dead. The current expander never
checks A-liveness, so the win is missed.

---

## 2. Strategy

### Approach: stop sharing `expandMemOpM`; specialised expander

Replace the `STORE8_IMM_P` case in `V6ClangInstrInfo::expandPostRAPseudo`
with an inline expander that dispatches on `(AddrReg, A-dead, HL-dead,
DE-dead)`. Other M-operand pseudos still use the generic helper.

### Why this works

- `MVI A, imm` and `STAX rp` together have no side effect on memory other
  than the targeted byte; the end-state is identical to `MVI M, imm`
  routed through HL=AddrReg.
- A-dead is the precondition that lets us trash A. The four other M-pseudos
  (ADDM/SUBM/INRM/DCRM/CMPM with M-source) cannot use A-routing because
  their semantics intrinsically need to compose with A or M — only
  `MVIM` is purely a memory write.
- The DE-routing trick (`MOV D,B; MOV E,C; XCHG; MVI M; XCHG`) preserves
  HL because `MVI M` doesn't touch any register; the second XCHG is the
  exact inverse of the first. DE-dead is the precondition that lets us
  trash DE.

### Summary of changes

- `V6ClangInstrInfo.cpp`: replace the `case V6CLANG::V6CLANG_STORE8_IMM_P` block
  (one `expandMemOpM` call) with ~50 lines of specialised dispatch.
- No `.td` changes (operand list unchanged, no new pseudo).
- Reuses existing `isRegDeadAtMI` helper. No `findDeadGR8AtMI`.
- One new lit test + one feature test (`tests/features/60/`).

---

## 3. Implementation Steps

### Step 3.1 — Replace `V6CLANG_STORE8_IMM_P` case in `expandPostRAPseudo` [x]

File: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp` (~line 2459).

New body:

```cpp
case V6CLANG::V6CLANG_STORE8_IMM_P: {
  int64_t Imm = MI.getOperand(0).getImm();
  Register AddrReg = MI.getOperand(1).getReg();

  if (AddrReg == V6CLANG::HL) {
    // Row 1: direct.
    BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
  } else {
    bool ADead = isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI);
    if (ADead) {
      // Rows 2/3: A dead → MVI A, imm; STAX rp.
      BuildMI(MBB, MI, DL, get(V6CLANG::MVIr), V6CLANG::A).addImm(Imm);
      BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
          .addReg(V6CLANG::A).addReg(AddrReg);
    } else if (AddrReg == V6CLANG::DE) {
      // Row 4: A live, addr=DE → XCHG bypass.
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
      BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
    } else {
      // AddrReg == V6CLANG::BC, A live.
      bool HLDead = isRegDeadAtMI(V6CLANG::HL, MI, MBB, &RI);
      bool DEDead = isRegDeadAtMI(V6CLANG::DE, MI, MBB, &RI);
      if (HLDead) {
        // Row 5: BC + HL dead.
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::L).addReg(V6CLANG::C);
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::H).addReg(V6CLANG::B);
        BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
      } else if (DEDead) {
        // Row 6: BC + HL live + DE dead → DE-route.
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::D).addReg(V6CLANG::B);
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::E).addReg(V6CLANG::C);
        BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
        BuildMI(MBB, MI, DL, get(V6CLANG::MVIM)).addImm(Imm);
        BuildMI(MBB, MI, DL, get(V6CLANG::XCHG));
      } else {
        // Row 7: BC, all live → PUSH H envelope (legacy fallback).
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
  }
  MI.eraseFromParent();
  return true;
}
```

> **Design Notes**: STAX operand format mirrors line 2336/2390 of the
> same file: `BuildMI(... STAX).addReg(V6CLANG::A).addReg(AddrReg)`. PUSH/POP
> HL must include the SP implicit-def operand to keep the verifier happy
> (matches the existing BC-fallback path inside `expandMemOpM`).
>
> **Implementation Notes**: <empty. filled after completion>

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**:

### Step 3.3 — Lit test: `store8imm-shape-redesign.ll` [x]

New file `llvm-project/llvm/test/CodeGen/V6Clang/store8imm-shape-redesign.ll`
covering all 7 rows. Use free-list CC pinning to control AddrReg
(1st i16 arg → HL, 2nd → DE, 3rd → BC) plus inline-asm `OUT 0xde`
consumers to control liveness of A/HL/DE.

Required CHECK shapes:
- `addr=HL, imm=0x42`: `MVI M, 0x42` only.
- `addr=BC, A dead`: `MVI A, 0x42`/`STAX B`, no PUSH/POP, no XCHG.
- `addr=DE, A dead`: `MVI A, 0x42`/`STAX D`.
- `addr=DE, A live`: `XCHG`/`MVI M`/`XCHG`.
- `addr=BC, A live, HL dead`: `MOV L, C`/`MOV H, B`/`MVI M`, no PUSH H.
- `addr=BC, A live, HL live, DE dead`: `MOV D, B`/`MOV E, C`/`XCHG`/`MVI M`/`XCHG`.
- `addr=BC, all live`: `PUSH H`/.../`POP H` envelope (legacy).

Run with:
```
llvm-build\bin\llvm-lit -v llvm-project\llvm\test\CodeGen\V6Clang\store8imm-shape-redesign.ll
```

> **Implementation Notes**:

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**:

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Folder `tests\features\60\`. Mirror feature 59's structure: pinned-register
test for each new path (BC+A-dead, DE+A-dead, BC+HL-live+DE-dead) plus the
unchanged HL/DE-A-live/BC-all-live rows for negative coverage. Driver
calls each.

> **Implementation Notes**:

### Step 3.6 — Make sure result.txt is created. `tests\features\README.md` [x]

Compare cycles/bytes of v6clang_old vs v6clang_new vs c8080 per function.

> **Implementation Notes**:

### Step 3.7 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:
>
> - Expander rewritten in `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`
>   (~line 2459) as a per-shape dispatch covering all seven rows of the
>   design table. `expandMemOpM` is no longer used for `V6CLANG_STORE8_IMM_P`.
> - Lit test: 7 CHECK blocks at
>   `llvm-project/llvm/test/CodeGen/V6Clang/store8imm-shape-redesign.ll` — PASS.
> - `python tests\run_all.py` → 134/134 PASS. Benchmarks unchanged.
> - Per-fire wins (vs OLD): row 2 (BC, A-dead) −3B/−40cc, row 3 (DE, A-dead)
>   −1B/−4cc, row 6 (BC, DE-dead) 0B/−20cc. Other shapes already optimal.
> - Total across the seven feature-60 probes: −4B / −64cc per call cycle.

---

## 4. Expected Results

### Example 1 — `*p = 0` over BC pointer with A dead

Common in zero-init loops. Today emits 6B/56cc when HL is live elsewhere;
new emit is 3B/16cc. Composes with O55 (`MVI A, 0` → `XRA A`) for an
extra −1B/−4cc.

### Example 2 — Tag-byte store via BC with HL holding loop pointer, DE free

Today: 56cc. New: 36cc.

### Example 3 — `*p = imm` via DE with A live (e.g. `imm` is also an arg in A's region)

Unchanged behaviour: 4B/20cc.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `isRegDeadAtMI` reports a false positive for A on the entry instruction of a successor that defines A on entry | Same semantics as already used by O76/O77; covered by lit & regression suite |
| Mis-ordering of ADead vs DEDead checks could miss the BC+HL-live+DE-dead path | Dispatch ordered cheapest-first (ADead before DEDead); table verifies strictly cheaper-or-equal at every row |
| PUSH H operand list missing SP implicit-def | Mirrors existing fallback inside `expandMemOpM` verbatim |
| Test pollution: free-list CC change may shift register pinning | Use direct `register T x asm("...")` and inline asm sinks (matches feature 59) |

---

## 6. Relationship to Other Improvements

- **O46/O49** introduced this pseudo and the generic `expandMemOpM`. O78 only
  refines the expander.
- **O55** (`MVI A, 0` → `XRA A`): composes naturally with the A-dead paths
  for `*p = 0`.
- **O76 / O77**: orthogonal — those handle register-source loads/stores;
  O78 handles immediate-source stores.
- **`expandMemOpM`**: unchanged; still used by ADDM/SUBM/INRM/DCRM/CMPM.

## 7. Future Enhancements

- Symmetric A-routing for register-source `V6CLANG_STORE8_P` is already covered
  by O77 (priority 4 fallback uses STAX).

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\V6ClangInstructionTimings.md)
* [Future Improvements](design\future_plans\README.md)
* [O78 design](design\future_plans\O78_V6CLANG_STORE8_IMM_P_redesign.md)
* [O77 plan (template)](design\plan_O77_V6CLANG_STORE8_P_redesign.md)
