# Plan: O84 — INX/DCX-Through-Spill Round-Trip Fold

## 1. Problem

### Current behavior

After the O83 POP/PUSH pair elimination, a 6-instruction sequence is exposed
in the sieve benchmark that computes `SHLD addr` with `HL = HL ± 1`:

```asm
; From tests/features/64/v6clang_new01.asm after O83 — block .LLo61_12:
LHLD  .LLo61_12+1        ; load HL from spill slot
MOV   C, L               ; save HL into BC
MOV   B, H               ;   (spill round-trip preamble)
INX   B                  ; BC++  (the actual increment)
MOV   L, C               ; restore L from BC
MOV   H, B               ; restore H from BC
SHLD  .LLo61_12+1        ; write HL back to spill slot
```

The four MOV instructions are pure round-trip overhead: they copy HL into BC,
increment BC, then copy BC back into HL.  The entire sequence is equivalent to
`INX H / SHLD`, and BC is dead after the SHLD (it is reloaded at the next
loop iteration).

A second secondary pattern (Pattern B) also appears — a complete round-trip
with no INX/DCX at all (the copy is a no-op):

```asm
; .LLo61_10 slot (spill of i_sq, no increment):
MOV   B, H               ; save HL into BC
MOV   C, L               ;   (rh first, rl second)
MOV   L, C               ; restore L — no-op
MOV   H, B               ; restore H — no-op
SHLD  .LLo61_10+1
```

Here BC is also dead after SHLD; the four MOVs can be dropped entirely.

### Root cause

The 6-instruction sequence originates from three consecutive pseudos that are
lowered separately and whose interaction the peephole never inspected:

```
V6CLANG_RELOAD16  rp, slot   → LHLD slot    (or MOV B,H / MOV C,L)
V6CLANG_INX16 / V6CLANG_DCX16    → (INX|DCX) rp
V6CLANG_SPILL16   hl, slot   → MOV rl,L / MOV rh,H / (INX|DCX) rp /
                             MOV L,rl / MOV H,rh / SHLD slot
```

Before O83, a POP/PUSH pair surrounded the INX, masking this pattern from
view.  O83 removes those POP/PUSH pairs, leaving the 6-instruction window
visible.

---

## 2. Strategy

### Approach: New `foldInxDcxSpillRoundTrip()` method in `V6ClangPeephole`

Add a forward-scan method to `V6ClangPeephole`.  The scan is O(n) per MBB and
operates directly on the 6- (or 5-) instruction sequence already in the MBB.

**Pattern A — INX/DCX round-trip (6 instructions)**:

```
I0: MOV rl, L    rl ∈ {C, E}
I1: MOV rh, H    rh paired with rl: C→B, E→D
I2: INX rp  or  DCX rp    rp = BC or DE
I3: MOV L, rl
I4: MOV H, rh
I5: SHLD addr
```

Preconditions:
1. `rp` is dead after I5 (via `isRegDeadAfter`).
2. No instruction in I0..I4 is an O61 patched-imm site.

Replace:
- Insert `INX H` (or `DCX H`) immediately before I5.
- Erase I0, I1, I2, I3, I4.
- I5 (SHLD) is preserved unchanged.

**Pattern B — round-trip copy without INX/DCX (5 instructions)**:

```
J0: MOV rh, H    rh ∈ {B, D}
J1: MOV rl, L    rl paired with rh: B→C, D→E
J2: MOV L, rl
J3: MOV H, rh
J4: SHLD addr
```

Preconditions:
1. `rp` is dead after J4.
2. No instruction in J0..J3 is an O61 patched-imm site.

Replace:
- Erase J0, J1, J2, J3.
- J4 (SHLD) is preserved unchanged.

### Correctness argument

- **INX/DCX on 8080 do not affect FLAGS.**  Even if FLAGS are live after SHLD,
  replacing `INX BC` with `INX H` is safe: no flag state changes.
- **rp dead after SHLD**: the four MOV instructions are the only writers of
  `rp` in this window.  If `rp` is not read after I5, erasing the window is
  safe.
- **HL is the SHLD source**: SHLD reads HL implicitly.  By the time we insert
  `INX H` before SHLD, HL contains the post-increment value.
- **O61 symbol preservation**: SHLD carries the `.LLo61_N+1` patched-imm
  symbol on its own instruction (as an operand target flag or pre-instr
  symbol).  We never erase SHLD, only the four preceding MOVs.  The symbol
  is safe.

### Summary of changes

| File | Change |
|------|--------|
| `V6ClangPeephole.cpp` | Add `DisableInxDcxSpillFold` flag, `foldInxDcxSpillRoundTrip()` method, call site after `eliminateDeadPopPush()` |
| `tests/lit/CodeGen/V6Clang/peephole-inx-dcx-spill-fold.ll` | New lit test covering Pattern A (INX, DCX, BC pair, DE pair), Pattern B, disabled-flag case |

