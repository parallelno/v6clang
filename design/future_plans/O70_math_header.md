# Plan: V6CLANG Header-Only Math Runtime (`v6clang_arith.h`)

Replace the current `.s`-file libcall runtime (`__mulhi3` etc.) with a
header-only runtime that ships as a single auto-included header. Every
routine the V6CLANG backend can emit a libcall to is defined in the header
in one of two forms:

- **Tier A — `static inline __attribute__((always_inline))`** with the
  full asm body. Used for short routines (≤25B body). The asm body is
  pasted at every call site; RA sees the exact clobber list.
- **Tier B — wrapper + body.** A `static inline always_inline` wrapper
  whose only body is `__asm__("CALL __body_name" : ... clobbers ...)`,
  paired with a separate `__attribute__((noinline))` function carrying
  the real asm. RA trusts the wrapper's declared clobber list and
  treats the call site as cheaply as a one-instruction asm.

Both tiers achieve full RA-awareness. Tier B additionally enables
**custom calling conventions per routine** (see below).

## Motivation

1. **Linkage works out of the box.** `clang -target i8080-unknown-v6clang file.c
   -o file.rom` succeeds even when `file.c` uses `*`, `/`, `%`, or variable
   shifts. Today it fails with `undefined symbol: __mulhi3` because no
   builtins archive is built or installed.
2. **Single source of truth.** No parallel `.s` and `.h` definitions to
   keep in sync. The asm bodies live exactly once, in the header.
3. **i8 multiply gets its own routine.** Today `MUL i8` is `Promote`d to
   i16 (`__mulhi3` runs 16 shift-add iterations). With a real `__mulqi3`
   it runs 8 iterations — **~3× faster** for any i8 mul.
4. **RA-aware call sites.** Both tiers expose the asm clobber set to
   the register allocator. The default V6CLANG path (`CALL` to an external
   function) forces the RA to spill everything live, because
   `getCallPreservedMask = {0}`. The header-only path eliminates that.
5. **Tier B unlocks custom calling conventions.** Because the wrapper
   is inlined and the call to the body lives inside the asm string,
   the V6CLANG C calling convention does not apply to the body. Each
   routine can pin args to the registers its asm naturally wants and
   return values through any register pair (or multiple pairs at once,
   e.g. quotient + remainder). This eliminates the HL/DE/BC shuffle
   the C ABI would otherwise force.

## Tier choice and the empirical RA finding

This section captures the experiment that drove the design.

**Test:** `tests/v6clang_lib/ra_clobber_lp.c`. A trivial i8 doubler
(`A = A + A`, clobbers `A, FLAGS` only) is defined five ways. Each is
called from a low-pressure caller `(uint16_t hl_val, uint8_t d) ->
uint16_t` that stores the result then returns `hl_val` — so RA's only
job is to keep `hl_val` alive across the doubler call.

| Variant | Body form | Caller code size | HL preserved across call? |
|---------|-----------|------------------|----------------------------|
| `static noinline` (asm body)        | real CALL                  | 3 insns           | **YES** (IPRA recovers) |
| `weak   noinline` (asm body)        | real CALL                  | ~14 insns + spill | **NO** |
| wrapper + `static noinline` body    | wrapper inlined, asm CALL  | 3 insns           | **YES** |
| wrapper + `weak   noinline` body    | wrapper inlined, asm CALL  | 3 insns           | **YES** |
| `static inline always_inline` (asm) | inlined                    | 3 insns           | **YES** |

**Key conclusions:**

1. **`weak noinline` is the worst option.** Because a weak symbol may
   be replaced at link time, IPRA cannot trust the locally-visible
   body and falls back to the empty target preserved-mask. Every live
   reg spills around the call. This invalidates the "weak for user
   override" approach the earlier draft of this plan recommended.
2. **`static noinline` gets full RA-awareness via IPRA.** Clang's
   IPRA computes the actual clobber set of any `static` callee in the
   same TU and uses that instead of the empty target mask. The single
   shared body produces zero spill traffic at the call site.
3. **The wrapper trick (Tier B) gives RA-awareness regardless of body
   linkage** — because RA never inspects the body. It trusts the
   wrapper's declared clobber list. Verified with both `static` and
   `weak` body linkage.
