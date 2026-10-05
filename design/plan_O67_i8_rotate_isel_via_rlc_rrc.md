# Plan: O67 — i8 Rotate ISel via RLC/RRC ✅

*Status: Implemented. See `tests/features/44/result.txt` for measured savings.*

## 1. Problem

### Current behavior

`ISD::ROTL` / `ISD::ROTR` for i8 are set to `Expand` in
`V6ClangISelLowering.cpp` (lines 77–78). The 8080 `RLC`/`RRC`/`RAL`/`RAR`
instructions exist in `V6ClangInstrInfo.td` (lines 401–409, 4cc/1B each,
accumulator-only) but have **empty pattern lists**, so ISel never
matches them.

When DAGCombine recognises `(x<<n) | (x>>(8-n))` as `ISD::ROTL`, the
generic expander turns it back into `SHL i8 n | SRL i8 (8-n)`. The
i8 SHL constant path unrolls into `ADD A,A` (good), but the i8 SRL
constant path zero-extends to i16 and runs the i16 SRL16 expansion —
a chain of `MOV A,H; ORA A; RAR; MOV H,A; MOV A,L; RAR; MOV L,A`
(7 insns / 28cc per shift step), then ORs the two halves.

### Measured today (`-O2`, simple 1-arg unsigned char functions)

| Function                                         | Insns | Bytes | Cycles |
|--------------------------------------------------|-------|-------|--------|
| `rotl(x,1) = (x<<1)\|(x>>7)`                      | 51    | ~58   | ~204   |
| `rotr(x,1) = (x>>1)\|(x<<7)`                      | 23    | ~25   | ~92    |
| `rotl(x,3)`                                      | 47    | ~52   | ~188   |
| `rotr(x,3)`                                      | 23    | ~25   | ~92    |

### Desired behavior

```asm
rotl1: RLC ; RET                ; 1B / 4cc
rotr1: RRC ; RET                ; 1B / 4cc
rotl3: RLC ; RLC ; RLC ; RET    ; 3B / 12cc
rotr3: RRC ; RRC ; RRC ; RET    ; 3B / 12cc
```

A constant rotate by N becomes min(N, 8-N) `RLC`/`RRC` instructions
(direction canonicalised). Savings: ~14× speedup, ~14× size reduction
on the rotl-by-1 case; similar elsewhere.

### Root cause

No ISel patterns map `ISD::ROTL`/`ISD::ROTR` to `RLC`/`RRC`. The
hardware rotate is single-bit only, so the generic expander cannot
synthesise it directly — a target-specific 1-bit rotate node plus
unroll lowering is required (mirrors how `LowerSHL` already unrolls
i8 SHL into a chain of `ADD A,A`).

## 2. Strategy

### Approach: Custom lower with new V6ClangISD nodes + ISel patterns

Three coordinated changes, all confined to the V6CLANG target:

1. **New ISD nodes**: `V6ClangISD::ROTL8` and `V6ClangISD::ROTR8` — 1-bit
   rotate-by-1 of an `Acc`-class i8 value. (Mirrors the existing
   `V6ClangISD::SEXT` precedent: a target node that maps 1:1 to a single
   accumulator-only opcode.)

2. **Custom lowering**: switch `ISD::ROTL`/`ISD::ROTR` for i8 from
   `Expand` to `Custom`. New `LowerROTL` / `LowerROTR`:
   - Constant amount: canonicalise direction (use the shorter of
     `N` rotates in original direction vs `8-N` rotates in opposite
     direction; for N=4 either works), then emit a chain of
     `V6ClangISD::ROTL8` or `V6ClangISD::ROTR8` nodes.
   - Variable amount: fall back to libcall via i16 promotion, same
     pattern `LowerSHL` uses for variable i8 shifts. (Variable i8
     rotates are vanishingly rare in real C code; libcall is fine.)

