# O63 — Split i8/i16 Spill/Reload Pseudos to Drop False `Defs=[FLAGS]` on Static-Stack Path

## Resolution
Rejected
O63 as written is mostly obsolete on the current pipeline, and on the strongest repro I could get it still did not change generated code. If you want to revisit it later, the only plausible remaining target is earlier generic post-RA scheduling behavior, not the late V6CLANG zero-test / redundant-flag passes. I reverted the temporary backend change and rebuilt the baseline compiler afterward; the normal build/test sweep passed again.

**Source:** V6CLANG
**Savings:** indirect — gives the pre-RA / post-RA scheduler freedom to
            move flag-setters (`CMP`, `XRA`, `INR`, `DCR`, `ADD`, …)
            across spill/reload pseudos in static-stack functions.
            Per fold: typically 4–12cc / 1–3B saved when the scheduler
            drops a redundant zero-test or re-establishes flags.
**Frequency:** Medium. Occurs wherever a compare/zero-test is separated
            from its consumer branch by a spill/reload site.
**Complexity:** Low-Medium
**Risk:** Low-Medium (correctness on the dynamic-stack path must be
          preserved; easy to get wrong if the two pseudos are not
          selected mode-consistently).
**Dependencies:** O10 (static stack) done; interacts with O42
          (liveness-aware expansion), O61 (spill-patched reload).
**Status:** [ ] not started.


## Problem

All four spill/reload pseudos declare `Defs = [FLAGS]`:

```tablegen
let mayStore = 1, Defs = [FLAGS] in
def V6CLANG_SPILL8  : V6ClangPseudo<(outs), (ins GR8:$src, i16imm:$fi), ...>;

let mayLoad  = 1, Defs = [FLAGS] in
def V6CLANG_RELOAD8 : V6ClangPseudo<(outs GR8:$dst), (ins i16imm:$fi), ...>;

// Same for V6CLANG_SPILL16 / V6CLANG_RELOAD16.
```
(`llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td` — `def V6CLANG_SPILL8`)

The flag def is **only actually true** on the dynamic-stack lowering in
`V6ClangRegisterInfo::eliminateFrameIndex` (lines ~391–456), which emits

```
PUSH HL; LXI HL, offset+2; DAD SP; MOV M, r; POP HL
         └────────────────────────────┘
         DAD SP is the sole flag-setter (CY).
```

The **static-stack lowering** (same file, lines ~143–250) emits only
flag-clean instructions:

| Shape              | Instructions                           | Flags |
|--------------------|----------------------------------------|-------|
| A src=A / dst=A    | `STA addr` / `LDA addr`                | clean |
| B r ∈ {B,C,D,E}    | `[PUSH HL]; LXI HL,addr; MOV M,r / MOV r,M; [POP HL]` | clean |
| C r ∈ {H,L}        | adds `MOV D,H` / `MOV E,L` / `MOV r,M` | clean |
| i16 HL             | `SHLD addr` / `LHLD addr`              | clean |
| i16 DE             | `XCHG; SHLD/LHLD addr; XCHG`           | clean |
| i16 BC             | routes through D/E + SHLD/LHLD         | clean |

No instruction in any static-stack expansion writes PSW. Static stack is
the default mode (`hasStaticStack()` is true unless
`-mv6clang-no-static-stack`), so for the overwhelming majority of functions
the `Defs=[FLAGS]` attribute is a **false positive**.

### Cost of the false positive

Any pass operating on the machine-IR after `storeRegToStackSlot` /
`loadRegFromStackSlot` have fired — and before `eliminateFrameIndex`
expands the pseudos — treats every spill as if it clobbered CY, SIGN,
ZERO, PARITY, AUX. In particular:

* **O17** (redundant flag elimination) stops a backwards scan at any
  spill/reload, even though the flags are actually preserved.
* **O58** (CmpZero backward scan) cannot skip past a spill slot when
  deciding whether an earlier `XRA`/`ORA` has already established Z.
* **Post-RA machine scheduler** refuses to sink a `CMP`/`CPI` past a
  spill to shorten the live range of its operands.
