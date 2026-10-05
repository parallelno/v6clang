# Plan: O93 — V6CLANG_AND16_IMM / V6CLANG_OR16_IMM / V6CLANG_XOR16_IMM (Immediate Bitwise 16)

> Feature description: `design\future_plans\O93_bitwise16_immediate_pseudos.md`
> Pipeline: `design\pipeline_feature.md`

## 1. Problem

### Current behavior

A 16-bit bitwise op against a **compile-time constant** is lowered as a
register/register `V6CLANG_AND16` / `V6CLANG_OR16` / `V6CLANG_XOR16`. ISel must first
materialise the constant into a scratch register **pair** with `LXI`, then run
the 6-instruction pair-wise sequence.

Example — `lfsr ^= 0xb400` from `tests/benchmarks_c/asm/v6clang_lfsr16_O2.s`:

```asm
LXI   B, 0xb400        ; 12cc  3B   materialise constant into BC
;--- V6CLANG_XOR16 ---
MOV   A, L             ;  8cc  1B
XRA   C                ;  4cc  1B
MOV   C, A             ;  8cc  1B
MOV   A, H             ;  8cc  1B
XRA   B                ;  4cc  1B
MOV   B, A             ;  8cc  1B
; op = 40cc / 6B + 12cc/3B LXI = 52cc total, ties up a whole pair (BC)
```

### Desired behavior

```asm
;--- V6CLANG_XOR16_IMM  (dst = src ^ 0xb400) ---
MVI   A, 0x00          ; lo byte of constant   (folded away — XOR identity)
XRA   L
MOV   L, A
MVI   A, 0xb4          ;  8cc  2B   hi byte of constant
XRA   H                ;  4cc  1B
MOV   H, A             ;  8cc  1B
; NO LXI, NO scratch pair. With lo-byte 0x00 folding: 20cc / 4B (52 → 20)
```

No constant pair is materialised → **no extra register pair consumed**, so the
spill/reload that the `LXI` provoked in the hot loop disappears.

### Root cause / the commutativity trick

The naïve immediate lowering `MOV A,reg; <op>I imm; MOV reg,A` uses the 8cc
immediate ALU forms (`ANI`/`ORI`/`XRI`) → `8+8+8 = 24cc`/byte, *worse* than the
reg/reg `8+4+8 = 20cc`. The win comes from loading the **constant** into `A` and
applying the cheaper **4cc register ALU** form against the source register:

```
MVI A, imm_byte   ; 8cc   (constant → A)
XRA reg_byte      ; 4cc   (register operand, NOT immediate)
MOV reg_byte, A   ; 8cc
```

Legal only because AND/OR/XOR are **commutative**:
`A & r == r & A`, `A | r == r | A`, `A ^ r == r ^ A`. `CMP` is excluded
(`A - r ≠ r - A`, ordered flags) — out of scope.

---

## 2. Strategy

### Approach: three `_IMM` pseudos with constant-in-A expansion + per-byte folding

1. Add `V6CLANG_AND16_IMM` / `V6CLANG_OR16_IMM` / `V6CLANG_XOR16_IMM`, each
   `(outs GR16:$dst), (ins GR16:$src, i16imm:$imm)`, `Defs = [A, FLAGS]`,
   `Constraints = "$dst = $src"`, with ISel patterns
   `(and/or/xor GR16:$src, imm:$imm)` and higher `AddedComplexity` than the
   reg/reg defs so a constant RHS prefers the `_IMM` form.
2. Expand in `expandPostRAPseudo` (sibling to the existing
   `V6CLANG_AND16/OR16/XOR16` case) using the constant-in-A shape, with per-byte
   specialisation:

   | Op  | Byte == 0x00            | Byte == 0xFF        | else                          |
   |-----|-------------------------|---------------------|-------------------------------|
   | AND | `MVI reg,0`             | identity — skip      | `MVI A,b; ANA reg; MOV reg,A` |
   | OR  | identity — skip         | `MVI reg,0xFF`      | `MVI A,b; ORA reg; MOV reg,A` |
   | XOR | identity — skip         | (generic)            | `MVI A,b; XRA reg; MOV reg,A` |

   - XOR `0x00`, OR `0x00`, AND `0xFF` are identities → emit nothing for byte.
   - AND `0x00` → `MVI reg,0`; OR `0xFF` → `MVI reg,0xFF`.
   - Hi byte additionally folded away when `DstHi` is dead (reuse O89
     `isRegDeadAfter`).

### Why this works

Constant operands of 16-bit bitwise ops are common (masks, flag toggles, LFSR
taps) and currently pay full `LXI` + reg-pair cost. Removing the scratch pair is
the dominant win — it directly relieves the RA pressure that drives spills in
tight loops. The constant-in-A trick keeps per-byte cost at the cheaper 20cc,
and per-byte identity folding frequently makes one or both bytes free.

### Summary of changes

