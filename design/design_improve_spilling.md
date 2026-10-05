# V6CLANG Spill Optimization — Design Document

## 1. Problem Statement

The current V6CLANG backend expands SPILL16/RELOAD16 pseudos into stack-relative
addressing sequences that cost **~104 cc / 16 bytes per spill-reload pair**.
The Intel 8080 has no stack-relative load/store instructions, so every stack
access requires a multi-instruction sequence:

```
PUSH HL/DE            ; save scratch pair
LXI  HL, offset       ; load stack offset
DAD  SP               ; HL = SP + offset
MOV  M, lo / MOV lo,M ; store/load low byte
INX  HL               ; advance pointer
MOV  M, hi / MOV hi,M ; store/load high byte
POP  HL/DE            ; restore scratch pair
```

This dominates inner-loop code whenever two 16-bit pointers are live
simultaneously (common in copy, search, compare patterns), because the 8080
has only one general-purpose memory pointer register (HL).

### 1.1 Motivating Example

A simple `uint8_t` array copy loop:

```c
for (uint8_t i = 0; i < 100; i++)
    array2[i] = array1[i];
```

compiles to **~30 instructions per iteration** (two spill-reload pairs at
~52 cc each) versus the ideal **6 instructions** (LDA via HL, STAX via DE,
INX both, DCR+JNZ).

### 1.2 Goal

Reduce spill-reload cost by replacing stack-relative sequences with cheaper
8080 instructions when safety conditions are met, without changing register
allocation or instruction selection.

---

## 2. Tiered Spill Strategy

Three tiers, selected per spill slot based on local analysis:

| Tier | Mechanism | Spill | Reload | Total | Bytes | Constraints |
|------|-----------|-------|--------|-------|-------|-------------|
| **T1** | PUSH / POP | 16 cc | 12 cc | **28 cc** | 2 B | Same-BB, LIFO order, no intervening branches/calls |
| **T2** | SHLD / LHLD (HL) or STA / LDA (A) | 20 cc | 20 cc | **40 cc** | 6 B | Same-BB, non-LIFO or cross-BB; not reentrant |
| **T3** | Current stack-relative | 52 cc | 52 cc | **104 cc** | 16 B | Always safe (fallback) |

Selection priority: T1 → T2 → T3. Each tier's constraints are checked
statically. Slots that fail T1 checks are tried for T2; slots that fail
both fall through to T3 (current behavior, no code change needed).

---

## 3. Tier 1 — PUSH / POP Spilling

### 3.1 Concept

Replace a SPILL pseudo with PUSH of the enclosing register pair, and the
corresponding RELOAD with POP. This reuses the hardware stack as a temporary
store without address computation overhead.

### 3.2 Applicability

| Register class | PUSH/POP pair | Side effects |
|----------------|---------------|--------------|
| GR16 (HL, DE, BC) | PUSH pair / POP pair | None — restores both halves |
| GR8 (B, C, D, E, H, L) | PUSH enclosing pair / POP enclosing pair | Other half also saved/restored; harmless |
| Acc (A) | PUSH PSW / POP PSW | **Clobbers FLAGS** — requires FLAGS dead at POP |

### 3.3 Safety Conditions

All conditions are evaluated **per basic block**:

1. **LIFO nesting.** Every SPILL to slot *S* must be matched by a RELOAD
   from slot *S*, and matched pairs must form a proper bracket nesting
   (stack discipline). No interleaving of different slots.

2. **No intervening control flow.** Between a PUSH-spill and its POP-reload,
   there must be no branch instructions (conditional or unconditional),
   CALL instructions, or RET instructions. The basic block boundary already
   enforces this for cross-BB cases, but intra-BB branches (tail calls,
   conditional jumps from pseudo expansion) must be checked.

3. **No intervening stack mutations.** Between the matched pair, no
   instructions may modify SP (other than recognized balanced PUSH/POP from
   other T1 conversions in the same nesting context). This excludes CALL,
   ADJCALLSTACK, SPHL, DAD SP used for frame adjustment.

4. **FLAGS liveness (PUSH PSW only).** When spilling A via PUSH PSW, the
   POP PSW will clobber FLAGS. The pass must verify FLAGS is dead at the
   reload point. If FLAGS is live, the slot falls through to T2 (STA/LDA)
   or T3.

5. **Enclosing pair liveness (GR8 only).** When spilling a single 8-bit
   register via PUSH of the enclosing pair, the other half of the pair is
   also pushed and popped. This is safe because POP restores both halves.
   However, any write to the other half between PUSH and POP would be
   lost on POP. The pass must verify the other half is not written between
   the PUSH and POP (or is dead after POP).

