# O67. i8 Rotate ISel via RLC/RRC

*Identified from analysis of `temp/rot_check.c` codegen at `-O2`.*
*Companion plan: [../plan_O67_i8_rotate_isel_via_rlc_rrc.md](../plan_O67_i8_rotate_isel_via_rlc_rrc.md).*
*Distinct from [O57](O57_shift_rotate_chaining.md) (chain-reuse across multiple shifts) — this entry adds the missing 1-bit rotate ISel that O57 would otherwise build on.*

## Problem

The 8080 has four single-bit rotate instructions in `V6ClangInstrInfo.td`
(lines 401–409, 4cc / 1B each, accumulator-only):

```
def RLC : V6ClangInstImplied<0x07, ..., "RLC", []>;   // circular left
def RRC : V6ClangInstImplied<0x0F, ..., "RRC", []>;   // circular right
def RAL : V6ClangInstImplied<0x17, ..., "RAL", []>;   // through CY, left
def RAR : V6ClangInstImplied<0x1F, ..., "RAR", []>;   // through CY, right
```

All four ship with **empty pattern lists** — ISel never matches them.
And in `V6ClangISelLowering.cpp` (lines 77–78):

```cpp
setOperationAction(ISD::ROTL, MVT::i8, Expand);
setOperationAction(ISD::ROTR, MVT::i8, Expand);
```

So when DAGCombine recognises `(x<<n) | (x>>(8-n))` as `ISD::ROTL`,
the generic expander turns it back into `SHL i8 n | SRL i8 (8-n)`.
The i8 SHL constant path unrolls into `ADD A, A` (good); the i8 SRL
constant path zero-extends to i16 and runs the slow `V6CLANG_SRL16`
expansion — `MOV A,H; ORA A; RAR; MOV H,A; MOV A,L; RAR; MOV L,A`
(7 insns / ~28cc per shift step), then ORs the two halves.

### Measured today (`-O2`, simple 1-arg `unsigned char` functions)

| Function                                    | Insns | Bytes | Cycles |
|---------------------------------------------|-------|-------|--------|
| `rotl(x,1) = (x<<1) \| (x>>7)`              | 51    | ~58   | ~204   |
| `rotr(x,1) = (x>>1) \| (x<<7)`              | 23    | ~25   | ~92    |
| `rotl(x,3)`                                 | 47    | ~52   | ~188   |
| `rotr(x,3)`                                 | 23    | ~25   | ~92    |

### Desired output

```asm
rotl1: RLC ; RET                ; 1B / 4cc
rotr1: RRC ; RET                ; 1B / 4cc
rotl3: RLC ; RLC ; RLC ; RET    ; 3B / 12cc
rotr3: RRC ; RRC ; RRC ; RET    ; 3B / 12cc
```

A constant rotate by N collapses to `min(N, 8-N)` single-byte
`RLC`/`RRC` instructions (direction canonicalised). On the
`rotl(x,1)` worst case that is **~14× speedup and ~14× size
reduction**; equivalent gains across all constant amounts.

### Root cause

The hardware rotate is single-bit only, so the generic LegalizeOp
expander cannot synthesise it from the LLVM `ISD::ROTL` / `ISD::ROTR`
nodes (which model arbitrary-amount rotates). A target-specific
1-bit rotate node plus an unroll-by-N custom lowering is required.
The pattern mirrors how `LowerSHL` already unrolls i8 SHL constants
into a chain of `ADD A, A`.

## Pattern

### Custom-lower `ISD::ROTL` / `ISD::ROTR` for i8 only

```
(rotl i8 x, imm N)
  N ∈ {0}      → x
  N ∈ {1..4}   → chain of N × V6ClangISD::ROTL8(x)   → N × RLC
  N ∈ {5..7}   → chain of (8-N) × V6ClangISD::ROTR8  → (8-N) × RRC
                  (canonicalised: shorter direction)

(rotl i8 x, %amt) [variable]
  → promote to i16 via (x<<8 | x), shift right by ((8-amt)&7), trunc
  (synthesised in DAG; no new runtime libcall).
```

Symmetric for `ISD::ROTR`.

### New ISD nodes

```cpp
// V6ClangISelLowering.h, alongside V6ClangISD::SEXT
ROTL8,    // 1-bit accumulator rotate left  → RLC.
ROTR8,    // 1-bit accumulator rotate right → RRC.
```

### TableGen patterns

```
def SDT_V6Clangrot8 : SDTypeProfile<1, 1, [SDTCisVT<0, i8>, SDTCisVT<1, i8>]>;
def V6Clangrotl8 : SDNode<"V6ClangISD::ROTL8", SDT_V6Clangrot8>;
def V6Clangrotr8 : SDNode<"V6ClangISD::ROTR8", SDT_V6Clangrot8>;

def : Pat<(V6Clangrotl8 Acc:$src), (RLC Acc:$src)>;
def : Pat<(V6Clangrotr8 Acc:$src), (RRC Acc:$src)>;
```