4. **Tier B also enables custom calling conventions.** The body's
   args and returns are bound by the wrapper's inline-asm constraint
   list (`"=p"(out_HL), "=p"(out_DE)` returns two pair regs at once;
   `"p"(in_HL)` pins one input). The C ABI does not apply to the
   inlined call.
5. **Tier B's RA-awareness is a hand-maintained contract.** The
   wrapper's declared clobber list must be a superset of the body's
   real clobbers. There is no compiler check. Documented as a
   stability requirement on any future refactor of a body.

### Tier policy

| Tier | Form                                                       | Inlines body?       | RA aware? | Custom CC? | Use when |
|------|------------------------------------------------------------|---------------------|-----------|------------|----------|
| A    | `static inline always_inline`, full asm in body            | yes                 | yes       | n/a        | Body ≤25B / ≤240cc |
| B    | wrapper `static inline always_inline` + `static noinline` body | wrapper yes; body no | yes       | yes        | Body >25B, want RA-awareness + custom CC |

There is no "weak" path. Per-routine user override is **not**
supported — it costs IPRA-awareness for every other call site of that
routine across the program (see empirical finding) and is not a
feature anyone has asked for. Users who want a different runtime use
the whole-runtime opt-out (see "Auto-include").

The Tier A 25B/240cc threshold rationale: at smaller sizes the
inlined body is cheaper than a CALL+RET pair (24+12=36cc), and
per-callsite duplication is bounded. At larger sizes Tier B wins on
ROM with no measurable cycle penalty, since the wrapper's CALL inside
inline-asm carries the same overhead as a real CALL but exposes the
clobber set to RA.

## Design

### File layout

```
compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h     ← the header
clang/lib/Driver/ToolChains/V6Clang.cpp                  ← auto-include wiring
clang/include/clang/Driver/Options.td                ← opt-out flag
llvm/lib/Target/V6Clang/V6ClangISelLowering.cpp              ← MUL_I8 = LibCall
docs/V6ClangRuntimeAndInlineAsm.md                       ← user-facing doc
tests/v6clang_lib/                                       ← linkage + perf + RA tests
```

The legacy `.s` files in `compiler-rt/lib/builtins/v6clang/` (`mulhi3.s`,
`divhi3.s`, `udivhi3.s`, `mulsi3.s`, `shift.s`, `memory.s`) are kept
for reference but no longer participate in the link path. `crt0.s`
stays — still built into `crt0.o` by the driver.

### Function inventory

ISel-emitted libcalls (auto-emitted on `*`/`/`/`%`/shift):

| Symbol         | Signature                | Tier | Body est.    |
|----------------|--------------------------|------|--------------|
| `__mulqi3`     | `i16 (i8, i8)` — see note | B    | ~30B / ~370cc |
| `__mulhi3`     | `u16 (u16, u16)`         | B    | ~50B / ~1280cc |
| `__mulsi3`     | `u32 (u32, u32)`         | B    | ~80B         |
| `__udivhi3`    | `u16 (u16, u16)`         | B    | ~60B         |
| `__divhi3`     | `i16 (i16, i16)`         | B    | ~80B         |
| `__umodhi3`    | `u16 (u16, u16)`         | B    | ~60B         |
| `__modhi3`     | `i16 (i16, i16)`         | B    | ~80B         |
| `__ashlhi3`    | `u16 (u16, i8)`          | A    | ~25B         |
| `__ashrhi3`    | `i16 (i16, i8)`          | A/B  | ~30B (decide on impl) |
| `__lshrhi3`    | `u16 (u16, i8)`          | A    | ~25B         |

Inline-only convenience helpers (callable explicitly from user code):

| Symbol             | Signature      | Tier | Notes |
|--------------------|----------------|------|-------|
| `__v6clang_mulqihi3`   | `u16 (u8, u8)` | A    | Thin alias around `__mulqi3`; documents intent |
| `__v6clang_udivmodhi3` | `(u16,u16) → (u16 quot in HL, u16 rem in DE)` | B | Returns both via custom CC. Saves one full divide call when both wanted. |

