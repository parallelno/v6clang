# O84 — INX/DCX-Through-Spill Round-Trip Fold (`MOV rp←HL / INX|DCX rp / MOV HL←rp / SHLD` → `INX|DCX H / SHLD`)

**Source:** V6CLANG — observed in `tests/features/64/v6clang_new01.asm` (outer-loop latch of `main`, post-O83)
**Savings:** 4 instructions, 4 B, 32 cc per occurrence (four 8cc/1B MOV instructions removed)
**Frequency:** Low–moderate — arises whenever a 16-bit increment or decrement is performed through an intermediate register pair that is dead after the subsequent store
**Complexity:** Low — single-pass forward scan within a basic block, one liveness query
**Risk:** Low — the replacement preserves the exact values of HL and the memory location; the discarded register pair is provably dead
**Dependencies:** O83 done (POP/PUSH pair elimination, which exposes this pattern); post-RA peephole pass
**Status:** [ ] not started

---

## Problem

After O83 eliminates redundant `POP`/`PUSH` pairs, the following 6-instruction
pattern is exposed in a single basic block:

```asm
MOV  rl, L        ; park L in the low byte of some pair rp
MOV  rh, H        ; park H in the high byte of some pair rp
INX  rp           ; increment rp (= old HL + 1)     ← or DCX rp (= old HL − 1)
MOV  L, rl        ; copy rp low back to L
MOV  H, rh        ; copy rp high back to H
SHLD addr         ; store HL (= old HL ± 1) to memory
```

where `rp` is `BC` (rh = `B`, rl = `C`) or `DE` (rh = `D`, rl = `E`), and
`rp` is **dead** after the `SHLD`.

The sequence is a round-trip: HL is copied into `rp`, `rp` is incremented or
decremented, then `rp` is copied back into HL, and the result is stored.
Because HL and `rp` hold the same value throughout and the copy back to HL is
the last use of `rp`, the entire copy machinery is unnecessary.  The same
result is achieved by:

```asm
INX  H            ; increment HL directly  (or DCX H for the decrement variant)
SHLD addr         ; store HL
```

### Concrete instance (`tests/features/64/v6clang_new01.asm`, lines ~282–290)

The outer-loop latch of `main` (Sieve benchmark) updates `i_sq` by incrementing
the previously computed `i_sq + 2*i` by 1:

```asm
; Before O84 (6 instructions):
        LHLD    .LLo61_12+1   ; reload i_sq into HL
        MOV     C, L          ; park HL in BC
        MOV     B, H
        INX     B             ; BC = i_sq + 1
        MOV     L, C          ; copy BC back to HL
        MOV     H, B
        SHLD    .LLo61_12+1   ; store updated i_sq

; After O84 (2 instructions for the update, LHLD unchanged):
        LHLD    .LLo61_12+1   ; reload i_sq into HL
        INX     H             ; HL = i_sq + 1
        SHLD    .LLo61_12+1   ; store updated i_sq
```

`BC` is dead after the `SHLD` (it is overwritten by the next `LHLD` /
`MOV C,L` / `MOV B,H` sequence at the next loop iteration).

**Net savings: 4 instructions, 4 B, 32 cc** per loop iteration.

---

## Root Cause

The pattern originates from three consecutive pseudo-instruction expansions:

1. **V6CLANG_SPILL16** (`HL → rp`): saves the current HL value into a scratch
   register pair so that HL is free for the subsequent `DAD` operation.
   Expands to `MOV rl, L` / `MOV rh, H`.
2. **V6CLANG_INX16** (`rp++`) or **V6CLANG_DCX16** (`rp--`): increments or decrements
   the spilled value in the register pair.  Expands to `INX rp` or `DCX rp`.
3. **V6CLANG_RELOAD16** (`rp → HL`) + **SHLD**: loads the modified value back
   into HL so it can be stored to the spill slot.
   Expands to `MOV L, rl` / `MOV H, rh` / `SHLD addr`.

The intermediate register pair is needed only to free HL for intervening DAD
instructions.  Once O83 removes the surrounding `POP H` / `PUSH H` pair and
the register allocator no longer requires that HL be preserved across this
window, the copy into `rp` is revealed as dead.

---

## Correctness Conditions

All of the following must hold:

1. **Same basic block** — all six instructions (`MOV rl,L`, `MOV rh,H`,
   `INX rp`, `MOV L,rl`, `MOV H,rh`, `SHLD`) reside in the same
   `MachineBasicBlock` with no intervening branches, calls, or returns.

2. **No use of HL between the first MOV and SHLD** — the closed interval
   `[MOV rl,L .. MOV L,rl)` (i.e., the two saves, the INX, up to but not
   including the reloads) must not contain any instruction that reads or
   writes `H` or `L`.  In practice `INX rp` (where `rp ≠ HL`) satisfies this
   trivially; any other intervening instruction that touches HL would
   invalidate the optimization.

