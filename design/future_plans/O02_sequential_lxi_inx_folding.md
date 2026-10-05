# O2. Sequential Address Reuse (LXI → INX Folding)

## Problem

When loading from consecutive addresses, the compiler materializes each
address with a full `LXI H, imm16` (12cc, 3 bytes — Vector-06c timing).
After `MOV A, M` the HL register still holds the same address, so
`INX H` (8cc, 1 byte) suffices for the next address.

Per-instance saving: **4cc + 2 bytes** per replaced LXI.

## Before → After

```asm
; Before                          ; After
LXI  H, 0      ; 12cc            LXI  H, 0      ; 12cc
MOV  A, M      ;  8cc            MOV  A, M      ;  8cc
...                               ...
LXI  H, 1      ; 12cc  ← costly  INX  H         ;  8cc
MOV  A, M      ;  8cc            MOV  A, M      ;  8cc
...                               ...
LXI  H, 2      ; 12cc  ← costly  INX  H         ;  8cc
MOV  A, M      ;  8cc            MOV  A, M      ;  8cc
```

## Existing implementation (V6ClangLoadStoreOpt.cpp `mergeAdjacentAccess`)

Matches the strict 4-instruction window
`LXI H,N ; <load|store via M> ; LXI H,N+1 ; <load|store via M>` with
both LXI operands being plain `imm`. Does NOT match:

1. `GlobalAddress` operands (`LXI H, g+1` etc.) — `isLXI_HL` requires `isImm`.
2. Chains longer than 2 — only the first pair folds; the third LXI never
   sees `LXI H, prev+1` because the previous one was already deleted.
3. HL-preserving instructions interleaved between LXI and the M access
   (e.g. `LDA`, `STA`, `MVI A,imm`, `ADI/SUI/ANI/ORI/XRI/CPI`, ALU on A).
4. Decrement direction (consecutive descending addresses → DCX).

Real example from `temp/o02_test.c -O2`:

```asm
read4_global:
    LDA  0x100
    LXI  H, 0x101
    ADD  M
    INX  H            ; 0x101→0x102 — folded by current pass
    ADD  M
    LXI  H, 0x103     ; MISSED — would be INX H if chain were tracked
    ADD  M

read_struct:
    LXI  H, g
    LDA  g+1          ; HL preserved across LDA, but interrupts the pattern
    ADD  M
    LXI  H, g+2       ; MISSED — GlobalAddress operand, also gap
    ADD  M
    LXI  H, g+3       ; MISSED
    ADD  M
```

## Required extensions to the pass

### E1. Track HL state across a sliding window

Replace the rigid `LXI; access; LXI; access` pattern with a per-block
forward scan that maintains a small state:

```
HLKnown : { Unknown, Imm(int64), GA(GlobalValue*, offset) }
```

Update rules per instruction:
- `LXI H, imm` → `HLKnown = Imm(imm)` (record the LXI position).
- `LXI H, ga+off` → `HLKnown = GA(ga, off)`.
- `INX H` → if `HLKnown = Imm(v)` set `Imm(v+1)`; if GA, bump offset.
- `DCX H` → symmetric −1.
- Any other instruction defining H, L, or HL → `HLKnown = Unknown`.

When a new `LXI H, X` is seen and `HLKnown` already equals `X` ± Δ with
`|Δ| ≤ 3`, replace the new LXI with Δ copies of `INX H` (or `DCX H` if
negative). Δ = 0 → drop the LXI entirely (subsumes `eliminateDeadLXI`
for the common path).

Threshold `|Δ| ≤ 3`: 3 × INX H = 24cc / 3B vs. 12cc / 3B for LXI — break-even
in size, +12cc in speed. Choose threshold dynamically using the dual cost
model (`V6ClangCost::INX` vs. `V6ClangCost::LXI`) so `-Os` allows up to 3 and `-O2`
allows up to 1 (any more loses speed). For mixed: Δ = 1 always wins
(8cc < 12cc, 1B < 3B).

### E2. Match `GlobalAddress` operands

Loosen `isLXI_HL` to accept `MachineOperand::isGlobal()` and capture
`(getGlobal(), getOffset())`. Two LXI operands are "consecutive" when
they reference the same `GlobalValue *` and the offset differs by Δ
(within threshold). Same for `MO_ExternalSymbol` / `MO_BlockAddress` —
match by symbol identity + offset.

### E3. Allow HL-preserving instructions between LXI and the access

