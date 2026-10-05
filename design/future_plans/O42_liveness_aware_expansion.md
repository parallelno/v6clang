# O42. Liveness-Aware Pseudo Expansion (Skip PUSH/POP When Dead)

*Identified during investigation of suboptimal codegen for two-array*
*summation loop (`sum += arr1[i] + arr2[i]`). The RA correctly spills*
*the partial sum with `killed $hl`, making HL dead at the next RELOAD16-BC.*
*But the expansion unconditionally emits `PUSH HL; ...; POP HL` to preserve*
*a register that is already dead. Same pattern appears in SPILL, RELOAD,*
*LOAD16_P, LOAD16_G, STORE16_P, LOAD8_P, and STORE8_P expansions.*

## Problem

Many pseudo expansions need HL (or DE) as a scratch register for addressing.
To preserve the caller's value, they wrap the addressing in PUSH/POP:

```asm
; RELOAD16 BC (static stack, current):
PUSH HL           ; 1B 11cc  ← unnecessary if HL dead
LXI  HL, addr     ; 3B 10cc
MOV  C, M         ; 1B  7cc
INX  HL           ; 1B  5cc
MOV  B, M         ; 1B  7cc
POP  HL           ; 1B 10cc  ← unnecessary if HL dead
                  ; total: 8B 50cc
```