3. **No use of rp between INX rp and SHLD** — the instructions `MOV L,rl`
   and `MOV H,rh` must be the only consumers of `rp` after the `INX`.
   (This is guaranteed by the exact 6-instruction form of the pattern.)

4. **rp is dead after SHLD** — immediately after the `SHLD`, neither `rh`
   nor `rl` (nor the pair `rp`) is live on any reachable path.  Query
   post-RA liveness at the `SHLD` instruction.

5. **INX/DCX does not affect flags (always true on 8080/8085)** — neither
   `INX rp` nor `DCX rp` sets or clears any condition code.  Consequently,
   even if flags are live after the `SHLD`, replacing `INX rp` with `INX H`
   (or `DCX rp` with `DCX H`) is still valid.

---

## Algorithm

Implement inside the existing `V6ClangPeephole` pass (post-RA, single basic block
forward scan).

```
for each instruction MI in MBB:
    if MI is  MOV rl, L  (where rl ∈ {C, E}):
        I0 = MI
        I1 = next(I0)  ;  expect MOV rh, H  (rh paired with rl)
        I2 = next(I1)  ;  expect INX rp  *or*  DCX rp
        I3 = next(I2)  ;  expect MOV L, rl
        I4 = next(I3)  ;  expect MOV H, rh
        I5 = next(I4)  ;  expect SHLD addr

        if I1..I5 all present in same MBB and match the pattern:
            if no instruction in [I0..I4] reads or writes H or L (except the
               MOVs that ARE the pattern):
                if rp is dead after I5 (liveness query):
                    if I2 is INX rp:  emit  INX H  before I5
                    if I2 is DCX rp:  emit  DCX H  before I5
                    erase I0, I1, I2, I3, I4
                    (I5 = SHLD remains, now preceded by INX H or DCX H)
                    Changed = true
```

The register-pair mapping to match:

| `rl` | `rh` | `rp` | `INX` opcode | `DCX` opcode |
|------|------|------|--------------|---------------|
| `C`  | `B`  | `BC` | `INX B`      | `DCX B`       |
| `E`  | `D`  | `DE` | `INX D`      | `DCX D`       |

The liveness check for `rp` dead after `SHLD`: query whether both `rh` and
`rl` are dead at the `SHLD` instruction using the standard post-RA liveness
information available in the peephole pass.

---

## Related Patterns

### Pattern B — Round-trip copy without INX (dead spill/reload)

A degenerate form of the same root cause produces a no-op copy when there is
no increment:

```asm
MOV  rh, H        ; park H in rh
MOV  rl, L        ; park L in rl
MOV  L, rl        ; restore L = rl = L  (no-op)
MOV  H, rh        ; restore H = rh = H  (no-op)
SHLD addr
```

All four MOV instructions form a complete identity transformation on HL and can
be removed if `rp` is dead after `SHLD`, leaving only `SHLD addr`.  This
variant is visible at `LLo61_12` and `LLo61_10` in the same file and saves
4 instructions / 4 B / 32 cc per site.  It may be addressed in the same pass
entry as a second match arm or as a follow-on micro-optimization.

---

## Expected Output

### Before O84 (`tests/features/64/v6clang_new01.asm`, inner-loop update)

```asm
        LHLD    .LLo61_12+1   ; 20cc 3B  reload i_sq
        MOV     C, L          ;  8cc 1B  \
        MOV     B, H          ;  8cc 1B   | spill HL → BC
        INX     B             ; 10cc 1B  — BC = i_sq + 1
        MOV     L, C          ;  8cc 1B   | reload BC → HL
        MOV     H, B          ;  8cc 1B  /
        SHLD    .LLo61_12+1   ; 16cc 3B  store
```
Total for update: 6 instructions, 8 B, 58 cc

### After O84

```asm
        LHLD    .LLo61_12+1   ; 20cc 3B  reload i_sq
        INX     H             ; 10cc 1B  HL = i_sq + 1
        SHLD    .LLo61_12+1   ; 16cc 3B  store
```
Total for update: 2 instructions, 4 B, 26 cc

**Savings: 4 instructions, 4 B, 32 cc** (executed once per outer-loop
iteration ≈ 14 times for the SIZE=200 sieve).

---

## Test Plan

1. **Unit test** — add a lit test in `tests/features/` with the six-instruction
   pattern for all four variants: BC+INX, BC+DCX, DE+INX, DE+DCX.  Verify
   the SHLD is preceded by exactly `INX H` or `DCX H` and no other MOV
   instructions remain.

2. **Regression** — `tests/features/64/v6clang_new01.asm` (current golden
   output after O83); after O84 the sequence
   `MOV C,L / MOV B,H / INX B / MOV L,C / MOV H,B / SHLD .LLo61_12+1`
   must become `INX H / SHLD .LLo61_12+1`.

3. **Benchmark** — re-run `tests/benchmarks_c/run_benchmarks.py`; cycle count
   for the sieve benchmark should decrease by approximately 32 cc × (number of
   outer-loop iterations).

4. **Correctness** — verify the sieve result byte (`return` value of `main`)
   is unchanged before and after O84.