The `__v6clang_udivmodhi3` helper is the headline example of Tier B's
custom-CC win: compiles `unsigned q=a/b, r=a%b;` into one CALL
instead of two.

**`__mulqi3` returns u16, not u8** (libgcc divergence, accepted).
Standard libgcc `__mulqi3` returns `i8`. V6CLANG's i8 multiply produces
the full i16 in HL for free — the only difference is whether the
body emits `MOV A,L; RET` (i8 return) or just `RET` (i16 return).
Choosing i16 lets ISel emit `i16 = __mulqi3(zext a, zext b)` followed
by an i16→i8 truncate. The truncate elides when only the low byte is
used (common case), and costs exactly `MOV A,L` (8cc) when the caller
actually needs both bytes. Net: same cost as classic `__mulqi3` for
i8×i8→i8, free i16 promotion for i8×i8→i16. V6CLANG is freestanding
(no external libgcc to clash with); divergence documented in
`docs/V6ClangRuntimeAndInlineAsm.md`.

### `__mulqi3` body and wrapper (Tier B template)

Body. Custom CC: input `a` in `A`, input `b` in `B`, returns full i16
product in `HL`.

```asm
__v6clang_mulqi3_body:
    MOV  E, B           ; DE = zext(b) (multiplicand)
    LXI  H, 0           ; HL = 0 (result)
    MOV  D, L           ; D = 0  (1B cheaper than MVI D,0)
    MVI  B, 8
1:  DAD  H              ; result <<= 1
    RLC                 ; A <<= 1, bit7 -> CY
    JNC  2f
    DAD  D              ; result += zext(b)
2:  DCR  B
    JNZ  1b
    RET                 ; full i16 in HL
```

Wrapper:

```c
static inline __attribute__((always_inline))
unsigned __mulqi3(unsigned char a, unsigned char b) {
    register unsigned       hl __asm__("HL");
    register unsigned char  ar __asm__("A") = a;
    register unsigned char  br __asm__("B") = b;
    __asm__ volatile (
        "CALL __v6clang_mulqi3_body"
        : "=p"(hl), "+a"(ar), "+b"(br)
        :
        : "C", "D", "E", "FLAGS"
    );
    return hl;
}
```

The wrapper's clobber declaration enumerates every register the body
mutates beyond its inputs/outputs: `C`, `D`, `E`, `FLAGS`. Anything
not in that list RA may keep alive across the call site.

### ISel ↔ wrapper integration

ISel emits CALLs to libcall symbols (e.g. `CALL __mulhi3`) directly,
bypassing C-level inlining. To preserve Tier B's RA-awareness for
ISel-emitted calls, each Tier B routine is structured as:

- A C-callable wrapper named with the libcall symbol (`__mulhi3`).
  This is the entry point ISel's CALL resolves to.
- The wrapper's signature matches the V6CLANG C calling convention so
  ISel's normal arg-placement code Just Works.
