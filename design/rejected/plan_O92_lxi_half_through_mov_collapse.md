# Plan: O92 — LXI-Half-through-MOV Collapse

# Resolution
Rejected. The pattern as written has no monotonic win

## 1. Problem

### Current behavior

When a 16-bit constant is materialised with `LXI RP, Imm16` for a later
16-bit consumer (XOR/AND/store) and one of its halves is **independently**
read into the accumulator afterwards, the backend emits a redundant
`MOV A, RP_HALF` copy that depends on the half-register still holding the
original byte:

```asm
LXI   D, 0xB4FF    ; D=0xB4, E=0xFF      12cc 3B
... 16-bit XOR via DE ...
SHLD  g_sink16     ;                     20cc 3B
MOV   A, E         ; A = lo(0xB4FF)       8cc 1B   ← could be MVI A, 0xFF
RET                ;                     12cc 1B
```

The intermediate dependency on `E` keeps `DE` live across the entire span,
even though the *byte value* is a compile-time constant known at the LXI site.

### Desired behavior

Forward the constant byte directly from the LXI's immediate into the consumer:

```asm
LXI   D, 0xB4FF    ; (unchanged)
... 16-bit XOR via DE ...
SHLD  g_sink16     ;
MVI   A, 0xFF      ; A = lo(0xB4FF)       8cc 2B   ← direct materialisation
RET                ;
```

Net cycles are identical for the lone MOV→MVI swap (both 8cc); the win is
that the half-register's liveness across the consumer is removed, freeing the
register allocator and potentially eliminating spills.  In small functions
where the LXI is otherwise dead after the half consumer, the LXI itself is
also erased (saves 12cc / 3B).

### Root cause

`collapseMovChain` in `V6ClangPeephole.cpp` already handles two producer kinds:

| Producer | Variant | Status |
|----------|---------|--------|
| `MOVrr`  | O82 Pattern B (classic), O89 (rewrite-producer when Y clobbered) | implemented |
| `MVIr`   | O88 (MVI-through-MOV) | implemented |
| `LXIrp`  | none — gap                                                       | **this plan**  |

`LXI` defines two 8-bit halves of a register pair from a 16-bit immediate, so
its consumer `MOV Z, RP_HALF` is structurally identical to the O88 pattern —
the producer just needs to know which half is being consumed and extract the
matching byte from the immediate.

---

## 2. Strategy

### Approach: add an `LXI`-producer loop to `collapseMovChain`

After the existing O88 `MVIr`-producer loop, add a third forward-scan loop
that handles `V6CLANG::LXI` producers.  When the sole consumer `MOV Z, RP_HALF`
is reached and `RP_HALF` is dead after that consumer, emit `MVI Z, byte` in
place of the `MOV` and (if the full pair is now dead) erase the `LXI` too.

### Why this works

- `LXI RP, Imm16` writes `RP_LO = (uint8_t)Imm` and `RP_HI = (uint8_t)(Imm>>8)`
  atomically and does not touch FLAGS.
- If `RP_HALF` is not read or clobbered between LXI and the consumer, the byte
  is still the same compile-time constant.
- If `RP_HALF` is dead after the consumer, the `MOV Z, RP_HALF` is the sole
  use of that byte.
- Replacing `MOV Z, RP_HALF` with `MVI Z, byte` is semantically identical and
  has the same cycle cost (8cc), but breaks the dependency on `RP_HALF`.
- Conservatively, `LXI` itself is erased only when the **whole pair** is dead
  after the consumer; otherwise it must stay because the other half is still
  used.
