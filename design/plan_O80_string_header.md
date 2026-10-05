# Plan: Header-only `<string.h>` Runtime (O80)

Convert V6CLANG's `memcpy` / `memset` / `memmove` plus new `strlen` / `strcmp` /
`strcpy` from a (currently unbuilt) `compiler-rt/lib/builtins/v6clang/memory.s`
archive model to the same header-only inline-asm pattern used by
`v6clang_arith.h`. Fixes the `undefined symbol: memset` link error users hit
today, removes the divergent toolchain stub header, unifies the V6CLANG
runtime under one pattern, and improves IPRA visibility into these
helpers. Old `.s` files (all except `crt0.s`) are deleted as dead code.

Builds use the existing `cmake --build llvm-build -j` workflow documented
in [docs/V6ClangBuildGuide.md](../docs/V6ClangBuildGuide.md); no new CMake rules
required.

## Phases

### Phase 0 — Factor out `V6CLANG_RT` into a shared internal header

1. Create `compiler-rt/lib/builtins/v6clang/include/v6clang_rt_macros.h`:
   * `#ifndef __V6CLANG_RT_MACROS_H` guard, `__V6CLANG__` sanity check.
   * Move the `V6CLANG_RT` macro definition out of `v6clang_arith.h` into this
     file verbatim (`static __attribute__((noinline, used, naked,
     annotate("v6clang-rt-helper")))`).
   * No other declarations — this header is pure macro plumbing so it
     can be pulled in by any runtime header without dragging in math
     prototypes.
2. Edit `compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h`:
   * Remove the inline `V6CLANG_RT` definition.
   * Add `#include "v6clang_rt_macros.h"` at the top (after the `__V6CLANG__`
     guard, before the routine bodies).
   * Verify no other site in the tree defines `V6CLANG_RT` independently
     (grep for `define V6CLANG_RT`).

### Phase 1 — Author the new header (parallelizable internally)

1. Create `compiler-rt/lib/builtins/v6clang/include/string.h`, mirroring the
   header layout/comment style of `v6clang_arith.h`:
   * `#ifndef __V6CLANG_STRING_H` guard, `__V6CLANG__` sanity check, `<stddef.h>` /
     `<stdint.h>` includes, `extern "C"` block.
   * `#include "v6clang_rt_macros.h"` to pick up the shared `V6CLANG_RT` macro
     (factored out in Phase 0). This keeps `<string.h>` independent of
     `v6clang_arith.h` — a TU that uses only `memset` does not pull in math
     helper prototypes.
