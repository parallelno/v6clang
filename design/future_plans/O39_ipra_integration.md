# O39 — Interprocedural Register Allocation (IPRA) Integration

## Problem

V6CLANG has zero callee-saved registers. Every CALL instruction is treated as
clobbering A, B, C, D, E, H, L, and FLAGS. The register allocator must
spill all live registers to the stack before every call and reload them
after, even when the callee only touches a small subset.

### C example

```c
volatile int sink;

__attribute__((noinline))
void action_a(void) { sink = 1; }

__attribute__((noinline))
void action_b(void) { sink = 2; }

unsigned int test_ne_same_bytes(unsigned int x) {
    if (x != 0x4242) {
        action_a();
    }
    action_b();
    return x;
}
```

`action_a` and `action_b` each only use HL (for `LXI HL, imm; SHLD sink`),
but the caller `test_ne_same_bytes` still spills `x` (in DE) to the stack
around each call — 13 extra instructions for a 3-instruction callee.

LLVM has a built-in IPRA infrastructure (`-enable-ipra`) that collects
per-function register usage and propagates it to callers. However, it
currently has **no effect** on V6CLANG due to how the CALL instruction is
defined.

## Root Cause

The V6CLANG CALL instruction has two redundant clobber signals:

1. **Register mask** from `getCallPreservedMask()` — returns all-zero
   (no preserved registers). IPRA's `RegUsageInfoPropagation` pass can
   replace this mask at each call site with a narrower one.

2. **Explicit implicit-defs** on the CALL TableGen definition:
   ```tablegen
   let Defs = [SP, A, B, C, D, E, H, L, FLAGS] in
   def CALL : ...
   ```
   These are baked into every CALL MachineInstr at creation time. The
   register allocator sees them as hard clobbers regardless of the
   register mask. IPRA does not patch these.

The implicit-defs override any narrowing IPRA does to the register mask,
making the optimization ineffective.

## Strategy

Remove explicit register defs from CALL (and CALL_INDIRECT if present),
keeping only `Defs = [SP]`. Let the register mask alone communicate
which registers are clobbered.

### Changes required

| File | Change |
|------|--------|
| `V6ClangInstrInfo.td` | Change CALL `Defs` from `[SP, A, B, C, D, E, H, L, FLAGS]` to `[SP]` |
| `V6ClangTargetMachine.h` | Add `bool useIPRA() const override { return true; }` to enable IPRA by default |
| `V6ClangISelLowering.cpp` | Verify `LowerCall` attaches register mask via `getCallPreservedMask()` (already does) |
| `V6ClangRegisterInfo.cpp` | No change — all-zero mask is correct default; IPRA replaces it per call site |

### Enabling IPRA

IPRA can be enabled in two ways:

1. **Per-target default** (recommended): override `useIPRA()` in `V6ClangTargetMachine`:
   ```cpp
   bool useIPRA() const override { return true; }
   ```
   This makes IPRA always active for V6CLANG at `-O1` and above.

2. **Command-line flag**: pass `-mllvm -enable-ipra` to clang (or `-enable-ipra` to llc).
   This overrides the per-target default. Use `-mllvm -enable-ipra=false` to disable.

### How it works end-to-end

1. Functions are compiled bottom-up in the call graph (callee before caller).
2. After register allocation for `action_a`, `RegUsageInfoCollector` records
   it only clobbers HL (the registers actually used/defined).
3. When compiling `test_ne_same_bytes`, `RegUsageInfoPropagation` runs
   before RA and replaces the all-zero register mask on `CALL action_a`
   with a mask that preserves A, B, C, D, E (only HL clobbered).
4. RA sees DE is safe across the call → no spill/reload needed.

### Safety considerations

- **External/library calls**: `getCallPreservedMask()` still returns all-zero.
  Without IPRA info, the mask stays all-zero → full clobber → safe.