- O61 patched LXIs (carrying a pre-instr label or `MO_PATCH_IMM` flag) and
  LXIs with non-immediate operands (global addresses, MCSymbols) are skipped —
  their immediate is not a static value.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp` | Add `LXI`-producer loop in `collapseMovChain`; local `pairHalves(RP)` helper |
| `llvm-project/llvm/test/CodeGen/V6Clang/peephole-lxi-half-mov-collapse.ll` | New lit test (CHECK + DISABLED) |
| `tests/features/75/` | C source, baseline asm, post-fix asm, `result.txt` |
| `design/future_plans/README.md` | Mark O92 `[x]` after completion |

---

## 3. Implementation Steps

### Step 3.1 — Add `pairHalves(RP)` helper [ ]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

Add a file-static helper near `isO61PatchedImm` returning `{Hi, Lo}` for an
i16 pair physical register, or `{NoRegister, NoRegister}` for any other
register:

```cpp
// Map a GR16 pair to its {Hi, Lo} 8-bit halves.  Returns {0,0} for non-pairs.
static std::pair<Register, Register> pairHalves(Register RP) {
  switch (RP.id()) {
  case V6CLANG::HL: return {V6CLANG::H, V6CLANG::L};
  case V6CLANG::DE: return {V6CLANG::D, V6CLANG::E};
  case V6CLANG::BC: return {V6CLANG::B, V6CLANG::C};
  default:      return {Register(), Register()};
  }
}
```

> **Design Notes**: identical pattern is used in `V6ClangArgAllocator::halves`
> inside `V6ClangISelLowering.cpp`; duplicating a 5-line switch here is simpler
> than exposing the existing helper.

> **Implementation Notes**:

### Step 3.2 — Add `LXI`-producer loop in `collapseMovChain` [ ]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangPeephole.cpp`

After the existing O88 `MVIr`-producer loop (ends before `return Changed;`),
insert:

```cpp
  // O92: LXI-producer variant.
  // Pattern: LXI RP, Imm16  ; [window, RP_HALF not read/clobbered]
  //          ; MOV Z, RP_HALF       (RP_HALF dead after consumer)
  // Transform: emit MVI Z, byte(Imm16) at the consumer's position,
  //            erase the consumer MOV; if the whole pair is dead at
  //            the LXI site, erase LXI too.
  for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
    MachineInstr &ProducerMI = *I;
    if (ProducerMI.getOpcode() != V6CLANG::LXI)
      continue;
    if (isO61PatchedImm(ProducerMI))
      continue;
    if (!ProducerMI.getOperand(1).isImm())
      continue;  // global address / MCSymbol — byte unknown statically

    Register RP  = ProducerMI.getOperand(0).getReg();
    auto     HL  = pairHalves(RP);
    Register RPHi = HL.first;
    Register RPLo = HL.second;
    if (!RPHi || !RPLo)
      continue;
    int64_t  Imm = ProducerMI.getOperand(1).getImm();
    uint8_t  Lo  = static_cast<uint8_t>(Imm & 0xFF);
    uint8_t  Hi  = static_cast<uint8_t>((Imm >> 8) & 0xFF);

    unsigned Steps = 0;
    for (auto J = std::next(I); J != E && Steps < kChainWindow; ++J) {
      if (J->isDebugInstr())
        continue;
      ++Steps;

      bool IsLoConsumer = J->getOpcode() == V6CLANG::MOVrr &&
                          TRI->regsOverlap(J->getOperand(1).getReg(), RPLo);
      bool IsHiConsumer = !IsLoConsumer && J->getOpcode() == V6CLANG::MOVrr &&
                          TRI->regsOverlap(J->getOperand(1).getReg(), RPHi);
      bool IsConsumer   = IsLoConsumer || IsHiConsumer;
      Register Half     = IsLoConsumer ? RPLo : RPHi;
      uint8_t  Byte     = IsLoConsumer ? Lo   : Hi;

      // Foreign read/write of either half terminates the scan.  The
      // consumer's own source operand (Half) does not count as foreign.
      bool ReadsHalf = false, ClobbersHalf = false;
      for (const MachineOperand &MO : J->operands()) {
        if (!MO.isReg() || !MO.getReg())
          continue;
        Register Tracked = IsConsumer ? Half : RP;
        if (!TRI->regsOverlap(MO.getReg(), Tracked))
          continue;
        bool IsConsumerSrc =
            IsConsumer && MO.isUse() && &MO == &J->getOperand(1);
        if (MO.isUse() && !MO.isUndef() && !IsConsumerSrc)
          ReadsHalf = true;
        if (MO.isDef())
          ClobbersHalf = true;
      }

      if (IsConsumer) {
        if (ClobbersHalf)
          break;
        if (!isRegDeadAfter(MBB, J, Half, TRI))
          break;

        Register Z = J->getOperand(0).getReg();
        const TargetInstrInfo &TII =
            *MBB.getParent()->getSubtarget().getInstrInfo();
        BuildMI(MBB, J, J->getDebugLoc(), TII.get(V6CLANG::MVIr), Z).addImm(Byte);
        auto Next = std::next(I);
        J->eraseFromParent();
        // Erase LXI only if the entire pair is now dead at the LXI site.
        if (isRegDeadAfter(MBB, I, RP, TRI)) {
          ProducerMI.eraseFromParent();
          I = std::prev(Next);
        }
        Changed = true;
        break;
      }

      if (ReadsHalf || ClobbersHalf)
        break;
    }
  }
```

