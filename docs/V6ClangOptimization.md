# V6CLANG Optimization Passes

The V6CLANG backend includes 11 custom optimization passes targeting the specific constraints of the Intel 8080 architecture. Each pass is individually toggleable via a command-line flag.

In addition to these custom passes, the target now enables LLVM's built-in
interprocedural register allocation (IPRA) by default at optimized levels.
IPRA is not a V6CLANG-specific pass, but it materially reduces call-site spill /
reload traffic by narrowing preserved-register masks for direct calls when the
callee's real register usage is known.

## LSR Strategy (`-v6clang-lsr-strategy`)

`V6ClangTTIImpl::isLSRCostLess` ranks LSR formula cost vectors with one of two
lexicographic orderings over the generic `LSRCost` fields. Both orderings
keep all other fields (`AddRecCost`, `NumIVMuls`, `NumBaseAdds`,
`ImmCost`, `SetupCost`, `ScaleCost`) in their LLVM-default positions; only
the `NumRegs`/`Insns` priority swaps.

* `regs-first` — `NumRegs` then `Insns` (default). Minimises register
  pressure first, which on i8080's 3 GP pairs (`HL`, `DE`, `BC`) is
  usually the correct proxy for total post-RA cost: every IV beyond the
  third forces a spill slot plus an in-loop reload sequence
  (`LXI HL,slot` / `MOV r,M` / `INX HL` / ... or `LHLD slot`).
* `insns-first` — `Insns` then `NumRegs` (Z80-style). Picks the formula
  with fewest pre-RA instructions; will accept +1 GP-pair pressure for
  one less in-loop ADD/INX or one less load fold.

**Flag.** `-v6clang-lsr-strategy={auto,insns-first,regs-first}`. `auto` is the
default and currently maps to `regs-first` unconditionally — neither the
optimisation level (`-O2` vs `-Os`) nor per-function attributes
(`optsize`, `minsize`, `hot`, `cold`) change the dispatch yet. The
captured `Function *` is reserved for that future use; see plan §7.

**Examples.**

```bash
# Default: auto = regs-first at every -O level.
clang -target i8080-unknown-v6clang -O2 file.c -S -o file.asm

# Opt in to insns-first for the whole TU (e.g. when the loop matches
# the bsort_two profile: >3 IVs, all touched every iteration).
clang -target i8080-unknown-v6clang -O2 file.c -S -o file.asm \
      -mllvm -v6clang-lsr-strategy=insns-first

# Force regs-first explicitly (bisection / pinning a known-good shape;
# byte-identical to -O2 default today, but immune to a future
# auto-dispatch change).
clang -target i8080-unknown-v6clang -O2 file.c -S -o file.asm \
      -mllvm -v6clang-lsr-strategy=regs-first

# Combine with -Os; insns-first overrides the size-mode default
# (which is also regs-first today).
clang -target i8080-unknown-v6clang -Os file.c -S -o file.asm \
      -mllvm -v6clang-lsr-strategy=insns-first
```

**Per-function selection (not yet supported).** `__attribute__((optsize))`
or `__attribute__((hot))` on individual functions does **not** currently
switch ordering — the flag is TU-global. If you need per-function
control today, split the loops across two compilation units. Plan §7
tracks the attribute-driven dispatch as a future enhancement.

**Empirical results.**

*Regression corpus A/B*
([tests/features/43/result.txt](../tests/features/43/result.txt)). All
42 feature tests rebuilt at `-O2` with each strategy and compared on
`.text` bytes:

| outcome                          | tests |
|----------------------------------|------:|
| `insns < regs` (insns-first wins) |     0 |
| `insns > regs` (insns-first regresses) | 3 |
| identical                        |    39 |

The three regressions: test 20 +235 B, test 29 +315 B, test 43 +53 B.
On test 43's `axpy3` kernel (4 stream pointers + counter) the inner
body grew 71 → 80 instructions (+12.7 %) under insns-first because LSR
picked formulas with one extra pointer IV and the post-RA reload
sequence is invisible to the `Insns` cost estimate. This is what set
the `auto = regs-first` default.