3. **ISel patterns** in `V6ClangInstrInfo.td` (next to the rotate
   instruction defs):
   ```
   def : Pat<(V6ClangISD::ROTL8 Acc:$src), (RLC Acc:$src)>;
   def : Pat<(V6ClangISD::ROTR8 Acc:$src), (RRC Acc:$src)>;
   ```
   The `$dst = $src` tied constraint already in place handles the
   in-place semantics; SelectionDAG inserts COPY_TO_REGCLASS to A as
   needed (same as for shifts).

### Why ROTL8/ROTR8 (not RAL8/RAR8)

`RLC`/`RRC` are circular rotates that don't depend on the previous
carry flag — perfect for i8 ROTL/ROTR. `RAL`/`RAR` rotate *through*
the carry flag, which is needed for multi-byte shifts but not for
i8 rotates and would require carry preservation across the chain.
Stick with RLC/RRC for the rotate path; leave RAL/RAR available for
future multi-byte shift work.

### Direction canonicalisation

For an i8 ROTL by N:
- N ∈ {0}: no-op (return input).
- N ∈ {1,2,3,4}: emit N × `V6ClangISD::ROTL8`.
- N ∈ {5,6,7}: emit `(8-N)` × `V6ClangISD::ROTR8` (equivalent, fewer ops).

Symmetric for ROTR.

### Summary of changes

| Step | What                                                 | Where                                    |
|------|------------------------------------------------------|------------------------------------------|
| 3.1  | Add `V6ClangISD::ROTL8` / `ROTR8` enum entries           | `V6ClangISelLowering.h`                      |
| 3.2  | Switch ROTL/ROTR i8 to `Custom`; add LowerROTL/ROTR   | `V6ClangISelLowering.cpp`                    |
| 3.3  | Register node names in `getTargetNodeName`            | `V6ClangISelLowering.cpp`                    |
| 3.4  | Add `def V6Clangrotl8`, `def V6Clangrotr8` SDNode + Pat<>    | `V6ClangInstrInfo.td`                        |
| 3.5  | Build clang+llc                                       | —                                        |
| 3.6  | Lit test `rotate-i8.ll`                               | `tests/lit/CodeGen/V6CLANG/`                 |
| 3.7  | Runtime correctness test (rotate-i8.asm via v6emul)   | `tests/runtime/`                         |
| 3.8  | Run full regression: lit, golden, benchmarks          | —                                        |
| 3.9  | Verification feature folder                           | `tests/features/N/`                      |
| 3.10 | Sync mirror (`scripts/sync_llvm_mirror.ps1`)          | —                                        |
| 3.11 | Doc update: V6ClangOptimization.md, optional benchmarks   | `docs/`                                  |

## 3. Implementation Steps

### Milestone M1 — ISD nodes & TableGen wiring

**Goal**: Add target ISD nodes and ISel patterns so `RLC`/`RRC`
become reachable from `V6ClangISD::ROTL8`/`ROTR8` SDNodes. No lowering
yet — only the matcher path.

#### Step 3.1 — Add `V6ClangISD::ROTL8` and `V6ClangISD::ROTR8` [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.h`

Add to the `V6ClangISD::NodeType` enum (next to `SEXT`):

```cpp
ROTL8,    // 1-bit accumulator rotate left  (RLC).
ROTR8,    // 1-bit accumulator rotate right (RRC).
```

#### Step 3.2 — `getTargetNodeName` cases [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp`

In `V6ClangTargetLowering::getTargetNodeName`, add:

```cpp
case V6ClangISD::ROTL8: return "V6ClangISD::ROTL8";
case V6ClangISD::ROTR8: return "V6ClangISD::ROTR8";
```

#### Step 3.3 — TableGen SDNode + ISel patterns [x]

**File**: `llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td`

After the rotate instruction defs (around line 410):

