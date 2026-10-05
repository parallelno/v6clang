# O80 — i8 Zero-Test Compare via INR/DCR (A-Preserving Pseudo)

The i8 "compare against zero" idiom currently lowers, during ISel, directly to
two real machine instructions:

```asm
MOV  A, src    ; 1B,  8cc   (WriteMOV8 — Vector-06c MOV r,r = 8cc)
ORA  A         ; 1B,  4cc   (WriteALU4 — sets Z/S/P from src; clobbers A; clears CY)
```

Total: 2B / 12cc, **destroys A**.

When `A` is live across the compare (a very common shape — A is the most
popular accumulator and routinely holds a value used after the branch), the
register allocator has to rescue `A` by routing it through another GR8 or
through the stack. The typical resulting sequence (observed in
[tests/features/37/v6clang.s](tests/features/37/v6clang.s) line 76):

```asm
MOV  L, A      ; save A          (1B / 8cc)
MOV  A, C      ; zero-test idiom (1B / 8cc)
ORA  A         ;                 (1B / 4cc)
;--- V6CLANG_BRCOND ---
JZ   .LBB17_2
; %bb.1:
MOV  A, L      ; restore A       (1B / 8cc)
```

The save/restore around the test costs **2B / 16cc** on top of the test
itself, and burns a GR8 (`L` here) that may itself need to be spilled.

The `INR r; DCR r` pair leaves `r` unchanged, sets the same Z/S/P flag bits
from `r`'s pre-instruction value as `ORA A` does from `A`, and **does not
touch the accumulator**. This optimization turns the compare into an
A-preserving pseudo whose post-RA expansion picks the cheapest correct
sequence given the live-A and src-equals-A states.

## Problem

The current ISel lowering of `V6ClangISD::CMP %r8, 0` is a fixed `MOVrr A, src` +
`ORAr A` regardless of liveness. Three shapes exist in practice:

|#|shape                     |today's expansion                                 |siz/ccs|
|-|--------------------------|--------------------------------------------------|-------|
|1|`src = A` (any A-liveness)|`ORA A`                                           |1B/4cc |
|2|`src ≠ A`, A dead         |`MOV A,src; ORA A`                                |2B/12cc|
|3|`src ≠ A`, A live         |`MOV scratch,A; MOV A,src; ORA A; … MOV A,scratch`|4B/28cc|

(Per [docs/V6ClangInstructionTimings.md](docs/V6ClangInstructionTimings.md):
`MOV r,r` = 1B / 8cc `WriteMOV8`; `ORA r` = 1B / 4cc `WriteALU4`. Vector-06c
costs MOV r,r the same as MOV r,M, unlike the classic 8080.)

Shape 1 only emerges if ISel lucked into picking `src = A`; nothing in the
current pipeline tries to make that happen. Shape 3 is the painful one — it
shows up wherever a value held in A flows past a branch that tests an
unrelated i8 register, e.g. the very common `if (cond) f(a);` pattern.

`INR r; DCR r`:
- `INR r` = 1B / 8cc (`WriteALU8`).
- `DCR r` = 1B / 8cc (`WriteALU8`).
- Pair total: **2B / 16cc**.
- Sets `Z`, `S`, `P` from the post-DCR value of `r`, which equals the
  pre-INR value (the pair is byte-idempotent on `r`).
- **Does not modify `A`** and **does not modify carry** (`INR`/`DCR` are the
  rare i8080 ALU ops that preserve `CY`).

So when `A` is live, replacing the four-instruction shape 3 sequence (4B /
28cc) with a single `INR src; DCR src` pair (2B / 16cc) saves **2B and 12cc
per fire** and additionally relieves register pressure (no scratch GR8 burn,
which can transitively avoid spills in tight loops — see tests/features/43).

## Why `INR/DCR` is correct as a zero-test

The semantics of `V6ClangISD::CMP %r8, 0` is "set FLAGS from `%r8`":

| flag | `ORA A` value          | `INR r; DCR r` value     | match |
|------|------------------------|--------------------------|-------|
| Z    | A == 0                 | r == 0                   | ✓ (after MOV A,r) |
| S    | bit7(A)                | bit7(r)                  | ✓     |
| P    | parity(A)              | parity(r)                | ✓     |
| AC   | 0 (ORA clears it)      | flag from `DCR` of `r+1` | ✗ (different value) |
| CY   | 0 (ORA clears it)      | unchanged                | ✗ (different value) |