When the RA marks the source register as `killed` on the preceding SPILL
(or the pseudo's input operand is dead), the preserved register is dead at
the expansion point. The PUSH/POP is wasted.

### Scope of affected expansions

#### `eliminateFrameIndex` (V6ClangRegisterInfo.cpp) — static stack

| Line | Pseudo | Preserves | Current | If dead |
|------|--------|-----------|---------|---------|
| 117 | SPILL8 (H/L src) | DE | PUSH DE; MOV D,src; MOV E,other; LXI; DAD SP; MOV M,D; restore; POP DE | Skip PUSH DE ... POP DE |
| 134 | SPILL8 (other src) | HL | PUSH HL; LXI; MOV M,r; POP HL | LXI; MOV M,r (skip PUSH/POP) |
| 157 | RELOAD8 (H/L dst) | DE | PUSH DE; MOV D,other; LXI; DAD SP; MOV dst,M; restore; POP DE | Skip PUSH DE ... POP DE |
| 170 | RELOAD8 (other dst) | HL | PUSH HL; LXI; MOV r,M; POP HL | LXI; MOV r,M (skip PUSH/POP) |
| 202 | **SPILL16 (BC)** | HL | PUSH HL; LXI; MOV M,C; INX; MOV M,B; POP HL | MOV L,C; MOV H,B; SHLD addr (5B 26cc vs 8B 50cc) |
| 233 | **RELOAD16 (BC)** | HL | PUSH HL; LXI; MOV C,M; INX; MOV B,M; POP HL | LHLD addr; MOV C,L; MOV B,H (5B 26cc vs 8B 50cc) |

#### `eliminateFrameIndex` (V6ClangRegisterInfo.cpp) — dynamic stack

| Line | Pseudo | Preserves | Current | If dead |
|------|--------|-----------|---------|---------|
| 282 | SPILL8 (H/L src) | DE | PUSH DE; ...; POP DE | Skip PUSH/POP |
| 298 | SPILL8 (other src) | HL | PUSH HL; LXI; DAD SP; MOV M,r; POP HL | Skip PUSH/POP |
| 322 | RELOAD8 (H/L dst) | DE | PUSH DE; ...; POP DE | Skip PUSH/POP |
| 336 | RELOAD8 (other dst) | HL | PUSH HL; LXI; DAD SP; MOV r,M; POP HL | Skip PUSH/POP |
| 356 | SPILL16 (HL) | DE | PUSH DE; MOV D,H; MOV E,L; LXI; DAD SP; store; POP DE | Skip PUSH/POP |
| 379 | SPILL16 (DE/BC) | HL | PUSH HL; LXI; DAD SP; store; POP HL | Skip PUSH/POP |
| 401 | RELOAD16 (HL) | DE | PUSH DE; LXI; DAD SP; load; copy; POP DE | Skip PUSH/POP |
| 419 | RELOAD16 (DE/BC) | HL | PUSH HL; LXI; DAD SP; load; POP HL | Skip PUSH/POP |

#### `expandPostRAPseudo` (V6ClangInstrInfo.cpp) — pseudo instructions

| Line | Pseudo | Preserves | When |
|------|--------|-----------|------|
| 1159 | **LOAD16_P (addr=BC)** | HL | Always |
| 1193 | STORE16_P (val=HL, addr=DE) | DE | Always |
| 1204 | STORE16_P (val=HL, addr=BC) | BC | Always |
| 1259 | **LOAD16_G (dst=BC)** | HL | Always |
| 1512 | LOAD8_P (priority 4) | HL | addr=BC/DE, A alive |
| 1550 | STORE8_P (priority 4) | HL | addr=BC/DE, A alive |

## Solution

### Approach: Liveness check at expansion time

At each expansion point, query whether the preserved register is dead
using `LiveRegUnits` backward scan. The backend already has helper
infrastructure for this:

- `isRegDeadAfter()` in V6ClangInstrInfo.cpp — used by ADD16 and peephole
- `isRegDeadAtMI()` in V6ClangInstrInfo.cpp — used by LOAD8_P/STORE8_P

Both compute local BB liveness by walking successors and scanning backward.
The same mechanism applies here.

### Implementation

#### 1. Add helper to V6ClangRegisterInfo

```cpp
/// Check if Reg is dead at the point just before II in MBB.
/// Uses backward LiveRegUnits scan from the end of MBB.
static bool isRegDeadBefore(MachineBasicBlock &MBB,
                            MachineBasicBlock::iterator II,
                            MCPhysReg Reg,
                            const TargetRegisterInfo *TRI) {
  LiveRegUnits LRU(*TRI);
  LRU.addLiveOuts(MBB);
  for (auto I = MBB.rbegin(), E = MBB.rend(); I != E; ++I) {
    if (&*I == &*II)
      return LRU.available(Reg);
    LRU.stepBackward(*I);
  }
  return false;
}
```

#### 2. Static stack SPILL16 BC (line 202) — HL dead

Replace:
```
PUSH HL; LXI HL,addr; MOV M,C; INX HL; MOV M,B; POP HL  (8B 50cc)
```
With:
```
MOV L,C; MOV H,B; SHLD addr                                (5B 26cc)
```
Savings: 3B, 24cc.

#### 3. Static stack RELOAD16 BC (line 233) — HL dead

Replace:
```
PUSH HL; LXI HL,addr; MOV C,M; INX HL; MOV B,M; POP HL  (8B 50cc)
```
With:
```
LHLD addr; MOV C,L; MOV B,H                                (5B 26cc)
```
Savings: 3B, 24cc.

#### 4. Static stack SPILL16 DE (line 190) — HL dead

The current `XCHG; SHLD; XCHG` path (when HL is live) becomes:
```
XCHG; SHLD addr                                             (4B 20cc)
```
When HL is dead, skip the trailing XCHG. (Note: current code already
does this when `IsKill==true` on DE. This extends to HL-dead case.)

#### 5. Static stack RELOAD16 DE (line 222) — HL dead

Replace `XCHG; LHLD; XCHG` with `LHLD addr; XCHG` (HL dead, so
don't need to restore HL to its original value — just swap into DE).
Savings: 1B, 4cc.

#### 6. LOAD16_P addr=BC (V6ClangInstrInfo.cpp line 1159) — HL dead

Replace:
```
PUSH HL; MOV H,B; MOV L,C; load; POP HL  (7B ~54cc)
```
With:
```
MOV H,B; MOV L,C; load                    (5B ~33cc)
```
Savings: 2B, 21cc.

#### 7. LOAD16_G dst=BC (V6ClangInstrInfo.cpp line 1259) — HL dead

Replace:
```
PUSH HL; LHLD addr; MOV B,H; MOV C,L; POP HL  (7B 47cc)
```
With:
```
LHLD addr; MOV B,H; MOV C,L                     (5B 26cc)
```
Savings: 2B, 21cc.

#### 8. Dynamic stack paths — same principle

For all dynamic stack PUSH/POP pairs at lines 282, 298, 322, 336, 356,
379, 401, 419: check liveness of the preserved register and skip the
PUSH/POP wrapper when dead. The DAD SP offset adjustment (`+2`) must
also be corrected to `+0` when the PUSH is skipped (since no value was
pushed onto the stack before DAD SP).

### Detailed expansion for dynamic stack cases

When HL is dead and we skip PUSH HL, the `LXI HL, offset+2; DAD SP`
becomes `LXI HL, offset; DAD SP` because there's no PUSH HL on the stack
to account for:

```asm
; SPILL16 DE/BC (dynamic, HL dead):
; Before: PUSH HL; LXI HL, offset+2; DAD SP; MOV M,lo; INX HL; MOV M,hi; POP HL
; After:  LXI HL, offset; DAD SP; MOV M,lo; INX HL; MOV M,hi
; Savings: 2B, 21cc
```

Same for DE-preserved paths (SPILL16 HL, RELOAD16 HL): skip PUSH DE/POP DE
and adjust offset from `offset+2` to `offset`.

## Before → After (Motivating example)

Two-array summation loop, steps 5–8 (partial sum spill/reload region):

```asm
; BEFORE (current):
  SHLD  ss+2                ; (5) spill partial (HL=partial, killed)
  PUSH  HL                  ; (6) RELOAD16 BC: preserve dead HL
  LXI   HL, ss
  MOV   C, M
  INX   HL
  MOV   B, M
  POP   HL                  ; HL = partial (restored unnecessarily)
  PUSH  HL                  ; (7) LOAD16_P BC: preserve dead HL again
  MOV   H, B
  MOV   L, C
  MOV   E, M
  INX   HL
  MOV   D, M
  POP   HL                  ; HL = partial (restored again)
  LHLD  ss+2                ; (8) RELOAD16 HL: redundant

; AFTER (with O42):
  SHLD  ss+2                ; (5) spill partial (HL killed → dead)
  LHLD  ss                  ; (6) RELOAD16 BC, HL dead → LHLD path
  MOV   C, L
  MOV   B, H                ; BC = arr2_ptr, HL = clobbered (dead, OK)
  MOV   H, B                ; (7) LOAD16_P BC, HL dead → no PUSH/POP
  MOV   L, C
  MOV   E, M
  INX   HL
  MOV   D, M                ; DE = arr2[i], HL = arr2_ptr+1 (dead, OK)
  LHLD  ss+2                ; (8) RELOAD16 HL → still needed
```

Steps 5–8 shrink from **16B 132cc** to **12B 88cc** (saves **4B, 44cc**).

With `V6ClangSpillForwarding` fix (O16-adjacent), step 8 can also be
eliminated if the forwarding pass tracks HL across the RELOAD/LOAD
expansions, giving an additional 3B 16cc savings.

## Benefit

- **Per-instance savings**: 2–3B, 21–24cc per skipped PUSH/POP pair
- **Frequency**: Very high — fires whenever RA kills a register before a
  SPILL/RELOAD/LOAD/STORE that uses that register's pair as scratch
- **Compound effect**: Removing PUSH/POP reduces stack traffic and may
  enable further peephole optimizations (consecutive LHLD/SHLD folding)
- **Loop impact**: In the two-array sum loop, saves 4B + 44cc per iteration
  on the spill/reload cluster alone

## Complexity

Low-Medium. ~80-100 lines total:
- 1 shared liveness helper function (~15 lines)
- 10 expansion sites with conditional PUSH/POP skip (~5-8 lines each)
- Dynamic stack offset adjustment (+2 → +0) when PUSH is skipped

## Risk

Low.
- The liveness check is conservative — if uncertain, it reports "live" and
  the PUSH/POP is kept (safe fallback).
- The `LiveRegUnits` / backward-scan approach is already proven in the
  backend (used by ADD16 expansion, LOAD8_P, STORE8_P, and peephole passes).
- The optimization is invisible to later passes — it simply emits fewer
  instructions up front.
- Dynamic stack offset adjustment must be tested carefully: `+2` accounts
  for the PUSH; when PUSH is omitted, the offset changes to `+0`. Getting
  this wrong silently accesses wrong memory.

## Dependencies

- None strictly required — works with current codebase.
- **O10** (done): Static stack makes the LHLD/SHLD-based alternatives for
  BC SPILL/RELOAD available (wouldn't work with dynamic stack offsets).
- **O16** (planned): Store-to-load forwarding benefits from O42 — once
  PUSH/POP wrappers are removed, the spill forwarding pass sees cleaner
  SHLD/LHLD sequences that are easier to track.
- **O20** (done): Honest defs — allows RA to freely assign DE to pointers,
  creating more situations where HL is dead at expansion time.

## Test cases

1. **Two-array sum** (temp/o08_test.c): Verifies RELOAD16-BC and LOAD16_P
   skip PUSH/POP when HL is killed by preceding SPILL16
2. **Single-pointer loop with spill**: Verifies SPILL16-BC skips PUSH/POP
   when HL is dead after a computation
3. **Dynamic stack variant**: Same patterns but with `-mv6clang-no-static-stack`
   to verify offset adjustment (+2 → +0) is correct
4. **HL-live control path**: Verifies PUSH/POP is preserved when HL is
   actually live (no false optimization)
5. **Existing regression suite**: All 100 lit + 15 golden tests must pass