```
def SDT_V6Clangrot8 : SDTypeProfile<1, 1, [SDTCisVT<0, i8>, SDTCisVT<1, i8>]>;
def V6Clangrotl8 : SDNode<"V6ClangISD::ROTL8", SDT_V6Clangrot8>;
def V6Clangrotr8 : SDNode<"V6ClangISD::ROTR8", SDT_V6Clangrot8>;

def : Pat<(V6Clangrotl8 Acc:$src), (RLC Acc:$src)>;
def : Pat<(V6Clangrotr8 Acc:$src), (RRC Acc:$src)>;
```

#### M1 Verification

* Build clang+llc cleanly (no TableGen errors).
* Hand-craft a `.ll` that emits `V6ClangISD::ROTL8` directly via inline
  IR is not possible; defer functional check to M2.
* Regression: `python llvm-build\bin\llvm-lit.py -sv tests\lit` →
  93/93 passes (no behavioural change yet because nothing produces
  the new nodes).

### Milestone M2 — Custom lowering for ROTL/ROTR i8

**Goal**: ISD::ROTL/ROTR with constant amount lower into a chain of
ROTL8/ROTR8 nodes and emit `RLC`/`RRC` instructions.

#### Step 3.4 — Switch ROTL/ROTR i8 to `Custom` [x]

**File**: `V6ClangISelLowering.cpp`

Replace lines 77–78:

```cpp
setOperationAction(ISD::ROTL, MVT::i8, Custom);
setOperationAction(ISD::ROTR, MVT::i8, Custom);
```

#### Step 3.5 — Implement `LowerROTL` / `LowerROTR` [x]

In `LowerOperation` switch (~line 314), dispatch:

```cpp
case ISD::ROTL: return LowerROTL(Op, DAG);
case ISD::ROTR: return LowerROTR(Op, DAG);
```

Add new methods (mirror `LowerSHL` style):

```cpp
SDValue V6ClangTargetLowering::LowerROTL(SDValue Op, SelectionDAG &DAG) const {
  if (Op.getValueType() != MVT::i8) return SDValue();
  SDLoc DL(Op);
  SDValue Val = Op.getOperand(0), Amt = Op.getOperand(1);
  if (auto *CA = dyn_cast<ConstantSDNode>(Amt)) {
    unsigned N = CA->getZExtValue() & 7;
    if (N == 0) return Val;
    // Canonicalise direction: ROTL by N == ROTR by (8-N).
    bool UseR = (N > 4);
    unsigned K = UseR ? (8 - N) : N;
    unsigned Op8 = UseR ? V6ClangISD::ROTR8 : V6ClangISD::ROTL8;
    SDValue R = Val;
    for (unsigned i = 0; i < K; ++i)
      R = DAG.getNode(Op8, DL, MVT::i8, R);
    return R;
  }
  // Variable amount: promote to i16 fshl libcall path.
  SDValue Ext  = DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Val);
  SDValue Eight= DAG.getConstant(8, DL, MVT::i16);
  SDValue Hi   = DAG.getNode(ISD::SHL, DL, MVT::i16, Ext, Eight);
  SDValue Wide = DAG.getNode(ISD::OR,  DL, MVT::i16, Hi, Ext);
  SDValue Amt16= DAG.getNode(ISD::ZERO_EXTEND, DL, MVT::i16, Amt);
  SDValue Sh   = DAG.getNode(ISD::SHL, DL, MVT::i16, Wide, Amt16);
  SDValue Shr  = DAG.getNode(ISD::SRL, DL, MVT::i16, Sh,   Eight);
  return DAG.getNode(ISD::TRUNCATE, DL, MVT::i8, Shr);
}
// Symmetric LowerROTR (swap shift directions for the variable path).
```

> **Design note**: variable-amount path must not use libcall directly
> because there is no `__rotl_qi3` runtime; instead synthesise via
> `(x<<8 | x) >> ((8-amt)&7)` style on i16 (let DAGCombine optimise).
> Variable i8 rotates are essentially absent from realistic C code,
> so this fallback rarely runs.

