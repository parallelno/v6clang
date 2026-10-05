# Plan: O64 — Liveness-Aware i8 Spill/Reload Lowering (Static-Stack Shapes B & C)

> **Scope.** Replace the single fixed fallback shape used by
> `V6ClangRegisterInfo::eliminateFrameIndex` for static-stack
> `V6CLANG_SPILL8` / `V6CLANG_RELOAD8` pseudos with a small cost-model
> decision ladder driven by post-RA liveness queries already used by
> O42. No TableGen changes, no new CLI flag, no ABI change.
> See the feature spec:
> [O64_liveness_aware_i8_spill_lowering.md](future_plans/O64_liveness_aware_i8_spill_lowering.md).

---

## 1. Problem

### Current behavior

`V6ClangRegisterInfo::eliminateFrameIndex`, static-stack branch
([V6ClangRegisterInfo.cpp lines ~143–250](../llvm-project/llvm/lib/Target/V6Clang/V6ClangRegisterInfo.cpp)):

* **Shape A** (src/dst == `A`): `STA addr` / `LDA addr` — already optimal
  (16 cc, 3 B).
* **Shape B** (src/dst ∈ {B, C, D, E}): routes through HL.
  With O42 live-HL gating, emits one of:
  * HL dead: `LXI HL, addr; MOV M, r` / `LXI HL, addr; MOV r, M`
    (20 cc, 4 B).
  * HL live: `PUSH HL; LXI HL, addr; MOV M/r, …; POP HL`
    (48 cc, 6 B).
* **Shape C spill** (src ∈ {H, L}): always takes the DE-detour,
  whether DE is dead or not (DE-dead skips the `PUSH/POP DE` wrap
  but still copies both HL halves into D/E and back — ~48 cc, 5 B
  when DE dead; ~76 cc, 7 B when DE live).
* **Shape C reload** (dst ∈ {H, L}): uses the "other half of HL dead"
  fast path (20 cc, 4 B) when applicable, otherwise falls back to
  the DE-detour (~48–76 cc).

The backend never considers routing an i8 spill/reload through the
accumulator (`MOV A, r; STA addr` / `LDA addr; MOV r, A`) when HL is
live but A is dead. This is the single most common situation in
call-heavy loops where HL carries a pointer across the call boundary
but A is kill-returned.

### Desired behavior

For each i8 spill/reload site, pick the cheapest expansion from an
ordered decision list that checks preconditions via the existing
`isRegDeadAfterMI` helper:

* **Shape B spill** (src ∈ {B, C, D, E}):
  1. HL dead → `LXI HL, addr; MOV M, r`                          (20 cc, 4 B)
  2. HL live, A dead → `MOV A, r; STA addr`                       (24 cc, 4 B)
  3. HL live, A live, a GPR `Tmp` ∈ {B,C,D,E}\{r} dead →
     `MOV Tmp, A; MOV A, r; STA addr; MOV A, Tmp`                 (40 cc, 6 B)
  4. else (= current) `PUSH HL; LXI HL, addr; MOV M, r; POP HL`   (48 cc, 6 B)

* **Shape B reload** (dst ∈ {B, C, D, E}):
  1. HL dead → `LXI HL, addr; MOV r, M`                          (20 cc, 4 B)
  2. HL live, A dead → `LDA addr; MOV r, A`                       (24 cc, 4 B)
  3. HL live, A live, a GPR `Tmp` ∈ {B,C,D,E}\{r} dead →
     `MOV Tmp, A; LDA addr; MOV r, A; MOV A, Tmp`                 (40 cc, 6 B)
  4. else (= current) `PUSH HL; LXI HL, addr; MOV r, M; POP HL`   (48 cc, 6 B)

* **Shape C spill** (src ∈ {H, L}): DE-detour is dropped entirely.
  Ladder (HL-dead rows do not apply — src *is* in HL):
  1. A dead → `MOV A, H/L; STA addr`                              (24 cc, 4 B)
  2. A live, a GPR `Tmp` ∈ {B,C,D,E} dead →
     `MOV Tmp, A; MOV A, H/L; STA addr; MOV A, Tmp`               (40 cc, 6 B)
  3. else `PUSH PSW; MOV A, H/L; STA addr; POP PSW`               (52 cc, 5 B)

