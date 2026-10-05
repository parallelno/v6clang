# O92 — LXI-Half-through-MOV Collapse

# Resolution
Rejected. The pattern as written has no monotonic win

**Source:** `temp/test_lxi_nonzero.c`; investigated 2026-06-01
**Savings:** 8cc, 1B per occurrence (MOV eliminated; LXI unchanged)
**Frequency:** Any function that materialises a 16-bit constant for a 16-bit use
  while also needing an individual byte of that constant in a separate 8-bit use
**Complexity:** Low — extends the O88 `collapseMovChain` MVI-producer scan with
  a second producer kind (`LXIrp` instead of `MVIr`)
**Risk:** Low — conservative: only folds when the RP half-register is dead after
  the consumer MOV and the LXI immediate is a compile-time constant
**Dependencies:** O88 done (infrastructure in place)
**Status:** [ ] not started

---

## Problem

When a 16-bit immediate is loaded into a register pair with `LXI RP, Imm16`,
both the lo and hi bytes land in the pair's half-registers (`RP_LO = lo(Imm16)`,
`RP_HI = hi(Imm16)`).  If the 16-bit value is later used by a 16-bit operation
(XOR, AND, etc.) and one of its byte values is independently needed in A, the
compiler emits a `MOV A, RP_HALF` copy that could instead be a direct
`MVI A, byte(Imm16)`:

```asm
; Before
LXI  D, 0xB4FF     ; D=0xB4, E=0xFF        12cc  3B
MOV  A, L          ; \
XRA  E             ;  | 16-bit XOR via A   ...
MOV  L, A          ; /
MOV  A, H          ;
XRA  D             ;
MOV  H, A          ;
SHLD g_sink16      ; sink the XOR result    20cc  3B
MOV  A, E          ; A = 0xFF              8cc   1B ← redundant copy
RET                ;                       12cc  1B

; After
LXI  D, 0xB4FF     ; D=0xB4, E=0xFF        12cc  3B   (unchanged)
... XOR uses ...
SHLD g_sink16      ;                        20cc  3B
MVI  A, 0xFF       ; A = lo(0xB4FF)        8cc   2B ← direct materialisation
RET                ;                       12cc  1B
```

Net: same cycle count (8cc either way), but eliminates the dependency on the
live-until-the-end `E` register — meaning RA can potentially assign `DE` to
something else sooner.  The more important benefit arises when the LXI is
placed far from the use: the half-register would need to be kept live across a
long sequence, potentially causing spills.

### Variant A — lo byte

```asm
LXI  RP, Imm16     ; RP_LO = lo(Imm16)
[... RP_LO not clobbered, RP_LO not read except as source below ...]
MOV  Z, RP_LO      ; Z = lo(Imm16)
```
→ `MVI Z, lo(Imm16)` + erase MOV.  If RP is now dead (both halves dead), erase
LXI too.

### Variant B — hi byte

```asm
LXI  RP, Imm16     ; RP_HI = hi(Imm16)
[... RP_HI not clobbered, RP_HI not read except as source below ...]
MOV  Z, RP_HI      ; Z = hi(Imm16)
```
→ `MVI Z, hi(Imm16)` + erase MOV.  If RP is now dead, erase LXI too.

### Confirmed current output (`temp/test_lxi_nonzero.c`, clang -O2, 2026-06-01)

```asm
p2_nonzero_lo:                    ; return (mask & 0xFF) where mask=0xB4FF
    LXI  D, 0xb4ff
    MOV  A, L
    XRA  E
    MOV  L, A
    MOV  A, H
    XRA  D
    MOV  H, A
    SHLD g_sink16
    MOV  A, E       ← not optimised: remains MOV A, E (should be MVI A, 0xFF)
    RET

p3_nonzero_hi:                    ; return (mask >> 8) where mask=0xB4FF
    LXI  D, 0xb4ff
    MOV  A, L
    XRA  E
    MOV  L, A
    MOV  A, H
    XRA  D
    MOV  H, A
    SHLD g_sink16
    MOV  A, D       ← not optimised: remains MOV A, D (should be MVI A, 0xB4)
    RET
```

Note: the zero-byte case (`mask = 0xB400`, lo = 0x00) bypasses this entirely
via `foldMviZeroToXraA` / `foldXraCmpZeroTest` which see A=0 after the XOR and
replace the zero `MOV A, E` with `XRA A`.  O92 is needed only for non-zero
byte values where those existing transforms do not fire.