* **O38** (XRA+CMP i8 zero-test peephole) is blocked when a spill site
  sits between the XRA and the branch.

On static-stack builds (production default) none of that is necessary.


## Proposed solution

**Split each spill/reload pseudo into a STATIC flavour (no flag def) and
a DYNAMIC flavour (keeps the flag def).** Select the flavour in
`V6ClangInstrInfo::storeRegToStackSlot` / `loadRegFromStackSlot` based on
`MachineFunctionInfo::hasStaticStack()`, which is already known at that
point.

```tablegen
// Static-stack flavour: flag-safe — every expansion is LXI+MOV*/STA/LDA/
// SHLD/LHLD, all of which leave PSW untouched.
let mayStore = 1 in
def V6CLANG_SPILL8_S  : V6ClangPseudo<(outs), (ins GR8:$src, i16imm:$fi), ...>;
let mayLoad  = 1 in
def V6CLANG_RELOAD8_S : V6ClangPseudo<(outs GR8:$dst), (ins i16imm:$fi), ...>;

// Dynamic-stack flavour: DAD SP in the expansion clobbers CY.
let mayStore = 1, Defs = [FLAGS] in
def V6CLANG_SPILL8_D  : V6ClangPseudo<(outs), (ins GR8:$src, i16imm:$fi), ...>;
let mayLoad  = 1, Defs = [FLAGS] in
def V6CLANG_RELOAD8_D : V6ClangPseudo<(outs GR8:$dst), (ins i16imm:$fi), ...>;
```

Same split for `V6CLANG_SPILL16` / `V6CLANG_RELOAD16`. `eliminateFrameIndex`
already has two disjoint lowering branches — they simply key off the new
opcodes rather than off `hasStaticStack()` at expansion time.


## Approach B — Preserve flags inside the dynamic-stack expansion

Fallback plan for the case where Approach A turns out impractical
(e.g. downstream consumers that hard-code the opcode names prove too
tangled, or the split interacts badly with a future pass). Dynamic-stack
allocation is the **lowest-priority code path** — it's used only when
`-mv6clang-no-static-stack` is on, or for functions that aren't
`norecurse`. Its instruction count and cycle count are already dominated
by `PUSH HL / LXI HL / DAD SP / MOV M,r / POP HL` (≥ 42 cc, 6 B per i8
spill), so paying 2 extra instructions to preserve PSW is negligible
there.

**Idea:** wrap `DAD SP` in each dynamic-stack spill/reload expansion with
`PUSH PSW` / `POP PSW`, then drop `Defs = [FLAGS]` from the pseudo
declaration entirely (single pseudo, no flavours).

```tablegen
// No Defs = [FLAGS] anywhere. Every expansion is guaranteed to leave
// PSW unchanged: static-stack lowering is naturally flag-clean, and
// dynamic-stack lowering wraps DAD SP with PUSH PSW / POP PSW.
let mayStore = 1 in
def V6CLANG_SPILL8  : V6ClangPseudo<(outs), (ins GR8:$src, i16imm:$fi), ...>;
let mayLoad  = 1 in
def V6CLANG_RELOAD8 : V6ClangPseudo<(outs GR8:$dst), (ins i16imm:$fi), ...>;
```

Dynamic-stack lowering in `V6ClangRegisterInfo::eliminateFrameIndex`
(lines ~391–456) gets a **tight** wrapper around the only flag-setter:

```
PUSH HL               ; 11cc, 1B  — (already present, if HL live)
LXI  HL, offset+2     ; 10cc, 3B
PUSH PSW              ; 11cc, 1B  — save A + flags
DAD  SP               ; 10cc, 1B  — clobbers CY (now saved)
POP  PSW              ; 10cc, 1B  — restore A + flags
MOV  M, r             ;  7cc, 1B
POP  HL               ; 10cc, 1B  — (already present, if HL live)
```

Only `DAD SP` sits between the `PUSH PSW` / `POP PSW`, so the wrap is
as small as possible. Everything outside the wrap — `LXI`, `MOV M,r`,
`MOV r,M`, `STA`, `LDA`, `SHLD`, `LHLD`, `XCHG`, `PUSH`, `POP` — leaves
PSW untouched on the i8080, so A and flags flow through undisturbed.

