# O66 — `switch` → Jump Table via `PCHL` (JMP-Table Layout)

**Source:** V6CLANG
**Savings:** Two-fold:
          1. **Bug-fix.** `clang -O2` currently aborts with
             `Cannot select: br_jt` on any dense V6CLANG `switch` (the
             mid-end emits `BR_JT`, ISel has no pattern). This
             plan adds the lowering and removes the crash.
          2. **Performance.** Replaces the current
             `-fno-jump-tables` fallback (a balanced-binary-search
             tree, 75 cc avg / 92 cc worst / 66 B at N=8) with a
             **four-mode dispatch**: linear cascade for small or
             skewed switches, **cascade-prefix + JT** for skewed
             switches with a dense remainder, **cascade-prefix +
             binary search** for skewed switches with a sparse
             remainder, and pure JT (`PCHL`) for large uniform
             dense switches.
             For an 8-case uniform switch: pure JT is 68 cc / 42 B
             (−7 cc avg, −24 cc worst-case, −24 B vs current).
             For an 8-case 80/20-skewed switch: linear cascade hits
             the hot case in 20 cc (−56 cc vs binary search's 56 cc
             best, −48 cc vs JT's 68 cc).
             Hard cap: i8-indexed JT supports ≤ 64 dense cases
             (table = 64 × 4 B = 256 B, the largest reachable by an
             unsigned i8 scaled by 4); above that, fall back to the
             cascade or the binary-search hybrid until i16 indexing
             is added (follow-up).
**Frequency:** Medium \u2014 every dense `switch (i8) {\u2026}` with \u2265 4 cases
          is affected. Source-level if/else ordering is *not* a
          mitigation: SimplifyCFG normalises all forms to
          `SwitchInst` (verified: 3 textually-different sources \u2192
          byte-identical 66 B output). Frequency information must
          enter through `__builtin_expect` / PGO weights.
**Complexity:** Medium. JT lowering ~150 LoC, pre-isel cascade
          rewrite ~80 LoC, hybrid peeling ~50 LoC.
**Risk:** Low. The crash-fix half is a strict improvement (today
          fails to compile). The three-mode cost model has graceful
          fallback to pure JT on missing weight metadata.
**Dependencies:** O11 (dual cost model) \u2014 used to gate
          cascade-vs-hybrid-vs-JT per `-Os` / `-O2` mode.
**Status:** [ ] not started.


## Hard-error bug this also fixes (must-do, not just an optimisation)

The LLVM mid-end *already decides* a dense V6CLANG `switch` deserves a
jump table and emits `ISD::BR_JT` — but V6CLANG ISel has no pattern for
it and `clang -O2` aborts with:

```text
LLVM ERROR: Cannot select: t<N>: ch = br_jt t<N-1>, JumpTable:i16<0>, ...
```

Reproduced on `temp/o66_if_cascades.c` (8-case dense `switch`).
Workaround today is `-fno-jump-tables`, which forces every dense
switch into a binary-search lowering and silently regresses code
size. So this plan is **not optional polish** — it closes a
clang-crashes-on-valid-O2-code gap. Even the smallest viable
implementation (lower `BR_JT` + emit a 4-byte-padded `JMP` table
behind `setMinimumJumpTableEntries`) is enough to remove the
crash; the layout/cost-model refinements below are stacked on top.


## Problem

`ISD::BR_JT` and `ISD::BRIND` are not customised by the V6CLANG backend.
[`V6ClangISelLowering.cpp`](../../llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp#L70)
sets no action for either node and provides no `LowerBR_JT`.
With `-fno-jump-tables` the mid-end's `SwitchLoweringUtils` falls
through to a **balanced binary-search tree** of `CPI/JP/JZ` tests
(*not* a linear cascade — verified empirically, see Empirical
baseline below). Without `-fno-jump-tables` the compile fails
outright (see *Hard-error bug* above).

For a 16-case `switch (a)`:

```asm
    CPI 0   ;  8 cc, 2 B
    JZ  L0  ; 12 cc, 3 B
    CPI 1
    JZ  L1
    ...
    CPI 15
    JZ  L15
    JMP Ldefault   ; 12 cc, 3 B
```

Worst-case dispatch = 16 × 20 cc + 12 cc = 332 cc, 83 B.
Average (taken at midpoint) ≈ 8 × 20 + 12 = 172 cc.

The 8080 has `PCHL` (jump to address in HL, 1 B / 8 cc) which makes
constant-time dispatch trivial — but only if the backend *emits*
the indexed-load + `PCHL` sequence and a corresponding rodata table.

`PCHL` is already defined in
[V6ClangInstrInfo.td](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L439)
with empty pattern `[]` and is unreferenced anywhere in the backend.


## Proposed solution

Implement `ISD::BR_JT` lowering that emits a **JMP-table** (a table
of `JMP target` instructions, 3 B each) rather than the conventional
**address-table** (a table of 2-byte target addresses).

### Two layouts compared

#### Layout A — address table (conventional)

```
LXI  HL, jt        ; 12 cc, 3 B
ADD  A             ;  4 cc, 1 B   ; idx*2
MOV  E, A          ;  8 cc, 1 B
MVI  D, 0          ;  8 cc, 2 B
DAD  D             ; 12 cc, 1 B   ; HL = jt + idx*2
MOV  A, M          ;  8 cc, 1 B   ; lo byte
INX  H             ;  8 cc, 1 B   ; (sets no flags — safe)
MOV  H, M          ;  8 cc, 1 B   ; hi byte
MOV  L, A          ;  8 cc, 1 B
PCHL               ;  8 cc, 1 B
                   ; --------------
                   ; 84 cc, 13 B code + 2 B per entry
jt:
    .word  L0
    .word  L1
    ...
```

#### Layout B — JMP table (proposed, faster + simpler)

```
LXI  HL, jt        ; 12 cc, 3 B
ADD  A             ;  4 cc, 1 B   ; idx*2
ADD  A             ;  4 cc, 1 B   ; idx*4
MOV  E, A          ;  8 cc, 1 B
MVI  D, 0          ;  8 cc, 2 B
DAD  D             ; 12 cc, 1 B   ; HL = jt + idx*4   (with 4 B padding)
PCHL               ;  8 cc, 1 B   ; jumps into table
                   ; --------------
                   ; 56 cc, 10 B code + 4 B per entry (3 B JMP + 1 B pad)
jt:
    JMP  L0        ; 12 cc, 3 B   (the table slot's JMP)
    .byte 0        ; pad to 4 B   (so idx*4 indexing stays ADD A; ADD A)
    JMP  L1
    .byte 0
    ...
```

Total dispatch = 56 cc preamble + 12 cc table-`JMP` = **68 cc**,
10 B of code + 4 B per entry.

**Without** padding (3 B per entry) we'd need an `idx*3` multiply,
which on 8080 costs `MOV B,A; ADD A; ADD B` (= 8 + 4 + 4 = 16 cc).
With 4 B padding (`ADD A; ADD A`) the index scale is 8 cc and the
preamble is 8 cc faster. Trade 1 B/entry for 8 cc per dispatch —
the right call for any switch on a hot path.

For very large tables (`-Oz`) we can fall back to the 3 B unpadded
form with the `idx*3` multiply: 76 cc total / 11 B code + 3 B per
entry.

### Recommended default

| Mode | Layout | Per-entry | Dispatch |
|------|--------|-----------|----------|
| `-O2`, `-O3`, `-O1` | B (4 B padded) | 4 B | 68 cc |
| `-Os` | B (3 B unpadded, `idx*3`) | 3 B | 76 cc |
| `-Oz` | A (address table) | 2 B | 84 cc |

The cost-model decision is exposed through
[`V6ClangInstrCost.h`](../../llvm/lib/Target/V6Clang/V6ClangInstrCost.h) in the
existing dual-cost framework (O11).

### Why JMP-table (Layout B default) beats the address table

1. **No second memory fetch.** Address tables need
   `MOV A,M; INX H; MOV H,M; MOV L,A` (32 cc) to assemble the
   target. JMP tables fold that step into a `JMP` already at the
   indexed slot — `PCHL` jumps straight into the table, the `JMP`
   at that slot does the second hop in 12 cc. Net saving: 16 cc.
2. **No carry-propagation hazard.** `INX H` is flag-clean on
   8080 but the address-table code still has to *use* HL after the
   `INX`. A JMP table needs only one DAD result.
3. **Relocations are simpler.** Each table entry is a regular
   16-bit absolute relocation embedded in a `JMP` opcode — exactly
   the relocation kind we already emit for ordinary `JMP foo`. The
   address-table form needs a target-aware emission that knows to
   write `R_V6CLANG_16` against a label, which our asm printer can do
   but is one more code path to maintain.
4. **Table addresses can be patched by `ld.lld` without the linker
   knowing about a "jump table" relocation type** — JMP tables
   reuse the existing `R_V6CLANG_16` PC-absolute relocation we already
   support (M10 / O-LLD).


## Implementation plan

### Step 1 — Lowering hooks

`V6ClangISelLowering.cpp` — in the constructor:

```cpp
setOperationAction(ISD::BR_JT,  MVT::Other, Custom);
setOperationAction(ISD::BRIND,  MVT::Other, Custom);
setOperationAction(ISD::JumpTable, MVT::i16, Custom);
setMinimumJumpTableEntries(6);     // break-even with avg-taken cascade
setJumpIsExpensive(false);
```

Add `LowerBR_JT(SDValue Op, SelectionDAG &DAG)`:

* Take `Index` (i8 or i16) and clamp / zext to i8 (typical case).
* Emit `V6ClangISD::JT_DISPATCH8` (new node) with operands
  `(Chain, JTAddr, Index)`. The DAG-to-DAG selector lowers it to the
  `LXI + ADD A + ADD A + MOV E,A + MVI D,0 + DAD + PCHL` sequence
  via a new pseudo `V6CLANG_BR_JT8` (post-RA expanded — see step 2).

Also `LowerJumpTable`: wraps the JT symbol in `V6ClangISD::Wrapper` so
`LXI HL, $jt` is matched by the existing wrapper pattern.

### Step 2 — Pseudo + post-RA expansion

`V6ClangInstrInfo.td`:

```td
let isTerminator = 1, isBarrier = 1, isIndirectBranch = 1,
    Uses = [A], Defs = [A, FLAGS, HL, DE] in
def V6CLANG_BR_JT8 : Pseudo<(outs), (ins i16imm:$jt),
    "# V6CLANG_BR_JT8 $jt", []>;
```

`V6ClangInstrInfo::expandPostRAPseudo` case `V6CLANG::V6CLANG_BR_JT8`:

```
LXI  HL, $jt
ADD  A
ADD  A           ; only if Layout B padded
MOV  E, A
MVI  D, 0
DAD  D
PCHL
```

(For `-Os` 3-byte-entry layout, replace `ADD A; ADD A` with
`MOV B, A; ADD A; ADD B` — encoded in a separate pseudo
`V6CLANG_BR_JT8_TIGHT`.)

### Step 3 — AsmPrinter / table emission

`V6ClangAsmPrinter.cpp` — override `emitJumpTableInfo()` (or
`EmitJumpTableEntry()`):

* For each `MachineJumpTableEntry`, emit:
  ```
      JMP MBB_label
      .byte 0          ; padding (Layout B padded only)
  ```
* Section: `.rodata` (or a dedicated `.jumptable` section so the
  linker can dead-strip if no `JMP` references it — minor).
* Alignment: 4 B for Layout B padded, 3 B for Layout B tight,
  2 B for Layout A.

The existing `JMP` opcode emission path in `V6ClangMCCodeEmitter` already
produces a 16-bit `R_V6CLANG_16` relocation against the target label —
nothing new on the linker side.

### Step 4 — Cost-model gate (frequency-aware)

`V6ClangInstrCost.h`:

```cpp
// Dispatch cost (preamble + table-slot JMP).
constexpr V6ClangInstrCost JTDispatchPadded   { /*B*/10, /*cc*/68 };
constexpr V6ClangInstrCost JTDispatchTight    { /*B*/11, /*cc*/76 };
constexpr V6ClangInstrCost JTDispatchAddr     { /*B*/13, /*cc*/84 };
// Per-case cascade step: CPI imm + JZ Li.
constexpr V6ClangInstrCost CascadeStep        { /*B*/ 5, /*cc*/20 };
```

The gate cannot use a flat `setMinimumJumpTableEntries` — a cascade
with one dominant case is dramatically cheaper than the JT, and a
flat threshold pessimises that pattern. Use
`isSuitableForJumpTable` (or override `getEstimatedNumberOfCaseClusters`)
to compare:

```
Cascade_expected_cc = sum_i ( weight_i * (rank_i * 20) ) + 12
JT_expected_cc      = JTDispatch.cc       // constant
```

where `weight_i` comes from `BranchProbabilityInfo` /
`MDBuilder::createBranchWeights` (LLVM populates this from `__builtin_expect`,
PGO, or the default uniform distribution) and `rank_i` is the
0-based position of case *i* in the (target-sorted) cascade.

* If the SwitchInst has **no** branch-weight metadata, fall back
  to the uniform model:
  * N ≥ 6 (Layout B padded, default)
  * N ≥ 7 (Layout B tight, `-Os`)
  * N ≥ 8 (Layout A, `-Oz`)
* If the SwitchInst **has** branch weights, compute
  `Cascade_expected_cc` from the weights, sort cases by descending
  weight (target-side cascade ordering is up to us), and prefer the
  cascade unless the JT is strictly cheaper.
* Provide a function attribute / pragma escape hatch for users with
  out-of-band knowledge:
  * `__attribute__((v6clang_switch_table))` — force JT.
  * `__attribute__((v6clang_switch_cascade))` — force cascade.
  Keyed off the `SwitchInst`'s containing function.

**Cascade target ordering.** When emitting a cascade we should sort
cases by descending branch weight so the hot case is tested first.
This is independent of the JT decision and worth doing as a separate
small pass in `V6ClangISelLowering::LowerOperation` for `BR_CC` chains —
but at minimum, the cost-model comparison **must** assume that
ordering, otherwise the JT will win artificially in cases where the
cascade would have been re-ordered for free.

### Step 5 — Restrictions / fall-back

* **Range gating.** SwitchLowering already clusters cases by
  density. For low-density switches (sparse), it splits into
  multiple clusters. We accept clusters of density ≥ 60 % (LLVM
  default) — sparse clusters fall back to comparison cascade.
* **Index size.** First cut: i8 only (case values 0–255). i16
  switches are rare and would need an `idx*4` 16-bit multiply
  (`DAD H; DAD H`) — straight extension of the same pseudo, defer
  to a follow-up.
* **Out-of-range.** SwitchLowering inserts the bounds check
  (`CPI Hi+1; JNC default`) before the JT dispatch — this is
  generic LLVM behaviour, no V6CLANG work required.

### Step 6 — Tests

* `llvm/test/CodeGen/V6Clang/switch-jt-basic.ll` — 8-case dense
  switch, `CHECK` exact dispatch sequence and table layout.
* `llvm/test/CodeGen/V6Clang/switch-jt-cascade.ll` — 3-case switch,
  must remain a cascade (below threshold).
* `llvm/test/CodeGen/V6Clang/switch-jt-sparse.ll` — sparse switch,
  must split into cascade + JT or remain cascade.
* `llvm/test/CodeGen/V6Clang/switch-jt-os.ll` — `attributes optsize`,
  must pick Layout B tight.
* `tests/golden/switch_jt/` — runtime emulator round-trip:
  10-case dispatcher returning unique `OUT 0xED, imm` per case,
  golden output verifies indices 0–9 hit the correct case.
* `tests/features/<NN>/` — feature-test harness with
  `EXPECT_OUTPUT` covering all branches.


## Why this works

1. **`PCHL` is a 1-instruction indirect jump.** No call/return
   bookkeeping, no extra register save: it simply replaces PC with
   HL. Composes with the existing wrapper-based GA emission.
2. **Existing relocation infrastructure suffices.** Layout B emits
   `JMP` instructions in `.rodata` — same encoding, same fixup,
   same linker behaviour as any other unconditional branch.
3. **Generic LLVM SwitchLowering already does the hard part**
   (case clustering, bounds checks, sparse-vs-dense decisions).
   We only have to provide costs + the lowering of one node.
4. **No interaction with register allocator.** The pseudo's
   `Defs=[A,FLAGS,HL,DE]` is conservative — at expansion time we
   know exactly which physregs we touch.


## Empirical baseline (April 2026 — `temp/o66_if_cascades.c`)

A small experiment compiled three semantically-equivalent dispatchers
with the current `clang --target=i8080-unknown-v6clang -O2
-fno-jump-tables`:

1. `dispatch_switch` — plain C `switch (x) { case 0..7: ... }`.
2. `dispatch_if_freq` — `if (x==3) ... else if (x==5) ...` ordered
   by descending hand-tagged frequency.
3. `dispatch_if_seq` — `if (x==0) ... else if (x==1) ...` in
   numerical order.

**All three functions compiled to byte-identical code: 66 B each
(`.text` section size, verified via `llvm-readelf -S`).**

Why? LLVM `SimplifyCFG` normalises if/else cascades back into a
`SwitchInst` in IR, and the mid-end emits a **balanced binary
search** (not a linear cascade) for dense unsigned-i8 switches.
The pattern, for an 8-case dense switch on `x` (lowering uses `JP`
which on V6CLANG is "jump if positive" ≡ unsigned ≥):

```asm
        CPI 4 ; JP upper      ; pivot: x<4 vs x>=4
  lower:
        CPI 2 ; JP {2,3}
        ORA A ; JZ  f0        ; x==0
        CPI 1 ; JNZ fdef
        JMP   f1              ; x==1
  {2,3}:
        CPI 2 ; JZ  f2
        CPI 3 ; JNZ fdef
        JMP   f3
  upper:
        CPI 6 ; JP {6,7}
        CPI 4 ; JZ  f4
        CPI 5 ; JNZ fdef
        JMP   f5
  {6,7}:
        CPI 6 ; JZ  f6
        CPI 7 ; JNZ fdef
        JMP   f7
```

Per-case dispatch cycles (this is the *real* baseline the JT must
beat — not a linear cascade):

| Reaches | Path                              | cc |
|---------|-----------------------------------|----|
| f0      | 2× `CPI;JP` + `ORA;JZ`            | **56** |
| f1      | 2× `CPI;JP` + `ORA;JZ`(nt) + `CPI;JNZ` + `JMP` | **88** |
| f2      | 2× `CPI;JP` + `CPI;JZ`            | **60** |
| f3      | 2× `CPI;JP` + `CPI;JZ`(nt) + `CPI;JNZ` + `JMP` | **92** |
| f4      | 2× `CPI;JP` + `CPI;JZ`            | **60** |
| f5      | same shape as f3                  | **92** |
| f6      | same shape as f2                  | **60** |
| f7      | same shape as f3                  | **92** |

Uniform-distribution average: **(56+88+60+92+60+92+60+92)/8 = 75 cc**.
Worst case: 92 cc. Best case: 56 cc. Code: 66 B.

JT (Layout B padded), 8 cases: **68 cc constant**, 10 B code +
32 B table = **42 B** total.

| Metric        | Binary search (current) | JT padded | Δ            |
|---------------|------------------------|-----------|--------------|
| Avg cc        | 75                     | 68        | **−7 cc**    |
| Worst cc      | 92                     | 68        | **−24 cc**   |
| Best cc       | 56                     | 68        | +12 cc       |
| Code+table B  | 66                     | 42        | **−24 B**    |

### Three-way comparison (N=8, uniform)

The linear cascade is a virtual baseline here — LLVM does not emit
it today on V6CLANG — but it is what we *would* emit if we suppress
binary-search lowering (see *Suppressing LLVM's binary-search
lowering* below).

| Metric                  | Binary search (current) | Linear cascade (CPI;JZ × N + JMP) | JT padded (Layout B) |
|-------------------------|-------------------------|-----------------------------------|----------------------|
| Avg cc (uniform)        | 75                      | 90                                | **68**               |
| Worst-case cc           | 92                      | 172                               | **68**               |
| Best-case cc            | **56**                  | 20                                | 68                   |
| **Hot-case-first cc**   | ≥ 56 (tree-dependent)   | **20**                            | 68                   |
| Code+table B            | 66                      | **43**                            | 42                   |

This is the picture the plan is actually built around:

* **JT beats binary search on every metric except best-case cc.**
  Constant-time dispatch dominates a 3-deep tree of conditional
  branches at N=8.
* **Linear cascade is *smaller* than binary search.** Each case is
  one `CPI imm; JZ Li` (5 B / 20 cc) plus a final `JMP fdef`. For
  N=8 the cascade is 43 B vs the binary search's 66 B — a 23 B
  saving for free, just by suppressing tree lowering.
* **Linear cascade owns the hot path when one case dominates.** A
  frequency-ordered cascade hits the hot case in a flat 20 cc;
  neither the binary search (≥ 56 cc) nor the JT (68 cc) can match
  that. This is the core of point (b) below.

### What this empirical data changes about the plan

1. **Frequency-ordered if/else is a non-mitigation in source.**
   `SimplifyCFG`/`FlattenCFG` normalises every if/else cascade into
   a `SwitchInst` before SwitchLowering runs. Source-level case
   ordering is discarded — all three forms in `temp/o66_if_cascades.c`
   produce byte-identical 66 B output. Frequency information has
   to enter through `__builtin_expect` / PGO / branch-weight
   metadata, **or** through a target-side cascade-ordering pass
   that re-orders cases by descending weight before emitting the
   `CPI;JZ` chain.

2. **The current binary-search baseline is dominated by both
   alternatives.** It is bigger than the linear cascade (66 B vs
   43 B) and slower than the JT (75 cc avg / 92 cc worst vs 68 cc
   constant). There is no hit-distribution under which today's
   output is the right answer — it should be replaced *unconditionally*
   for V6CLANG, in favour of either a linear cascade (small N or
   skewed distribution) or a JT (larger uniform N).

3. **Worst-case latency: JT wins by the largest margin.** At N=8
   the JT shaves 24 cc off the binary-search worst case and 104 cc
   off the linear-cascade worst case. For interrupt handlers, IO
   polling, and any code where dispatch jitter matters, the JT is
   the only acceptable answer.

4. **Code-size: linear cascade and JT are within 1 B at N=8 and
   the JT pulls ahead from N≥10.** Each cascade case adds 5 B; each
   padded-JT case adds 4 B. Crossover is N=10 (cascade 53 B, JT
   50 B). For `-Os` priorities below this crossover the cascade is
   the right answer.

5. **Hot-case-dominant distributions favour the cascade.** A
   frequency-ordered cascade with weight-aware ordering hits the
   hot case in 20 cc vs the JT's 68 cc; the JT only wins on average
   when no case has > ~40 % share.


## Suppressing LLVM's binary-search lowering

`SwitchLoweringUtils.cpp` decides between three sub-lowerings of a
`SwitchInst`:

1. **Jump table** — gated by `TLI.areJTsAllowed()` and
   `TLI.getMinimumJumpTableEntries()`. Today V6CLANG returns the
   default (4) and `areJTsAllowed = true`, but with no `BR_JT`
   selection pattern this currently crashes — fixed by Step 1.
2. **Bit test** — gated by `TLI.isJumpTableRelative()` /
   `getMinimumBitTestSwitchClusterEntries()`. Not useful for V6CLANG
   (no efficient bittest on i8080).
3. **Binary-search of clusters** — *fallback when 1 and 2 are
   declined*. Builds a balanced tree of `if (x<pivot) goto lo;
   else goto hi;` until each leaf is a single case → `if (x==v)
   goto Lv;`.

There is no per-target hook to swap the binary-search fallback for
a **linear cascade** of the leaves. We have two clean ways to get
a cascade:

### Option A — `setMinimumJumpTableEntries(0)` + cluster-collapse hook

Make every multi-case `SwitchInst` a single "jump-table cluster"
for SwitchLoweringUtils, then in our `LowerBR_JT` decide *inside
the target* whether to materialise a real JT or a hand-written
cascade. This puts all the policy on V6CLANG-side (good).
Downside: we have to faithfully recreate cascade lowering ourselves
(case sorting by weight, default fall-through, range-check skip)
— maybe 200 LoC.

### Option B — Pre-isel pass that lowers small `SwitchInst`s to
IR-level cascades (recommended for the smallest viable patch)

A function pass running **before** `SelectionDAGISel` walks each
`SwitchInst`, and if its case count is below the JT threshold (or
the cost model picks cascade), rewrites it to:

```ll
  %eq0 = icmp eq i8 %x, 0
  br i1 %eq0, label %case0, label %t1
t1:
  %eq1 = icmp eq i8 %x, 1
  br i1 %eq1, label %case1, label %t2
  ...
```

ordered by descending branch-weight metadata. SimplifyCFG **does
not** re-fuse this back into a `SwitchInst` after isel-prep, so the
cascade survives to selection unchanged. ~80 LoC, no SDAG
intrusion, easy to test.

Recommendation: **Option B**. Land the JT lowering first (closes
the crash), add the pre-isel cascade pass second.


## Hybrid layout (cascade-prefix + JT, recommended)

With both cascade and JT lowerings available the natural design is
to **combine** them: a short prefix of `CPI;JZ` for the **K**
hottest cases, then a `BR_JT` for the dense remainder.

**K** = number of hot cases peeled out of the switch and tested
as an inline `CPI imm; JZ Lcase` pair *before* the JT dispatch.
K is chosen by the cost model from the branch-weight metadata; the
recommended cap is K=3 (see *When to use which K* below).

```asm
        ; cascade prefix — K hot cases, frequency-ordered
        CPI <hot0> ; JZ  L_hot0     ; 20 cc / 5 B
        CPI <hot1> ; JZ  L_hot1     ; 20 cc / 5 B
        ...                          ; up to K times
        ; tail — JT for the rest (range_lo..range_hi)
        CPI <range_hi + 1>           ;  8 cc / 2 B   (upper bound)
        JNC L_default                ; 12 cc / 3 B
        ; (lower-bound check elided when range_lo == 0;
        ;  otherwise: CPI <range_lo>; JC L_default — see below)
        LXI  HL, (jt - range_lo*4)   ; 12 cc / 3 B   ← fold offset here!
        ADD  A                       ;  4 cc / 1 B
        ADD  A                       ;  4 cc / 1 B
        MOV  E, A                    ;  8 cc / 1 B
        MVI  D, 0                    ;  8 cc / 2 B
        DAD  D                       ; 12 cc / 1 B
        PCHL                         ;  8 cc / 1 B
        ; table-slot:  JMP L_caseN   ; 12 cc / 3 B
```

### Why no `SUI` (re-base) instruction

A naive lowering would re-base the switch value with
`SUI <range_lo>` so the JT can start at index 0. **We don't do
that**, for two reasons:

1. **`SUI` clobbers `A` and `FLAGS`.** The cascade prefix already
   used `A` for `CPI` tests, and the upper-bound `CPI` we *do*
   keep relies on `A` still holding the original switch value.
   Re-basing would force us to either reload `A` from a temp or
   redo the bounds check on the rebased value — dead weight.
2. **The rebase folds into the `LXI` immediate at link time.**
   `LXI HL, (jt - range_lo*4)` is a single 16-bit absolute
   relocation, computed by the assembler. The `DAD D` that adds
   `idx*4` then lands at `jt + (orig − range_lo)*4` exactly. Zero
   runtime cost for the rebase.

**Bounds check is one `CPI` (not two) in the common case.** If
`range_lo == 0` (the typical state-machine `case 0..N-1` shape),
only the upper bound `CPI <range_hi+1>; JNC L_default` is needed.
If `range_lo > 0`, a lower-bound check `CPI <range_lo>; JC
L_default` is added — still 8 cc / 2 B per check, no `A` clobber.
For a switch over a `(uint8_t)`-typed expression with `range_hi ==
255`, even the upper bound is elidable.

### `i8`-index cap: 64 dense cases

Layout B padded uses `idx*4` indexing through `A` (an 8-bit
register). The largest table addressable by an unsigned i8 index
scaled by 4 is **256 bytes → 64 entries**. Above N=64 the index
would overflow `A` and we must promote to i16 indexing
(`DAD H; DAD H` for `idx*4` on `HL`, ~12 extra cc). For Layout B
tight (idx*3) the cap is **85 entries**; for Layout A (idx*2),
**128 entries**.

N ≥ 65 is rare in practice (large state machines tend to fan out
through a function-pointer table instead). The first cut of this
plan implements only the i8 fast-path — above the cap, the cost
model falls back to cascade-or-cascade+BS, and i16 indexing is a
follow-up.

### Cycle profile (N total cases, K hot prefix entries)

Let `p_hot = sum_{i<K} weight_i` and `p_tab = 1 − p_hot`.

```
E[cc] = p_hot × E[cc | in prefix]            // 20..K*20
      + p_tab × (K*20 + 84)                  // misses then JT
```

Worst case of the hybrid: `K*20 + 84` cc.

### Cycle table (N=16, weights 50/20/10 for top-3 then uniform)

| Layout            | Avg cc | Worst cc | Bytes |
|-------------------|--------|----------|-------|
| Linear cascade    | ~80    | 332      | 83    |
| Binary search     | ~110   | 124      | ~120  |
| Pure JT (Layout B)| 68     | 68       | 74    |
| **Hybrid K=2**    | **0.7×30 + 0.3×124 = 58** | 124 | 84 |
| **Hybrid K=3**    | **0.8×40 + 0.2×144 = 61** | 144 | 89 |

The hybrid is the only layout that wins both the average *and* the
worst-case for skewed distributions, at a small (≤ 15 B) extra
footprint over pure JT.

### When to use which K

| Distribution shape       | Recommended K |
|--------------------------|---------------|
| Uniform                  | 0 (pure JT)   |
| One dominant case ≥ 50 % | 1             |
| Two-three hot cases      | 2–3           |
| Skewed long-tail         | 3 (cap)       |

**Cap K at 3.** Each prefix step adds 20 cc to every "miss" path
and 5 B to the function. Beyond K=3 the worst-case explodes faster
than the average improves.

### Cost-model decision

`V6ClangInstrCost.h` (extends Step 4):

```cpp
constexpr V6ClangInstrCost CascadeStep      { /*B*/ 5, /*cc*/20 }; // CPI imm + JZ
constexpr V6ClangInstrCost JTBoundsCheck    { /*B*/ 5, /*cc*/20 }; // CPI imm + JNC (per side)
constexpr V6ClangInstrCost JTDispatchPadded { /*B*/10, /*cc*/56 }; // LXI..PCHL preamble
constexpr V6ClangInstrCost JTSlotJmp        { /*B*/ 0, /*cc*/12 }; // the table-slot JMP
// Tail total = 1–2 × JTBoundsCheck + JTDispatchPadded + JTSlotJmp.
// Hybrid total = K × CascadeStep + tail.
```

The selector walks the case-cluster list sorted by descending
weight, peels off cases while `weight_i > break_even_threshold`,
and stops at K=3 or when the remaining cluster is < 4 cases (in
which case the whole switch becomes a pure cascade).

The pre-isel pass from Option B above is a natural place to do the
peeling: rewrite the `SwitchInst` into

```ll
  switch i8 %x, label %tail [ i8 hot0, label %case_hot0
                              i8 hot1, label %case_hot1 ]
tail:
  switch i8 %x, label %default [ ... rest ... ]   ; ← real JT
```

LLVM treats the inner switch as a separate cluster and lowers it
as a JT, while the outer switch (≤ K cases) gets the cascade
treatment. Zero new pseudos, all on top of Step 2's JT lowering.


## Cascade-prefix + binary-search variant (sparse remainder)

The pure cascade+JT hybrid above assumes the **remainder after
peeling K hot cases is dense** — dense enough that LLVM's
`getMinimumJumpTableDensity()` (default 40 %) accepts it as a JT
cluster. When it is **not** — e.g. the switch is over scattered
opcodes `{0x00, 0x10, 0x20, 0x80, 0xC3, 0xCD, ...}` — the JT either
explodes (a 256-byte table for 8 actual entries) or, more often,
LLVM splits it into multiple clusters and falls back to the binary
search we are trying to replace.

For that case we want **cascade-prefix + binary-search tail**.

### Why the binary-search tail beats both pure-cascade and JT here

| Tail shape                          | Pure cascade tail     | JT tail (forced) | Binary-search tail |
|-------------------------------------|-----------------------|------------------|--------------------|
| Dense `0..M-1`                      | 90 cc avg / 5M+3 B    | **68 cc / ~10+4M B** | 75 cc / ~5M+8 B   |
| Sparse `{v₀, … v_{M-1}}`, range R   | 90 cc avg / 5M+3 B    | broken (4R B)    | **75 cc / ~5M+8 B** |
| Mixed (one tight cluster + outliers)| 90 cc avg / 5M+3 B    | broken            | **75 cc** (probes the cluster boundary) |

Key property the user surfaced: **binary search tolerates arbitrary
case values — there is no "density" requirement and no padding
blowup.** JT requires density (or wastes code-size on padding).
This makes BS the right tail for the long-tail of cold sparse
cases that PGO has not annotated.

### Four-mode dispatch table

The cost model now picks among four shapes (in order of
recommendation, cheapest first):

| Mode | Layout                          | Best for                                         |
|------|---------------------------------|--------------------------------------------------|
| 1    | **Linear cascade**              | N ≤ 5, or one case ≥ 50 % weight                  |
| 2a   | **Cascade-prefix + JT**         | K hot + dense remainder (density ≥ 40 %, M ≤ 64)  |
| 2b   | **Cascade-prefix + Binary search** | K hot + sparse remainder (density < 40 %, M ≤ 64)|
| 3    | **Pure JT** (Layout B padded)   | Uniform / unknown distribution, dense N ≥ 6, N ≤ 64|

Mode 2b's tail is the binary-search **leaf cluster** lowering that
LLVM already emits today (we do not have to write it). The new
work is just the K-case peeling — the same pre-isel pass that
peels for mode 2a peels for 2b; only the inner switch lowers
differently because its cluster is sparse.

### Worked example: scattered 12-case opcode dispatch

Cases: `{0x00, 0x01, 0x10, 0x20, 0x21, 0x80, 0xC3, 0xCD, 0xCE,
0xD3, 0xDB, 0xFF}`, with 0xCD (CALL) carrying ~50 % weight per
PGO and 0xC3 (JMP) ~20 %.

* **Pure cascade** (frequency-ordered): hot 20 cc, cold worst
  12 × 20 + 12 = 252 cc, 63 B.
* **Pure JT**: range = 0xFF, table = 256 × 4 = **1024 B** —
  unacceptable.
* **Hybrid 2a (cascade + JT)**: peel 0xCD, 0xC3 (K=2), remainder
  is still spread 0..0xFF → still no JT possible.
* **Hybrid 2b (cascade + BS)**: peel 0xCD, 0xC3; remainder of 10
  scattered cases lowered as binary search. Hot path 20 cc;
  miss-then-BS ≈ 20 + 80 = 100 cc; ~63 B. **Wins on every
  metric** for this distribution.


## Savings estimate

Cascade cost depends entirely on the hit distribution. With the
cascade ordered by descending case frequency:

* `Cascade_expected_cc = sum_i weight_i * rank_i * 20 + 12`
* `Cascade_worst_cc    = N * 20 + 12`

JT padded: 68 cc / 10 B code + 4 B per entry.

### Distribution: uniform (e.g. opcode decoder, no hot case)

| Cases (dense) | Cascade avg cc | Cascade worst cc | JT padded cc | Δ avg     |
|---------------|----------------|------------------|--------------|-----------|
| 4             | 50             | 92               | 68           | −18 cc (cascade wins) |
| 5             | 60             | 112              | 68           | −8 cc (cascade wins)  |
| 6             | 70             | 132              | 68           | **+2 cc** |
| 8             | 90             | 172              | 68           | **+22 cc** |
| 16            | 170            | 332              | 68           | **+102 cc** |
| 32            | 330            | 652              | 68           | **+262 cc** |

### Distribution: hot-case-dominant (frequency-ordered cascade)

One case takes 80 % of the traffic (hot), remaining (N−1) cases
share 20 % uniformly. Cascade tests the hot case first.

| Cases | Cascade avg cc                              | JT cc | Δ avg |
|-------|---------------------------------------------|-------|--------|
| 4     | 0.8×20 + 0.2×((1+2+3)/3)×20+12 = 16+40+12=37 | 68    | **−31 cc** |
| 8     | 16 + 0.2×4×20+12 = 16+16+12 = 44            | 68    | **−24 cc** |
| 16    | 16 + 0.2×8×20+12 = 16+32+12 = 60            | 68    | **−8 cc**  |
| 32    | 16 + 0.2×16×20+12 = 16+64+12 = 92           | 68    | **+24 cc** |

The cascade is competitive even at N=32 when one case dominates.

### Distribution: bimodal 50/50 (two equally-hot cases first)

| Cases | Cascade avg cc                                         | JT cc | Δ avg |
|-------|--------------------------------------------------------|-------|--------|
| 4     | 0.5×20+0.5×40 = 30 + 12 = 42                          | 68    | **−26** |
| 8     | 0.5×20+0.5×40 = 30 + 12 = 42                          | 68    | **−26** |
| 16    | same first-two pattern + tail ≈ 42                    | 68    | **−26** |

If the two hottest cases are tested first, the cascade wins at any N.

### Code-size delta (independent of distribution)

| Cases | Cascade B | JT padded code+table B | Δ        |
|-------|-----------|------------------------|----------|
| 4     | 23        | 10 + 16 = 26           | +3       |
| 6     | 33        | 10 + 24 = 34           | +1       |
| 8     | 43        | 10 + 32 = 42           | **−1**   |
| 16    | 83        | 10 + 64 = 74           | **−9**   |
| 32    | 163       | 10 + 128 = 138         | **−25**  |

Layout B tight (`-Os`): subtract 1 B per entry, add 8 cc to dispatch
(76 cc total). Layout A (`-Oz`): subtract 2 B per entry, add 16 cc
(84 cc total).

### Conclusion

The full plan replaces the current binary-search lowering with a
**four-mode dispatch** chosen per `SwitchInst` by the cost model
(see *Four-mode dispatch table* above):

1. **Linear cascade** (frequency-ordered) — small N (≤ 5) or one
   case ≥ 50 % weight. Smallest code, hot-case dispatch in 20 cc.
2a. **Hybrid cascade-prefix + JT** — skewed distribution with a
    **dense** remainder, N ≥ 6, total range ≤ 64 (i8-indexable).
    Wins on average *and* worst-case.
2b. **Hybrid cascade-prefix + binary-search** — skewed distribution
    with a **sparse** remainder (the JT would need padding the
    table can't justify). Hot path 20 cc, cold path matches the
    current binary-search baseline but pays only on the cold path.
3. **Pure JT** (Layout B padded) — uniform / unknown distribution,
   dense N ≥ 6, N ≤ 64. Constant 68 cc, 42 B at N=8.

The key axis is **density of the remainder after peeling**:
JT requires density and tops out at 64 entries (i8 index cap, see
*`i8`-index cap* above); binary search has neither limit. This is
why the user's preferred composition — cascade for the first K hot
cases, then a smarter dispatch for the rest — is the right shape:
it lets the cost model pick JT *or* binary search for the tail
based on the actual cluster geometry, instead of forcing one or
the other.

The current LLVM-generated balanced binary search (without a
cascade prefix) is **not** in that list — for V6CLANG it is dominated
by the linear cascade in size and by the JT in cycles, with no
distribution where it is the right answer for the *whole* switch.
Suppressing it in favour of one of the four modes above (Option B
in *Suppressing LLVM's binary-search lowering*) is part of the
plan, not just an optional follow-up.

For PGO-instrumented or `__builtin_expect`-annotated switches the
cost model picks among the four modes precisely. For un-annotated
switches we assume a uniform distribution and pick mode 1 (small
N), mode 3 (large dense N), or mode 2b (large sparse N). Users
who know the hot case can annotate it with `__builtin_expect` (or
`[[likely]]` on case labels) to push the decision into mode 2a/2b
or mode 1.


## Risks

* **Table-in-rodata vs. flat-binary memory layout.** Vector-06C
  builds use a single contiguous flat binary (`elf2bin.py` /
  `ld.lld -O binary`); putting JMP tables in `.rodata` is
  already supported by the linker script. Worth a one-time
  smoke-test that the tables land at the expected addresses.
* **Out-of-range indices.** If user code indexes a JT-lowered
  switch with a value outside the case range *and* skips the
  bounds check (e.g. via inline-asm shenanigans), `PCHL` will
  jump into garbage. SwitchLowering always inserts the bounds
  check — the risk is theoretical.
* **Interaction with `-mv6clang-start-address`.** JT addresses are
  link-time absolute, same as any function — no special handling.


## References

* Existing `PCHL` definition —
  [V6ClangInstrInfo.td](../../llvm/lib/Target/V6Clang/V6ClangInstrInfo.td#L436)
  (currently unreferenced).
* `ISD::BR_JT` lowering reference: AVR backend
  (`AVRISelLowering.cpp::LowerBR_JT`) and MSP430 backend
  (`MSP430ISelLowering.cpp`) — both small, instructive, sub-300-LOC
  examples.
* Cost model — [V6ClangInstrCost.h](../../llvm/lib/Target/V6Clang/V6ClangInstrCost.h).
* SwitchLowering hooks documented in
  `llvm/include/llvm/CodeGen/TargetLoweringBase.h`:
  `setMinimumJumpTableEntries`, `isSuitableForJumpTable`,
  `getMinimumJumpTableDensity`.
* Related design:
  * `O11_dual_cost_model.md` — provides the cycle/byte trade-off
    primitives used to gate the JT-vs-cascade decision.
  * `O28_branch_threading_jmp_only.md` — composes: `JMP table` slots
    that target a single-JMP block can be threaded through to the
    final block, eliminating one hop.