* **Shape C reload** (dst ∈ {H, L}):
  1. Other half of HL dead (= current fast path) →
     `LXI HL, addr; MOV H/L, M`                                   (20 cc, 4 B)
  2. A dead → `LDA addr; MOV H/L, A`                              (24 cc, 4 B)
  3. A live, a GPR `Tmp` ∈ {B,C,D,E} dead →
     `MOV Tmp, A; LDA addr; MOV H/L, A; MOV A, Tmp`               (40 cc, 6 B)
  4. else `PUSH PSW; LDA addr; MOV H/L, A; POP PSW`               (52 cc, 5 B)
     (replaces the DE-detour fallback, strictly cheaper: 52 cc vs
     ~76 cc for the DE-PUSH/POP path.)

> **Timings** use `docs/V6ClangInstructionTimings.md`: `MOV r,r`=8,
> `MOV r,M`=8, `MOV M,r`=8, `LXI`=12, `STA`/`LDA`=16, `PUSH PSW`=16,
> `POP PSW`=12.

### Root cause

The existing lowering was designed to preserve *all* non-target
registers unconditionally (match the pseudo's `implicit-def FLAGS`
contract and not cause the RA to see any extra clobbers). That
pessimism is unnecessary on the static-stack path: the pseudo's
expansion is the *whole* region — anything dead after `MI` can be
clobbered freely. O42 already uses this insight to skip the
`PUSH/POP HL` wrap; we extend the same reasoning to consider routing
through `A` or a spare `r8`.

---

## 2. Strategy

### Approach: decision ladder per (shape, width) driven by `isRegDeadAfterMI`, factored into a shared header

Both `V6ClangRegisterInfo::eliminateFrameIndex` (slot-address form) and
`V6ClangSpillPatchedReload`'s non-winner i8 emitter (MCSymbol `Sym+1` form)
need the same decision ladder. To avoid copy-paste drift, factor the
ladder and its helpers into a new compilation unit:

* `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillExpand.h` — declarations.
* `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillExpand.cpp` — impl.

Public API (free functions in namespace `llvm`):

```cpp
// Liveness helper. Moved from its current duplicated static definitions
// in V6ClangRegisterInfo.cpp and V6ClangSpillPatchedReload.cpp.
bool isRegDeadAfterMI(unsigned Reg, const MachineInstr &MI,
                      MachineBasicBlock &MBB,
                      const TargetRegisterInfo *TRI);

// First register in {B, C, D, E}, excluding those overlapping Excluded,
// reported dead after MI. Returns Register() if none.
Register findDeadSpareGPR8(Register Excluded, const MachineInstr &MI,
                           MachineBasicBlock &MBB,
                           const TargetRegisterInfo *TRI);

// Address operand appender. Called to attach the final address to LXI,
// STA, or LDA; lets callers supply either a GlobalAddress+offset (the
// static-stack FI form) or an MCSymbol+MO_PATCH_IMM (the O61 form).
using AppendAddrFn = llvm::function_ref<void(MachineInstrBuilder &)>;

// Emit O64 decision ladder for V6CLANG_SPILL8 at `InsertBefore`. Does NOT
// erase MI — caller owns that.
void expandSpill8Static(MachineInstr &MI, MachineBasicBlock::iterator InsertBefore,
                        Register SrcReg, bool SrcIsKill,
                        const TargetInstrInfo &TII,
                        const TargetRegisterInfo *TRI,
                        AppendAddrFn AppendAddr);

// Emit O64 decision ladder for V6CLANG_RELOAD8.
void expandReload8Static(MachineInstr &MI, MachineBasicBlock::iterator InsertBefore,
                         Register DstReg,
                         const TargetInstrInfo &TII,
                         const TargetRegisterInfo *TRI,
                         AppendAddrFn AppendAddr);
```

Why `AppendAddrFn` and not an `enum Kind { FI, Sym }`: the two callers
use distinct operand *kinds* but identical *placement* (always the last
operand of an LXI/STA/LDA). A lambda keeps the core ladder free of
kind-dispatch and keeps the call sites readable:

```cpp
// V6ClangRegisterInfo.cpp call
expandSpill8Static(MI, II, SrcReg, IsKill, TII, this,
    [&](MachineInstrBuilder &B) { B.addGlobalAddress(GV, StaticOffset); });

// V6ClangSpillPatchedReload.cpp call
expandReload8Static(*R, R, Dst, TII, TRI,
    [&](MachineInstrBuilder &B) { B.addSym(Syms[0], V6ClangII::MO_PATCH_IMM); });
```

Each helper builds the decision ladder in the order listed above and
emits the cheapest shape whose precondition holds. Preconditions are
answered by the shared `isRegDeadAfterMI`; row 3 uses
`findDeadSpareGPR8` which iterates `{B, C, D, E}`, excluding any
register that is part of the pseudo's source/destination, and returns
the first one reported dead after `MI`.

Shape A (`A` src/dst) stays as-is — handled by the caller *before*
invoking the helper (both callers already special-case `A` today, and
giving `A` its own fast path in the helper would only add a branch).

### Why this works

1. **Every new row is functionally equivalent** to the existing
   fallback. The current "row 4" code is exactly the fallback row in
   each ladder. So if every new precondition fails, we emit the
   exact bytes we emit today — zero correctness regression surface.
2. **Liveness answers are already available.** `isRegDeadAfterMI`
   is the hook O42 uses to decide the `PUSH/POP HL` gate. We reuse
   it unchanged, just query more registers.
3. **Flag safety.** Every new shape uses only `LXI`, `MOV r,r`,
   `MOV r,M`, `MOV M,r`, `STA`, `LDA`, `PUSH`, `POP` — none sets
   PSW. The pseudo's `Defs=[FLAGS]` contract remains satisfied
   (vacuously).
4. **Row ordering is monotonic in cost.** Row N is strictly cheaper
   than row N+1 when its precondition holds, so a greedy first-
   match selection is optimal. (Exception: spill row 3 "40 cc, 6 B"
   vs spill row 4 "48 cc, 6 B" — same size, row 3 is still 8 cc
   cheaper.)
5. **No RA re-entry.** Post-RA, all registers in the ladder are
   physical. Writing `A` or a spare GPR can't create a live-range
   fragment that needs further allocation.

### Why not split by shape into separate pseudos

Three reasons to keep one pseudo per width:

* No TableGen changes.
* Pseudo commutes through the rest of the pipeline (IPRA, O61,
  O42-for-i16) exactly as today.
* Decision is a local cost-model query; a new pseudo would only
  move the same query one pass earlier.

### Summary of changes

| Step | What | Where |
|------|------|-------|
| New shared module | `V6ClangSpillExpand.h` + `V6ClangSpillExpand.cpp`; add to `CMakeLists.txt`. | `llvm-project/llvm/lib/Target/V6Clang/` |
| Consolidate `isRegDeadAfterMI` | Move from its two duplicate static definitions into the shared module. | `V6ClangSpillExpand.{h,cpp}` |
| Add helper `findDeadSpareGPR8` | Walks {B,C,D,E}\Excluded, returns first dead after MI; `Register()` on failure. | `V6ClangSpillExpand.{h,cpp}` |
| Implement `expandSpill8Static` / `expandReload8Static` | Emit the decision ladder using `AppendAddrFn` for the address operand. | `V6ClangSpillExpand.cpp` |
| Rewire `V6ClangRegisterInfo::eliminateFrameIndex` | Replace static-stack `V6CLANG_SPILL8` / `V6CLANG_RELOAD8` bodies with calls to the shared helpers (pass a `GV + StaticOffset` appender). Keep Shape A (`STA`/`LDA`) inline. | `V6ClangRegisterInfo.cpp` |
| Rewire `V6ClangSpillPatchedReload` non-winner emitter | Replace the duplicated classical i8 reload emission with a call to `expandReload8Static` (pass a `Syms[0] + MO_PATCH_IMM` appender). Keep winner emission (MVI) and spill rewrite (STA Sym+1) untouched. | `V6ClangSpillPatchedReload.cpp` |
| Drop H/L DE-detour spill path | Replaced by Shape C ladder (A-routed) inside the shared helper. | `V6ClangSpillExpand.cpp` |
| Add H/L reload rows 2–4 | Keep current "other-half dead" fast path as row 1; add A-dead / spare-GPR / `PUSH PSW` rows. | `V6ClangSpillExpand.cpp` |
| Lit test | One function per decision row with exact `CHECK` sequences. | `llvm/test/CodeGen/V6Clang/spill-reload-i8-static-shapes.ll` |
| Regression | All existing O42/O43/O61 lit tests pass unchanged, or with `CHECK` lines tightened to the shorter sequences. Re-verify `spill-patched-reload-i8.ll` in particular — its non-winner reload sequences will change. | existing `.ll` files |
| Feature test | `tests/features/38/` — a function with an HL-live-but-A-dead i8 spill/reload site. | new folder |