*Bubble-sort microbenchmark*
([tests/features/43/result_bsort.txt](../tests/features/43/result_bsort.txt)).
Counter-example showing where insns-first does help:

| function   | regs-first | insns-first | Δ      |
|------------|-----------:|------------:|-------:|
| `bsort` (2 ptrs) | 526 insn | 526 insn | 0 (byte-identical) |
| `bsort_two` (4 ptrs, all touched/iter) | 410 insn | 367 insn | **−43 (−10.5 %)** |

Both kernels nominally exceed the GP budget, but `bsort_two` touches
every stream every iteration, so insns-first's "one INX rp per stream"
schedule beats regs-first's pointer-fold-plus-recover schedule.
`axpy3` does not behave this way because its formulas only need one of
the streams reloaded per inner iteration.

**When to opt in.** Use `-mllvm -v6clang-lsr-strategy=insns-first` for
loops where (a) the IV count exceeds 3 GP pairs and (b) every IV is
touched on every iteration. Verify with the A/B procedure documented
in `result_bsort.txt` before committing to it. For everything else
the default (`regs-first`) is the safer choice.

## TTI Cost Hooks (`-v6clang-tti-cost-*`)

V6CLANG overrides four `TargetTransformInfo` hooks to feed the generic
LLVM IR optimizers (LSR, IndVarSimplify, LoopUnroll, SLP, …) numbers
that reflect i8080 reality instead of BasicTTI's "everything costs 1"
defaults. The hooks bias the optimizers toward i8 IVs and away from
i32 ops in hot loops.

| Hook                     | i1/i8 | i16 | i32 | What it influences                                  |
|--------------------------|------:|----:|----:|------------------------------------------------------|
| `getArithmeticInstrCost` |     1 |   6 |  20 | IV widening, SLP, LoopUnroll, IndVarSimplify        |
| `getMemoryOpCost`        |     2 |   4 |   8 | Load/store hoisting, IV-rewrite to memory pointer    |
| `getCmpSelInstrCost`     |     1 |   2 |   8 | Loop-exit IV choice, branch threading                |
| `getScalingFactorCost`   |  legal: 0/1; otherwise invalid | | | LSR addressing-mode legality |

**Master flag.** `-mllvm -v6clang-tti-cost-hooks=0` disables all four at once.
Falls back to BasicTTI defaults (mostly 1 for everything). Default ON.

**Per-hook flags** (all default ON, all `cl::Hidden`):

* `-v6clang-tti-cost-arith=0` — disable `getArithmeticInstrCost` override.
* `-v6clang-tti-cost-mem=0` — disable `getMemoryOpCost` override.
* `-v6clang-tti-cost-cmp=0` — disable `getCmpSelInstrCost` override.
* `-v6clang-tti-cost-scaling=0` — disable `getScalingFactorCost` override.

**Why opt-out exists.** The arith hook is the dominant lever — it drives
LSR/IndVarSimplify to keep i8 IVs and refuse to widen them to i16. On
benchmarks this is large-win/small-loss:

| Benchmark | hooks ON | hooks OFF | Δ      |
|-----------|---------:|----------:|-------:|
| bsort     | 21,372 cc| 39,084 cc | **−45%** |
| sieve     | 90,556 cc| 84,904 cc |   +6.7% |
| fib_crc   | 67,324 cc| 67,324 cc |    0%  |

Bisection (`-v6clang-tti-cost-arith=0` only) confirms both the bsort win
and the sieve loss come from the arithmetic hook alone — the mem,
cmp, and scaling hooks are inert on this benchmark set but kept for
correctness on i32 / non-trivial addressing.

**When to opt out.** If a workload has a hot i8 loop where:

* the i8 IV is decremented (`DCR A`-style), AND
* the same loop body uses A for a memory load / accumulator / I/O,