> **Design Notes**:
> - The scan tracks only the *consumed half* until a consumer is identified;
>   before that, any read or write of *either half of the pair* is a
>   barrier because we don't yet know which half is needed.  Using the
>   whole-pair register `RP` for the barrier check before the consumer is
>   slightly conservative but always safe.
> - `isRegDeadAfter(MBB, I, RP, TRI)` answers "is the entire pair dead after
>   the LXI site, given the now-erased consumer".  If only one half was used
>   and the other was always dead, this returns true and the LXI is erased.
> - Window size `kChainWindow = 8` matches the existing O82/O88/O89 limit.

> **Implementation Notes**:

### Step 3.3 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

If the build fails, diagnose and fix, then rebuild.

> **Implementation Notes**:

### Step 3.4 — Lit test: `peephole-lxi-half-mov-collapse.ll` [ ]

**File**: `llvm-project/llvm/test/CodeGen/V6Clang/peephole-lxi-half-mov-collapse.ll`

Cover four cases:

1. **Lo-byte fold** — `LXI DE, 0xB4FF; ... 16-bit XOR ...; MOV A, E` →
   `MVI A, 0xFF`
2. **Hi-byte fold** — `LXI DE, 0xB4FF; ... 16-bit XOR ...; MOV A, D` →
   `MVI A, 0xB4`
3. **Whole-pair-dead** — single-use half with no other consumer: LXI erased
4. **Negative** — a non-immediate LXI (global address) MUST NOT be folded

Add `RUN: llc ... < %s | FileCheck %s` and a second
`RUN: llc ... --v6clang-disable-peephole < %s | FileCheck %s --check-prefix=DISABLED`
to exhibit the baseline behaviour.

> **Implementation Notes**:

### Step 3.5 — Run regression tests [ ]

```
python tests\run_all.py
```

If any test fails, diagnose and fix, rebuild, rerun.

> **Implementation Notes**:

### Step 3.6 — Verification assembly steps from `tests\features\README.md` [ ]

Use `tests/features/75/` (prepared in Phase 1).  Compile `v6clang.c` with the
fix and save as `v6clang_new01.asm`.  Inspect:

- `p2_lxi_lo_used` — expect `MVI A, 0xFF` replacing `MOV A, E`
- `p3_lxi_hi_used` — expect `MVI A, 0xB4` replacing `MOV A, D`
- `p_lxi_full_dead` (whole-pair-dead case) — expect the LXI itself erased

> **Implementation Notes**:

### Step 3.7 — Make sure `result.txt` is created (`tests\features\README.md`) [ ]

Populate `tests/features/75/result.txt` with:

- C test case code
- `c8080` asm body (main + helpers) converted to i8080
- `c8080` per-function stats (worst-case cycles, bytes)
- v6clang old asm
- v6clang new asm
- Comparison table

> **Implementation Notes**:

### Step 3.8 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1 — `temp/test_lxi_nonzero.c` (`p2_nonzero_lo`)

```c
uint8_t p2_nonzero_lo(uint16_t x) {
    const uint16_t mask = 0xB4FF;
    g_sink16 = x ^ mask;
    return (uint8_t)(mask & 0xFF);   // = 0xFF
}
```