The CMP-against-zero callers we care about are i8 conditional branches
emitted via `V6Clangbrcond` / `V6ClangCC::COND_Z` / `COND_NZ` / `COND_P` / `COND_M` /
`COND_PE` / `COND_PO`. None of these CCs reads `AC` or `CY`. Branching on
`COND_C` / `COND_NC` after a CMP-against-zero would be ill-formed (the
zero-test never produced carry under either lowering), so absence of carry
update is harmless.

A grep over the backend's pattern files confirms no zero-test-against-zero
consumer reads `AC` or `CY`. The replacement is therefore semantics-
equivalent over the actual consumer set.

## Proposed design

### 1. New pseudo `V6CLANG_CMP8_ZERO`

Mirror the existing `V6CLANG_CMP16_ZERO`:

```tablegen
// V6CLANG_CMP8_ZERO — Set FLAGS from i8 source against zero.
// Consumed by V6CLANG_BRCOND / V6CLANG_SELECT_CC.
let Defs = [FLAGS] in
def V6CLANG_CMP8_ZERO : V6ClangPseudo<(outs), (ins GR8:$src),
    "# V6CLANG_CMP8_ZERO $src",
    [(set FLAGS, (V6Clangcmp i8:$src, (i8 0)))]>;
```

Pattern preference: the existing match for `(V6Clangcmp i8:$src, (i8 imm:$cst))`
must be sharpened so the literal-zero case picks `V6CLANG_CMP8_ZERO` and the
non-zero case continues to lower to `CPI imm` (today's path is already
shape-aware for i16; this just extends the i16 zero-test discrimination to
i8).

### 2. Post-RA expansion

Single new `case` in `V6ClangInstrInfo::expandPostRAPseudo`:

|#|src  |A-liveness| expansion          |size/cycles|
|-|-----|----------|--------------------|-----------|
|1|A    |any       | `ORA A`            | 1B /  4cc |
|2|not-A|A dead    | `MOV A,src; ORA A` | 2B / 12cc |
|3|not-A|A live    | `INR src; DCR src` | 2B / 16cc |

