# O20. Honest Store/Load Pseudo Defs (Remove False HL Clobber)

*Discovered via comparison analysis: `temp/compare/06/` — single-pointer
store loop generates unnecessary DE→HL copy every iteration.*

## Problem

`V6CLANG_STORE8_P` and `V6CLANG_LOAD8_P` are defined with `Defs = [HL]`,
telling the register allocator that HL is always clobbered:

```tablegen
let mayStore = 1, Defs = [HL] in
def V6CLANG_STORE8_P : V6ClangPseudo<(outs), (ins GR8:$src, GR16:$addr), ...>;

let mayLoad = 1, Defs = [HL] in
def V6CLANG_LOAD8_P : V6ClangPseudo<(outs GR8:$dst), (ins GR16:$addr), ...>;
```

The RA sees `Defs = [HL]` and avoids allocating HL for a pointer that
must survive past the store/load. It puts the pointer in DE/BC instead.
Then the post-RA expansion copies DE→HL before the actual MOV M/MOV r,M.

**Irony**: When addr IS HL, the expansion emits just `MOV M, r` — HL is
NOT clobbered. But the RA can't know this; `Defs` is unconditional.

### Example: single-pointer store loop

**Source** (`temp/compare/06/v6clang.c`):
```c
uint8_t v = 42;
for (int i = 0; i < LEN; ++i)
    array1[i] = v + i;
```

**Current output** (52cc/iter):
```asm
    LXI  DE, array1
    MVI  C, 0x2a
.loop:
    MOV  H, D       ;  8cc  ← unnecessary copy
    MOV  L, E       ;  8cc  ← unnecessary copy
    MOV  M, C       ;  7cc
    INX  DE          ;  6cc
    INR  C           ;  4cc
    MVI  A, <(array1+100)  ;  7cc
    CMP  E           ;  4cc
    JNZ  .loop       ; 12cc  (+ high-byte check omitted)
```

**Expected output** (38cc/iter, −27%):
```asm
    LXI  HL, array1
    MVI  C, 0x2a
.loop:
    MOV  M, C       ;  7cc
    INX  HL          ;  6cc
    INR  C           ;  4cc
    MVI  A, <(array1+100)  ;  7cc
    CMP  L           ;  4cc
    JNZ  .loop       ; 12cc  (+ high-byte check)
```

## Solution

Remove `Defs = [HL]` from both pseudos and make the expansion **preserve
HL in every code path**. The RA then freely allocates HL for pointers
(cheapest path), while DE/BC remain available as safe fallbacks.

### TableGen changes

```tablegen
// Remove Defs = [HL]
let mayStore = 1 in
def V6CLANG_STORE8_P : V6ClangPseudo<(outs), (ins GR8:$src, GR16:$addr), ...>;

let mayLoad = 1 in
def V6CLANG_LOAD8_P : V6ClangPseudo<(outs GR8:$dst), (ins GR16:$addr), ...>;
```

### Expansion priority chain — V6CLANG_STORE8_P

In `V6ClangInstrInfo.cpp` `expandPostRAPseudo()`:

| Priority | Condition | Emitted code | Cost | HL preserved? |
|----------|-----------|-------------|------|---------------|
| 1 | addr=HL | `MOV M, src` | 7cc | ✓ (addr=HL, no copy) |
| 2 | src=A, addr=BC\|DE | `STAX addr` | 7cc | ✓ (no HL touch) |
| 3 | addr=BC\|DE, A dead | `MOV A, src; STAX addr` | 12cc | ✓ (no HL touch) |
| 4 | addr=BC\|DE, A live | `PUSH HL; MOV H,hi; MOV L,lo; MOV M,src; POP HL` | 43cc | ✓ (PUSH/POP) |

Pseudocode:
```cpp
case V6CLANG::V6CLANG_STORE8_P: {
  Register SrcReg = MI.getOperand(0).getReg();
  Register AddrReg = MI.getOperand(1).getReg();

  if (AddrReg == V6CLANG::HL) {
    // Priority 1: addr is HL — just store
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVMr)).addReg(SrcReg);
  } else if (SrcReg == V6CLANG::A &&
             (AddrReg == V6CLANG::BC || AddrReg == V6CLANG::DE)) {
    // Priority 2: STAX — src already in A
    BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
        .addReg(SrcReg).addReg(AddrReg);
  } else if ((AddrReg == V6CLANG::BC || AddrReg == V6CLANG::DE) &&
             isRegDeadAt(V6CLANG::A, MI, MBB)) {
    // Priority 3: route through A for STAX — A is dead
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
        .addReg(V6CLANG::A, RegState::Define).addReg(SrcReg);
    BuildMI(MBB, MI, DL, get(V6CLANG::STAX))
        .addReg(V6CLANG::A).addReg(AddrReg);
  } else {
    // Priority 4: fallback — save/restore HL
    BuildMI(MBB, MI, DL, get(V6CLANG::PUSH)).addReg(V6CLANG::HL);
    MCRegister Hi = RI.getSubReg(AddrReg, V6CLANG::sub_hi);
    MCRegister Lo = RI.getSubReg(AddrReg, V6CLANG::sub_lo);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
        .addReg(V6CLANG::H, RegState::Define).addReg(Hi);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVrr))
        .addReg(V6CLANG::L, RegState::Define).addReg(Lo);
    BuildMI(MBB, MI, DL, get(V6CLANG::MOVMr)).addReg(SrcReg);
    BuildMI(MBB, MI, DL, get(V6CLANG::POP))
        .addDef(V6CLANG::HL);
  }
  MI.eraseFromParent();
  return true;
}
```