- Inside the wrapper, inline-asm `CALL __body` invokes the actual
  algorithm. The wrapper does any reshuffle the body's custom CC
  needs (often none — V6CLANG C CC already places i16 args in HL/DE/BC
  which matches most algorithms' natural layout).

For most routines the V6CLANG C CC is already what the algorithm wants
(e.g. `__mulhi3(a,b)`: `a` in HL, `b` in DE — exactly the algorithm's
natural placement, zero shuffle). Custom-CC wins are realized where
the algorithm wants a non-default placement OR where multiple return
values are desired (`__v6clang_udivmodhi3`).

When a routine has no custom-CC benefit, the wrapper degenerates to a
straight `CALL __body` with default-CC bindings — still wins on
RA-awareness vs. an ISel-emitted CALL with empty preserved mask.

`V6ClangISelLowering.cpp` change:

```cpp
// Was: setOperationAction(ISD::MUL, MVT::i8, Promote);
setOperationAction(ISD::MUL, MVT::i8, LibCall);
setLibcallName(RTLIB::MUL_I8, "__mulqi3");
// __mulqi3 returns i16; type-legalizer/DAGCombine inserts a trunc
// which elides when only the low byte is consumed.
```

Other libcall names (`__mulhi3` etc.) are already set via
`setLibcallName` — no change needed there.

### Auto-include and opt-out

Driver injects `-include v6clang_arith.h` unless the user passes
`-fno-v6clang-auto-include`:

```cpp
// In V6ClangToolChain::addClangTargetOptions()
if (!Args.hasArg(options::OPT_fno_v6clang_auto_include)) {
    std::string Hdr = findV6ClangHeader(TC, "v6clang_arith.h");
    if (!Hdr.empty()) {
        CC1Args.push_back("-include");
        CC1Args.push_back(Args.MakeArgString(Hdr));
    }
}
```

`findV6ClangHeader` searches:
1. `<resource-dir>/lib/v6clang/include/v6clang_arith.h` (installed)
2. `<bin>/../../compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h` (dev tree)
3. `<bin>/../../llvm-project/compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h` (mirror)

Returns empty string if none found — driver does not error; user gets
the legacy "undefined symbol" link error if they then use `*`. Matches
how `crt0.o` and `v6clang.ld` are looked up today.

The header self-guards via `#ifndef V6CLANG_ARITH_H_INCLUDED` so manual
`#include "v6clang_arith.h"` plus auto-include doesn't double-define.

**`-fno-v6clang-auto-include` is the only override mechanism.** The user
takes full responsibility for providing every routine the backend will
emit libcalls to. Per-routine override is not supported (see "Tier
choice" finding above).

### Driver changes

1. New flag in `clang/include/clang/Driver/Options.td`:
   ```td
   def fno_v6clang_auto_include : Flag<["-"], "fno-v6clang-auto-include">,
       Group<f_Group>, Flags<[NoXarchOption]>,
       HelpText<"Suppress auto-inclusion of v6clang_arith.h on V6CLANG targets">;
   ```
2. `findV6ClangHeader()` helper in `V6Clang.cpp` (same shape as
   `findV6ClangDriverFile` / `findV6ClangRuntimeFile` already present).
3. `addClangTargetOptions()` injects `-include v6clang_arith.h` unless
   suppressed.
4. **Drop `-nodefaultlibs` from documentation examples.** V6CLANG has no
   default libraries to suppress; the flag is a no-op. Keep
   `-nostartfiles` documented as the escape hatch for users who write
   their own `_start`.

### Documentation

New `docs/V6ClangRuntimeAndInlineAsm.md` covering:

1. **The runtime header.** What it is, why it's auto-included, how to
   opt out (`-fno-v6clang-auto-include`).
2. **Function reference.** Every routine: signature, custom CC if any,
   declared clobbers, cycle and byte estimates.
3. **Inline-asm syntax for V6CLANG.** Register binding via `register T x
   __asm__("HL")`, constraints (`a`, `r`, `p`, `I`, `J`), clobber names.
4. **Tier A vs Tier B.** When and why each is used.
5. **The Tier B contract.** Wrappers' declared clobbers must remain a
   superset of the body's real clobbers; any body refactor must
   re-audit the wrapper.
6. **End-to-end example.** Compile, link, measure with v6emul.
7. **Future work: `libv6clang-builtins.a` archive migration.** If
   per-program ROM duplication ever becomes a real problem, the
   migration path is: build the `.s` files in
   `compiler-rt/lib/builtins/v6clang/` into a single `libv6clang-builtins.a`
   static archive shipped in the resource dir; change `v6clang_arith.h`
   so the bodies become `extern` declarations instead of definitions;
   have the driver pass the archive on the link line. The user-facing
   API does not change.

`docs/V6ClangBuildGuide.md` keeps its build/test scope and gains a link
to the new doc.

## Implementation steps

1. **Header skeleton.** Write `v6clang_arith.h` with all routines per the
   inventory table. Tier A as `static inline always_inline` with full
   asm. Tier B as wrapper (`static inline always_inline` with `CALL
   __body` in asm) + body (`static noinline`). Audit each wrapper's
   clobber list against its body.
2. **MUL_I8 → LibCall.** Update `V6ClangISelLowering.cpp` and verify with
   a small test that `unsigned char a*b` emits `CALL __mulqi3` and
   the trunc elides when only the low byte is consumed.
3. **Driver auto-include.** Wire `-include v6clang_arith.h` into
   `V6ClangToolChain::addClangTargetOptions`. Add `-fno-v6clang-auto-include`
   to `Options.td`.
4. **Tests.** `tests/v6clang_lib/`:
   - `mul_bench.c` — extend to all four ops.
   - `linkage_smoke.c` — every operator the header replaces, builds
     with bare `clang foo.c -o foo.rom`.
   - `ra_clobber_lp.c` — keep as regression: any future change must
     preserve the empirical results in the "Tier choice" table.
   - `divmod_combined.c` — verify `__v6clang_udivmodhi3` lowers to one
     CALL.
   - `optout.c` — verify `-fno-v6clang-auto-include` actually suppresses
     and produces an undefined-symbol link error.
5. **Lit tests.** Mirror linkage-smoke and Tier B clobber-correctness
   tests under `llvm/test/CodeGen/V6Clang/`.
6. **Doc.** `docs/V6ClangRuntimeAndInlineAsm.md` per outline above. Update
   `docs/V6ClangBuildGuide.md` cross-link. Strip `-nodefaultlibs` from any
   user-facing example.
7. **Regression.** Full lit + 16/16 golden + 3/3 benchmarks (bsort,
   sieve, fib_crc) — measure cycle delta from `MUL_I8 = LibCall`
   change. Expectation: bsort and sieve unchanged (no mul); fib_crc
   may shift slightly.
8. **Cleanup.** The `.s` files under `compiler-rt/lib/builtins/v6clang/`
   (other than `crt0.s`) become reference material. Keep them — they
   document the algorithms independently of C.

## Risks / open questions

- **`__mulqi3` returning i16 deviates from libgcc convention.** Anyone
  linking V6CLANG against an externally-provided libgcc would mismatch.
  Mitigation: V6CLANG is freestanding, no libgcc, document loudly.
- **Per-TU duplication of Tier B bodies.** Each `static noinline` body
  is duplicated per TU it's used in. For a typical 1–3 TU program
  with all 10 routines used, total runtime ROM is bounded at ~1.5KB.
  Acceptable given typical V6CLANG ROM budgets. Future work: archive
  migration.
- **Tier B wrapper-clobber contract is not compiler-checked.** A body
  refactor that introduces a new clobber without updating the wrapper
  silently corrupts callers. Mitigation: lit tests that lock down each
  body's exact clobber set; mandatory wrapper review whenever a body
  changes.
- **`-include` ordering.** `-include` runs before any user `#include`,
  so user code can't `#define __mulhi3 my_thing` to redirect. Users
  who want that must use `-fno-v6clang-auto-include`.
- **Diagnostic when header is missing.** If the resource-dir layout is
  broken and `findV6ClangHeader` returns empty, the user sees a generic
  "undefined symbol __mulhi3" link error. Consider emitting a driver
  warning. Deferred.

## Future work

- **`libv6clang-builtins.a` archive migration.** Documented in
  `docs/V6ClangRuntimeAndInlineAsm.md` per the doc outline. Triggered if
  per-program ROM duplication of Tier B bodies becomes a measurable
  problem.
- **Per-call `RegMask` operands** for any future ISel-materialized
  CALL that does not route through a wrapper — would let RA see the
  actual preserved-reg set per callee. Subsumed by Tier B for
  header-routed calls. Separate plan if pursued.

## Success criteria

- `clang -target i8080-unknown-v6clang foo.c -o foo.rom` succeeds for any
  `foo.c` that uses `*`/`/`/`%`/shift, with no `-nostartfiles
  -nodefaultlibs` boilerplate.
- `tests/v6clang_lib/linkage_smoke.c` builds, runs, produces correct
  checksum.
- `mul_bench.c` Tier B path cycles ≤ 105% of the current `.s`-libcall
  baseline.
- i8 mul micro-benchmark shows ≥2.5× speedup vs current `Promote`-to-
  `__mulhi3`.
- `divmod_combined.c` lowers `(a/b, a%b)` to exactly one CALL.
- `ra_clobber_lp.c` regression test produces the same per-variant
  code sizes as the empirical table above.
- All 120/120 lit + 16/16 golden + 3/3 benchmark checksums pass.
- `-fno-v6clang-auto-include` test produces the documented link error.