Extra cost: **+21 cc, +2 B per dynamic spill/reload that uses `DAD SP`**
(i.e. every dynamic-stack expansion; static-stack shapes are unaffected
because they never emit `DAD SP`).

### Dynamic-stack caveats

* **Shapes without `DAD SP` need no wrap.** Inside dynamic-stack
  lowering this is rare, but if any fast path exists that resolves a
  frame address without `DAD SP`, skip the wrap there.
* **A as spill source / reload dest is a non-issue.** The wrap brackets
  `DAD SP` only; the subsequent `MOV M,r` (or preceding `LDA`/`MOV r,M`)
  runs *outside* the wrap, so it doesn't matter whether the data
  register is A. `PUSH PSW` saves A; nothing between `PUSH PSW` and
  `POP PSW` touches A; `POP PSW` restores the same A.
* **Ordering discipline.** `LXI HL, offset+2` must stay *before*
  `PUSH PSW`, because `PUSH PSW` pushes 2 bytes and the frame offset
  already includes the `+2` adjustment that compensates for the
  already-emitted `PUSH HL`. Adding another PSW push between the two
  means the `DAD SP` sees SP two bytes lower than expected — bug.
  **Mitigation:** emit `LXI HL` *before* the `PUSH PSW`, and bump the
  offset by `+2` again if (and only if) the wrap is emitted:
  ```
  Offset = baseOffset
         + (HL-live ? 2 : 0)      // for the outer PUSH HL
         + (wrap    ? 2 : 0);     // for the PSW wrap
  ```
  This mirrors the existing O42-style offset accounting already present
  in the expansion (`AdjOffset = HLDead ? Offset : Offset + 2`).
* **`SHLD`/`LHLD` variants** don't use `DAD SP` or set flags, so they
  don't need the wrap in either mode.

### Trade-off vs Approach A

|                                  | Approach A (split)        | Approach B (wrap)              |
|----------------------------------|---------------------------|--------------------------------|
| TableGen churn                   | 4 pseudos → 8             | none                           |
| Consumer updates                 | O16, O61, AsmPrinter, MIR tests — rename | none (opcode names unchanged) |
| Static-stack perf                | +0 cc, +0 B               | +0 cc, +0 B                    |
| Dynamic-stack perf               | +0 cc, +0 B               | +21 cc, +2 B per spill/reload  |
| Correctness surface              | flavour must match mode   | one wrapper branch only        |
| Honesty at MachineIR level       | perfect                   | perfect                        |

Approach A is still preferred because the cost on the dynamic path is
literally zero. Approach B is strictly simpler to implement (one
function modified, no opcode renames, no ABI-style ripple through the
codebase) and is the right choice if a blocker is hit while rolling out
A.

### Implementation sketch (Approach B)

1. **`V6ClangInstrInfo.td`** — remove `Defs = [FLAGS]` from the four
   spill/reload pseudos. No new pseudos.
2. **`V6ClangRegisterInfo.cpp::eliminateFrameIndex`** — in every dynamic-stack
   branch that currently emits `DAD SP`, emit `PUSH PSW` immediately
   **before** the `DAD SP` and `POP PSW` immediately **after** it. The
   wrap is tight — it brackets only the flag-setter, not the surrounding
   `LXI` / `MOV M,r` / `MOV r,M` / PUSH HL / POP HL.
   * Bump the `LXI HL, offset` adjustment by an extra `+2` when the
     wrap is emitted (the intervening `PUSH PSW` shifts SP). Mirrors
     the existing `HLDead ? Offset : Offset + 2` accounting for the
     outer `PUSH HL`.
   * Skip the wrap on SHLD/LHLD fast paths inside dynamic stack — they
     don't emit `DAD SP` and don't set flags.
3. **Tests** — identical to Approach A: add flag-preservation lit
   tests for both `-mv6clang-no-static-stack` and default (static-stack).
4. **No changes** in `V6ClangInstrInfo.cpp`, `V6ClangSpillForwarding.cpp`,
   `V6ClangSpillPatchedReload.cpp`, or MIR-level tests.