the IV-narrowing decision can force a stash/unstash through a second
register every iteration (sieve `count_set` pattern). Try
`-mllvm -v6clang-tti-cost-arith=0` for that translation unit; verify with
v6emul cycle counts before committing.

For most code, leave the defaults alone.

## Pass Pipeline Order

1. **IR-level** (in `addIRPasses()`): V6ClangLoopPointerInduction → V6ClangTypeNarrowing
2. **Post-register allocation** (in `addPostRegAlloc()`): V6ClangStaticStackAlloc
3. **Pre-register allocation** (in `addPreRegAlloc()`): V6ClangDeadPhiConst
4. **Pre-emit** (in `addPreEmitPass()`): V6ClangAccumulatorPlanning → V6ClangLoadImmCombine → V6ClangPeephole → V6ClangLoadStoreOpt → V6ClangXchgOpt → V6ClangBranchOpt → V6ClangZeroTestOpt → V6ClangRegValueForwarding → V6ClangRedundantFlagElim → V6ClangSPTrickOpt

## Pass Descriptions

### V6ClangZeroTestOpt

**Purpose:** Replace `CPI 0` (compare immediate 0, 8cc) with `ORA A` (OR accumulator with itself, 4cc) for zero-testing. Both set the Zero flag identically, but `ORA A` is 1 byte / 4 cycles cheaper.

**Pattern:**
```
Before: CPI 0       ; 2 bytes, 8cc
After:  ORA A       ; 1 byte, 4cc
```

**Toggle:** `-v6clang-disable-zero-test-opt`

**Impact:** Saves 4 cycles and 1 byte per zero comparison. Common in loop termination and null checks.

---

### V6ClangXchgOpt

**Purpose:** Detect consecutive MOV instructions that swap DE and HL byte-by-byte, and replace them with the single `XCHG` instruction.

**Pattern:**
```
Before: MOV D, H    ; 8cc
        MOV E, L    ; 8cc  (total: 16cc, 2 bytes)
After:  XCHG        ; 4cc, 1 byte
```

**Toggle:** `-v6clang-disable-xchg-opt`

**Impact:** Saves 12 cycles and 1 byte per DE↔HL swap. Frequent in 16-bit operations where values move between register pairs.

---

### V6ClangPeephole

**Purpose:** General peephole optimizations including:
- **Self-MOV elimination:** Remove `MOV X, X` (no-op moves).
- **Redundant consecutive MOV elimination:** Remove `MOV A, B; MOV A, B` sequences.
- **Strength reduction:** Replace `SHL 1` patterns with `ADD A, A` (same operation, already native).

**Toggle:** `-v6clang-disable-peephole`

**Impact:** Eliminates dead code generated by pseudo-instruction expansion and register allocation.

---

### V6ClangLoadImmCombine

**Purpose:** Replace redundant `MVI r, imm` (move-immediate) instructions when the value is already available in another register or can be derived from the current register value.

**Patterns:**
- If another register already holds the same immediate → replace with `MOV r, r'` (1 byte saved)
- If the target register holds `imm - 1` → replace with `INR r` (1 byte saved)
- If the target register holds `imm + 1` → replace with `DCR r` (1 byte saved)

```
Before: MVI B, 5        ; 2 bytes
        ...              ; (A already = 5)
        MVI C, 5         ; 2 bytes (redundant)
After:  MVI B, 5         ; 2 bytes
        ...              ; (A already = 5)
        MOV C, A         ; 1 byte
```

**Toggle:** `-v6clang-disable-load-imm-combine`

**Impact:** Saves 1 byte per replaced MVI. Per-basic-block analysis tracks all 7 general-purpose registers (A, B, C, D, E, H, L). Prefers non-A source registers to avoid accumulator contention.

---

### V6ClangAccumulatorPlanning

