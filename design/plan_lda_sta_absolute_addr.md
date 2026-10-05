# Plan: LDA/STA for Absolute Address Loads/Stores (O6)

## 1. Problem

### Current behavior

Loading `i8` from a constant integer address (e.g. memory-mapped I/O)
generates a two-instruction sequence:

```asm
LXI  HL, 0x8000    ; 12cc, 3B — materialize address in HL
MOV  A, M           ;  8cc, 1B — load byte through HL
; Total: 20cc, 4B
```

Similarly, storing `i8` to a constant integer address:

```asm
LXI  HL, 0x8000    ; 12cc, 3B
MOV  M, A           ;  8cc, 1B
; Total: 20cc, 4B
```

Note: loads/stores from **global variables** already use LDA/STA via
existing `V6Clangwrapper tglobaladdr` patterns. This issue only affects
constant integer addresses produced by `inttoptr` in the IR —
typically used for memory-mapped I/O.

### Desired behavior

```asm
LDA  0x8000         ; 16cc, 3B — direct absolute load
; Saves: 4cc + 1B per load
```

```asm
STA  0x8000         ; 16cc, 3B — direct absolute store
; Saves: 4cc + 1B per store
```

### Root cause

The SelectionDAG ISel has combined patterns for `(load (V6Clangwrapper
tglobaladdr))` → LDA and `(store val, (V6Clangwrapper tglobaladdr))` → STA,
but no corresponding patterns for bare `ConstantSDNode` addresses.

When the address is a constant integer (from `inttoptr`), ISel
materializes it first via `(i16 imm) → LXI`, then selects
`V6CLANG_LOAD8_P` / `V6CLANG_STORE8_P` for the load/store through the register.

## 2. Strategy

### Approach: Add ISel patterns for constant-address LDA/STA

Add two `Pat<>` entries in `V6ClangInstrInfo.td` that match loads/stores
from bare immediate addresses, directly selecting LDA/STA.

### Why this works

TableGen patterns with an `imm` constraint on the address operand are
more specific than the generic `V6CLANG_LOAD8_P` pattern (which accepts any
`i16:$addr`). The more specific pattern wins during ISel, so LDA/STA
will be selected whenever the address is a compile-time constant.

LDA constrains the output to `Acc` (register A). If the loaded value
is needed in another register, a `MOV` will be inserted by the register
allocator — still cheaper than `LXI + MOV A,M + MOV r,A`.

### Summary of changes

| File | Change |
|------|--------|
| `V6ClangInstrInfo.td` | Add 2 `Pat<>` for constant-address LDA/STA |

## 3. Implementation Steps

### Step 3.1 — Add ISel patterns for constant-address LDA/STA [x]

**File**: `llvm-project/llvm/lib/Target/V6Clang/V6ClangInstrInfo.td`

Add after the existing `(load (V6Clangwrapper tglobaladdr))` → LDA pattern:

```tablegen
// Load i8 from constant integer address via LDA
def : Pat<(i8 (load imm:$addr)), (LDA imm:$addr)>;

// Store i8 to constant integer address via STA
def : Pat<(store i8:$val, imm:$addr), (STA i8:$val, imm:$addr)>;
```

> **Design Notes**: The `imm` predicate matches `ConstantSDNode`, which
> is what `inttoptr (i16 const)` becomes in the SelectionDAG. This is
> more specific than the `i16:$addr` in `V6CLANG_LOAD8_P`/`V6CLANG_STORE8_P`,
> ensuring the new patterns take priority.
>
> **Implementation Notes**: Added 2 `Pat<>` entries after existing global-address patterns in V6ClangInstrInfo.td (lines ~650-654). The `imm` operand matches `ConstantSDNode` from `inttoptr` in IR.

### Step 3.2 — Build [x]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

> **Implementation Notes**: Clean build, 28 targets rebuilt (TableGen re-run + 1 object + link).

### Step 3.3 — Lit test: lda-sta-const-addr.ll [x]

**File**: `tests/lit/CodeGen/V6Clang/lda-sta-const-addr.ll`

