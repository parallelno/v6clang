# Plan: O70 — V6CLANG Header-Only Math Runtime (`v6clang_arith.h`)

## 1. Problem

### Current behavior

`clang -target i8080-unknown-v6clang foo.c -o foo.rom` fails to link any C
program that uses `*`, `/`, `%`, or a variable-amount shift on `i16`:

```
ld.lld: error: undefined symbol: __mulhi3
ld.lld: error: undefined symbol: __udivhi3
...
```

The libcall names are set by `setLibcallName` in
`llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp` (lines 178-185), but the
corresponding object files are never produced or installed. The
sources exist as `.s` files in `compiler-rt/lib/builtins/v6clang/` but
they are not built into a library anywhere in the toolchain — the
driver makes no attempt to link them.

The user must hand-assemble the `.s` files, link them manually, OR
add `-nodefaultlibs -nostartfiles` boilerplate plus path overrides.
Empirically (the user's recent benchmark) this is undocumented and
trips up everyone who tries to compile a non-trivial program.

`MUL i8` is additionally `Promote`d to i16 (line 59), so every i8
multiply runs the 16-iteration `__mulhi3` algorithm even when an
8-iteration `__mulqi3` would do.

### Desired behavior

1. `clang -target i8080-unknown-v6clang foo.c -o foo.rom` succeeds for
   any C program. No flags, no boilerplate.
2. The runtime is **RA-aware**: i16 values live in HL/DE/BC across a
   `*`/`/`/`%`/shift call site survive without spilling, when the
   routine doesn't actually clobber them.
3. Some routines expose a **custom calling convention** to eliminate
   the HL/DE/BC reshuffle the V6CLANG C ABI would otherwise force —
   notably a combined `(quot, rem)` divmod that returns both pair
   values.
4. `i8 * i8` lowers to a real `__mulqi3` (8 iterations), ~3× faster
   than the current `Promote` to `__mulhi3`.
5. Users can opt out of the auto-include with `-fno-v6clang-auto-include`
   and supply their own runtime.

### Root cause

The runtime was authored as standalone `.s` files mirroring libgcc,
but no CMake rule was ever written to assemble + archive them, and
the driver never points at the install location. Empirically, this
gap has been hidden by users always linking `crt0.o` + their own
`.s` manually.

A header-only design fixes the linkage cleanly (one `-include` flag),
preserves the libcall symbol names so ISel changes are minimal, and
unlocks two performance wins along the way (RA-awareness + custom CC)
that the `.s`-based approach can't deliver because of V6CLANG's empty
`getCallPreservedMask`.

---

## 2. Strategy

### Approach: header-only runtime with two implementation tiers

Define every libcall the V6CLANG backend can emit in one auto-included
header, `v6clang_arith.h`, in one of two forms:

- **Tier A — `static inline __attribute__((always_inline))`** with the
  full asm body. Body is pasted at every call site; RA sees the exact
  clobber list. Used for short routines (≤25B body / ≤240cc).
- **Tier B — wrapper + body.** A `static inline always_inline` wrapper
  whose body is `__asm__("CALL __body" : ... clobbers ...)` paired
  with a separate `__attribute__((noinline))` function carrying the
  real algorithm. RA trusts the wrapper's declared clobber list; the
  body executes once per program.

Wire the driver to inject `-include v6clang_arith.h` automatically on
the V6CLANG target (suppressible via `-fno-v6clang-auto-include`).

Change `MUL i8` from `Promote` to `LibCall` and add
`setLibcallName(RTLIB::MUL_I8, "__mulqi3")`.

### Why this works

The empirical RA experiment in `tests/v6clang_lib/ra_clobber_lp.c`
(captured below) proves all three claims:

1. `static noinline` (asm body) — IPRA recovers the real clobber set;
   3-instruction caller. **Works.**
2. `weak noinline` (asm body) — IPRA cannot trust a weak body; falls
   back to the empty target `getCallPreservedMask`; 14-instruction
   caller with full spill traffic. **Broken — do not use.**
3. wrapper + (`static` or `weak`) `noinline` body — wrapper inlines,
   carrying its declared clobber list to the call site; body's
   linkage is irrelevant because RA never inspects it; 3-instruction
   caller. **Works regardless of body linkage.**
4. `static inline always_inline` — body inlined, RA sees clobbers
   directly. **Works.**

The wrapper trick (Tier B) additionally enables custom calling
conventions per routine: arg/return registers are bound by the
wrapper's `register T x __asm__("R")` declarations and the
inline-asm constraint list, not by the C ABI.

### Summary of changes

- **Header.** `compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h` — all
  routines per the inventory below. Tier A or Tier B per body size.
- **ISel.** `MUL i8` action `Promote` → `LibCall`; add
  `setLibcallName(RTLIB::MUL_I8, "__mulqi3")`.
- **Driver.** `clang/lib/Driver/ToolChains/V6Clang.cpp`:
  `findV6ClangHeader()` helper (mirror of existing `findV6ClangRuntimeFile`);
  `addClangTargetOptions` injects `-include v6clang_arith.h`.
- **Driver flag.** `clang/include/clang/Driver/Options.td`:
  `-fno-v6clang-auto-include`.
- **Doc.** `docs/V6ClangRuntimeAndInlineAsm.md` (new). Cross-link from
  `docs/V6ClangBuildGuide.md`. Strip `-nodefaultlibs` from existing
  examples.
- **Tests.** `tests/v6clang_lib/{linkage_smoke,divmod_combined,optout}.c`
  added; `mul_bench.c` extended; `ra_clobber_lp.c` locked in as a
  regression. `tests/features/52/` — feature-style c8080 ↔ v6clang
  comparison for `i8 * i8`.
- **Lit.** `llvm/test/CodeGen/V6CLANG/runtime_*.ll` (linkage smoke,
  i8 mul lowering, opt-out behavior).
- **Backlog.** Mark O70 complete in `design/future_plans/README.md`.

### Empirical RA finding (drives the tier policy)

Test `tests/v6clang_lib/ra_clobber_lp.c`. A trivial i8 doubler
(`A=A+A`, clobbers `A,FLAGS` only) is defined five ways. Each is
called from a low-pressure caller `(uint16_t hl_val, uint8_t d) ->
uint16_t` that returns `hl_val` after invoking the doubler.

| Variant | Caller code | HL preserved? |
|---------|-------------|---------------|
| `static noinline` (asm body)        | 3 insns           | YES (IPRA)  |
| `weak   noinline` (asm body)        | ~14 insns + spill | NO          |
| wrapper + `static noinline` body    | 3 insns           | YES         |
| wrapper + `weak   noinline` body    | 3 insns           | YES         |
| `static inline always_inline` (asm) | 3 insns           | YES         |

### Tier policy

| Tier | Form | Use when |
|------|------|----------|
| A | `static inline always_inline`, full asm in body | Body ≤ 25B / ≤ 240cc |
| B | wrapper `static inline always_inline` + `static noinline` body | Body > 25B; want RA-awareness + optional custom CC |

There is no "weak" path. Per-routine user override is **not**
supported. The only override mechanism is the whole-runtime opt-out
(`-fno-v6clang-auto-include`).

### Function inventory

ISel-emitted libcalls (auto-emitted on `*`/`/`/`%`/shift):

| Symbol         | Signature                | Tier | Body est.   |
|----------------|--------------------------|------|-------------|
| `__mulqi3`     | `i16 (i8, i8)` — see note | B   | ~30B / ~370cc |
| `__mulhi3`     | `u16 (u16, u16)`         | B    | ~50B / ~1280cc |
| `__mulsi3`     | `u32 (u32, u32)`         | B    | ~80B        |
| `__udivhi3`    | `u16 (u16, u16)`         | B    | ~60B        |
| `__divhi3`     | `i16 (i16, i16)`         | B    | ~80B        |
| `__umodhi3`    | `u16 (u16, u16)`         | B    | ~60B        |
| `__modhi3`     | `i16 (i16, i16)`         | B    | ~80B        |
| `__ashlhi3`    | `u16 (u16, i8)`          | A    | ~25B        |
| `__ashrhi3`    | `i16 (i16, i8)`          | A/B  | ~30B (decide on impl) |
| `__lshrhi3`    | `u16 (u16, i8)`          | A    | ~25B        |

Inline-only convenience helpers:

| Symbol             | Signature      | Tier | Notes |
|--------------------|----------------|------|-------|
| `__v6clang_mulqihi3`   | `u16 (u8, u8)` | A    | Thin alias around `__mulqi3`; documents intent |
| `__v6clang_udivmodhi3` | `(u16,u16) → quot in HL, rem in DE` | B | Custom CC: returns both pair values. One CALL replaces two. |

**`__mulqi3` returns u16, not u8** (libgcc divergence, accepted).
V6CLANG's i8 multiply produces the full i16 in HL for free. Choosing i16
return lets ISel emit `i16 = __mulqi3(zext a, zext b)` followed by
an i16→i8 truncate that elides when only the low byte survives DAG
combine. V6CLANG is freestanding (no external libgcc to clash with);
divergence documented in `docs/V6ClangRuntimeAndInlineAsm.md`.

---

## 3. Implementation Steps

### Step 3.1 — Read reference documents [ ]

Read in this order:
- `design/future_plans/O70_math_header.md` — feature description (this plan's source).
- `design/plan_asm_interop_overhaul.md` — overlapping work; understand which pieces are shared so we don't conflict.
- `docs/V6ClangBuildGuide.md` — build commands, mirror sync, driver flow.
- `docs/Vector_06c_instruction_timings.md` — for cycle-budget claims in the body sizing.
- `clang/lib/Driver/ToolChains/V6Clang.cpp` — current driver shape; pattern for `findV6ClangRuntimeFile` / `addClangTargetOptions` / `AddClangSystemIncludeArgs`.
- `llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp` lines 55-185 — current libcall wiring, `MUL i8` action.
- `compiler-rt/lib/builtins/v6clang/*.s` — algorithm references.
- Existing inline-asm test `tests/features/inline_asm_clobber/` — verify our assumptions about how RA reads clobber lists today.

> **Implementation Notes**:

### Step 3.2 — Header skeleton (Tier A routines first) [ ]

Create `compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h`. Implement
the small Tier A routines first (`__ashlhi3`, `__lshrhi3`, plus the
`__v6clang_mulqihi3` alias) with full asm bodies, `static inline
always_inline`. Self-guard with `#ifndef V6CLANG_ARITH_H_INCLUDED`.

For each routine: signature, full asm body, register-binding via
`register T x __asm__("HL")` for inputs/outputs, accurate `clobber`
list. Include a one-line cycles-and-bytes comment per body.

> **Design Notes**: Audit the asm clobber list against the body line by line. Anything written that isn't an output operand must be in the clobber list. Anything read that isn't an input operand must not be assumed live afterwards (i.e. if the body trashes E and we don't list it, RA may have parked something in E that we just lost).

> **Implementation Notes**:

### Step 3.3 — Tier B template (`__mulqi3`) [ ]

Implement `__mulqi3` per the body in the feature description: input
`a` in `A`, `b` in `B`, returns full i16 in `HL`. Body name
`__v6clang_mulqi3_body` (`static __attribute__((noinline))`). Wrapper
named `__mulqi3` (the libgcc symbol — this is the entry point ISel
resolves to). Wrapper is `static inline always_inline` with
`register` declarations binding `a→A, b→B`, output `HL`, and the
inline-asm `CALL __v6clang_mulqi3_body` plus `clobber("C","D","E","FLAGS")`.

Verify by manual asm inspection that:
1. The wrapper inlines at the call site.
2. The asm CALL emits as `CALL __v6clang_mulqi3_body`.
3. RA does not spill HL/DE/BC across the call site if they're live (test with a 1-line caller that returns its 16-bit input alongside `__mulqi3(a,b)`).

> **Implementation Notes**:

### Step 3.4 — Remaining Tier B libcall routines [ ]

Implement `__mulhi3`, `__mulsi3`, `__udivhi3`, `__divhi3`,
`__umodhi3`, `__modhi3`, `__ashrhi3`. Use the existing `.s` files in
`compiler-rt/lib/builtins/v6clang/` as algorithm reference. For each:

- Wrapper name = libcall symbol (matches `setLibcallName` strings).
- Wrapper signature matches the V6CLANG C calling convention so
  ISel-emitted CALLs Just Work.
- If the algorithm naturally wants a non-default register layout,
  shuffle inside the wrapper before `CALL __body`.
- Audit clobbers carefully — Tier B's RA contract is hand-maintained.

> **Design Notes**: The V6CLANG C ABI places the first i16 arg in HL and the second in DE (free-list CC). Most algorithms here want exactly that, so the wrapper degenerates to a straight `CALL __body` with no shuffle. Only `__v6clang_udivmodhi3` (Step 3.5) realizes a custom-CC win.

> **Implementation Notes**:

### Step 3.5 — `__v6clang_udivmodhi3` (custom-CC headline routine) [ ]

The combined divmod helper. Returns quotient in HL **and**
remainder in DE through a Tier B wrapper that declares two pair
outputs. C signature returns a struct (or uses out-pointers) at the
source level; the wrapper's inline-asm constraints route both
returns into registers.

Verify the test `tests/v6clang_lib/divmod_combined.c` lowers
`unsigned q=a/b, r=a%b;` to **exactly one** CALL (instead of the
two CALLs the C ABI would force).

> **Design Notes**: Returning two values in registers from C requires either (a) an out-pointer for the second value, with the inline-asm storing into the register the pointer eventually loads, or (b) a struct return that the V6CLANG ABI happens to layout in HL+DE. Option (a) is simpler and portable; option (b) requires checking the V6CLANG struct-return CC.

> **Implementation Notes**:

### Step 3.6 — ISel: `MUL_I8 = LibCall` [ ]

In `llvm-project/llvm/lib/Target/V6CLANG/V6ClangISelLowering.cpp` change
line 59:

```cpp
// Was: setOperationAction(ISD::MUL, MVT::i8, Promote);
setOperationAction(ISD::MUL, MVT::i8, LibCall);
```

Add (near line 178):

```cpp
setLibcallName(RTLIB::MUL_I8, "__mulqi3");
```

Verify `unsigned char a*b` emits `CALL __mulqi3` and the i16→i8
trunc elides when only the low byte is consumed.

> **Implementation Notes**:

### Step 3.7 — Driver: `findV6ClangHeader` helper [ ]

In `clang/lib/Driver/ToolChains/V6Clang.cpp` add `findV6ClangHeader(const
ToolChain &TC, StringRef Filename)` mirroring the existing
`findV6ClangRuntimeFile` (line 63). Search order:
1. `<resource-dir>/lib/v6clang/include/<Filename>`
2. `<bin>/../../compiler-rt/lib/builtins/v6clang/include/<Filename>` (dev tree)
3. `<bin>/../../llvm-project/compiler-rt/lib/builtins/v6clang/include/<Filename>` (mirror)

Returns empty string if not found. No error.

> **Implementation Notes**:

### Step 3.8 — Driver: auto-include in `addClangTargetOptions` [ ]

In `V6ClangToolChain::addClangTargetOptions` (line 171), inject:

```cpp
if (!Args.hasArg(options::OPT_fno_v6clang_auto_include)) {
    std::string Hdr = findV6ClangHeader(getToolChain(), "v6clang_arith.h");
    if (!Hdr.empty()) {
        CC1Args.push_back("-include");
        CC1Args.push_back(Args.MakeArgString(Hdr));
    }
}
```

> **Implementation Notes**:

### Step 3.9 — Driver flag: `-fno-v6clang-auto-include` [ ]

In `clang/include/clang/Driver/Options.td`:

```td
def fno_v6clang_auto_include : Flag<["-"], "fno-v6clang-auto-include">,
    Group<f_Group>, Flags<[NoXarchOption]>,
    HelpText<"Suppress auto-inclusion of v6clang_arith.h on V6CLANG targets">;
```

> **Implementation Notes**:

### Step 3.10 — Build [ ]

```
cmd /c "call ""C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat"" -arch=amd64 >nul 2>&1 && ninja -C llvm-build clang llc 2>&1"
```

Diagnose and fix any build errors. Re-run until clean.

> **Implementation Notes**:

### Step 3.11 — Lit test: i8 mul lowers to `__mulqi3` [ ]

Add `llvm-project/llvm/test/CodeGen/V6CLANG/i8_mul_libcall.ll`. Verify:
- `mul i8 %a, %b` lowers to `CALL __mulqi3`.
- The trunc after the libcall elides when only the low byte is used.

> **Implementation Notes**:

### Step 3.12 — Lit test: linkage smoke (auto-include works) [ ]

Add `llvm-project/clang/test/Driver/v6clang-auto-include.c`. Verify
`clang -target i8080-unknown-v6clang -###` shows `-include
.../v6clang_arith.h`, and that `-fno-v6clang-auto-include` removes it.

> **Implementation Notes**:

### Step 3.13 — Test: `tests/v6clang_lib/linkage_smoke.c` [ ]

Standalone C program exercising every operator the header replaces
(`* / % << >> i16`, `* i8`). Build with bare:

```
llvm-build\bin\clang -target i8080-unknown-v6clang -O2 linkage_smoke.c -o linkage_smoke.rom
```

Run in `v6emul`. Verify no link errors, correct output checksum.

> **Implementation Notes**:

### Step 3.14 — Test: `tests/v6clang_lib/divmod_combined.c` [ ]

Verifies `__v6clang_udivmodhi3` lowers `unsigned q=a/b, r=a%b;` to one
CALL.

> **Implementation Notes**:

### Step 3.15 — Test: `tests/v6clang_lib/optout.c` [ ]

Compile with `-fno-v6clang-auto-include` and `*` in the source.
Expected: `ld.lld: error: undefined symbol: __mulhi3`. Documents
the opt-out semantics.

> **Implementation Notes**:

### Step 3.16 — Test: extend `mul_bench.c` to all four ops [ ]

Add div/mod/shift micro-benchmarks alongside the existing mul.
Capture cycle counts before/after. Tier B path must be ≤ 105% of
the current `.s`-libcall baseline.

> **Implementation Notes**:

### Step 3.17 — Run regression tests [ ]

```
python tests\run_all.py
```

All 120/120 lit + 16/16 golden + 3/3 benchmarks must pass. The i8
mul change may shift `fib_crc` cycles slightly — record the delta.

> **Implementation Notes**:

### Step 3.18 — Verification assembly steps from `tests\features\README.md` [ ]

For `tests/features/52/` (i8 multiply): compile c8080 reference
and v6clang. Compare `main`/test-function asm. Document the
`__mulqi3` (8-iteration) vs the old `__mulhi3`-via-`Promote`
(16-iteration) cycle difference.

> **Implementation Notes**:

### Step 3.19 — Make sure result.txt is created (`tests\features\README.md`) [ ]

`tests/features/52/result.txt` per the documented structure.

> **Implementation Notes**:

### Step 3.20 — Documentation [ ]

Create `docs/V6ClangRuntimeAndInlineAsm.md` covering:
1. The runtime header — what, why, opt-out.
2. Function reference for every routine.
3. Inline-asm syntax for V6CLANG.
4. Tier A vs Tier B; when to use each.
5. The Tier B contract (wrapper clobber list = superset of body's real clobbers).
6. End-to-end example.
7. Future work: `libv6clang-builtins.a` archive migration if per-program ROM duplication ever bites.

Cross-link from `docs/V6ClangBuildGuide.md`. Strip `-nodefaultlibs` from any user-facing example in existing docs (V6CLANG has no default libs to suppress).

> **Implementation Notes**:

### Step 3.21 — Update backlog [ ]

In `design/future_plans/README.md`: mark O70 row complete (`[x]`).

> **Implementation Notes**:

### Step 3.22 — Sync mirror [ ]

```
powershell -ExecutionPolicy Bypass -File scripts\sync_llvm_mirror.ps1
```

> **Implementation Notes**:

---

## 4. Expected Results

### Example 1 — bare `clang foo.c` link succeeds for any C program

```c
// foo.c
unsigned char product(unsigned char a, unsigned char b) {
    return a * b;
}
```

Today: `ld.lld: error: undefined symbol: __mulhi3`.
After O70: `foo.rom` produced. `__mulqi3` body inlined into program
ROM via the wrapper.

### Example 2 — i16 RA preserved across i16 multiply

```c
unsigned f(unsigned hl_val, unsigned a, unsigned b) {
    sink = a * b;
    return hl_val;     // hl_val survives in HL across the multiply
}
```

Today: `__mulhi3` is not even resolved, so it doesn't link. If we
imagine the legacy `.s` form linked in, RA would still spill HL via
`SHLD/LHLD` because of the empty `getCallPreservedMask`.
After O70: caller body is `CALL __v6clang_mulhi3_body; SHLD sink; RET`
— HL is preserved across the call because the wrapper's clobber
list includes only `A,B,C,FLAGS` (and DE, the multiplier).

### Example 3 — combined divmod compiles to one CALL

```c
unsigned q, r;
void divmod(unsigned a, unsigned b) { q = a / b; r = a % b; }
```

Today: two separate CALLs (`__udivhi3` then `__umodhi3`), each
recomputing the same algorithm.
After O70: one CALL to `__v6clang_udivmodhi3_body`; quotient stored
from HL, remainder from DE. ~½ cycle cost.

### Example 4 — i8 multiply 3× faster

```c
unsigned char p = a * b;     // a, b are unsigned char
```

Today: `Promote` to i16, runs `__mulhi3` (16 iterations of DAD H +
RLC + DAD D + DCR + JNZ).
After O70: `__mulqi3` (8 iterations). ~3× cycle reduction.

---

## 5. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| `__mulqi3` returning i16 deviates from libgcc convention | V6CLANG is freestanding — no external libgcc to clash with. Document loudly in `docs/V6ClangRuntimeAndInlineAsm.md`. |
| Per-TU duplication of Tier B bodies bloats ROM | Bound is ~1.5KB worst-case (all 10 routines used in a 1-3 TU program). Acceptable vs. typical 32K-64K V6CLANG ROM. Future-work archive migration documented. |
| Tier B wrapper-clobber contract is not compiler-checked; a body refactor that adds a clobber silently corrupts callers | Lit tests lock down each body's exact written-register set; mandatory wrapper review when a body changes. Document the contract as a stability requirement in `docs/V6ClangRuntimeAndInlineAsm.md`. |
| `-include v6clang_arith.h` runs before user `#include`s, so user `#define __mulhi3 my_mul` cannot redirect | Documented; users who want per-routine override use `-fno-v6clang-auto-include` and supply their own header. |
| `findV6ClangHeader` returns empty (broken install) → user sees generic "undefined symbol" link error | Acceptable; matches existing `crt0.o` behavior. Future enhancement: driver warning. |
| Conflict with `plan_asm_interop_overhaul.md` (O-AsmInterop) which also creates a V6CLANG resource-dir include directory | The directory layout is identical (`<resource-dir>/lib/v6clang/include/`). O70 lands first; O-AsmInterop's Phase 5 then adds `string.h`/`stdlib.h`/`v6clang.h` to the same directory and removes any duplicated logic. Document the shared infrastructure in both plans' "Relationship" sections. |
| IPRA changes in the future could weaken Tier B's wrapper-clobber claim | The wrapper's clobber list is asm-level, not IPRA-derived; unaffected by IPRA changes. Verified via `ra_clobber_lp.c` regression test. |

---

## 6. Relationship to Other Improvements

- **O-AsmInterop (`plan_asm_interop_overhaul.md`)** — significant
  overlap. That plan ships `<resource-dir>/lib/v6clang/include/{string.h,
  stdlib.h, v6clang.h}` and retires `libv6clang-builtins.a`. O70 ships
  `v6clang_arith.h` to the **same directory**, requires the same
  `findV6ClangHeader` helper, and has the same "no `libv6clang-builtins.a`"
  outcome. Plan: O70 lands first (it's the smallest viable slice that
  makes `clang foo.c` work end-to-end); O-AsmInterop's Phase 5 then
  adds the additional headers reusing the helper.
- **O39 (IPRA Integration)** — already complete. O70 relies on IPRA
  for Tier B's claim that `static noinline` bodies don't poison RA at
  call sites. The empirical RA test confirms IPRA is doing its job
  today.
- **O19 (Inline Arithmetic Expansion)** — deprecated. O70 supersedes
  it: the goal of O19 was per-callsite RA-aware mul/div via ISel-time
  expansion, but Tier B achieves the same RA win with one shared body
  and no new ISel infrastructure.
- **O-LLD (Native ld.lld Linker)** — required (already complete). The
  driver auto-include only matters because the link step is now
  end-to-end via clang.

---

## 7. Future Enhancements

- **`libv6clang-builtins.a` archive migration.** If per-program ROM
  duplication of Tier B bodies ever becomes a measurable problem
  (programs with many TUs each touching every operator), build the
  `.s` files into a single static archive, change `v6clang_arith.h` so
  bodies become `extern` declarations, and have the driver pass the
  archive on the link line. The user-facing API does not change.
- **Per-call `RegMask` operands** for any future ISel-materialized
  CALL that does not route through a wrapper — would let RA see the
  actual preserved-reg set per callee. Subsumed by Tier B for
  header-routed calls.
- **Driver warning when `findV6ClangHeader` returns empty** — better
  diagnostic than the link-time "undefined symbol" message.
- **Optional `__v6clang_smulqihi3`** (signed i8 → i16 multiply) if any
  benchmark surfaces a need.

---

## 8. References

- [V6CLANG Build Guide](docs\V6ClangBuildGuide.md)
- [Vector 06c CPU Timings](docs\Vector_06c_instruction_timings.md)
- [Future Improvements](design\future_plans\README.md)
- [O70 Feature Description](design\future_plans\O70_math_header.md)
- [Asm-Interop Overhaul (overlap)](design\plan_asm_interop_overhaul.md)
- [Plan Format Reference](design\plan_cmp_based_comparison.md)
- [Feature Pipeline](design\pipeline_feature.md)
- [Feature Test Cases README](tests\features\README.md)