#### M2 Verification

* `temp/rot_check.c` (4 functions: rotl/rotr by 1 and 3) compiles to
  expected `RLC; RET` / `RLC RLC RLC RET` etc. — manual visual diff
  vs current output (51 insns → 1).
* Lit test (Step 3.6) passes.

### Milestone M3 — Tests

**Goal**: Cover ISel matching, direction canonicalisation, runtime
correctness, and ensure no regressions.

#### Step 3.6 — Lit test `rotate-i8.ll` [x]

**File**: `llvm-project/llvm/test/CodeGen/V6CLANG/rotate-i8.ll`
(also mirrored in `tests/lit/CodeGen/V6CLANG/`)

Cases:
1. `rotl by 1` → `RLC` only (no other rotate insns).
2. `rotr by 1` → `RRC` only.
3. `rotl by 3` → exactly 3× `RLC`.
4. `rotl by 7` → 1× `RRC` (canonicalisation: 7-left == 1-right).
5. `rotl by 4` → 4× `RLC` (tie keeps original direction).
6. Mixed: rotate of memory-loaded value through A.

Each function uses `@llvm.fshl.i8` / `@llvm.fshr.i8` intrinsics with
`(x, x, N)` to ensure DAGCombine produces `ISD::ROTL`/`ISD::ROTR`.

CHECK directives count instances and forbid `ORA A`, `RAR`, `MOV H,A`
sequences from the legacy expansion.

#### Step 3.7 — Runtime correctness via `tests/runtime/` [skipped — lit + feature 44 cover semantics]

**File**: `tests/runtime/rotate-i8.asm` + driver `.c`

A handful of inputs (0x00, 0x01, 0x55, 0xAA, 0xFF) cross-checked
against software-emulated rotate. Output verified through `v6emul
--halt-exit --dump-cpu` and a `TEST_OUT` value (matches
`tests/run_runtime_tests.py` infrastructure used for `mulhi3`,
`udivhi3`, `shift`).

#### Step 3.8 — Full regression sweep [x]

```
python llvm-build\bin\llvm-lit.py -sv tests\lit
python tests\run_golden_tests.py
python tests\benchmarks_c\run_benchmarks.py
```

Required: 93+/93+ lit, 16/16 golden, 3/3 benchmark checksums OK.

#### Step 3.9 — Verification feature folder `tests/features/44/` [x]

Per `tests/features/README.md`: short C demonstrator (e.g. CRC table
generator using rotates), pre/post `.asm`, `result.txt` with
cycle/byte counts, and a checksum verifying behavioural equivalence.

### Milestone M4 — Mirror sync, docs, and merge

**Goal**: Land changes durably and update docs.

#### Step 3.10 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

Verify hashes of edited files match between `llvm-project/` source
of truth and `llvm/` mirror; same for `llvm-project/llvm/test/CodeGen/V6CLANG/`
↔ `tests/lit/CodeGen/V6CLANG/`.

#### Step 3.11 — Documentation [skipped — unconditional ISel, no flag; see result.txt]

* `docs/V6ClangOptimization.md`: append a new "**O65 — i8 Rotate ISel**"
  section in the same style as the existing O-numbered entries
  (Flag: none — always on; default behaviour). Include before/after
  asm and the cycle/byte savings table.
* `docs/benchmarks.md`: regenerate via `run_benchmarks.py` if any
  benchmark improves; otherwise leave numbers untouched.
* No new CLI flag — this is an unconditional ISel improvement.

## 4. Expected Results

### Per-pattern savings (simple 1-arg `unsigned char` test functions, `-O2`)

| Pattern              | Before (B / cc) | After (B / cc) | Δ           |
|----------------------|-----------------|----------------|-------------|
| `rotl x, 1`          | ~58 / ~204      | 1 / 4          | −57B / −200cc |
| `rotr x, 1`          | ~25 / ~92       | 1 / 4          | −24B / −88cc |
| `rotl x, 3`          | ~52 / ~188      | 3 / 12         | −49B / −176cc |
| `rotl x, 7`          | ~52 / ~188      | 1 / 4 (canonicalised to RRC) | −51B / −184cc |