### 3.4 Stack Offset Adjustment

Converting N spill slots to PUSH/POP inserts N×2 bytes of stack growth at
the PUSH point, which shifts the SP-relative offsets of any remaining T3
(stack-relative) spill/reload instructions between the PUSH and POP.

**Resolution:** The pass runs **before** `eliminateFrameIndex()`. It does
not compute numerical offsets — it operates on frame index references.
Converted slots are marked eliminated so `eliminateFrameIndex()` accounts
for them correctly and the frame lowering prologue does not allocate stack
space for them.

---

## 4. Tier 2 — Global Address Spilling

### 4.1 Concept

Replace SPILL16/RELOAD16 of HL with SHLD/LHLD to a dedicated `.bss` global,
and SPILL8/RELOAD8 of A with STA/LDA. These are single-instruction
load/store operations at fixed addresses — no scratch register needed.

### 4.2 Applicability

| Register | Spill | Reload | Cost |
|----------|-------|--------|------|
| HL | SHLD `__spill_N` | LHLD `__spill_N` | 40 cc / 6 B |
| A | STA `__spill_N` | LDA `__spill_N` | 32 cc / 6 B |
| DE, BC | XCHG + SHLD / LHLD + XCHG | XCHG + LHLD / LHLD + XCHG | 48 cc / 8 B |
| GR8 (B–L) | MOV A,r + STA / LDA + MOV r,A | Needs A free | 58 cc / 8 B |

T2 is most beneficial for **HL** (direct SHLD/LHLD) and **A** (direct
STA/LDA). For DE/BC, the XCHG overhead narrows the gap versus T3. For
non-A 8-bit registers, T2 is marginal unless A is demonstrably dead (the
MOV A,r clobbers A).

### 4.3 Safety Conditions

1. **Non-reentrancy.** Global spill slots are shared across all invocations
   of the function. If the function is called recursively (including via
   interrupt handlers), the slot contents are corrupted. The pass must
   conservatively treat any function that could be called from an ISR as
   ineligible, or emit DI/EI guards (at +16 cc overhead).

2. **Symbol uniqueness.** Each spill slot maps to a distinct global symbol
   (`__v6clang_spill_<func>_<slot>`). Symbols are function-scoped (local
   linkage) to avoid cross-function collision.

3. **RAM budget.** Each T2 slot costs 2 bytes of `.bss`. The pass should
   track total allocation and cap at a configurable limit.

### 4.4 When T2 Wins Over T3

T2 is chosen for slots that:
- Cannot be converted to T1 (non-LIFO or cross-BB access patterns), AND
- Involve HL or A directly (no register shuffling needed), AND
- Are in a non-reentrant context.

---

## 5. Architecture — V6ClangSpillOpt Pass

### 5.1 Pass Identity

| Property | Value |
|----------|-------|
| Name | `V6CLANG Spill Optimization` |
| Type | `MachineFunctionPass` |
| ID | `V6ClangSpillOpt::ID` |
| Pipeline slot | `addPreEmitPass()`, **before** all existing optimization passes |
| Toggle | `-v6clang-disable-spill-opt` (cl::opt, default false) |

### 5.2 Pipeline Position

```
Register Allocation
  └─ eliminateFrameIndex()   ← spill pseudos expanded to stack-relative code
       └─ addPreEmitPass()
            └─ [existing passes: AccumulatorPlanning, Peephole, ...]
```

**Critical constraint:** `eliminateFrameIndex()` is called by the register
allocator framework, before `addPreEmitPass()`. The SPILL/RELOAD pseudos are
already expanded to concrete machine instructions by the time `addPreEmitPass`
runs.

This means V6ClangSpillOpt has two viable insertion points:

**Option A — Inside `eliminateFrameIndex()`:** Add tier selection logic
directly into `V6ClangRegisterInfo::eliminateFrameIndex()`. When expanding a
SPILL/RELOAD pseudo, check if the slot qualifies for T1 or T2, and emit
the cheaper sequence instead. This is the simplest approach but limits
analysis to a single pseudo at a time (no cross-pseudo LIFO verification).

**Option B — Separate pass before `eliminateFrameIndex()`:** Override
`addPreRegAlloc()` or  use `addPostRegAlloc()` to insert V6ClangSpillOpt
before frame index elimination. The pass scans all SPILL/RELOAD pseudos
(still intact), performs BB-level LIFO analysis, converts qualifying slots,
and marks them so `eliminateFrameIndex()` skips them.