The `$dst = $src` tied constraint already on `RLC`/`RRC` handles the
in-place semantics; SelectionDAG inserts `COPY_TO_REGCLASS` to A as
needed, identical to the existing accumulator-only paths used by
`LowerSHL` and `V6ClangISD::SEXT`.

### Why RLC/RRC and not RAL/RAR

`RLC`/`RRC` are circular and don't depend on the previous carry flag,
so a chain of them is well-defined regardless of intervening
flag-clobbering code. `RAL`/`RAR` rotate *through* CY and would
require carry preservation across the chain — only useful for
multi-byte shifts (out of scope; tracked as a future shift-expansion
follow-up that builds on the same `ROTL8`/`ROTR8` precedent).

### Direction canonicalisation

For `rotl x, N`:
- `N == 0`: identity, no instruction.
- `1 ≤ N ≤ 4`: emit N × `V6ClangISD::ROTL8` (shorter or tied with right).
- `5 ≤ N ≤ 7`: emit `(8-N)` × `V6ClangISD::ROTR8` (shorter).

The N=4 tie keeps the requested direction (4×RLC ≡ 4×RRC, no
measurable difference). Symmetric for ROTR.

### Correctness

| Op       | Bit semantics                                   | Carry side-effect |
|----------|-------------------------------------------------|-------------------|
| `RLC`    | `A' = (A<<1) \| (A>>7)`                          | CY = old bit 7    |
| `RRC`    | `A' = (A>>1) \| (A<<7)`                          | CY = old bit 0    |

Both match the i8 ROTL/ROTR semantics exactly; CY is overwritten by
each rotate but no V6CLANG peephole / flag-tracking pass assumes a clean
CY across rotates (`ZeroTestOpt`, `RedundantFlagElim` operate on Z
produced by ALU/ORA paths). Pattern is safe.

## Implementation

### Approach: ISD nodes + Custom lowering + TableGen patterns

Three coordinated edits, all confined to the V6CLANG target:

1. **`V6ClangISelLowering.h`**: add `ROTL8` / `ROTR8` to the `V6ClangISD` enum.
2. **`V6ClangISelLowering.cpp`**:
   - Switch `setOperationAction(ISD::ROTL/ROTR, MVT::i8, ...)` from
     `Expand` to `Custom`.
   - Add `LowerROTL` / `LowerROTR` (mirror `LowerSHL` skeleton).
   - Wire dispatch in `LowerOperation` switch and `getTargetNodeName`.
3. **`V6ClangInstrInfo.td`**: add the SDTypeProfile, two SDNode defs, and
   two `Pat<>` matchers next to the existing rotate instruction defs.

Total: ~60 LOC (40 in `V6ClangISelLowering.cpp`, 5 in the header, 6 in
TableGen).

### Pass ordering

None — this is an ISel-time change. Runs unconditionally at every
optimisation level; no CLI flag.

## Complexity & Risk

- **Complexity:** Low (~60 lines across three files). The hardest
  part is the variable-amount fallback synthesis, which is rarely
  exercised in real C code.
- **Risk:** Very Low. The current Expand path is strictly worse;
  there is no debug scenario where preserving it is useful. The
  custom lowering is gated by `getValueType() == MVT::i8`, so i16
  rotates (already absent from V6CLANG) are unaffected.
- **Dependencies:** None. Composes with O27/O17/O38 (independent
  flag-tracking work) and O13 (LoadImmCombine — not relevant here).

## Relationship to Other Plans

- **[O57 — Shift/Rotate Chaining](O57_shift_rotate_chaining.md)**:
  O57 reuses partial shift results across multiple shift expressions
  on the same base. It assumes the underlying single-shift codegen
  is already efficient. O67 makes that assumption true for the
  rotate path; O57 can then chain `RLC`/`RRC` sequences.
- **[O62 — Efficient i16 Shift Expansion (constant amount)](O62_efficient_shift_expansion.md)**
  (✅ landed): handles i16 SHL/SRL/SRA by 8/16. Independent — i8
  rotates do not flow through i16 SHL16.
- **Future O68 (i8 SRL/SRA constant-shift via RAR chain)**: the
  same lowering style would replace the i16-promotion blowup for
  `SRL i8 const`. Out of scope here but unblocked by introducing
  the `ROTR8` precedent.

## Expected Savings

| Pattern         | Before (B / cc) | After (B / cc)                        | Δ              |
|-----------------|-----------------|---------------------------------------|----------------|
| `rotl x, 1`     | ~58 / ~204      | 1 / 4                                 | −57B / −200cc  |
| `rotr x, 1`     | ~25 / ~92       | 1 / 4                                 | −24B /  −88cc  |
| `rotl x, 3`     | ~52 / ~188      | 3 / 12                                | −49B / −176cc  |
| `rotl x, 7`     | ~52 / ~188      | 1 / 4 (canonicalised to RRC)          | −51B / −184cc  |

**Frequency:** Low across the current C benchmark suite (none of
`bsort` / `sieve` / `fib_crc` rotate). High-impact for any user code
that does CRC tables, byte permutations, or hashing primitives —
any of which currently regress to dozens of i16-promoted instructions
per rotate.