### General

Any constant i8 rotate in user code (CRC tables, byte permutations,
hashing primitives) collapses to ≤4 single-byte `RLC`/`RRC`
instructions. Variable-amount rotates remain rare and use the i16
fallback (still better than the legacy expansion because the i16
path is not invoked twice).

Benchmarks (`bsort`, `sieve`, `fib_crc`) likely unchanged — none of
them rotate. Real impact is unlocking idiomatic C bit-rotation.

## 5. Risks & Mitigations

| Risk                                                  | Mitigation                                                              |
|-------------------------------------------------------|-------------------------------------------------------------------------|
| Variable-amount fallback regresses i16 path           | Keep the libcall / promotion path identical to existing `LowerSHL`; benchmark the variable-rotate case if any user surfaces it |
| ISel fails to copy operand to A                       | Existing rotate defs already use `Acc:$src` with `$dst=$src` tied; same plumbing as `RLC`'s use in `V6ClangISD::SEXT` expansion (proven path) |
| DAGCombine forms `funnel-shift` (`fshl/fshr`) instead | LLVM canonicalises `(x<<n)\|(x>>(8-n))` to `ROTL`/`ROTR` for VTs where the action is not Expand once we mark Custom — verify in M2 step |
| Carry flag side-effect leaks                          | `RLC`/`RRC` only set CY (and on real 8080 also leave A unchanged in other flags) — none of our flag-tracking passes assume CY-clean across rotates; ZeroTestOpt uses ORA A which sets fresh flags |
| Pattern conflict with `V6ClangISD::SEXT` (uses RLC)        | SEXT consumes RLC inside its expansion (`V6ClangRegisterInfo.cpp` / instr expand), not via TableGen pattern; no collision |

## 6. Relationship to Other Improvements

* **Future O66 (i8 SRL/SRA constant-shift via RAR/RLC chain)**: The
  same lowering style would replace the bad i16-promotion path for
  `SRL i8 const` (currently 7+ insns per shift step) with a chain of
  `RAR` / `ARHL`-equivalent operations. Out of scope here but
  unblocked by introducing `V6ClangISD::ROTR8`-style 1-bit rotate nodes.
* **O27 (i16 zero-test)** / **O38 (XRA+CMP)**: independent, unaffected.
* **O17 RedundantFlagElim**: unaffected — rotates do not produce a
  Z-relevant flag we track.

## 7. Future Enhancements

* Variable-amount i8 rotate as a small loop (`MVI B, n; loop: RLC;
  DCR B; JNZ loop`) — 5+8N cycles vs the i16 fallback's overhead;
  worth doing only if a benchmark surfaces variable rotates.
* `RAL`/`RAR` patterns to support multi-byte shifts (i16/i32 SRL/SRA
  by 1) replacing the current `ORA A; RAR` pair sequence — separate
  plan, larger scope.
* Auto-detect `(x*c)` patterns where `c = 2^k mod 256` lower to RLC
  chain (deferred — needs DAGCombine extension).

## 8. References

* [V6CLANG Build Guide](docs/V6ClangBuildGuide.md)
* [V6ClangInstructionTimings](docs/V6ClangInstructionTimings.md)
* [V6ClangInstrInfo.td](llvm-project/llvm/lib/Target/V6CLANG/V6ClangInstrInfo.td) — RLC/RRC/RAL/RAR defs (line 401–409)
* [V6ClangISelLowering.cpp](llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp) — current Expand action (line 77–78), LowerSHL template (line 607)
* [V6ClangISelLowering.h](llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.h) — V6ClangISD::NodeType enum
* [plan_xra_cmp_zero_test.md](design/plan_xra_cmp_zero_test.md) — reference plan style