---

## 3. Implementation Steps

### Step 3.1 — Create test folder and baseline assembly [ ]

Create `tests/features/65/` with `v6clang.c`, `c8080.c`, and baseline
assembly.  The sieve C source is copied from `tests/features/64/` (same
kernel, same test).

### Step 3.2 — Add `DisableInxDcxSpillFold` cl::opt [ ]

In `V6ClangPeephole.cpp`, after `DisablePopPushElim`:

```cpp
static cl::opt<bool> DisableInxDcxSpillFold(
    "v6clang-disable-inx-dcx-spill-fold",
    cl::desc("Disable INX/DCX-through-spill round-trip fold (O84)"),
    cl::init(false), cl::Hidden);
```

### Step 3.3 — Declare method in class [ ]

Add to the `V6ClangPeephole` private section:

```cpp
bool foldInxDcxSpillRoundTrip(MachineBasicBlock &MBB);
```

### Step 3.4 — Implement `foldInxDcxSpillRoundTrip()` [ ]

Implement at the bottom of `V6ClangPeephole.cpp`, before
`runOnMachineFunction()`.  The method uses `isRegDeadAfter()` and
`BuildMI` to insert `INX H` / `DCX H`.  Full pseudocode:

```
for each I in MBB:

  // ── Pattern A (INX/DCX round-trip) ──────────────────────────────────
  if I is MOVrr and src==L:
    Rl = dst
    if Rl not in {C, E}: continue
    Rh = (Rl==C ? B : D);  Rp = (Rl==C ? BC : DE)
    I1 = next non-debug after I
    if I1 is not MOVrr(dst=Rh, src=H): continue
    I2 = next after I1
    if I2 is not (INX or DCX) with dst==Rp: continue
    IsInx = (I2.opcode == INX)
    I3 = next after I2
    if I3 is not MOVrr(dst=L, src=Rl): continue
    I4 = next after I3
    if I4 is not MOVrr(dst=H, src=Rh): continue
    I5 = next after I4
    if I5 is not SHLD: continue
    if not isRegDeadAfter(MBB, I5, Rp, TRI): continue
    // Emit INX H or DCX H before SHLD
    BuildMI(MBB, I5, ..., IsInx ? INX : DCX)
      .addReg(HL, Define).addReg(HL)
    // Erase I4..I0 in reverse order; advance I past I0
    erase I4, I3, I2, I1
    I = erase(I)   // advances to I5
    Changed = true; continue

  // ── Pattern B (round-trip copy, no INX/DCX) ─────────────────────────
  if I is MOVrr and src==H:
    Rh = dst
    if Rh not in {B, D}: continue
    Rl = (Rh==B ? C : E);  Rp = (Rh==B ? BC : DE)
    J1 = next after I
    if J1 is not MOVrr(dst=L... wait, src=L, dst=Rl):
      // actually J1 should be MOV rl, L
    if J1 is not MOVrr(dst=Rl, src=L): continue
    J2 = next after J1
    if J2 is not MOVrr(dst=L, src=Rl): continue
    J3 = next after J2
    if J3 is not MOVrr(dst=H, src=Rh): continue
    J4 = next after J3
    if J4 is not SHLD: continue
    if not isRegDeadAfter(MBB, J4, Rp, TRI): continue
    // Erase J3..J0; advance I past J0
    erase J3, J2, J1
    I = erase(I)   // advances to J4
    Changed = true; continue
```

### Step 3.5 — Add call site in `runOnMachineFunction()` [ ]

Directly after `eliminateDeadPopPush(MBB)`:

```cpp
Changed |= foldInxDcxSpillRoundTrip(MBB);  // O84: must follow O83
```

### Step 3.6 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

### Step 3.7 — Create lit test `tests/lit/CodeGen/V6Clang/peephole-inx-dcx-spill-fold.ll` [ ]

Cases to cover:
- Pattern A (INX): BC pair, `SHLD addr` — verify 4 MOVs gone, `INX H` present.
- Pattern A (DCX): BC pair — verify `DCX H`.
- Pattern A with DE pair.
- Pattern B: round-trip copy — verify 4 MOVs gone, SHLD preserved.
- Negative: rp not dead after SHLD — verify pattern not applied.
- Disabled flag (`-v6clang-disable-inx-dcx-spill-fold`) — verify pattern not applied.

### Step 3.8 — Run regression tests [ ]

```
cd llvm-build && ctest -R V6CLANG --output-on-failure
```

### Step 3.9 — Compile new ASM and create result.txt [ ]

Compile the sieve with the new compiler, diff against old, capture result in
`tests/features/65/result.txt`.

### Step 3.10 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```