**Decision: Option B.** A separate pass provides the BB-wide view needed for
LIFO analysis and keeps tier selection logic isolated from the frame index
machinery.

### 5.3 Pass Phases

```
┌─────────────────────────────────────┐
│        V6ClangSpillOpt Pass             │
│                                     │
│  Phase 1: Inventory                 │
│    Scan MF for all SPILL/RELOAD     │
│    pseudos. Group by frame index.   │
│    Record: slot → [(BB, MI, kind)]  │
│                                     │
│  Phase 2: Tier Classification       │
│    For each slot:                   │
│      T1 check: same-BB, LIFO,      │
│        no branches/calls between,   │
│        FLAGS/pair liveness OK       │
│      T2 check: HL or A direct,     │
│        non-reentrant context        │
│      Else: T3 (no action)          │
│                                     │
│  Phase 3: Rewrite                   │
│    T1 slots: Replace SPILL→PUSH,   │
│      RELOAD→POP. Erase pseudo.     │
│    T2 slots: Allocate global sym.  │
│      Replace SPILL→SHLD/STA,       │
│      RELOAD→LHLD/LDA. Erase.      │
│    Update MFI: mark slots dead.    │
└─────────────────────────────────────┘
```

### 5.4 Interfaces

```
// V6Clang.h
FunctionPass *createV6ClangSpillOptPass();

// V6ClangSpillOpt.cpp (internal)
class V6ClangSpillOpt : public MachineFunctionPass {
public:
  static char ID;
  bool runOnMachineFunction(MachineFunction &MF) override;

private:
  // Phase 1
  struct SpillRecord {
    MachineBasicBlock *MBB;
    MachineInstr *MI;
    bool IsSpill;       // true = SPILL, false = RELOAD
    Register Reg;       // physical register being spilled/reloaded
    int FrameIndex;
  };
  using SlotRecords = SmallVector<SpillRecord, 4>;
  DenseMap<int, SlotRecords> SlotMap;

  void collectSpillReloads(MachineFunction &MF);

  // Phase 2
  enum SpillTier { Tier1_PushPop, Tier2_Global, Tier3_Stack };
  DenseMap<int, SpillTier> SlotTiers;

  bool canUseTier1(int FrameIndex, const SlotRecords &Records);
  bool canUseTier2(int FrameIndex, const SlotRecords &Records,
                   MachineFunction &MF);
  void classifySlots(MachineFunction &MF);

  // Phase 3
  void rewriteTier1(int FrameIndex, const SlotRecords &Records);
  void rewriteTier2(int FrameIndex, const SlotRecords &Records,
                    MachineFunction &MF);
  void rewriteSlots(MachineFunction &MF);
};
```

---

## 6. LIFO Verification Algorithm (Tier 1)

### 6.1 Core Idea

Model spill/reload operations within a basic block as opening and closing
parentheses. A sequence is LIFO-safe iff the parentheses are properly nested.

### 6.2 Algorithm

```
Input: ordered list of SPILL/RELOAD pseudos in a single BB
Output: set of T1-eligible slot pairs

stack ← empty
for each MI in BB (program order):
    if MI is SPILL to slot S:
        push S onto stack
    if MI is RELOAD from slot S:
        if stack.top() == S:
            pop stack → mark (SPILL_S, RELOAD_S) as T1 candidate
        else:
            mark S as non-LIFO → T1 ineligible
```

After the scan, verify each T1 candidate pair has no intervening branches,
calls, or unmatched stack mutations between the PUSH and POP points.

### 6.3 Handling Multiple Uses

A slot may be spilled once and reloaded multiple times (or vice versa). Only
the innermost matched SPILL-RELOAD pair within a single BB qualifies for T1.
Multiple accesses to the same slot across different BBs are T2 or T3.

---

## 7. Global Symbol Management (Tier 2)

### 7.1 Symbol Naming

```
__v6clang_spill_<function_name>_<slot_index>
```

Example: `__v6clang_spill_main_0`, `__v6clang_spill_main_1`

Local linkage ensures no collisions with other translation units.

### 7.2 Emission

T2 symbols are emitted as zero-initialized `.bss` entries (2 bytes each for
i16, 1 byte for i8). The `V6ClangAsmPrinter` or a late-lowering hook emits them
at the end of the function's output.

### 7.3 RAM Budget Control