**Purpose:** *(Superseded by V6ClangRegValueForwarding / O92.)* Historically removed
redundant accumulator moves within a single basic block. Its
redundant-move-elimination logic was folded into the unified cross-BB
value-forwarding pass; the pass is now a no-op placeholder kept in the pipeline.

**Toggle:** `-v6clang-disable-acc-planning`

---

### V6ClangRegValueForwarding (O92)

**Purpose:** Unified cross-basic-block physical-register value forwarding.
A post-RA dataflow pass that tracks, per register, which register or constant
value it currently holds, and propagates that lattice across every CFG edge —
including loop back-edges — to a fixpoint. Any `MOV r, s` or `MVI r, imm` whose
result the lattice already proves is live in `r` on entry is erased. This
subsumes the older intra-block-only removers in `V6ClangAccumulatorPlanning`
(A-specific) and `V6ClangPeephole` (adjacent duplicate MOVs) with a single
register-agnostic, cross-block analysis.

**Pattern:**
```
Before: MOV D, A       ; A == D established
        ORA A          ; value-preserving (only sets FLAGS)
        ...
  loop: MOV M, E
        INR E
        MOV A, D       ; redundant: A already holds D across the back-edge
        CMP E
        JNZ loop
After:  (the in-loop MOV A, D is removed)
```

**Soundness:** `ORA A` / `ANA A` are treated as non-clobbering (they only set
FLAGS, so the `A == r` equality survives). A `MOV A, r` that is a genuine reload
(the source was clobbered in the loop body) is preserved. O61 patched
immediates are never folded. Register aliasing (e.g. writing `H` kills `HL`) is
handled via TRI alias queries.

**Toggle:** `-v6clang-disable-reg-value-forwarding`

**Impact:** Removes per-iteration register reloads that no local pass can prove
redundant. fannkuch (-O2) improved from 28,798,404 to 28,748,820 cycles
(−49,584 cc, −3 bytes).

---

### V6ClangLoadStoreOpt

**Purpose:** Merge adjacent memory accesses that use consecutive addresses. When two loads/stores target addresses that differ by 1, replace the second `LXI HL, addr` with `INX HL`.

**Pattern:**
```
Before: LXI H, addr     ; 12cc
        MOV A, M         ; 8cc
        LXI H, addr+1   ; 12cc  (redundant — HL already near)
        MOV B, M         ; 8cc
After:  LXI H, addr     ; 12cc
        MOV A, M         ; 8cc
        INX H            ; 8cc   (saves 4cc + 2 bytes)
        MOV B, M         ; 8cc
```

Also eliminates dead `LXI HL` instructions whose result is overwritten before use.

**Toggle:** `-v6clang-disable-loadstore-opt`

**Impact:** Reduces code size and cycle count for struct field access and array operations.

---

### V6ClangBranchOpt

**Purpose:** Optimize control flow:
- **Branch threading:** Thread conditional/unconditional branches through JMP-only blocks, redirecting them directly to the final target. Also handles tail-call (`V6CLANG_TAILJMP`) targets.
- **Fallthrough elimination:** Remove `JMP` to the immediately following block.
- **Branch inversion:** When a conditional branch jumps over an unconditional jump (including `V6CLANG_TAILJMP`), invert the condition and eliminate the jump.
- **Dead block removal:** Remove basic blocks with no predecessors.
- **Conditional return folding:** Fold conditional branches to return blocks into conditional return instructions.

**Pattern (branch threading):**
```
Before: JZ  .LBB1       ; conditional branch to JMP-only block
        ...
.LBB1:  JMP bar         ; JMP-only block
After:  JZ  bar         ; conditional branch directly to final target
```

**Pattern (branch inversion):**
```
Before: JZ  skip       ; if zero, jump over
        JMP target      ; unconditional jump
skip:   ...
After:  JNZ target      ; inverted: if not zero, jump to target
        ...              ; fall through
```

**Toggle:** `-v6clang-disable-branch-opt`