Note that shape 2 (12cc) remains cheaper than the INR/DCR pair (16cc), so
the priority order matters: when `A` is dead, the existing
`MOV A,src; ORA A` is the right choice. The INR/DCR pair only wins when `A`
is live (it is then strictly better than today's 28cc save/restore).


```cpp
case V6CLANG::V6CLANG_CMP8_ZERO: {
    Register Src = MI.getOperand(0).getReg();
    if (Src == V6CLANG::A) {
        // Priority 1: src already in A.
        BuildMI(MBB, MI, DL, get(V6CLANG::ORAr))
            .addReg(V6CLANG::A, RegState::Define)
            .addReg(V6CLANG::A);
    } else if (isRegDeadAtMI(V6CLANG::A, MI, MBB, &RI)) {
        // Priority 2: A is dead — clobber it for free.
        BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr), V6CLANG::A).addReg(Src);
        BuildMI(MBB, MI, DL, get(V6CLANG::ORAr))
            .addReg(V6CLANG::A, RegState::Define)
            .addReg(V6CLANG::A);
    } else {
        // Priority 3: A is live — A-preserving zero test via INR/DCR.
        // Both INR and DCR write Src; mark the second as kill if the
        // original $src was killed by the pseudo.
        bool SrcKilled = MI.getOperand(0).isKill();
        BuildMI(MBB, MI, DL, get(V6CLANG::INR))
            .addReg(Src, RegState::Define)
            .addReg(Src);
        BuildMI(MBB, MI, DL, get(V6CLANG::DCR))
            .addReg(Src, RegState::Define)
            .addReg(Src, getKillRegState(SrcKilled));
    }
    MI.eraseFromParent();
    return true;
}
```

The `isRegDeadAtMI` helper is the same one used by O76 / `V6CLANG_LOAD8_P` and
the BC-swap path in `V6ClangInstrInfo.cpp`; A's post-RA liveness is reliable
because `MachineFunctionProperties::TracksLiveness` is set for V6CLANG.

### 3. Allocator hint (optional, follow-up)

Once `V6CLANG_CMP8_ZERO` exists as a real pseudo with a single GR8 input, ISel
can attach an A-preference hint to the input vreg. RA will then route the
producing value through `A` when free, collapsing shape 2 into shape 1
(`MOV A,src` becomes a no-op because the producer already targets A). This
is a strictly additional win on top of the INR/DCR change and is tracked as
a non-goal of the present plan to keep the patch focused.

## Per-fire impact

Cycle/byte savings vs current expander, conditional on RA's `src`/A
allocation:

- **Shape 1 (`src = A`)**: −1B / −8cc per fire vs today's
  `MOV A,A; ORA A` (which RA-coalesces in some cases but not all). When
  uncoalesced today, the new explicit single-instruction form is strictly
  better; when already coalesced, no change.
- **Shape 2 (A dead)**: unchanged (2B / 12cc).
- **Shape 3 (A live)**: **−2B / −12cc per fire** (4B / 28cc → 2B / 16cc),
  plus elimination of one scratch GR8 burn.

Shape 3 is the headline win. Empirically it is the dominant shape inside
loops that fold a counter or accumulator in A while branching on an
unrelated condition byte (`for (uint8_t i; n; …) if (cond) …`). The
benchmark suite (`tests/benchmarks_c`) is expected to show measurable cycle
reductions on bsort, sieve, and fib_crc.

## Verification plan

- Lit test `tests/lit/CodeGen/V6CLANG/cmp8-zero-inr-dcr.ll` covering all three
  shapes. Use IR + `register asm` pinning of the source operand and an
  A-live-after pattern to deterministically materialise each row. Verify
  that the `INR/DCR` pair appears for shape 3 and that the surrounding
  `MOV scratch,A; ... ; MOV A,scratch` save/restore is gone.
- Annotation regression: `-mllvm -mv6clang-annotate-pseudos` must now print
  `;--- V6CLANG_CMP8_ZERO ---` before the expansion (resolves the
  unannotated `MOV A,C; ORA A` sequence noted in
  [tests/features/37/v6clang.s](tests/features/37/v6clang.s) line 77).
- Update the opcode→name map in `V6ClangInstrInfo.cpp` so the annotator
  recognises `V6CLANG_CMP8_ZERO`.
- Existing benchmark golden files: regenerate; expect strict improvement
  (or no change) on every entry. Any regression is a bug.
- 133/133 lit + golden + benchmark checksums must remain green.

## Risk surface

- **`AC`/`CY` divergence**. The replacement does not match `ORA A` on `AC`
  and `CY`. As argued above, no zero-test consumer in the V6CLANG pipeline
  reads either flag. Add a comment in the pseudo's TableGen doc and a
  `// AC/CY divergence: only Z/S/P consumers permitted` assertion guard
  near `V6CLANG_BRCOND`'s CC validation to harden against future changes that
  introduce a `COND_C` / `COND_NC` consumer of `V6ClangISD::CMP_ZERO`.
- **Verifier on twin-def of `Src`**. Both `INR` and `DCR` define `Src`.
  Mark the first as a regular def and the second with the kill flag from
  the original `V6CLANG_CMP8_ZERO` operand to keep MIR-verifier happy.
- **Interaction with `INX/DCX` peepholes (O41)**. The 8-bit `INR/DCR`
  pair is not a target of `pre_ra_inx_dcx_pseudo`; verify that no
  post-RA peephole tries to fold `INR r; DCR r` into nothing on the
  ground that "they cancel" — they cancel for the value but the pair is
  the entire purpose of the expansion. Add a `setIsCompareForFlags()`
  marker (or equivalent `MIFlag`) on the emitted instructions to inhibit
  any future flag-blind cancellation pass.

## Open questions / non-goals

- **`V6CLANG_CMP8` (against an immediate)**. The general i8 compare against a
  non-zero immediate already lowers to `CPI imm` (1 byte for the imm).
  This plan does not touch it.
- **i8 register-vs-register compare**. Out of scope — the win is specific
  to the zero comparand because `INR`/`DCR` reify a unary flag-set.
- **Shape symmetry with i16**. `V6CLANG_CMP16_ZERO` already exists; this plan
  is the i8 analogue. No further symmetry work needed.
- **A-preference allocator hint** (see §3). Worth doing as a follow-up
  but separable; included here for visibility, not in scope.