CLI option `-v6clang-global-spill-limit=<N>` (default 16) caps the number of
global spill slots per function. When the cap is hit, remaining non-T1 slots
fall through to T3.

---

## 8. Interaction with Frame Lowering

### 8.1 Stack Size Reduction

When V6ClangSpillOpt converts a slot to T1 or T2, the slot no longer needs stack
space. The pass marks such slots in `MachineFrameInfo` (e.g., via
`setObjectOffset` to a sentinel, or a side-channel `DenseSet<int>`) so that
`emitPrologue()` allocates a smaller frame.

### 8.2 Offset Correctness for Mixed Tiers

If some slots in a function are converted (T1/T2) and others remain T3,
the T3 slots still need correct SP-relative offsets. The frame lowering
must compute stack size based only on surviving T3 slots. Converted slots
are excluded from the stack layout via `MFI.RemoveStackObject(FrameIndex)`
or equivalent.

### 8.3 Prologue/Epilogue Impact

Functions where **all** spill slots are converted to T1/T2 may have a zero
remaining stack frame, eliminating the LXI+DAD+SPHL prologue/epilogue
entirely. This is a secondary benefit — no special handling needed, the
existing prologue already checks `StackSize == 0`.

---

## 9. Reentrancy and Interrupts (Tier 2)

### 9.1 Default Policy

The V6CLANG target is bare-metal with no OS threads. Reentrancy occurs only
through interrupt handlers. The default policy is:

- Functions **not** marked as interrupt handlers: T2 eligible.
- Functions marked as interrupt handlers (future attribute): T2 ineligible
  (conservative — use T1 or T3).

### 9.2 Future Extension: DI/EI Guards

A future refinement could wrap T2 spill-reload sequences with DI/EI to
protect against ISR corruption, at +16 cc overhead (still cheaper than T3).
Out of scope for initial implementation.

---

## 10. Testing Strategy

### 10.1 Lit Tests

| Test | Verifies |
|------|----------|
| `spill-opt-push-pop.ll` | T1: SPILL16/RELOAD16 HL → PUSH HL / POP HL |
| `spill-opt-push-pop-8.ll` | T1: SPILL8 B → PUSH BC / POP BC |
| `spill-opt-push-psw.ll` | T1: SPILL8 A with FLAGS dead → PUSH PSW / POP PSW |
| `spill-opt-psw-flags-live.ll` | T1 rejected when FLAGS live at reload → falls to T2/T3 |
| `spill-opt-non-lifo.ll` | T1 rejected for non-LIFO pattern → T2 or T3 |
| `spill-opt-global.ll` | T2: SPILL16 HL → SHLD / LHLD with `.bss` symbol |
| `spill-opt-sta-lda.ll` | T2: SPILL8 A → STA / LDA |
| `spill-opt-disabled.ll` | `-v6clang-disable-spill-opt` produces T3 (unchanged) |
| `spill-opt-mixed.ll` | Function with T1, T2, and T3 slots — correct offsets |
| `spill-opt-cross-bb.ll` | Cross-BB slot rejected from T1, eligible for T2 |

### 10.2 Integration Tests

Emulator round-trip tests exercising the array copy and similar two-pointer
patterns through the full pipeline (clang → llc → v6asm → v6emul), verifying
correctness of the optimized spill sequences.

### 10.3 Regression

All existing lit tests (55+), golden tests (15), and round-trip tests (13)
must continue to pass with the optimization enabled.

---

## 11. CLI Interface

| Flag | Default | Description |
|------|---------|-------------|
| `-v6clang-disable-spill-opt` | `false` | Disable the entire V6ClangSpillOpt pass |
| `-v6clang-global-spill-limit=<N>` | `16` | Max global spill slots per function |

---

## 12. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| LIFO analysis misidentifies a non-nested pair | Incorrect codegen (stack corruption) | Conservative analysis — any ambiguity → T3 fallback. Verify with `-verify-machineinstrs`. |
| T2 global corrupted by ISR | Silent data corruption | Default non-reentrant policy; DI/EI guard as future option |
| Frame offset miscalculation for mixed T1+T3 | Wrong stack accesses | Remove converted slots from MFI before eliminateFrameIndex runs |
| T1 PUSH/POP clobbers other half of pair (GR8) | Register value lost | Verify other-half not written between PUSH–POP; reject if written |
| Interaction with existing post-RA passes | Pass assumes spill sequences have specific shape | V6ClangSpillOpt runs first (before AccumulatorPlanning et al.) |
