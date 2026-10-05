# O45. Adjacent POP/PUSH Cancellation Peephole

*Identified while analyzing `test_multi_ptr` in `o16_spill_test.c`. Adjacent
pseudo expansions (e.g. store-via-HL followed by another store-via-HL) each
independently wrap their HL usage in `PUSH HL` / `POP HL`. When two such
expansions are adjacent, the trailing `POP HL` and the leading `PUSH HL`
cancel: HL comes back to the same value and gets pushed right back. Costs
24cc and 2B per pair for zero effect.*

## Problem

V6CLANG's static-stack store/load expansions use `PUSH HL; ...; POP HL` to
preserve HL while it's temporarily used for addressing. Each expansion is
self-contained, unaware of its neighbors. When two expansions are adjacent:

```asm
; Expansion 1: dereference p1 via HL
PUSH HL              ; 12cc 1B — save HL (holds p3)
MOV  H, B
MOV  L, C            ; HL = p1
MOV  C, M
INX  HL
MOV  B, M            ; BC = *p1
POP  HL              ; 12cc 1B — restore HL ← p3
; Expansion 2: spill BC to static stack via HL
PUSH HL              ; 12cc 1B — save HL again — redundant!
LXI  HL, __v6clang_ss...+2
MOV  M, C
INX  HL
MOV  M, B
POP  HL              ; 12cc 1B — restore HL ← p3
```

The `POP HL; PUSH HL` pair at the boundary is a no-op: HL is restored then
immediately saved again with the same value. Removing both saves 24cc + 2B.

## Approach

Post-expansion peephole in `V6ClangPeepholePass` (same pass as O44's XCHG
cancellation). Single linear scan looking for `POP rr; PUSH rr` pairs
on the same register pair.

### Pattern

```
POP  rr
PUSH rr
```

Two adjacent instructions: `V6CLANG::POP` followed by `V6CLANG::PUSH` for the same
register pair (HL, DE, or BC), with no intervening non-debug instructions.

### Safety conditions

1. **Same register pair** — POP destination must match PUSH source.
2. **Truly adjacent** — no labels, branches, or other instructions between
   them. Skip over `DBG_VALUE` / `CFI_INSTRUCTION`.
3. **No flags dependency** — neither POP nor PUSH affect flags on the 8080.
4. **SP is consistent** — after removing both, the stack depth is unchanged
   (POP +2 then PUSH −2 = net zero on SP).
5. **No other use of the register between** — by definition they're adjacent,
   so nothing reads the POP'd value before PUSH saves it.

### Why not fix in the expansion pass (O42)?

Making each expansion aware of its neighbors would create fragile coupling
between independent expansions — the same architectural issue that led to
the O44 XCHG cancellation being a separate peephole. The clean approach is
to expand independently and clean up in a post-expansion peephole pass.

## Before → After

```asm
; Before                                    ; After
PUSH HL                                     ; PUSH HL
MOV  H, B; MOV L, C                        ; MOV  H, B; MOV L, C
MOV  C, M; INX HL; MOV B, M                ; MOV  C, M; INX HL; MOV B, M
POP  HL              ; ← removed           ;
PUSH HL              ; ← removed           ;
LXI  HL, __v6clang_ss...+2                     ; LXI  HL, __v6clang_ss...+2
MOV  M, C; INX HL; MOV M, B                ; MOV  M, C; INX HL; MOV M, B
POP  HL                                     ; POP  HL
; Saves: 24cc, 2B per cancelled pair
```

## Implementation

### Location

`V6ClangPeephole.cpp`, new method `cancelAdjacentPopPush()`, called from
`runOnMachineFunction` alongside the existing `cancelAdjacentXchg()`.

### Algorithm

```cpp
bool V6ClangPeephole::cancelAdjacentPopPush(MachineBasicBlock &MBB) {
  bool Changed = false;
  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    if (I->getOpcode() != V6CLANG::POP)
      continue;

    // Skip debug instructions to find the next real instruction.
    auto Next = std::next(I);
    while (Next != E && Next->isDebugInstr())
      ++Next;
    if (Next == E)
      continue;

    if (Next->getOpcode() != V6CLANG::PUSH)
      continue;

    // Check same register pair.
    Register PopReg = I->getOperand(0).getReg();
    Register PushReg = Next->getOperand(0).getReg();
    if (PopReg != PushReg)
      continue;

    // Remove both.
    Next->eraseFromParent();
    I = MBB.erase(I);
    Changed = true;
    --I; // compensate for ++I in loop header
  }
  return Changed;
}
```

### Integration

Add to `runOnMachineFunction` after `cancelAdjacentXchg`:

```cpp
Changed |= cancelAdjacentXchg(MBB);
Changed |= cancelAdjacentPopPush(MBB);  // new
Changed |= foldShldLhldToPushPop(MBB);
```

Run before `foldShldLhldToPushPop` (O43) since POP/PUSH cancellation may
expose new SHLD/LHLD pairs that become adjacent after wrapper removal.

## Benefit

- **Savings per instance**: 24cc, 2B per cancelled pair
- **Frequency**: High — any function with multiple adjacent static-stack
  accesses (stores, loads, or mixed). Common in function prologues and
  loop bodies with register pressure.
- **Compound effect**: Removing POP/PUSH pairs reduces code size and may
  expose further peephole opportunities (O43, O44).

## Complexity

Very Low. ~20 lines. Near-identical structure to the existing
`cancelAdjacentXchg()` method.

## Risk

Very Low. POP rr followed immediately by PUSH rr with the same register
is always a no-op on the 8080. No flags, no side effects, no edge cases.