2. Port each routine from `compiler-rt/lib/builtins/v6clang/memory.s` into an
   inline-asm body, using:
   * **Local register variables** to pin args to the V6CLANG default CC
     (`HL`, `DE`, `BC`) and the return value to `HL`.
   * **Numeric labels** (`1:`, `2:`, `1f`, `1b`) instead of named labels —
     mandatory because the body will be emitted once per TU; named labels
     would multiply-define inside a TU if `memset` and `memcpy` shared
     macros or if a TU pulled in multiple copies via inlining decisions.
   * **`"memory"` clobber** plus the actual byte/flag clobbers (`"A"`,
     `"FLAGS"`, and any input-class registers the body trashes that
     aren't in the operand list).
   * Apply the standard `V6CLANG_RT` attributes (`static, noinline, used,
     naked, annotate("v6clang-rt-helper")`). The `annotate` tag means
     `-mv6clang-print-rt-helpers` controls whether the body appears in `.s`
     dumps.
   * Because routines are `naked`, every body **must** emit its own
     `RET` (the C epilogue is suppressed). The current `memory.s` ends
     each routine with `RET`, so the port is mechanical.
3. Routines to define:
   * `memcpy(void*, const void*, size_t)` — ported from `memory.s`.
   * `memset(void*, int, size_t)` — ported from `memory.s`; only low byte
     of `val` is used (C standard).
   * `memmove(void*, const void*, size_t)` — ported from `memory.s` with
     forward/backward branch on overlap.
   * `strlen(const char*)` — **new** (no current `.s`). HL = pointer;
     return HL = length, by walking until NUL and computing end-start.
   * `strcmp(const char*, const char*)` — **new**. HL=a, DE=b; return
     `int` in HL. Match standard libc semantics: negative / zero / positive.
     After the final `A = *a - *b` subtraction, sign-extend the i8 into
     the i16 in HL via:
     ```
     MOV  L, A       ; L = low byte of result
     MVI  H, 0       ; assume non-negative
     ORA  A          ; test sign flag (bit 7 of A)
     JP   1f         ; S clear → positive, done
     MVI  H, 0xFF    ; S set → negative, fill H with sign
     1:
     ```
     `MOV H,A` before the test is **wrong** — `A=0x10` would give
     `HL=0x1010` instead of `0x0010`. Always `MVI H,0` first.
   * `strcpy(char*, const char*)` — **new**. HL=dst, DE=src; copies until
     NUL inclusive; returns dst in HL.

### Phase 2 — Driver / toolchain plumbing (depends on Phase 1)

1. Delete `clang/lib/Driver/ToolChains/V6Clang/include/string.h` (stub).
   No driver code references it by path — the existing
   `findV6ClangHeader()` search order in
   `clang/lib/Driver/ToolChains/V6Clang.cpp` already includes
   `compiler-rt/lib/builtins/v6clang/include/`, and there is an
   `-internal-isystem` argument set up for that directory near line 252.
2. **Verify** the `-internal-isystem` line in
   `V6ClangToolChain::AddClangSystemIncludeArgs` points at the
   `compiler-rt/.../include/` dev-tree path (or the resource-dir
   equivalent) — `<string.h>` must resolve there for `#include
   <string.h>` to work.
3. Decision: `<string.h>` is **not** auto-included (unlike `v6clang_arith.h`
   at line 209 of `V6Clang.cpp`). Keep the `#include <string.h>` requirement
   explicit so a TU that never uses mem-helpers doesn't even
   compile/parse the inline-asm bodies. (Compile-time cost only; not
   codegen.)

### Phase 3 — Documentation (parallel with Phase 2)

1. Update `docs/V6ClangRuntimeAndInlineAsm.md`:
   * Add a "Header-only `<string.h>`" section after the existing math
     runtime section. Same pattern, same `V6CLANG_RT` macro, same
     `--gc-sections` story.
   * Mention that `<string.h>` must be `#include`'d explicitly (unlike
     `v6clang_arith.h` which is auto-included), and explain why (rare in
     non-text code).
2. Update `docs/V6ClangUsage.md` if it has a current note about
   `memcpy`/`memset` availability — point at the new header.
3. Update `docs/README.md` if its "Quick Links" mentions
   `compiler-rt/.../memory.s`.
4. Skim `docs/V6ClangBuildGuide.md` for any mention of `memory.s` being
   assembled (there is none today, but verify). Build steps require no
   changes — the header-only pattern uses the **existing build flow**,
   same as `v6clang_arith.h`.

### Phase 4 — Delete dead code (depends on Phases 1–3)

Files to delete from `compiler-rt/lib/builtins/v6clang/`:

* `memory.s` — replaced by header.
* `divhi3.s`, `mulhi3.s`, `mulsi3.s`, `shift.s`, `udivhi3.s` — all
  already superseded by inline routines in `v6clang_arith.h` (the file's
  own comment says "Routine bodies are ports of
  compiler-rt/lib/builtins/v6clang/...s").

Keep:

* `crt0.s` — still assembled by the CMake rule in
  `clang/lib/Driver/CMakeLists.txt`, the entry-point provider. Do **not**
  delete; deleting would re-introduce `cannot find entry symbol _start`.
* `.gitkeep` — can be removed for cleanliness; `crt0.s` will keep the
  directory non-empty.

### Phase 5 — Verification

1. **Build sanity**:
   * `cmake --build llvm-build -j` (per `docs/V6ClangBuildGuide.md`) — must
     succeed; no CMake rule references the deleted `.s` files (verify
     with a grep for `divhi3.s|mulhi3.s|mulsi3.s|shift.s|udivhi3.s|memory.s`).
   * `scripts\sync_llvm_mirror.ps1` — must not error on missing files.
2. **Functional smoke test** (the bug we're fixing):
   * Compile `temp\demo\main.c` with `__builtin_memset` *and* with
     `memset` directly. Both must link cleanly to `.rom`.
   * Run via `tools\v6emul\v6emul.exe --rom ... --halt-exit` (per
     `docs/V6ClangBuildGuide.md`); verify screen-memory range `0x8000–0x9FFF`
     fills with `0xF0`.
3. **Regression**: full test suite per build guide:
   * `python tests/run_all.py` (golden + lit).
   * `python tests/run_golden_tests.py -v` if any goldens involve
     `mem*`/`str*` symbols.
   * The `.asm`-only tests under `tests/runtime/test_memset.asm` and
     `tests/benchmarks/bench_memset256.asm` are **not** affected — they
     define `memset` themselves at the asm level.
4. **IR/ASM inspection** for one demo:
   * `clang -O3 -S -emit-llvm` on a TU that calls `memset` — confirm a
     local `define internal void @memset(...)` appears with the `naked` /
     `noinline` / `used` attributes.
   * `clang -O3 -S` — confirm the assembled body appears once, with the
     section enabling `--gc-sections` pruning (i.e. `.section
     .text.memset` or a per-function section header). Verify on a TU
     that doesn't call `memset` that the body is omitted.
5. **IPRA win check (optional)**: compile a hot-path file that calls
   `memset` + several other functions; with `-mllvm
   -print-after=v6clang-ipra` (or whatever the existing inspection flag is
   per `docs/V6ClangIPRA.md`), confirm IPRA computes a non-empty preserved
   mask for `memset` — proof of the IPRA improvement claim.

## Relevant Files

* `compiler-rt/lib/builtins/v6clang/include/v6clang_rt_macros.h` — **new file**
  in Phase 0; sole owner of the `V6CLANG_RT` macro.
* `compiler-rt/lib/builtins/v6clang/include/v6clang_arith.h` — edit in Phase 0
  to remove the inline `V6CLANG_RT` definition and `#include
  "v6clang_rt_macros.h"` instead. Otherwise the pattern template.
* `compiler-rt/lib/builtins/v6clang/include/string.h` — **new file** to
  create in Phase 1; includes `v6clang_rt_macros.h`.
* `compiler-rt/lib/builtins/v6clang/memory.s` — **delete** in Phase 4 after
  Phase 1 lands.
* `compiler-rt/lib/builtins/v6clang/{divhi3,mulhi3,mulsi3,shift,udivhi3}.s` —
  **delete** in Phase 4 (dead code).
* `clang/lib/Driver/ToolChains/V6Clang/include/string.h` — **delete** in
  Phase 2 (stub superseded by new header).
* `clang/lib/Driver/ToolChains/V6Clang.cpp` — verify `findV6ClangHeader` and
  `-internal-isystem` setup at ~lines 80, 209, 252 still cover the
  compiler-rt header dir. No code changes expected.
* `clang/lib/Driver/CMakeLists.txt` — verify the `crt0.s` rule at
  lines 100–125 is the **only** thing referencing the `.s` files; no
  edits expected.
* `docs/V6ClangRuntimeAndInlineAsm.md` — Phase 3 update.
* `docs/V6ClangUsage.md` — Phase 3 update if it documents string.h.
* `docs/README.md` — Phase 3 update if it points at `memory.s`.

## Decisions

* **`V6CLANG_RT` lives in its own header** (`v6clang_rt_macros.h`), included by
  both `v6clang_arith.h` and the new `string.h`. Avoids macro drift and
  keeps `<string.h>` from dragging in math prototypes.
* **Per-TU duplication is acceptable.** User explicitly accepted this.
* **`strlen` / `strcmp` / `strcpy` go into the new header**, not into a
  separate one. User explicitly requested.
* **Delete all `.s` files except `crt0.s`.** User explicitly requested.
* **No auto-include** of `<string.h>` (unlike `v6clang_arith.h`). String
  helpers are rarely used; require the explicit `#include`.
* **Keep `naked`** for consistency with `v6clang_arith.h`; each body emits
  its own `RET`.
* **Build steps unchanged.** Existing `cmake --build llvm-build -j`
  workflow from `docs/V6ClangBuildGuide.md` covers everything; no new CMake
  rules needed because we're removing files, not adding compiled
  artifacts.