### Decision rule

Ship Approach A first. If during implementation the consumer
rewrites in O16 / O61 / AsmPrinter / annotation / MIR tests prove
larger than expected (> ~200 LOC across the repo) or introduce
subtle flavour-mismatch bugs, fall back to Approach B.


## Alternative: single pseudo, late flag re-injection

Keep one pseudo (no flag def) and have the dynamic-stack expansion emit
`DAD SP` with an explicit `Defs = [FLAGS]` on the expanded MI. Simpler
TableGen diff but still correct.

Trade-off:
* **Split (preferred):** the flag-state model is correct at the
  MachineIR level — any future pass between `storeRegToStackSlot` and
  `eliminateFrameIndex` sees an honest model without needing to know
  the lowering.
* **Late re-injection:** zero TableGen churn, but relies on every MI
  consumer trusting the `DAD SP` inside the expansion. Works, but
  mirrors the O20 mistake (false HL clobber) in the opposite direction
  if anyone adds a pre-expansion flag-dependent transform.

Go with the split.


## Pseudos to split

| Current pseudo | Static flavour          | Dynamic flavour         | Flag truth |
|----------------|-------------------------|-------------------------|------------|
| `V6CLANG_SPILL8`   | `V6CLANG_SPILL8_S`  (no `Defs=[FLAGS]`) | `V6CLANG_SPILL8_D`  (keeps `Defs=[FLAGS]`) | DAD SP in dynamic |
| `V6CLANG_RELOAD8`  | `V6CLANG_RELOAD8_S` (no `Defs=[FLAGS]`) | `V6CLANG_RELOAD8_D` (keeps `Defs=[FLAGS]`) | DAD SP in dynamic |
| `V6CLANG_SPILL16`  | `V6CLANG_SPILL16_S` (no `Defs=[FLAGS]`) | `V6CLANG_SPILL16_D` (keeps `Defs=[FLAGS]`) | DAD SP in dynamic |
| `V6CLANG_RELOAD16` | `V6CLANG_RELOAD16_S` (no `Defs=[FLAGS]`) | `V6CLANG_RELOAD16_D` (keeps `Defs=[FLAGS]`) | DAD SP in dynamic |


## Implementation sketch

1. **`V6ClangInstrInfo.td`** — replace each of the four pseudos with the `_S`
   / `_D` pair. Keep the existing ins/outs/predicates identical.
2. **`V6ClangInstrInfo.cpp`** — in `storeRegToStackSlot` /
   `loadRegFromStackSlot` pick the flavour:
   ```cpp
   auto *MFI = MF.getInfo<V6ClangMachineFunctionInfo>();
   unsigned Opc = MFI->hasStaticStack()
                    ? V6CLANG::V6CLANG_SPILL8_S
                    : V6CLANG::V6CLANG_SPILL8_D;
   ```
   Four instances (i8 spill/reload, i16 spill/reload).
3. **`V6ClangRegisterInfo.cpp::eliminateFrameIndex`** — switch the opcode
   comparisons to the new names. Each existing lowering branch already
   corresponds one-to-one with a flavour.
4. **`V6ClangSpillPatchedReload.cpp`** — O61 only fires on static-stack
   functions, so match only `*_S`. Update the `if (Opc == V6CLANG::…)`
   chain.
5. **`V6ClangSpillForwarding.cpp`** — same (one-line update per branch).
6. **`V6ClangInstrInfo.cpp::expandPostRAPseudo` + AsmPrinter annotation
   comment** — update the opcode-to-name map so `-mv6clang-annotate-pseudos`
   still emits useful labels (`;--- V6CLANG_SPILL8_S ---` vs
   `;--- V6CLANG_SPILL8_D ---`, or strip the suffix for readability).
