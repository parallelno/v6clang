# O83 — POP/PUSH Pair Elimination for Dead Register Pairs

**Source:** V6CLANG — observed in `tests/benchmarks_c/asm/v6clang_sieve_O2.s`
**Savings:** 2 instructions, ~6B, 22cc per eliminated pair (POP = 10cc/1B, PUSH = 12cc/1B + 2B stack traffic)
**Frequency:** Moderate — arises naturally when spill/reload pseudo lowering wraps a basic block operation that does not need the saved register pair
**Complexity:** Low — single-pass forward scan within a basic block, liveness query
**Risk:** Low — only fires when the register pair is proven dead after the sequence and not used between POP and PUSH
**Dependencies:** Liveness information available in peephole pass (post-RA); no other prerequisites
**Status:** [ ] not started

---

## Problem

The spill/reload lowering and instruction selection occasionally emit a pattern
where a register pair is saved with `PUSH rp`, a sequence of instructions is
emitted that does not actually use `rp`, and then `POP rp` restores the
original value.  When viewed in reverse, this looks like:

```asm
POP  rp          ; restore rp (consumes stack slot)
  <instr_1>      ; does not read or write rp
  ...
  <instr_n>      ; does not read or write rp
PUSH rp          ; save rp back (produces stack slot)
  <rp is dead>
```

Because no instruction between `POP` and `PUSH` reads or writes `rp`, the
value of `rp` after `POP` is identical to what `PUSH` would store.  The net
effect on the stack is zero (SP is decremented then incremented back to the
original value).  Since `rp` is dead after the `PUSH`, the register value
itself is also irrelevant.  Both instructions are therefore dead and can be
eliminated.

### Concrete instances (`tests/benchmarks_c/asm/v6clang_sieve_O2.s`)

**Case 1 — trivially adjacent POP/PUSH (lines 149–154)**

```asm
        POP  H               ; restore HL (lines 149–151: nothing between)
;--- V6CLANG_SPILL16 ---
        PUSH H               ; immediately save HL back — HL dead after
        MOV  L, C            ; HL is overwritten ⇒ HL dead at PUSH
        MOV  H, B
        SHLD .LLo61_3+1
```

`POP H` + `PUSH H` with no intervening instruction that reads or writes HL.
HL is dead at the `PUSH` (overwritten by the two MOV instructions that follow).
Both instructions can be removed.

**Case 2 — invalid: rp used between (lines 155–160)**

```asm
        POP  H               ; restore HL
;--- V6CLANG_INX16 ---
        INX  H               ; ← reads AND writes HL  ✗
        INX  H               ; ← reads AND writes HL  ✗
;--- V6CLANG_RELOAD16 ---
        PUSH H               ; save (modified) HL
```

`INX H` both reads and modifies `HL`, so the `POP`/`PUSH` pair cannot be
eliminated: the increments are visible to the `PUSH` and to whatever consumes
the stack slot.

**Case 3 — valid: intervening instruction does not touch rp (lines 164–168)**

```asm
        POP  H               ; restore HL
;--- V6CLANG_INX16 ---
        INX  B               ; modifies BC, not HL  ✓
;--- V6CLANG_SPILL16 ---
        PUSH H               ; save HL back — HL dead after
        MOV  L, C
        MOV  H, B
        SHLD .LLo61_5+1
```

`INX B` does not read or write HL.  HL is dead at the `PUSH` (overwritten
immediately after).  The `POP H` + `PUSH H` pair is redundant and can be
removed; `INX B` is kept.

---

## Correctness Conditions

All of the following must hold for the pair to be eliminated:

1. **Same basic block** — both `POP rp` and `PUSH rp` are in the same
   `MachineBasicBlock`.  There must be no branch, call, or return between them
   (a branch would leave the basic block; a call may alter the stack pointer
   or clobber caller-saved registers).

2. **rp not used between POP and PUSH** — no instruction in the closed
   interval `[POP+1 .. PUSH-1]` reads or writes any sub-register of `rp`.
   For 8080/8085: if `rp = HL`, neither `H` nor `L` nor the pair `HL` may
   appear as a use or def.  Same for `BC` (`B`, `C`) and `DE` (`D`, `E`).
   Note: `XCHG` (which swaps HL and DE) counts as both a use and a def of HL
   and DE and therefore invalidates either pair.

3. **rp is dead after PUSH** — immediately after the `PUSH rp`, `rp` (and
   its component bytes) must be dead: no subsequent instruction in any
   reachable path reads `rp` before it is redefined.  This is equivalent to
   `rp` being dead at the `PUSH` instruction in the post-RA liveness sets.

4. **No stack-affecting instructions between POP and PUSH** — any instruction
   that modifies `SP` (another `PUSH`, another `POP`, `INX SP`, `DCX SP`,
   `XTHL`, `SPHL`, a `CALL`) invalidates the optimization because the stack
   slot that `POP` consumed is no longer the same slot that `PUSH` would
   produce.

---

## Algorithm

Implement inside the existing `V6ClangPeephole` pass (post-RA, single basic block
traversal).

```
for each MBB in MF:
  for each instruction I in MBB (forward scan):
    if I is POP rp:
      J = first instruction after I that:
        - is not a comment / debug value
      scan forward from J:
        candidate_push = null
        for each K in [J .. end of MBB]:
          if K reads or writes any byte of rp:
            if K is PUSH rp:
              candidate_push = K
            break           // rp touched — stop (invalid if not PUSH rp)
          if K is CALL / branch / PUSH any / POP any / XTHL / SPHL / INX SP / DCX SP:
            break           // stack shape changes — invalid
          // else: K is safe, continue
        if candidate_push != null:
          if rp is dead after candidate_push (liveness check):
            erase I (POP rp)
            erase candidate_push (PUSH rp)
            Changed = true
```

The liveness check uses the `LivePhysRegs` utility or the per-instruction
`MachineOperand::isDead()` flag computed by `LiveVariables` / `RABasic`
already available in the peephole pass.

---

## Register Pair Coverage

The 8080/8085 register pairs that can appear in `PUSH`/`POP`:

| Mnemonic | Pair | Bytes     |
|----------|------|-----------|
| PUSH/POP B | BC | B, C     |
| PUSH/POP D | DE | D, E     |
| PUSH/POP H | HL | H, L     |
| PUSH/POP PSW | AF | A, FLAGS |

`PUSH/POP PSW` must be treated conservatively: the FLAGS component (condition
codes) is implicitly read by almost every instruction, so condition 2 is
almost never satisfiable.  Skip PSW pairs unless the full liveness analysis
proves FLAGS dead.

---

## Expected Impact

The sieve benchmark alone contains at least 2 eliminable pairs within the hot
inner loop (`BB15_8`).  Each removal saves **22 cycles** (10cc POP + 12cc
PUSH) and **2 bytes** of code.  Given the spill-heavy code the current
allocator emits, this pattern should appear frequently in any function with
moderate register pressure.

---

## Implementation Notes

- Pair the scan with the existing `V6ClangPeephole` forward iterator so no
  additional pass infrastructure is needed.
- The "rp not used" scan can reuse the `LivePhysRegs::contains()` interface
  already used in O64 and O82.
- Take care with `XCHG`: it is encoded as a single opcode but implicitly
  defines and uses both `HL` and `DE` simultaneously.  It blocks elimination
  of both pairs.
- If the intervening instructions include a `SHLD`/`LHLD` (absolute memory
  spill of HL) those count as a def/use of HL and block HL-pair elimination.