---

## 3. Implementation Steps

### Step 3.1 — Create shared module `V6ClangSpillExpand.{h,cpp}` [x]

**Files**:
* `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillExpand.h`
* `llvm-project/llvm/lib/Target/V6Clang/V6ClangSpillExpand.cpp`
* `llvm-project/llvm/lib/Target/V6Clang/CMakeLists.txt` — add
  `V6ClangSpillExpand.cpp` to the `add_llvm_target(V6ClangCodeGen …)` list.

Declare the public API shown in §2 (`isRegDeadAfterMI`,
`findDeadSpareGPR8`, `expandSpill8Static`, `expandReload8Static`,
`AppendAddrFn`). Implement `isRegDeadAfterMI` by moving the existing
body verbatim from `V6ClangRegisterInfo.cpp` (which is the canonical
copy).

> **Design Notes**: Shared module is preferred over adding static
> helpers to one file and extern-declaring them from the other —
> explicit header makes ownership obvious and avoids TU-private
> linkage hacks.

> **Implementation Notes**: <empty>

### Step 3.2 — Add `findDeadSpareGPR8` helper [x]

**File**: `V6ClangSpillExpand.cpp`

```cpp
Register llvm::findDeadSpareGPR8(Register Excluded,
                                 const MachineInstr &MI,
                                 MachineBasicBlock &MBB,
                                 const TargetRegisterInfo *TRI) {
  static const MCPhysReg Candidates[] = {V6CLANG::B, V6CLANG::C, V6CLANG::D, V6CLANG::E};
  for (MCPhysReg R : Candidates) {
    if (Excluded && TRI->regsOverlap(R, Excluded))
      continue;
    if (isRegDeadAfterMI(R, MI, MBB, TRI))
      return R;
  }
  return Register();
}
```

