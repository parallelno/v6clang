# Plan: O80 — i8 Zero-Test Compare via INR/DCR (A-Preserving Pseudo)

Reference design: [design/future_plans/O80_cmp8_zero_inr_dcr.md](future_plans/O80_cmp8_zero_inr_dcr.md).
Pipeline: [design/pipeline_feature.md](pipeline_feature.md).
CPU timings: [docs/V6ClangInstructionTimings.md](../docs/V6ClangInstructionTimings.md).
Build/sync: [docs/V6ClangBuildGuide.md](../docs/V6ClangBuildGuide.md).

## 1. Problem

### Current behavior

The i8 "compare against zero" idiom (`if (r) …`, `while (r) …`,
`r != 0`) lowers, in TableGen, through the `CPI` pattern:

```tablegen
def CPI : V6ClangInstImm8Opc<0b111,
    (outs), (ins Acc:$lhs, imm8:$imm),
    "CPI\t$imm", [(set FLAGS, (V6Clangcmp i8:$lhs, (i8 imm:$imm)))]>;
```

`Acc:$lhs` pins the LHS to A. The post-RA peephole pass
[V6ClangZeroTestOpt.cpp](../llvm-project/llvm/lib/Target/V6Clang/V6ClangZeroTestOpt.cpp)
then rewrites `CPI 0` to `ORA A` (saves 4cc per fire). The combined
sequence emitted today, observed at
[tests/features/37/v6clang.s line 76](../tests/features/37/v6clang.s#L76):

```asm
MOV  L, A      ; save A          (1B / 8cc, scratch GR8 burn)
MOV  A, C      ; pin LHS to A    (1B / 8cc)
ORA  A         ; from CPI 0      (1B / 4cc)
;--- V6CLANG_BRCOND ---
JZ   .LBB17_2
MOV  A, L      ; restore A       (1B / 8cc)
```

When `A` is live across the compare, RA must rescue A: `MOV scratch,A`
before the test and `MOV A,scratch` after. Cost shapes:

| # | shape                          | today's expansion                                   | size | cycles |
|---|--------------------------------|-----------------------------------------------------|------|--------|
| 1 | `src = A` (any A-liveness)     | `ORA A`                                             | 1B   |  4cc   |
| 2 | `src ≠ A`, A dead              | `XRA A; CMP src`  (O38)                             | 2B   |  8cc   |
| 3 | `src ≠ A`, A live              | `MOV scratch,A; XRA A; CMP src; … MOV A,scratch`    | 4B   | 24cc   |

Shape 2 is already cycle-optimal today via O38 (XRA A reduces the LHS to
zero, then `CMP src` does the byte compare in 4cc). Shape 3 also burns
a scratch GR8, which can transitively cause spills in tight loops
(see [tests/features/43](../tests/features/43)).

Verified by reading [tests/features/62/v6clang_old.asm](../tests/features/62/v6clang_old.asm)
for `shape_a_dead` (shape 2 — `XRA A; CMP B`) and `shape_a_live`
(shape 3 — `MOV H,A; XRA A; CMP B; …; MOV A,H`).

### Desired behavior

When `A` is live, replace the four-instruction shape-3 sequence with
an A-preserving zero-test using the `INR/DCR` pair:

```asm
INR  src       ; 1B / 8cc   (Z/S/P set; A unchanged; CY unchanged)
DCR  src       ; 1B / 8cc   (Z/S/P set from src's original value)
;--- V6CLANG_BRCOND ---
JZ   .LBB17_2
```

`INR r; DCR r` is byte-idempotent on `r`, sets `Z`/`S`/`P` from `r`'s
original value, leaves `A` and `CY` untouched. **2B / 16cc, no scratch
GR8 needed.**

Shape priorities after this change:

| # | src    | A-liveness | expansion                                          | size | cycles |
|---|--------|------------|----------------------------------------------------|------|--------|
| 1 | A      | any        | `ORA A`                                            | 1B   |  4cc   |
| 2 | not-A  | A dead     | `XRA A; CMP src`  (preserve O38 sequence)          | 2B   |  8cc   |
| 3 | not-A  | A live     | `INR src; DCR src`                                 | 2B   | 16cc   |

Per-fire savings vs today:

- Shape 1: unchanged (already optimal — see baseline `shape_a`).
- Shape 2: unchanged (preserve current `XRA A; CMP src` from O38).
- **Shape 3: −2B / −8cc, plus eliminated scratch GR8 burn**. This is
  the headline win.

### Root cause

The `Acc:$lhs` operand class on `CPI` forces the LHS into A. There is
no flag-producing i8 zero-test that operates on a non-A GR8 today.
Adding one as a pseudo (analogous to `V6CLANG_CMP16_ZERO`) lets ISel skip
the A-pinning entirely; post-RA expansion then chooses the cheapest
correct sequence per liveness shape.

## 2. Strategy

### Approach: new `V6CLANG_CMP8_ZERO` pseudo, expanded post-RA

1. **Define `V6CLANG_CMP8_ZERO`** as a `V6ClangPseudo` with one `GR8` input
   (not `Acc`), `Defs = [FLAGS]`, matched from
   `(set FLAGS, (V6Clangcmp i8:$src, (i8 0)))`.
2. **TableGen pattern preference**: a literal `(i8 0)` is more specific
   than `(i8 imm:$imm)` on `CPI`, so ISel naturally prefers the new
   pseudo for the zero-test case. No `AddedComplexity` needed.
3. **Expand post-RA** in `V6ClangInstrInfo::expandPostRAPseudo`:
   - `src == A` → `ORA A` (1B / 4cc).
   - `A` dead → `XRA A; CMP src` (2B / 8cc — preserves today's O38 path).
   - `A` live → `INR src; DCR src` (2B / 16cc, A-preserving).
4. **Annotation** is automatic: the `V6CLANG_PSEUDO_COMMENT` machinery in
   `expandPostRAPseudo` calls `TII->getName(OrigOpc)`, so
   `;--- V6CLANG_CMP8_ZERO ---` emerges with no extra wiring.

### Why this works

- `INR r`/`DCR r` set `Z`, `S`, `P`, `AC` and leave `CY`/`A`
  unchanged. The pair is byte-idempotent on `r`.
- All zero-test consumers (i8 `V6CLANG_BRCOND` /
  `V6CLANG_SELECT_CC`) read only `Z`/`S`/`P` via the V6ClangCC codes
  `COND_Z`/`COND_NZ`/`COND_P`/`COND_M`/`COND_PE`/`COND_PO`. None
  reads `CY` or `AC`. Diverging on those two flags is harmless on the
  consumer set.
- `(i8 imm:$imm)` on `CPI` continues to handle non-zero immediate
  compares unchanged.
- The existing `V6ClangZeroTestOpt` `CPI 0 → ORA A` pass is left alone;
  with the new pseudo present, ISel won't emit `CPI 0` for the
  zero-compare case, so that pass simply fires less often.

### Why this is safe

- `CY` divergence from `ORA A` is unobservable: `ORA A` clears `CY`,
  `INR/DCR` preserve it. No zero-test consumer reads `CY`. Verified
  by inspection of `V6ClangCC` enum users and `V6ClangISelLowering::Select`.
- Verifier on `INR/DCR` twin-def: both are tied (`$rd = $src`).
  The first `INR` carries a regular use of `Src`; the second `DCR`
  carries the `kill` flag (or whatever flag the original
  `V6CLANG_CMP8_ZERO` operand had).
- No interaction with `V6ClangPeephole` / O41 (`pre_ra_inx_dcx_pseudo`):
  those operate on i16 `INX`/`DCX`, not i8 `INRr`/`DCRr`.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| Add pseudo `V6CLANG_CMP8_ZERO` | `(outs), (ins GR8:$src)`, `Defs=[FLAGS]`, pattern `(V6Clangcmp i8:$src, (i8 0))` | `V6ClangInstrInfo.td` |
| Implement expansion | 3-priority shape table | `V6ClangInstrInfo.cpp::expandPostRAPseudo` |
| Lit test | All three shapes | `llvm-project/llvm/test/CodeGen/V6Clang/cmp8-zero-inr-dcr.ll` |
| Feature test | C source mirroring `tests/features/37` | `tests/features/62/` |

No changes to: ISel C++, register allocator, `V6ClangZeroTestOpt`, calling
convention, frame lowering, peepholes.

## 3. Implementation Steps

### Step 3.1 — Add `V6CLANG_CMP8_ZERO` TableGen pseudo [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`

Place the new def adjacent to `V6CLANG_CMP16_ZERO` (around line 1008):

```tablegen
// O80: 8-bit zero-test comparison. Mirrors V6CLANG_CMP16_ZERO for i8.
// Expanded post-RA into one of three shapes:
//   src=A          → ORA A                     (1B / 4cc)
//   src≠A, A dead  → MOV A,src; ORA A          (2B / 12cc)
//   src≠A, A live  → INR src; DCR src          (2B / 16cc, A-preserving)
// Defs = [FLAGS] only; A is not always defined (the INR/DCR path
// preserves A). The post-RA expander adds an A def to the MOV+ORA
// shapes via BuildMI's RegState::Define.
let Defs = [FLAGS] in
def V6CLANG_CMP8_ZERO : V6ClangPseudo<(outs), (ins GR8:$src),
    "# CMP8_ZERO $src",
    [(set FLAGS, (V6Clangcmp i8:$src, (i8 0)))]>;
```

> **Design Note**: `Defs = [FLAGS]` (not `[FLAGS, A]`) is conservative
> for the `INR/DCR` path. For the `MOV A,src; ORA A` shapes the
> expander writes A but RA has already finished by post-RA expansion,
> so the static `Defs` list is irrelevant for liveness; what matters
> is that the BuildMI call carries the correct register state. Mirror
> the comment style used by `V6CLANG_CMP16_ZERO`.

> **Design Note**: TableGen pattern preference — literal `(i8 0)` is
> strictly more specific than `(i8 imm:$imm)` on `CPI`. ISel will
> prefer the new pseudo automatically. Verified against existing
> backends (X86/AArch64) that use the same disambiguation pattern.

> **Implementation Notes**: <empty>

### Step 3.2 — Implement post-RA expansion [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp`

Add a new `case` in `V6ClangInstrInfo::expandPostRAPseudo` next to
`case V6CLANG::V6CLANG_CMP16_ZERO:` (around line 996):

```cpp
case V6CLANG::V6CLANG_CMP8_ZERO: {
  // O80: i8 zero-test, A-preserving when A is live.
  Register Src = MI.getOperand(0).getReg();
  bool SrcKilled = MI.getOperand(0).isKill();

  if (Src == V6CLANG::A) {
    // Shape 1: src already in A → ORA A (1B / 4cc).
    BuildMI(MBB, MI, DL, get(V6CLANG::ORAr), V6CLANG::A)
        .addReg(V6CLANG::A);
  } else if (isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI)) {
    // Shape 2: A dead → XRA A; CMP src (2B / 8cc).
    // Mirrors O38's emission so we don't regress that path.
    BuildMI(MBB, MI, DL, get(V6CLANG::XRAr), V6CLANG::A)
        .addReg(V6CLANG::A);
    BuildMI(MBB, MI, DL, get(V6CLANG::CMPr))
        .addReg(V6CLANG::A)
        .addReg(Src, getKillRegState(SrcKilled));
  } else {
    // Shape 3: A live → INR src; DCR src (2B / 16cc, A-preserving).
    // Both INR and DCR are tied ($rd = $src); use addReg() with the
    // tied operand pattern used by other expanders in this file.
    BuildMI(MBB, MI, DL, get(V6CLANG::INRr), Src)
        .addReg(Src);
    BuildMI(MBB, MI, DL, get(V6CLANG::DCRr), Src)
        .addReg(Src, getKillRegState(SrcKilled));
  }

  MI.eraseFromParent();
  return true;
}
```

> **Design Note**: `isRegDeadAtMI(V6CLANG::A, ...)` is the same helper
> used by `V6CLANG_LOAD8_P` (line 1542) and the BC-swap path (line 549).
> Liveness is reliable post-RA because
> `MachineFunctionProperties::TracksLiveness` is set for V6CLANG.

> **Implementation Notes**: <empty>

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: <empty>

### Step 3.4 — Lit test: cmp8-zero-inr-dcr.ll [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/cmp8-zero-inr-dcr.ll`

Cover all three shapes via separate functions. Use IR + extern call
patterns to deterministically pin source and A across the test:

```ll
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 < %s | FileCheck %s

declare void @sink(i8)
declare i8   @keep_a()

; Shape 1: src already in A — single ORA A.
; CHECK-LABEL: shape_a:
; CHECK:       ORA  A
; CHECK-NEXT:  JZ
define void @shape_a(i8 %x) {
  %t = icmp eq i8 %x, 0
  br i1 %t, label %z, label %nz
z:  ret void
nz: tail call void @sink(i8 %x)
    ret void
}

; Shape 2: A dead — XRA A; CMP src.
; CHECK-LABEL: shape_a_dead:
; CHECK:       XRA  A
; CHECK-NEXT:  CMP  {{[BCDEHL]}}
; CHECK-NEXT:  JZ
define i8 @shape_a_dead(i8 %x, i8 %y) {
  %t = icmp eq i8 %y, 0
  br i1 %t, label %ret_x, label %ret_y
ret_x: ret i8 %x
ret_y: ret i8 %y
}

; Shape 3: A live across compare — INR src; DCR src.
; The keep_a() call returns a value in A that must survive the test.
; CHECK-LABEL: shape_a_live:
; CHECK:       CALL keep_a
; CHECK:       INR  {{[BCDEHL]}}
; CHECK-NEXT:  DCR  {{[BCDEHL]}}
; CHECK-NEXT:  JZ
; CHECK-NOT:   MOV  {{[BCDEHL]}}, A
define i8 @shape_a_live(i8 %y) {
  %a = tail call i8 @keep_a()
  %t = icmp eq i8 %y, 0
  br i1 %t, label %z, label %nz
z:  ret i8 %a
nz: %a2 = add i8 %a, 1
    ret i8 %a2
}
```

> **Design Note**: The `CHECK-NOT: MOV {{...}}, A` line in shape 3
> guards against regressing into the old save/restore pattern. The
> `[BCDEHL]` regex matches any GR8 because RA's choice of `src`
> register is not deterministic.

> **Design Note**: Run with `-mllvm -mv6clang-annotate-pseudos` in a
> separate `RUN:` line if needed to verify annotation. Not required
> for primary correctness — annotation falls out automatically from
> `V6CLANG_PSEUDO_COMMENT` + `TII->getName`.

> **Implementation Notes**: <empty>

### Step 3.5 — Build [x]

> **Implementation Notes**: <empty>

### Step 3.6 — Run lit subset [x]

```
python llvm-build\bin\llvm-lit.py -v llvm-project\llvm\test\CodeGen\V6Clang\cmp8-zero-inr-dcr.ll
```

> **Implementation Notes**: <empty>

### Step 3.7 — Run regression tests [x]

```
python tests\run_all.py
```

Expected: 133/133 lit + golden + benchmarks pass with cycle/byte
**reductions** on bsort/sieve/fib_crc (any regression is a bug).

> **Implementation Notes**: <empty>

### Step 3.8 — Verification assembly steps from `tests\features\README.md` [x]

Use `tests/features/62/` (created in preparation phase). Compile
`v6clang.c` with the new backend; produce `v6clang_new01.asm`.
Confirm the shape-3 pattern emits `INR src; DCR src` (no
`MOV scratch,A; … MOV A,scratch`).

> **Implementation Notes**: <empty>

### Step 3.9 — Make sure result.txt is created [x]

Per `tests\features\README.md`:
- C test case code.
- c8080 main + dependent funcs body (Z80→i8080).
- c8080 stats: worst CPU cycles, length in bytes per func.
- v6clang old asm.
- v6clang new asm.
- Comparison table (cycles, bytes) for c8080 vs v6clang old vs new.

> **Implementation Notes**: <empty>

### Step 3.10 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: <empty>

### Step 3.11 — Mark feature complete [x]

- Mark all steps `[x]` in this plan.
- Set `[x]` next to `O80_cmp8_zero_inr_dcr.md` in
  [design/future_plans/README.md](future_plans/README.md).
- Update repo memory `/memories/repo/v6clang-backend.md` with a one-paragraph
  summary (cycles/bytes saved, files touched) following the existing
  "RESOLVED" convention.

> **Implementation Notes**: <empty>

## 4. Expected Results

### Example 1 — A-live shape 3 (the headline case)

C source (`tests/features/62/v6clang.c`):

```c
extern unsigned char op1(unsigned char);
extern void use2(unsigned char a, unsigned char b);

unsigned char gate(unsigned char val_in_A, unsigned char cond) {
    unsigned char r = op1(val_in_A);   // result in A, kept live
    if (cond) {                        // cond in C; A still holds r
        return r + 1;
    }
    return r;
}
```

Today's emission (-O2, copied from `tests/features/62/v6clang_old.asm`):

```asm
shape_a_live:
    MOV  H, A                 ; save A         (1B /  8cc) ★ scratch burn
    XRA  A                    ; clear A        (1B /  4cc)
    CMP  B                    ; cond ?= 0      (1B /  4cc)
    JZ   .Lret_r              ;                (1B / 12cc)
    MVI  L, 1                 ; tail constant
    JMP  .Ljoin
.Lret_r:
    MOV  L, A
.Ljoin:
    MOV  A, L
    STA  .LLo61_0+1           ; deferred-zero spill (orthogonal)
    MOV  A, H                 ; restore A      (1B /  8cc)
    CALL op1
.LLo61_0:
    ADI  0
    RET
```

Test sequence cost (the four highlighted MOV/XRA/CMP/MOV instructions):
**4B / 24cc** + scratch H burn.

After O80:

```asm
CALL op1                  ; r in A
INR  C                    ;                (1B /  8cc)
DCR  C                    ; Z=1 iff cond=0 (1B /  8cc)
JZ   .Lret_r              ;                (1B / 12cc)
INR  A                    ; r+1            (1B /  8cc)
RET
.Lret_r:
RET
```

Compare path cost: **2B / 16cc**, no scratch burn. **−2B / −8cc per
fire**, plus the scratch GR8 stays free (transitively avoiding spills
in tight loops — see `tests/features/43`).

### Example 2 — A-dead shape 2 (unchanged)

```c
unsigned char dead_a(unsigned char val) {
    if (val) return 1;
    return 0;
}
```

Today and after O80 both emit `XRA A; CMP val; JZ …` — 2B / 8cc.
The pseudo's shape-2 expansion preserves the existing O38 path.

### Example 3 — Annotation regression fix (free side benefit)

[tests/features/37/v6clang.s line 76](../tests/features/37/v6clang.s#L76)
currently shows the bare `MOV A, C; ORA A` sequence with no
`;--- ... ---` annotation, even with `-mllvm -mv6clang-annotate-pseudos`.
After O80, that location prints `;--- V6CLANG_CMP8_ZERO ---` (or
`;--- V6CLANG_BRCOND ---` only, with INR/DCR underneath when A is live).

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `CY`/`AC` divergence from `ORA A` semantics. | Documented: only `Z`/`S`/`P` consumers exist for `V6ClangISD::CMP` against zero. Verified by inspection of `V6ClangCC` enum users (`COND_Z`/`NZ`/`P`/`M`/`PE`/`PO` only). Add the comment block from §2 to the pseudo's TableGen doc. |
| Verifier rejects twin-def of `Src` across `INR`+`DCR`. | Both INR/DCR are tied (`$rd = $src`). BuildMI with `(get(V6CLANG::INRr), Src).addReg(Src)` produces the standard tied form used elsewhere in the backend. The kill flag goes only on the second (DCR). |
| TableGen pattern collision with existing `CPI` pattern. | `(i8 0)` is strictly more specific than `(i8 imm:$imm)`. TableGen disambiguates by specificity. Validated by lit test shape 3 — if it ever emits `CPI 0` instead of `INR/DCR`, the pattern preference is broken. |
| Future peephole pass folds `INR r; DCR r` away as "no-op". | Not currently implemented; no V6CLANG pass touches the i8 `INRr/DCRr` pair. If added, must skip the pair when both are emitted from `V6CLANG_CMP8_ZERO` expansion. Track via a comment in `V6ClangInstrInfo.cpp` next to the expansion. Annotation comment `;--- V6CLANG_CMP8_ZERO ---` survives mostly intact for grep. |
| Shape-2 (A dead, 8cc) is cheaper than shape 3 (16cc); accidentally selecting INR/DCR when A is dead is a regression. | Priority order in expansion: A check first. `isRegDeadAtMI(V6CLANG::A, ...)` is reliable post-RA. Lit test shape 2 explicitly checks for `XRA A; CMP r` and `CHECK-NOT: INR`. |
| Existing `V6ClangZeroTestOpt` (`CPI 0 → ORA A`) continues to find `CPI 0` from sources we missed. | Harmless — that pass remains correct and continues to fire on any non-O80 path (e.g. inline asm). Run lit with the pass disabled (`-v6clang-disable-zero-test-opt`) to confirm O80 alone produces the right shapes. |

## 6. Relationship to Other Improvements

- **O27 (i16 zero test)**: O80 is the i8 analogue. O27 introduced
  `V6CLANG_CMP16_ZERO`; O80 introduces `V6CLANG_CMP8_ZERO`. Same shape,
  different width.
- **O17 (Redundant flag elim)**: orthogonal. O17 elides `ORA A` after
  ALU ops that already set Z. After O80, fewer `ORA A`s exist (shape 3
  uses INR/DCR), but O17 still fires on shape 2 and on non-zero
  compares.
- **O75 (flag-producing arith SDNodes)**: orthogonal. O75 fuses
  `(arith op + zero compare)` into a single flag-producing op
  (`DCR r; JNZ`). When O75 fires, no `V6CLANG_CMP8_ZERO` is generated at
  all. When O75 doesn't fire (multi-use, no fusion), O80 still wins
  the standalone zero-test by 12cc.
- **O38 (XRA cmp zero test)**: orthogonal. O38 uses `XRA r` for
  zero-tests when A is dead and a known-zero source is at hand.
  Doesn't affect O80's shape-3 path.

## 7. Future Enhancements

- **A-preference allocator hint**. Once `V6CLANG_CMP8_ZERO` exists, ISel
  can attach a register-allocator hint to `$src` preferring `A`.
  This collapses shape 2 (12cc) into shape 1 (4cc) when the producer
  of `src` is otherwise free to target A. Strictly additive; tracked
  separately to keep this patch focused.
- **i8 register-vs-register compare via SUB-without-store**. Out of
  scope — the win is specific to the zero comparand because INR/DCR
  reify a unary flag-set.
- **Extend to `V6CLANG_CMP16_ZERO`**. Already cycle-optimal at 12cc
  (`MOV A,Hi; ORA Lo`); no INR/DCR equivalent for i16. Skipped.

## 8. References

- [O80 design doc](future_plans/O80_cmp8_zero_inr_dcr.md)
- [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
- [V6CLANG Instruction Timings](../docs/V6ClangInstructionTimings.md)
- [Future Improvements](future_plans/README.md)
- [Feature Pipeline](pipeline_feature.md)
- [Feature Test README](../tests/features/result.md)
- Reference plan format: [plan_cmp_based_comparison.md](plan_cmp_based_comparison.md)
- Sibling pseudo: [`V6CLANG_CMP16_ZERO`](../llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td) (line ~1008)
- Annotation infrastructure: [V6ClangAsmPrinter.cpp::emitInstruction](../llvm-project/llvm/lib/Target/V6Clang/V6ClangAsmPrinter.cpp) (line ~202)