**Impact:** Eliminates 3-byte/12cc unconditional jumps. Branch threading saves 3 bytes per threaded JMP-only block. Particularly effective after other passes create new fallthrough opportunities.

---

### V6ClangRedundantFlagElim

**Purpose:** Remove redundant `ORA A` / `ANA A` instructions when the Z flag already reflects the accumulator's value from a preceding ALU instruction. Both `ORA A` and `ANA A` are identity operations used solely to set flags.

**Pattern:**
```
Before: ANI 0x0F        ; A = A & 0x0F, sets Z flag
        ORA A           ; redundant — Z already reflects A
        JZ  target      ; branch on zero
After:  ANI 0x0F        ; A = A & 0x0F, sets Z flag
        JZ  target      ; branch on zero (ORA A eliminated)
```

**Toggle:** `-v6clang-disable-redundant-flag-elim`

**Impact:** Saves 1 byte and 4 cycles per eliminated `ORA A` / `ANA A`. Common after instruction selection inserts flag-setting instructions before conditional branches.

---

## Debug Tools

### Disable SHLD/LHLD → PUSH/POP Fold (O43)

**Flag:** `-mllvm -v6clang-disable-shld-lhld-fold` (default: off / fold enabled)

**Purpose:** Disables the O43 peephole in `V6ClangPeephole` that rewrites
adjacent `SHLD addr` / `LHLD addr` pairs into `PUSH H` / `POP H`. Intended
for:

1. **Debugging / A-B testing O43.** Compare codegen with and without the
   fold to attribute size/cycle deltas or isolate a suspected miscompile.