| File | Change |
|------|--------|
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td` | 3 new `_IMM` pseudos + ISel patterns |
| `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.cpp` | New `expandPostRAPseudo` case: constant-in-A expansion + per-byte folding + dead-hi guard |
| `llvm-project/llvm/test/CodeGen/V6Clang/bitwise16-imm.ll` | New lit test |
| `tests/features/77/` | Feature test: C source, baseline, new asm, result.txt |
| `design/future_plans/O93_bitwise16_immediate_pseudos.md` | Mark complete |
| `design/future_plans/README.md` | ✅ O93 |

---

## 3. Implementation Steps

### Step 3.1 — Add `_IMM` pseudos + patterns in V6ClangInstrInfo.td [x]

In the `let Defs = [A, FLAGS]` block that holds `V6CLANG_AND16/OR16/XOR16`, add the
three immediate siblings with `Constraints = "$dst = $src"` and an
`AddedComplexity` high enough to beat the reg/reg pattern for a constant RHS.
Patterns: `(set i16:$dst, (and i16:$src, imm:$imm))` etc.

> **Design Notes**: The existing reg/reg pattern `(and i16:$lhs, i16:$rhs)` also
> matches a constant RHS, so the `_IMM` pattern needs greater complexity to win.
> Confirm reg/reg still matches for non-constant RHS. O90 (pre-ISel) narrows
> `C ≤ 0xFF` *zero-test-only* bitwise ops to i8 before ISel, so a surviving i16
> bitwise-with-constant at ISel is the correct owner for `_IMM`.

> **Implementation Notes**:

### Step 3.2 — Expansion in V6ClangInstrInfo.cpp [x]

Add a case next to `V6CLANG_AND16/OR16/XOR16`. Reuse `DstLo/DstHi/SrcLo/SrcHi`
sub-register extraction. Read the constant via `MI.getOperand(2).getImm()`,
split into `Lo = Imm & 0xFF`, `Hi = (Imm >> 8) & 0xFF`. Pick `OpOpc`
(`ANAr`/`ORAr`/`XRAr`). For each byte apply the §2 folding table; emit the
`MVI A,b; <op> reg; MOV reg,A` triple only in the generic case. Guard the hi
byte with `bool HiDead = isRegDeadAfter(MBB, MI.getIterator(), DstHi, &RI)`.

> **Design Notes**: A factored helper `emitBitwiseImmByte(MBB, MI, DL, Opcode,
> OpOpc, ByteVal, DstByte, SrcByte)` keeps lo/hi paths identical. The pseudo's
> `Defs=[A,FLAGS]` over-approximates on all-identity paths — safe. Ensure the
> all-identity case (e.g. `x ^ 0`) still erases the pseudo and leaves `$dst=$src`
> as a no-op (no MOV needed since they coalesce).

> **Implementation Notes**: Added a sibling `expandPostRAPseudo` case with an
> `emitByte` lambda applying the §2 folding table per byte; hi byte guarded by
> `isRegDeadAfter(DstHi)`. Two edit slips during insertion (dropped the
> reg/reg `MOV DstHi,A` line and the `CMP16_ZERO` case label) were caught by
> the compiler and fixed.

### Step 3.3 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: `[4/4] Linking CXX executable bin\clang.exe` —
> clean after the two syntax fixes.

### Step 3.4 — Lit test: bitwise16-imm.ll [x]

Create `llvm-project/llvm/test/CodeGen/V6Clang/bitwise16-imm.ll`. Per op:
- generic constant (both bytes non-trivial) → `MVI A,lo; <op> reglo; MOV reglo,A; MVI A,hi; <op> reghi; MOV reghi,A`, **no `LXI`**.
- XOR/OR `0x00` byte → that byte's triple absent.
- AND `0xFF` byte absent; AND `0x00` byte → `MVI reg,0`.
- OR `0xFF` byte → `MVI reg,0xFF`.
- dead-hi (`(u8)(x op C)`) → hi block absent.
- control: a narrowable zero-test case still emits `ANI/ORI/XRI` via O90, not `_IMM`.

> **Implementation Notes**: Created
> `llvm-project/llvm/test/CodeGen/V6Clang/bitwise16-imm.ll`. Discovered the
> dead-hi `(u8)(x ^ C)` case is narrowed by DAGCombiner straight to `XRI 0x3c`
> (i8 path) — strictly better than the `_IMM` expansion — and updated the
> expectation accordingly. LIT PASS.

### Step 3.5 — Run regression tests [x]

`python tests\run_all.py` (after `scripts\sync_llvm_mirror.ps1`). Verify the
`lfsr16` benchmark cc/size dropped and nothing regressed.

> **Implementation Notes**: All 3 suites PASS (golden / lit / benchmarks).
> `lfsr16` v6clang: 121 B → 90 B (−25.6%), 1,344,784 cc → 730,452 cc (−45.7%);
> speedup vs c8080 1.95x → 3.59x. Two pre-existing lit tests required updates
> because O93 legitimately removes the scratch-pair spills they assumed:
> `type-narrow-bitwise-const.ll` (now lowers via `ANA` not `LXI`) and
> `peephole-mov-chain-y-clobbered.ll` (the LFSR no longer spills through the
> MOV chain; repurposed to pin the O93 pair-free lowering, with both
> peephole-on/off RUN lines passing).

### Step 3.6 — Verification assembly steps from `tests\features\README.md` [x]

Compile `tests/features/77/v6clang.c` → `v6clang_new01.asm`, confirm removed
`LXI` + removed spill/reload, iterate if needed.

> **Implementation Notes**: `v6clang_new01.asm` confirms: `xor16_const` 6 insns
> no LXI; `xor16_hi_only` → `MVI A,0xb4; XRA H; MOV H,A` (lo 0x00 folded);
> `or16_lo_only` → `MVI A,0x80; ORA L; MOV L,A`; `and16_clear_lo` → single
> `MVI L, 0`; `and16_mask` 6 insns no LXI; `or16_set_all` → `LXI H,0xffff`
> (DAGCombiner const-fold, control). `lfsr_run` hot loop tap → `MVI A,0xb4;
> XRA H; MOV H,A` (20cc, no pair) and the BC shadow-register shuffles are gone.

### Step 3.7 — Make sure result.txt is created [x]

Per `tests\features\result.md`: C source, c8080 asm (main+deps, i8080), c8080
stats, v6clang old asm, v6clang new asm, comparison table (cc + bytes/function).

> **Implementation Notes**: Created `tests/features/77/result.txt` with C
> source, c8080 helper-based reference, v6clang old/new asm, per-function
> comparison table, and the whole-program lfsr16 benchmark delta.

### Step 3.8 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror synced; `tests/lit/` and the git-tracked
> `llvm/lib/Target/V6Clang/` mirror updated to match `llvm-project/`.

---

## 4. Expected Results

### Example 1 — LFSR tap (`lfsr ^= 0xb400`)

Hot-loop `V6CLANG_XOR16` against a constant drops from `LXI B,0xb400` + 6-insn
XOR16 (52cc, ties up BC) to a 2-insn hi-byte-only `MVI A,0xb4; XRA H; MOV H,A`
(lo byte `0x00` folded) = 20cc / 4B, **no scratch pair**, eliminating the
surrounding spill/reload.

### Example 2 — Mask set (`flags |= 0x0080`)

`V6CLANG_OR16_IMM` with lo `0x80`, hi `0x00`: hi byte is OR-identity → only
`MVI A,0x80; ORA L; MOV L,A` (20cc) instead of `LXI` + full OR16.

### Example 3 — Bit clear (`x &= 0xFF00`)

`V6CLANG_AND16_IMM` with lo `0x00` (→ `MVI L,0`) and hi `0xFF` (AND-identity, skip):
collapses to a single `MVI L,0` instead of `LXI` + full AND16.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `_IMM` pattern steals narrowable zero-test cases from O90 | O90 runs pre-ISel and rewrites the node; only un-narrowed i16 constants reach `_IMM`. Add lit control case asserting `ANI/ORI/XRI` still emitted for zero-test narrowing. |
| reg/reg pattern stops matching after adding `_IMM` | Higher `AddedComplexity` only changes preference for constant RHS; lit test covers a register-RHS case still emitting reg/reg `V6CLANG_*16`. |
| Code-size regression when constant reused in loop with free pair | First cut emits `_IMM` unconditionally; pressure dominates on V6CLANG. Revisit a cost heuristic only if a benchmark regresses on size. |
| AND `0x00` byte hand-rolled as `XRA reg` clobbers wrong reg | Always emit `MVI reg,0` (8cc/2B); leave A-zeroing folds to O55. |
| All-identity expansion leaves dangling pseudo | Explicitly erase pseudo; `$dst=$src` coalescing makes it a no-op. |
| Patched-imm (O61) interaction | `MVI A,imm` here carry no `MO_PATCH_IMM` flag; later passes treat normally. |

---

## 6. Relationship to Other Improvements

- **O89** (dead-hi-byte elision in reg/reg bitwise16): this plan reuses the same
  `isRegDeadAfter` hi-byte guard and generalises its expansion skeleton.
- **O90** (pre-ISel i8 narrowing): complementary — O90 owns `C ≤ 0xFF`
  zero-test-only cases; O93 owns full-width constants / register-persistent
  results.
- **O55** (`MVI A,0 → XRA A`): may further fold an AND-`0x00` accumulator zero.
- **O79** (`MVI; ALU reg → ALU imm` fold): must NOT collapse the deliberate
  `MVI A,b; <op> reg` constant-in-A pair (that is the whole optimization).

## 7. Future Enhancements

- `V6CLANG_CMP16_IMM` (EQ/NE-only) using byte-wise compare with borrow — separate
  plan (commutativity trick unavailable).
- Cost heuristic to keep a loop-hoisted `LXI` + reg/reg form when a pair is
  provably free and the constant is reused ≥ 2×.

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\V6ClangInstructionTimings.md)
* [Future Improvements](design\future_plans\README.md)
* [Feature description O93](design\future_plans\O93_bitwise16_immediate_pseudos.md)