### Expansion priority chain — V6CLANG_LOAD8_P

| Priority | Condition | Emitted code | Cost | HL preserved? |
|----------|-----------|-------------|------|---------------|
| 1 | addr=HL | `MOV dst, M` | 7cc | ✓ |
| 2 | dst=A, addr=BC\|DE | `LDAX addr` | 7cc | ✓ |
| 3 | addr=BC\|DE, A dead | `LDAX addr; MOV dst, A` | 12cc | ✓ |
| 4 | addr=BC\|DE, A live | `PUSH HL; MOV H,hi; MOV L,lo; MOV dst,M; POP HL` | 43cc | ✓ |

### Liveness helper

Add `isRegDeadAt(Register Reg, MachineInstr &MI, MachineBasicBlock &MBB)`:
- Forward-scan from MI to end of MBB for uses/defs of Reg
- If next reference is a def (or no reference + not in successor liveins) → dead
- If next reference is a use → live

Similar logic already exists in `V6ClangXchgOpt::isRegDeadAfter()` — can be
extracted to a shared utility or duplicated.

## Files to modify

1. **`V6ClangInstrInfo.td`** — Remove `Defs = [HL]` from V6CLANG_STORE8_P and V6CLANG_LOAD8_P
2. **`V6ClangInstrInfo.cpp`** — Rewrite expandPostRAPseudo cases with priority chains
3. **No ISel changes** — GR16 address operand stays, RA gets honest Defs info

## Impact on existing patterns

### Memcpy pattern (temp/compare/03) — no regression
Two pointers needed. RA puts one in HL (store), one in BC/DE (load).
Load path: `LDAX BC` (priority 2, dst=A). Store path: `MOV M, A` → but
addr=HL and we got A from LDAX, so we use `STAX`? No — addr IS HL, so
priority 1 fires: `MOV M, A`. Result:
```asm
LXI  HL, array2    ; dst in HL
LXI  BC, array1    ; src in BC
.loop:
  LDAX BC           ; 7cc — priority 2 (dst=A, addr=BC)
  MOV  M, A         ; 7cc — priority 1 (addr=HL)
  INX  HL
  INX  BC
```
Same 14cc/iter as current LDAX+STAX. Identical quality.

### Single-pointer store loop (temp/compare/06) — fixed
RA puts pointer in HL (no clobber), emits `MOV M, C` directly.
38cc/iter vs 52cc/iter. **27% faster, 2B smaller per iteration.**

### HL busy + store through DE/BC + src=A — identical
STAX fires (priority 2). Same as current code.

### HL busy + store through DE/BC + src≠A + A dead — new path
`MOV A, src; STAX addr` (12cc). Currently emits `MOV H,D; MOV L,E;
MOV M,src` (23cc). **11cc savings.**

### HL busy + store through DE/BC + src≠A + A live — rare worst case
PUSH/POP HL (43cc). Currently emits plain copy (23cc). **20cc worse.**
Only triggers when HL is genuinely occupied AND A is live AND src is not A.
This is rare — A is typically dead at store sites because it's clobbered
by ALU ops and comparisons.

## Benefit

- **Primary**: Eliminates DE→HL copy in single-pointer loops (−14cc, −2B/iter)
- **Secondary**: STAX-via-A path saves 11cc when A is dead
- **Tertiary**: RA gets more accurate info → better global allocation decisions

## Complexity

Medium. The expansion rewrite is ~40 lines per pseudo. The liveness helper
is ~15 lines (or reuse existing). TableGen change is 2 lines.

Total: ~100 lines changed.

## Risk

Low-Medium.
- Removing `Defs = [HL]` is semantically correct — HL IS preserved in all paths
- The PUSH/POP fallback guarantees correctness even in worst-case allocation
- The rare worst case (43cc vs 23cc) only fires under unusual register pressure
- Must validate with `-verify-machineinstrs` and full test suite

## Testing

1. Recompile `temp/compare/06/v6clang.c` — verify HL allocation and no DE→HL copy
2. Recompile `temp/compare/03/v6clang2.c` — verify memcpy quality unchanged
3. Full lit test suite (all CodeGen tests)
4. Full golden test suite (15 programs)
5. `-verify-machineinstrs` sweep on all tests
6. New lit test: `store-load-honest-defs.ll` with both patterns

## Dependencies

None. Independent of all other optimizations.