Test that:
1. Load i8 from constant address → LDA
2. Store i8 to constant address → STA
3. Existing global-address LDA/STA still works

> **Implementation Notes**: 5 CHECK-LABEL tests: load_const_addr, store_const_addr, copy_const_addr, load_global, store_global. All pass.

### Step 3.4 — Run regression tests [x]

```
python tests\run_all.py
```

> **Implementation Notes**: 82/82 lit + 15/15 golden = all pass.

### Step 3.5 — Verification assembly steps from `tests\features\README.md` [x]

Compile the feature test case and verify LDA/STA appear for constant addresses.

> **Implementation Notes**: read_port: LDA 0x100 (was LXI+MOV), write_port: STA 0x100 (was LXI+MOV), copy_port: LDA+STA (was 2×LXI+MOV). Savings: 16cc + 4B total across 3 test functions.

### Step 3.6 — Sync mirror [x]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**: Mirror synced successfully.

## 4. Expected Results

### Memory-mapped I/O read

```c
unsigned char read_port(void) {
    return *(volatile unsigned char*)0x8000;
}
```

Before:
```asm
LXI  HL, 0x8000    ; 12cc, 3B
MOV  A, M           ;  8cc, 1B
RET                  ; 12cc, 1B
; Body: 20cc, 4B
```

After:
```asm
LDA  0x8000         ; 16cc, 3B
RET                  ; 12cc, 1B
; Body: 16cc, 3B  (saves 4cc + 1B)
```

### Memory-mapped I/O write

```c
void write_port(unsigned char val) {
    *(volatile unsigned char*)0x8000 = val;
}
```

Before:
```asm
LXI  HL, 0x8000    ; 12cc, 3B
MOV  M, A           ;  8cc, 1B
RET                  ; 12cc, 1B
; Body: 20cc, 4B
```

After:
```asm
STA  0x8000         ; 16cc, 3B
RET                  ; 12cc, 1B
; Body: 16cc, 3B  (saves 4cc + 1B)
```

### Copy between ports

```c
void copy_port(void) {
    *(volatile unsigned char*)0x8001 = *(volatile unsigned char*)0x8000;
}
```

Before:
```asm
LXI  HL, 0x8000    ; 12cc, 3B
MOV  A, M           ;  8cc, 1B
LXI  HL, 0x8001    ; 12cc, 3B
MOV  M, A           ;  8cc, 1B
RET                  ; 12cc, 1B
; Body: 40cc, 8B
```

After:
```asm
LDA  0x8000         ; 16cc, 3B
STA  0x8001         ; 16cc, 3B
RET                  ; 12cc, 1B
; Body: 32cc, 6B  (saves 8cc + 2B)
```

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| LDA constrains result to A — extra MOV if value needed elsewhere | MOV copy is cheaper than LXI+MOV M; ISel naturally handles this |
| Pattern could interfere with V6CLANG_LOAD8_P for register-held addresses | `imm` is strictly more specific than `i16:$addr`; no interference |
| STA constrains source to A — extra MOV if value comes from elsewhere | Same reasoning; MOV copy cost is net-positive vs LXI+MOV M |

---

## 6. Relationship to Other Improvements

- **O2 (Sequential LXI → INX)**: O6 eliminates the LXI entirely for
  constant-address accesses, reducing the number of LXI instructions
  that O2 would need to fold.
- **O4 (ADD M / SUB M)**: Both assume HL is the addressing register.
  O6 frees HL for other uses when accessing known addresses.

## 7. Future Enhancements

- Add equivalent patterns for **LHLD/SHLD** (i16 load/store from
  constant addresses) — same approach, saves 16cc + 3B per instance.
- Combine consecutive LDA/STA to same region with HL-based addressing
  when cheaper (e.g. 3+ accesses to adjacent addresses).

## 8. References

* [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
* [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
* [Future Improvements](design\future_plans\README.md)
* [O6 Feature Description](design\future_plans\O06_lda_sta_absolute_addr.md)