2. **Measuring future spill/reload research.** Experiments like O61 (spill
   into the reload's immediate operand) operate on the same SHLD/LHLD
   pairs that O43 consumes; running O43 first hides the opportunity. Pass
   this flag during prototyping so the SHLD/LHLD pairs survive to the
   later stage.

**Usage:**
```bash
clang -target i8080-unknown-v6clang -O2 -S input.c -o output.s \
    -mllvm -v6clang-disable-shld-lhld-fold
```

**Scope:** Does not affect any other peephole. Leave disabled in
production builds — O43 saves 12cc + 4B per folded pair.

---

### O61 — Spill Into the Reload's Immediate Operand

**Flag:** `-mllvm -mv6clang-spill-patched-reload` (default: **on**); use
`-mllvm -mv6clang-no-spill-patched-reload` to disable.

**Purpose:** Enables the `V6ClangSpillPatchedReload` post-RA pass. Instead of
lowering a spill/reload pair to `SHLD slot` / `LHLD slot` (i16) or
`STA slot` / `LDA slot; MOV r, M` (i8), the pass rewrites the **reload**
to `LXI rp, 0` (i16) or `MVI r, 0` (i8) at a labelled site `.LLo61_N:`,
and rewrites the **spill** to store the live value directly into the
reload's immediate byte(s) — i.e. `SHLD .LLo61_N+1` / `STA .LLo61_N+1`
(self-modifying code).

**Preconditions:**
- Static stack allocation must be active for the function
  (`hasStaticStack()` — enabled by default, see `-mv6clang-no-static-stack`).
- The SHLD/LHLD → PUSH/POP fold (O43) consumes the same pairs; for
  prototyping or A/B measurements combine with
  `-mllvm -v6clang-disable-shld-lhld-fold`.

**Chooser (summary):** scores reloads by
`BlockFrequency × Δ(cycles)` and admits up to:
- K ≤ 2 patched reloads per single-source spill,
- K ≤ 1 patched reload per multi-source spill.
On the second patch of a single-source group the chooser excludes `A`
(i8, Δ = −8cc only) and `H`/`L` (they alias the `HL` pair used by the
unpatched classical reload fallback).

**Per-pattern savings (HL dead in the "before" path):**

| Width | Before                           | After        | Δ          |
|-------|----------------------------------|--------------|------------|
| i16   | `LHLD slot` = 16cc, 3B           | `LXI rp, 0` patched = 10cc, 3B | −6cc (HL dst), −12cc on `DAD` fold path |
| i8 → A | `LDA slot` = 13cc, 3B           | `MVI A, 0` patched = 7cc, 2B | −6cc, −1B |
| i8 → r8 | `LXI HL, slot` + `MOV r, M` = 17cc, 4B | `MVI r, 0` patched = 7cc, 2B | −10cc, −2B + BSS slot eliminated |

With HL live in the "before" path (classical reload wrapped in
`PUSH HL` / `POP HL`), the i8 non-A saving rises to −22cc / −4B.

**Usage:**
```bash
clang -target i8080-unknown-v6clang -O2 -S input.c -o output.s
```

The pass runs at every optimisation level by default. To opt out (for
example, when targeting a ROM-resident `.text` section that cannot be
patched at runtime), pass:
```bash
clang -target i8080-unknown-v6clang -O2 -S input.c -o output.s \
    -mllvm -mv6clang-no-spill-patched-reload
```

For clean demonstration of every patched site (no SHLD/LHLD pairs
getting folded away into `PUSH`/`POP`), combine with the O43 disable
flag:
```bash
clang -target i8080-unknown-v6clang -O2 -S input.c -o output.s \
    -mllvm -v6clang-disable-shld-lhld-fold
```

**Status:** Stages 1–5 complete (Stage 5 widens the i16 spill source
from HL-only to `{HL, DE, BC}`, unlocking DE/BC argument-routed spill
traffic). On by default since the optimisation has stabilised across
the C benchmark suite; the patched imm bytes live in `.text`, which
assumes code is RAM-resident and writable — true on Vector-06c but
not on ROM/EPROM targets, hence the `-mv6clang-no-spill-patched-reload`
opt-out. Test assets live under `tests/features/37/` (i8 scope),
`tests/features/39/` (Stage 5 DE/BC), and
`llvm/test/CodeGen/V6Clang/spill-patched-reload-*.ll`.

---

### Pseudo Expansion & Func Declaration Annotations

**Flag:** `-mv6clang-annotate-pseudos` (default: off)

**Purpose:** Two features in one flag:
1. **Function header comments** — emits a C-like declaration and parameter→register mapping at the start of each function.
2. **Pseudo expansion comments** — inserts `;--- PSEUDO_NAME ---` before each pseudo-instruction expansion.

Useful for understanding calling convention register assignments and debugging code generation.

**Usage:**
```bash
clang -target i8080-unknown-v6clang -O2 -S input.c -o output.s -mllvm -mv6clang-annotate-pseudos
llc -march=v6clang -O2 -mv6clang-annotate-pseudos < input.ll
```

Add `-fno-discard-value-names` to preserve original C parameter names (otherwise they appear as `arg0`, `arg1`, etc.).

**Example output:**
```asm
	;=== char multi_live(char x, char y, char z) ===
	;  x = A
	;  y = E
	;  z = C
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.multi_live+1
	;--- V6CLANG_RELOAD8 ---
	MOV	D, H
	LXI	HL, __v6clang_ss.multi_live
	MOV	L, M
	MOV	H, D
```

**Register assignment** (position-based, V6CLANG calling convention):
| Position | i8 | i16/ptr |
|----------|-----|--------|
| Arg 1    | A   | HL     |
| Arg 2    | E   | DE     |
| Arg 3    | C   | BC     |
| Arg 4+   | stack | stack |

**Scope:** Function headers via `emitFunctionBodyStart` (V6ClangAsmPrinter.cpp). Pseudo comments cover both `expandPostRAPseudo` (V6ClangInstrInfo.cpp) and `eliminateFrameIndex` (V6ClangRegisterInfo.cpp) expansions.

**Note:** When enabled, annotation comments inserted between real instructions may reduce some peephole optimization opportunities (adjacency-sensitive patterns like XCHG cancellation or consecutive load/store merging). Use only for debugging, not production builds.

---

### V6ClangSPTrickOpt

**Purpose:** Replace byte-by-byte memory copy/set sequences (≥6 bytes) with the SP-trick: temporarily repurpose SP as a high-speed sequential read pointer using `POP` (12cc per 2 bytes vs 8cc per byte for MOV).

**Pattern:**
```
Before: (6+ individual MOV M,r / MOV r,M sequences)
After:  DI              ; disable interrupts (SP is unsafe)
        LXI SP, src     ; point SP at source
        POP D           ; load 2 bytes
        POP H           ; load 2 bytes
        ...
        SHLD dst+N      ; store via SHLD
        ...
        LXI SP, saved   ; restore SP
        EI              ; re-enable interrupts
```

**Toggle:** `-v6clang-disable-sp-trick`

**Constraints:** Not used inside interrupt service routines (ISR). Always wrapped in DI/EI.

**Impact:** Major speedup for `memcpy`/`memset` of ≥6 bytes. Example: 64-byte copy drops from ~1024cc to ~400cc.

---

### V6ClangTypeNarrowing

**Purpose:** IR-level pass that narrows provably-bounded `i16` operations to `i8`. The 8080's native word is 8 bits; 16-bit operations expand to multi-instruction sequences. Narrowing saves significant code size and cycles.

**Patterns detected:**
- Loop induction variables with constant bounds fitting in 8 bits
- Values that are zero-extended from `i8` and only used in `i8`-width operations
- Truncated results where only the low byte is consumed

**Toggle:** `-v6clang-disable-type-narrowing`

**Impact:** Eliminates unnecessary 16-bit pseudo-instruction expansions. A loop counter bounded 0..255 narrows from a 6-instruction 16-bit compare to a single `CPI` instruction.

---

### V6ClangStaticStackAlloc

**Purpose:** Replace the dynamic stack frame of provably non-reentrant functions with a statically-allocated global memory region. On the 8080, SP-relative access requires expensive `LXI HL, offset; DAD SP` sequences (20+ cycles, 4+ bytes). Static allocation replaces these with direct `SHLD`/`LHLD`/`STA`/`LDA` instructions and eliminates the stack frame prologue/epilogue entirely.

**Eligibility criteria** (see [V6ClangStaticStackAlloc.md](V6ClangStaticStackAlloc.md) for full details):
1. Function has `norecurse` attribute (inferred by `PostOrderFunctionAttrs` at `-O2`)
2. Function does not have `__attribute__((interrupt))` (the `"interrupt"` function attribute)
3. Function is not reachable from any interrupt handler (module-wide BFS from all `"interrupt"` functions)
4. Function's address is not taken
5. Function has non-fixed frame objects (spill slots or locals)

**Allocation scheme:** Each eligible function gets its own BSS symbol (`__v6clang_ss.<funcname>`), sized to the function's stack frame. `eliminateFrameIndex` expands spill/reload pseudos to direct memory operations:

```
Before (SP-relative):
  PUSH HL             ; 16cc, 1B — save HL
  LXI  HL, offset     ; 12cc, 3B — compute stack address
  DAD  SP             ; 12cc, 1B
  MOV  M, E           ; 8cc,  1B — store low byte
  INX  HL             ; 8cc,  1B
  MOV  M, D           ; 8cc,  1B — store high byte
  POP  HL             ; 12cc, 1B — restore HL
  Total: 76cc, 9B

After (static, pair in HL):
  SHLD __v6clang_ss.func+N  ; 20cc, 3B
  Total: 20cc, 3B
```

**Toggle:** Enabled by default. Disable with `-mv6clang-no-static-stack`.

**Impact:** For spill-heavy functions, saves 32-56 cycles and 4-6 bytes per spill/reload operation. Eliminates prologue (PUSH + LXI + DAD SP + SPHL) and epilogue (LXI + DAD SP + SPHL + restore) entirely. In the feature test, `heavy_spill` improved by 404cc (53%) and 53B (52%).