---

## Root-cause analysis

`collapseMovChain` in `V6ClangPeephole.cpp` (O82/O88/O89) handles two producer kinds:
- **`MOVrr` producer** (O82 Pattern B, O89 rewrite-producer): `MOV X, Y ; ... ; MOV Z, X`
- **`MVIr` producer** (O88): `MVI X, Imm ; ... ; MOV Z, X`

`LXI RP, Imm16` is a **third producer kind**: it defines two 8-bit half-registers
at once (`RP_LO = lo(Imm16)` and `RP_HI = hi(Imm16)`).  When either half is
later consumed by a `MOV Z, RP_HALF`, the pattern is structurally identical to
the O88 MVI case — with two differences:

1. The producer opcode is `LXIrp` (defines a 16-bit register pair) rather than
   `MVIr` (defines a single 8-bit register).
2. We must track which half (`lo` or `hi`) is being consumed and extract the
   matching byte from the 16-bit immediate.

Because `collapseMovChain` only checks for `MVIr` as the O88 producer, the
`LXI`-produced constant in E (or D) is never forwarded.

---

## Proposed implementation

Extend the O88 loop in `V6ClangPeephole::collapseMovChain` with a second producer
loop (or extend the existing one) that matches `LXIrp`:

```cpp
// O92: LXIrp-producer variant.
// Pattern: LXI RP, Imm16 ; [window, RP_HALF not read/clobbered] ; MOV Z, RP_HALF
//          where RP_HALF is dead after the MOV.
// Transform: emit MVI Z, byte(Imm16) before the MOV, then erase MOV.
//            If RP is now dead at the LXI site, erase LXI too.
for (auto I = MBB.begin(), E = MBB.end(); I != E; ++I) {
  MachineInstr &ProducerMI = *I;
  if (ProducerMI.getOpcode() != V6CLANG::LXIrp)
    continue;

  Register RP  = ProducerMI.getOperand(0).getReg(); // e.g. V6CLANG::DE
  int64_t  Imm = ProducerMI.getOperand(1).getImm(); // 16-bit immediate
  uint8_t  Lo  = (uint8_t)(Imm & 0xFF);
  uint8_t  Hi  = (uint8_t)((Imm >> 8) & 0xFF);

  // Determine the two half-registers for RP.
  Register RPLo = pairLo(RP); // e.g. V6CLANG::E for DE
  Register RPHi = pairHi(RP); // e.g. V6CLANG::D for DE

  // Scan forward for a consumer MOV Z, RPLo or MOV Z, RPHi.
  unsigned Steps = 0;
  for (auto J = std::next(I); J != E && Steps < kChainWindow; ++J) {
    if (J->isDebugInstr()) continue;
    ++Steps;

    // Detect consumer: MOV Z, RPLo or MOV Z, RPHi
    bool IsLoConsumer = J->getOpcode() == V6CLANG::MOVrr &&
                        TRI->regsOverlap(J->getOperand(1).getReg(), RPLo);
    bool IsHiConsumer = J->getOpcode() == V6CLANG::MOVrr &&
                        TRI->regsOverlap(J->getOperand(1).getReg(), RPHi);
    bool IsConsumer   = IsLoConsumer || IsHiConsumer;

    // Barrier: anything reading or writing either half stops the scan.
    bool Blocked = false;
    for (const MachineOperand &MO : J->operands()) {
      if (!MO.isReg() || !MO.getReg()) continue;
      Register Half = IsLoConsumer ? RPLo : RPHi;
      if (IsConsumer && MO.isUse() && &MO == &J->getOperand(1)) continue;
      if (TRI->regsOverlap(MO.getReg(), Half)) { Blocked = true; break; }
    }
    if (Blocked) break;

    if (IsConsumer) {
      Register Half  = IsLoConsumer ? RPLo : RPHi;
      uint8_t  Byte  = IsLoConsumer ? Lo   : Hi;
      Register Z     = J->getOperand(0).getReg();
      if (!isRegDeadAfter(MBB, J, Half, TRI)) break;

      // Emit MVI Z, Byte at the consumer's position.
      BuildMI(MBB, J, J->getDebugLoc(), TII.get(V6CLANG::MVIr), Z).addImm(Byte);
      J->eraseFromParent();
      // If the full RP is now dead at the LXI site, erase LXI too.
      if (isRegDeadAfter(MBB, I, RP, TRI)) {
        auto Next = std::next(I);
        ProducerMI.eraseFromParent();
        I = std::prev(Next);
      }
      Changed = true;
      break;
    }
  }
}
```