- **Indirect calls**: Same — no IPRA info available → conservative.
- **Recursive calls**: IPRA handles SCC ordering; functions in the same SCC
  use conservative masks.
- **Pseudos expanding to calls**: Any pseudo that becomes a CALL must attach
  a register mask. Audit all pseudo expansions that generate CALLs.

## Expected Results

### Before (current — all registers spilled)

```asm
test_ne_same_bytes:
    MOV  D, H           ; save x
    MOV  E, L
    LXI  HL, 0xfffe     ; allocate stack frame
    DAD  SP
    SPHL
    MOV  H, D           ; shuffle for spill
    MOV  L, E
    PUSH DE
    XCHG
    LXI  HL, 2          ; store x to stack
    DAD  SP
    MOV  M, E
    INX  HL
    MOV  M, D
    XCHG
    POP  DE
    MVI  A, 0x42        ; compare
    CMP  L
    JNZ  .call_a
    CMP  H
    JZ   .skip_a
.call_a:
    CALL action_a
.skip_a:
    CALL action_b
    PUSH DE              ; reload x from stack
    LXI  HL, 2
    DAD  SP
    MOV  E, M
    INX  HL
    MOV  D, M
    XCHG
    POP  DE
    XCHG
    LXI  HL, 2          ; deallocate stack frame
    DAD  SP
    SPHL
    XCHG
    RET
```
**33 instructions** (13 for spill/reload overhead)

### After (with IPRA — DE known safe across calls)

```asm
test_ne_same_bytes:
    MOV  D, H
    MOV  E, L
    MVI  A, 0x42
    CMP  E
    JNZ  .call_a
    CMP  D
    JZ   .skip_a
.call_a:
    CALL action_a       ; only clobbers HL — DE survives
.skip_a:
    CALL action_b       ; only clobbers HL — DE survives
    XCHG                ; DE→HL for return
    RET
```
**12 instructions** — no stack frame, no spills, no restores.

### Savings per call site

- **Stack frame setup/teardown**: 4 instructions (LXI+DAD+SPHL × 2)
- **Spill**: 5–7 instructions per register pair
- **Reload**: 5–7 instructions per register pair
- **Total**: ~13–18 instructions eliminated per function with calls

## Applicability

IPRA is most effective for:
- Small leaf functions (like `action_a`, `action_b`) — common in embedded code
- Single-TU builds where all function bodies are visible
- Programs without indirect calls or virtual dispatch

IPRA has **no effect** on:
- External library calls (no body to analyze)
- Indirect calls through function pointers
- Separately compiled translation units (without LTO)

For V6Clang/i8080 programs, single-TU builds are the norm (small programs,
no OS, everything linked statically), making IPRA highly applicable.

## Risks

| Risk | Mitigation |
|------|------------|
| Removing Defs from CALL breaks correctness if mask missing | Audit all paths that create CALL MachineInstrs; verify mask attached |
| Pseudos expanding to CALL may not attach mask | Search for BuildMI(CALL) outside LowerCall; add masks if missing |
| Performance regression if IPRA analysis is slow | Unlikely — V6CLANG programs are small; IPRA scales with call graph size |
| Interaction with existing optimizations (LoadImmCombine, etc.) | These run post-RA; IPRA affects RA decisions, not post-RA passes |

## Dependencies

- None — standalone change to CALL definition + flag enablement
- Enhances O10 (Static Stack): with IPRA, fewer values need static slots
- Enhances O8 (Spill Optimization): fewer spills to optimize in the first place

## References

- LLVM IPRA: `llvm/lib/CodeGen/RegUsageInfoCollector.cpp`, `RegUsageInfoPropagate.cpp`
- Pass config: `TargetPassConfig.cpp` — enabled via `-enable-ipra` or `useIPRA()` override
- V6CLANG call lowering: `V6ClangISelLowering.cpp` lines ~849–852
- V6CLANG register mask: `V6ClangRegisterInfo.cpp` `getCallPreservedMask()`