7. **Tests**
   * Add a new lit test `test/CodeGen/V6CLANG/spill-flags-static.ll`:
     function with `CMP r; [spill]; JZ L` and assert that the `JZ` still
     reads the flags the `CMP` set (no reloaded flag restore).
   * Keep an analogous `spill-flags-dynamic.ll` under
     `-mv6clang-no-static-stack` that confirms the flag def is honoured
     (i.e. the scheduler / peephole doesn't fold across the spill).
   * Re-run the full lit + feature-test suites (O17 / O38 / O58 tests
     should still pass; a handful may tighten their CHECKs to show
     newly-enabled eliminations).


## Interaction with other passes

* **O42 (liveness-aware expansion)** — unaffected: it's keyed by opcode
  after the flavour is chosen.
* **O61 (spill-patched reload)** — Stage 4 shapes stay the same; the
  patch lowering already emits only `STA`, `MVI`, `LXI`, `DAD DE`, etc.
  `DAD DE` (Stage 2 / 3) **does** set CY, so the `_S` flavour still
  must *not* claim flag cleanliness across a patched i16 reload. Two
  options:
    1. Drop `Defs=[FLAGS]` only on i8-width `_S` and on i16-width HL
       reloads that remain pure SHLD/LHLD, not on the ones O61 rewrites
       to `LXI DE / DAD DE`. Requires O61 to be aware of the split and
       re-add the flag def when it patches a reload.
    2. Keep the `_S` model pessimistic for i16 (still `Defs=[FLAGS]`),
       drop it only for i8 (which never expands to DAD in any mode).
  Option 2 is simpler and captures most of the win (i8 spills are the
  common case). Recommended starting point.


## Savings estimate

Micro-benchmark on the existing corpus (Stage 4 build, static-stack
default) shows ~15–40 post-RA flag-restore or zero-test sites per
100-function TU that sit immediately adjacent to a spill/reload. If
each one that would be eliminated by O17 / O38 / O58 (currently blocked
by the false flag def) saves 4cc+1B, the per-TU cycle saving is in the
hundreds.

Concrete examples to measure after implementation:

1. Loops where the IV is spilled across a call — `CPI / JNZ` sequences
   will fuse with the preceding `DCR` the scheduler can now move.
2. `if (x)` patterns where the zero-test was materialised pre-spill —
   the spill no longer kills the Z flag.
3. `return x ? a : b;` at −O2 when the condition is produced before a
   caller-saved spill.


## Risks

* **Missed dynamic-stack path.** If any lowering under
  `!hasStaticStack()` is mislabelled as `_S`, the flag state becomes
  inconsistent with the real code and O17/O38/O58 silently miscompile.
  Mitigation: the dispatch is centralised in `storeRegToStackSlot` /
  `loadRegFromStackSlot` — one branch each.
* **External users of the opcodes.** O61 (`V6ClangSpillPatchedReload.cpp`),
  O16 (`V6ClangSpillForwarding.cpp`), and `-mv6clang-annotate-pseudos` all name
  the current opcodes explicitly. Straightforward rename, but the
  compiler must be rebuilt after the TableGen change.
* **MIR tests.** Any MIR-level test that literally spells
  `V6CLANG_SPILL8` needs updating. Grep first.


## References

* Pseudo defs — `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`
  (`def V6CLANG_SPILL8`, `def V6CLANG_RELOAD8`, `def V6CLANG_SPILL16`,
  `def V6CLANG_RELOAD16`).
* Static-stack lowering —
  `llvm-project/llvm/lib/Target/V6CLANG/V6ClangRegisterInfo.cpp` lines ~143–250.
* Dynamic-stack lowering — same file, lines ~391–456.
* Storage hook — `V6ClangInstrInfo::storeRegToStackSlot` /
  `loadRegFromStackSlot`.
* Consumer 1 — `V6ClangSpillForwarding.cpp` (`Opc == V6CLANG_SPILL8 ||
  V6CLANG_SPILL16`, `V6CLANG_RELOAD8 || V6CLANG_RELOAD16`).
* Consumer 2 — `V6ClangSpillPatchedReload.cpp` (same opcodes).
* Related design:
  * `design/future_plans/O20_honest_store_load_defs.md` — same class of
    fix for HL clobber on `STORE8_P` / `LOAD8_P`.
  * `design/future_plans/O17_redundant_flag_elimination.md` — direct
    beneficiary.
  * `design/future_plans/O42_liveness_aware_expansion.md` — unaffected
    consumer.