Before O92 (current build):
```asm
LXI  D, 0xB4FF
... XOR ...
SHLD g_sink16
MOV  A, E          ; 8cc 1B
RET
```

After O92:
```asm
LXI  D, 0xB4FF
... XOR ...
SHLD g_sink16
MVI  A, 0xFF       ; 8cc 2B   — breaks DE liveness across the SHLD
RET
```

### Example 2 — `p3_nonzero_hi`

```c
uint8_t p3_nonzero_hi(uint16_t x) {
    const uint16_t mask = 0xB4FF;
    g_sink16 = x ^ mask;
    return (uint8_t)(mask >> 8);     // = 0xB4
}
```

Before O92:
```asm
... LXI D, 0xB4FF; XOR; SHLD; MOV A, D; RET
```

After O92:
```asm
... LXI D, 0xB4FF; XOR; SHLD; MVI A, 0xB4; RET
```

### Example 3 — Whole-pair-dead

```c
uint8_t lo_only(void) {
    const uint16_t k = 0x37FF;       // pair never used as a pair
    return (uint8_t)(k & 0xFF);      // only the lo byte used
}
```

Note: this case will likely be folded earlier in SDAG (constant) — the win is
when register-allocation leaves a pair-write LXI followed by a single-half
consumer.  Real instances surface in patterns where a 16-bit immediate is
used in a single 16-bit context that then dies, followed by a half consumer.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| O61 patched LXI is erased, orphaning a spill site | `isO61PatchedImm` guard before fold |
| LXI's immediate is not a literal (global address / MCSymbol) | `getOperand(1).isImm()` check |
| Half-register written between LXI and consumer | Per-instruction `ClobbersHalf` barrier |
| Half-register read between LXI and consumer | Per-instruction `ReadsHalf` barrier |
| LXI erased while other half still live | Erase LXI only when `isRegDeadAfter(I, RP)` holds |
| `MOV Z, Half` where Z == Half (round-trip) | `isRegDeadAfter` returns false for a live def-after; would not fold |
| Implicit FLAGS dependency on producer | LXI does not affect FLAGS; MVI does not affect FLAGS — no FLAGS change |

---

## 6. Relationship to Other Improvements

- **O82 / O89 (`MOVrr` producer)** — disjoint producer kind (`MOVrr`).
- **O88 (`MVIr` producer)** — directly adjacent transform; O92 extends the
  same `collapseMovChain` function with a new producer case.  Order in the
  function: `MOVrr` loop → `MVIr` loop (O88) → `LXI` loop (O92).
- **O55 `foldMviZeroToXraA`** — when the folded byte is 0 and Z == A, this
  later pass will further fold the emitted `MVI A, 0` into `XRA A` (saves an
  additional 4cc/0B).  O92 deliberately does not duplicate that rewrite;
  pass-ordering already handles it.
- **`eliminateDeadMVI`** — if a different `MVI` somewhere becomes dead as a
  side effect of O92 erasing the LXI, the existing pass cleans it up.

---

## 7. Future Enhancements

- **O92b — propagate the byte across multiple consumers**: if the same
  `LXI RP, Imm16` feeds *several* `MOV Z, RP_HALF` reads, O92 currently only
  catches the first.  A follow-up could iterate or call O92 in a fixpoint
  until no change.
- **O92c — `LXI` to address-symbol**: a related pattern emits
  `LXI H, addr; MOV A, L` to materialise the low byte of an address.  This is
  trickier because the byte depends on link-time relocation; needs an
  expression-friendly form of `MVI A, lo8(sym)`.  Out of scope for O92.

---

## 8. References

* [Future Improvements](design/future_plans/README.md)
* [O92 Feature Description](design/future_plans/O92_lxi_half_through_mov_collapse.md)
* [V6CLANG Build Guide](docs/V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs/V6ClangInstructionTimings.md)
* [Pipeline Feature](design/pipeline_feature.md)
* [Plan O88 — MVI-through-MOV Collapse](design/plan_O88_mvi_through_mov_collapse.md)