> **Design Notes**: Excluding the pseudo's own source/dest prevents
> the ladder from picking the very register it's trying to
> spill/reload. We do *not* need to exclude `A` because `A` is not in
> the candidate set. We also do not need to exclude H/L — for Shape B
> the src/dst is one of {B,C,D,E}, not H/L; for Shape C the src/dst
> is H/L so HL will be live across the row anyway (it's the pointer)
> — and Candidates does not include H/L.

> **Implementation Notes**: <empty>

### Step 3.3 — Implement `expandSpill8Static` with decision ladder [x]

**File**: `V6ClangSpillExpand.cpp`

Implement the helper (called by both `V6ClangRegisterInfo` for the
full shape set and by `V6ClangSpillPatchedReload` for non-winner spills
— though in practice non-winner spills don't exist, since O61's
filter requires `SrcReg == A`, handled inline as Shape A by the
caller). The helper body covers:

```
// Shape A (SrcReg == A) handled by caller, not by this helper.

Shape C (SrcReg ∈ {H, L}):
    Row 1: A dead
        MOV A, H|L
        STA addr
    Row 2: A live, Tmp ∈ {B,C,D,E} dead
        MOV Tmp, A
        MOV A, H|L
        STA addr
        MOV A, Tmp
    Row 3 (fallback): A live, no spare
        PUSH PSW
        MOV A, H|L
        STA addr
        POP PSW

Shape B (SrcReg ∈ {B, C, D, E}):
    Row 1: HL dead
        LXI HL, addr
        MOV M, r
    Row 2: HL live, A dead
        MOV A, r
        STA addr
    Row 3: HL live, A live, Tmp ∈ {B,C,D,E}\{r} dead
        MOV Tmp, A
        MOV A, r
        STA addr
        MOV A, Tmp
    Row 4 (fallback): HL live, A live, no spare
        PUSH HL
        LXI HL, addr
        MOV M, r
        POP HL
```

> **Design Notes**: For Shape B the A-dead row is sufficient (A can
> be freely clobbered by `STA`). For Shape C the `MOV A, H|L` row
> may happen with HL live — that's fine, it's H/L we're reading; HL
> as a whole is not touched.

> **Implementation Notes**: <empty>

### Step 3.4 — Implement `expandReload8Static` with decision ladder [x]

**File**: `V6ClangSpillExpand.cpp`

Symmetric to 3.3:

```
// Shape A (DstReg == A) handled by caller, not by this helper.

Shape C (DstReg ∈ {H, L}):
    Row 1: other half of HL dead (= existing fast path)
        LXI HL, addr
        MOV H|L, M
    Row 2: other half live, A dead
        LDA addr
        MOV H|L, A
    Row 3: other half live, A live, Tmp ∈ {B,C,D,E} dead
        MOV Tmp, A
        LDA addr
        MOV H|L, A
        MOV A, Tmp
    Row 4 (fallback): other half live, A live, no spare
        PUSH PSW
        LDA addr
        MOV H|L, A
        POP PSW

Shape B (DstReg ∈ {B, C, D, E}):
    Row 1: HL dead
        LXI HL, addr
        MOV r, M
    Row 2: HL live, A dead
        LDA addr
        MOV r, A
    Row 3: HL live, A live, Tmp ∈ {B,C,D,E}\{r} dead
        MOV Tmp, A
        LDA addr
        MOV r, A
        MOV A, Tmp
    Row 4 (fallback): HL live, A live, no spare
        PUSH HL
        LXI HL, addr
        MOV r, M
        POP HL
```

> **Design Notes**: Keep the current "other half of HL dead" fast
> path as Shape C Row 1 (this subsumes O42's Shape C optimization).

> **Implementation Notes**: <empty>

### Step 3.5 — Wire the helpers into `V6ClangRegisterInfo::eliminateFrameIndex` [x]

**File**: `V6ClangRegisterInfo.cpp`

Replace the inline `V6CLANG_SPILL8` / `V6CLANG_RELOAD8` static-stack bodies
with:

```cpp
// Shape A stays inline (STA / LDA) — no ladder needed.
if (SrcReg == V6CLANG::A) { /* STA GV+StaticOffset */ }
else {
  expandSpill8Static(MI, II, SrcReg, MI.getOperand(0).isKill(),
      TII, this,
      [&](MachineInstrBuilder &B) {
        B.addGlobalAddress(GV, StaticOffset);
      });
}
MI.eraseFromParent();
return true;
```

…and symmetrically for `V6CLANG_RELOAD8`. Remove the now-static-private
`isRegDeadAfterMI` definition in this file and `#include
"V6ClangSpillExpand.h"` instead.

Leave the non-static (SP-relative, dynamic-stack) paths untouched —
O64's scope is static stack only.

> **Design Notes**: The dynamic (SP-relative) path is out of scope
> for O64; it needs `DAD SP` which clobbers FLAGS, so the shape
> selection there has additional constraints. Future work.

> **Implementation Notes**: <empty>

### Step 3.6 — Wire the helpers into `V6ClangSpillPatchedReload` non-winner emitter [x]

**File**: `V6ClangSpillPatchedReload.cpp`

In the non-winner i8 reload loop (currently
[lines 474–534](../llvm/lib/Target/V6Clang/V6ClangSpillPatchedReload.cpp#L474)),
replace the inline A / H|L / B..E branches with:

```cpp
if (Dst == V6CLANG::A) {
  BuildMI(*MBB, R, DL, TII.get(V6CLANG::LDA), V6CLANG::A)
      .addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
} else {
  expandReload8Static(*R, R, Dst, TII, TRI,
      [&](MachineInstrBuilder &B) {
        B.addSym(Syms[0], V6ClangII::MO_PATCH_IMM);
      });
}
R->eraseFromParent();
```

Remove the now-static-private `isRegDeadAfterMI` definition in this
file and `#include "V6ClangSpillExpand.h"` instead. Keep the winner
emitter (`MVI r, 0` + pre-instr symbol) and spill rewrite
(`STA Sym+1` per winner) unchanged.

> **Design Notes**: Spill rewrite in O61 is always from `A`
> (enforced by its filter), so it maps to Shape A / `STA` inline —
> no call into `expandSpill8Static` is needed for the spill side.

> **Implementation Notes**: <empty>

### Step 3.7 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc"
```

> **Implementation Notes**: <empty>

### Step 3.8 — Lit test: `spill-reload-i8-static-shapes.ll` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/spill-reload-i8-static-shapes.ll`

One small non-reentrant function per decision row, with precise
`CHECK` sequences:

| Function | Row triggered | Precondition setup |
|----------|---------------|--------------------|
| `spillB_row1_hlDead` | Shape B spill row 1 | HL not live across spill |
| `spillB_row2_hlLive_aDead` | Shape B spill row 2 | HL live, A dead |
| `spillB_row3_hlLive_aLive_tmp` | Shape B spill row 3 | HL & A both live, one of BCDE dead |
| `spillB_row4_fallback` | Shape B spill row 4 | HL, A, and BCDE all live |
| `reloadB_row1` … `reloadB_row4` | Shape B reload rows 1–4 | symmetric |
| `spillH_row1_aDead` | Shape C spill row 1 | A dead across spill of H |
| `spillL_row3_fallback` | Shape C spill row 3 | A live, no spare |
| `reloadH_row1_otherDead` | Shape C reload row 1 | L dead across reload of H |
| `reloadL_row2_aDead` | Shape C reload row 2 | H live, A dead |

Assert the exact sequence per row. Use `-O2`, `norecurse`, and force
static stack via the existing mechanism.

> **Design Notes**: Some rows may be hard to trigger deterministically
> from IR — allow the test to pin liveness by carefully constructing
> the caller pattern (calls before/after to saturate A, H, or BCDE).

> **Implementation Notes**: <empty>

### Step 3.9 — Lit test: O42 / O43 / O61 regressions [x]

Run existing `spill-reload.ll`, `spill-forwarding.ll`,
`spill-patched-reload-*.ll` (including `spill-patched-reload-i8.ll`
whose non-winner reload sequences will change now that they flow
through the shared ladder). Update `CHECK` lines where the new
ladder produces a strictly shorter or faster sequence than before;
*do not* loosen any correctness check.

> **Implementation Notes**: <empty>

### Step 3.10 — Run regression tests [x]

```
python tests\run_all.py
```

Expect all previously-green tests to stay green. Update `CHECK`
lines in the 1–2 lit tests where the ladder fires on an i8 spill
in a function that already had a deterministic classical sequence.

> **Implementation Notes**: <empty>

### Step 3.11 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests\features\38\v6clang.c` and produce
`v6clang_new01.asm`. Expect Shape B row 2 or row 3 to fire at least
once in the body of the HL-live-A-dead function, replacing a
`PUSH HL; LXI HL, …; MOV r, M; POP HL` sequence.

> **Implementation Notes**: <empty>

### Step 3.12 — Make sure result.txt is created. `tests\features\README.md` [x]

> **Implementation Notes**: <empty>

### Step 3.13 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: <empty>

### Step 3.14 — Mark O64 complete in `design/future_plans/README.md` [x]

Set the O64 row to `[x]` in both the plan table and the summary
table.

> **Implementation Notes**: <empty>

---

## 4. Expected Results

### Example 1 — Call-heavy loop (tests/features/38 pattern)

```c
extern unsigned char op(unsigned char, unsigned char *);
unsigned char f(unsigned char *p, unsigned char x) {
    unsigned char a = op(x, p);   // p pinned in HL; result in A
    unsigned char b = op(a, p);   // A clobbered; reload of `a`
    return a + b;
}
```

Classical reload: `PUSH HL; LXI HL, __v6clang_ss.f; MOV r, M; POP HL`
(48 cc). After O64 the reload is replaced with `LDA __v6clang_ss.f;
MOV r, A` (24 cc) — **−24 cc, −2 B** per spill/reload site in the
hot block.

### Example 2 — H/L spill drop DE-detour

```c
unsigned char *q;
unsigned char g(unsigned char *p) {
    q = p;                 // HL used to load q
    return external(p);    // HL reused for call
}
```

Classical H spill: `PUSH DE; MOV D,H; MOV E,L; LXI HL, …; MOV M,D;
MOV H,D; MOV L,E; POP DE` (76 cc). After O64 (A dead across the
spill): `MOV A, H; STA …` (24 cc) — **−52 cc, ~−3 B**.

### Example 3 — Orthogonal with O61

O61 rewrites the `A`-source, patched-reload class of sites. O64
takes over for every other i8 spill/reload. The two are disjoint by
construction: O61 handles `SrcReg == A` + patched `MVI`; O64
handles `SrcReg != A` or the unpatched reloads O61 skipped.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Bad spare-GPR pick fragments a live range | Post-RA, physical regs only — no re-allocation. Greedy first-match on {B,C,D,E} is good enough; any dead candidate is equivalent in cost. |
| Row ordering mis-matches real Vector-06c timings | Ladder is monotonic in cost. Even a mis-ordered row only produces a suboptimal but still-correct sequence. Verify with `docs/V6ClangInstructionTimings.md` numbers in the plan above. |
| `isRegDeadAfterMI` returns a stale answer after intermediate emission | Query only uses `MI`'s pre-expansion position and the original successor-livein state — unchanged by O64. Same guarantee O42 relies on. |
| Lit tests for specific rows hard to write deterministically | Pin liveness with calls that kill/keep A or GPRs. If a row is non-deterministic we fall back to `CHECK-DAG` or drop the row's test and cover it via feature test 38. |
| Code size regression on row 3 | Row 3 is 6 B vs fallback row 4's 6 B — identical size, strictly fewer cycles. |
| DE-detour drop surfaces latent bug where DE was used as "free" scratch by another pass | No pass depends on the DE-detour side-effect: it is emitted post-RA and consumed by the assembler. Verified by grep: `MOV D,H; MOV E,L` pattern in i8 spill expansion has no downstream reader. |

---

## 6. Relationship to Other Improvements

* **O42** (liveness-aware pseudo expansion). O42's Shape B row 1
  (HL-dead fast path) *is* O64's row 1 unchanged. O42 for i8
  static-stack is fully subsumed by O64; O42 remains live for
  i16 and for dynamic-stack paths.
* **O61** (patched reload). Orthogonal: O61 filters to `SrcReg == A`;
  O64 takes all other i8 sites plus O61's non-winner reloads. Both
  `V6ClangRegisterInfo::eliminateFrameIndex` and
  `V6ClangSpillPatchedReload`'s non-winner i8 reload emitter now call
  the shared `expandReload8Static` helper (Steps 3.5 / 3.6), so O61
  functions get the same ladder as the rest.
* **O63** (drop false `FLAGS` def). Orthogonal. O63 touches the
  pseudo's `Defs`; O64 touches the expansion. Neither affects the
  other.
* **O49** (direct memory ALU/store ISel). Disjoint: O49 folds the
  memory access into the ALU op at ISel time, so the spill/reload
  pseudo is never emitted in the first place for those patterns.
  When O49 doesn't fire, O64 handles the residual spill site.

## 7. Future Enhancements

* Dynamic-stack i8 spill/reload ladder (analogous ladder but must
  account for `DAD SP` setting FLAGS).
* Extend the ladder to pick *any* dead r8 as the value router, not
  just spare GPRs — would let row 2/3 fire more often on
  register-starved functions.
* Cost-driven row selection when two rows tie in cycles but differ
  in bytes (add `V6ClangOptMode` consultation — currently tied rows
  fall through in source order, which happens to pick the cheaper
  size).

## 8. References

* [V6CLANG Build Guide](../docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](../docs/Vector_06c_instruction_timings.md)
* [V6CLANG Instruction Timings](../docs/V6ClangInstructionTimings.md)
* [Future Improvements](future_plans/README.md)
* [O64 feature spec](future_plans/O64_liveness_aware_i8_spill_lowering.md)
* [O42 prior art](future_plans/O42_liveness_aware_expansion.md)
* [O61 Stage 4 plan (interaction reference)](plan_O61_spill_in_reload_immediate_stage4.md)