Whitelist instructions that neither read nor write HL:
- `LDA a16`, `STA a16`
- `MVI A, imm`, `MVI B/C/D/E, imm`
- `ADI/SUI/SBI/ACI/ANI/ORI/XRI/CPI imm`
- `ADD/SUB/SBB/ADC/ANA/ORA/XRA/CMP r` for r ∈ {A,B,C,D,E}
- `MOV` between non-H/L registers
- `INR/DCR` on non-H/L registers
- `IN/OUT port`
- `XCHG` is **not** in the whitelist (clobbers HL).

This widens the window so the `LDA g+1` / `ADD M` / `LXI H, g+2` chain
in `read_struct` can fold.

### E4. Symmetric DCX direction

Already covered by E1 (Δ < 0 path). Common in reverse-iteration loops
and tail-end array writes.

### E5. (Optional) Cross-MOV-A-from-table folding

When the accumulator round-trips through a temp register due to a load
on HL clobber, the LXI rebuild often follows. After E1–E3 land, audit
remaining cases — they typically need either spill avoidance (out of
scope) or O68-style ALU folding.

## Implementation sketch

```
runOnMachineFunction:
  for each MBB:
    HLState = Unknown
    PrevLXI = nullptr            // pointer to live LXI we may rewrite back from
    for each MI in MBB:
      if MI is LXI H, X:
        if HLState matches X within ±3:
          replace MI with |Δ| × INX/DCX H
          HLState = X
          continue
        HLState = X
        PrevLXI = MI
      else if MI is INX H: HLState.bump(+1)
      else if MI is DCX H: HLState.bump(-1)
      else if MI defines H/L/HL or is non-whitelisted:
        HLState = Unknown
        PrevLXI = nullptr
      // whitelisted instructions: leave HLState untouched
```

LOC estimate: ~120 lines replacing the existing ~70-line
`mergeAdjacentAccess`. `eliminateDeadLXI` becomes redundant for the
common case but kept for cross-pattern leftovers.

## Option B — Remove `Defs = [HL]` for HL-addressed loads (deferred)

When `V6CLANG_LOAD8_P` addr operand is already HL, the expansion is just
`MOV dst, M` — HL is preserved. An implicit-def of HL is only needed
when the address is in BC/DE (copy to HL clobbers it). Letting the
register allocator know HL is still live would enable natural sequential
reuse without a peephole.

Requires splitting V6CLANG_LOAD8_P into two variants or adding a dynamic
implicit-def during ISel based on the addr operand. Higher risk:
changes RA-visible liveness globally. Defer until E1–E4 land and
remaining gaps are characterized.

## Benefit

- **Per replaced LXI**: 4cc + 2 bytes (LXI 12/3 → INX 8/1).
- **Δ = 2 / 3 chains**: at `-O2` one INX still wins (8 < 12cc) but two/three
  INX are gated by cost model (size break-even, speed regression).
- **Frequency**: array traversals, struct field access (4-byte structs ≈
  three foldable LXIs), sequential volatile MMIO, `memcpy`/`memset` of
  small fixed sizes after unrolling.
- **Test case savings** (`temp/o02_test.c`):
  - `read4_global`: 1 missed LXI → 4cc + 2B.
  - `read_struct`: 2 missed LXIs → 8cc + 4B.
  - Combined: 12cc + 6B on a 26-instruction function.

## Complexity

- E1 + E4 (chain tracking, INX/DCX): Medium. Replaces existing pass core.
- E2 (GA operands): Small. ~10 LOC operand comparison helper.
- E3 (whitelist gap): Small-medium. ~15 LOC helper + table.
- Option B: Medium-high. Changes ISel pseudo semantics.

## Risk

- E1–E4: Low-medium. State machine is local to each MBB; on any
  unrecognized instruction the state resets to Unknown — fail-safe.
  Must cover implicit defs (CALL clobbers HL via libcalls; `V6CLANG_LOAD8_P`
  with addr=BC/DE clobbers HL via copy). Existing `definesHL` check
  already handles implicit operands — reuse.
- Option B: Medium. Changing `Defs` affects RA globally. Must verify no
  HL liveness bugs in complex control flow.

## Validation plan

1. Goldens (16/16) + lit (full suite) + 3 benchmarks (bsort/sieve/fib_crc)
   checksums must remain unchanged.
2. New lit test `loadstore-opt-chain.ll` exercising:
   - 3-LXI immediate chain → 1 LXI + 2 INX.
   - GlobalAddress-with-offset chain → 1 LXI + 2 INX.
   - LDA/STA gap between LXI and MOV M → fold.
   - XCHG between LXI and MOV M → no fold (negative test).
   - Δ = 4 → no fold (cost-model gate).
3. Update `temp/o02_test.c` golden expectations: 4 LXIs → 1 LXI + 3 INX
   in `read_struct`.