Helper functions `pairLo` / `pairHi` map a GR16 register to its half:

| RP    | Hi  | Lo  |
|-------|-----|-----|
| `BC`  | `B` | `C` |
| `DE`  | `D` | `E` |
| `HL`  | `H` | `L` |

These are already implicitly available via `TRI->getSubRegs` or can be
implemented as a small switch as is done in `V6ClangArgAllocator::halves`.

---

## Safety conditions

1. **Half-register not read between LXI and MOV** (except as the consumer's
   source): ensures the half still holds `Imm16`'s byte and is not a value
   computed by an intermediate instruction.
2. **Half-register not written between LXI and MOV**: ensures no intervening
   instruction overwrites the half before the consumer.
   (Conditions 1 and 2 together = the standard `ReadsHalf || ClobbersHalf`
   barrier that terminates the forward scan.)
3. **Half-register dead after the consumer MOV**: ensures no later use of the
   half register would observe the now-missing source (the MOV is erased).
4. **LXI immediate is a literal compile-time constant** (not an
   `MO_PATCH_IMM`-flagged O61 patched value): O61-patched LXIs have their
   immediate rewritten at runtime; the byte must not be extracted statically.

Condition 4 uses the same `isO61PatchedImm` guard already used in O88.

---

## Interaction with other passes

- **O88 (MVIr-producer)**: completely disjoint; O88 operates on `MVIr`,
  O92 on `LXIrp`.  No ordering dependency.
- **O55 `foldMviZeroToXraA`**: when `Byte == 0`, O92 would emit `MVI Z, 0`.
  If Z == A, `foldMviZeroToXraA` will subsequently replace it with `XRA A`
  (cheaper).  Run O92 before O55 in the pass ordering to allow this cascade.
  Alternatively, special-case `Byte == 0 && Z == A` inline and emit `XRA A`
  directly, skipping the MVI altogether.
- **O82 `eliminateDeadMVI`**: if LXI is erased (full RP now dead), subsequent
  dead MVIs from the same block are handled by the existing dead-MVI pass.
- **O89 rewrite-producer**: O92 handles `LXIrp` producers; O89 handles
  `MOVrr` producers where Y was clobbered.  These are orthogonal.

---

## Expected output after O92

```asm
; p2_nonzero_lo — return lo(0xB4FF) = 0xFF, after XOR sink
p2_nonzero_lo:
    LXI  D, 0xb4ff
    MOV  A, L
    XRA  E
    MOV  L, A
    MOV  A, H
    XRA  D
    MOV  H, A
    SHLD g_sink16
    MVI  A, 0xFF       ← was: MOV A, E
    RET

; p3_nonzero_hi — return hi(0xB4FF) = 0xB4, after XOR sink
p3_nonzero_hi:
    LXI  D, 0xb4ff
    MOV  A, L
    XRA  E
    MOV  L, A
    MOV  A, H
    XRA  D
    MOV  H, A
    SHLD g_sink16
    MVI  A, 0xB4       ← was: MOV A, D
    RET
```

(LXI DE survives because D and E are still read by the XOR body; only the
trailing `MOV A, E` / `MOV A, D` consumers are removed.)

---

## When to implement

After O91 is complete.  O92 is isolated from O91 and can be done in parallel,
but O91 has higher expected frequency in the benchmark suite and should be
prioritised first.

---

## Test plan

1. **C reproducer**: `temp/test_lxi_nonzero.c` (created 2026-06-01).
   - `p2_nonzero_lo`: `MOV A, E` → `MVI A, 0xFF`
   - `p3_nonzero_hi`: `MOV A, D` → `MVI A, 0xB4`

2. **Lit test**: `llvm-project/llvm/test/CodeGen/V6Clang/peephole-lxi-half-mov-collapse.ll`
   — at minimum two IR test cases:
   - i16 constant used in XOR + lo byte extracted separately
   - i16 constant used in XOR + hi byte extracted separately
   — with `; CHECK:` for `MVI A, 0xFF` / `MVI A, 0xB4`
   — and `; DISABLED:` for `MOV A, E` / `MOV A, D`

3. **Benchmark**: run `python tests/benchmarks_c/run_benchmarks.py` before and
   after; expect no regression.
