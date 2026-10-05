/* v6clang_rt_macros.h - Shared internal macros for V6CLANG runtime headers.
 *
 * Sole owner of the `V6CLANG_RT` decoration used by every header-only
 * inline-asm runtime routine (math in `v6clang_arith.h`, string/memory
 * in `<string.h>`). Pull this in instead of redefining `V6CLANG_RT`
 * locally — that way the attribute set stays consistent and the
 * `v6clang_rt_helper` tag (used to suppress these bodies from `-S`
 * output unless `-mv6clang-print-rt-helpers` is passed) is applied
 * uniformly.
 *
 * This header is pure macro plumbing: no declarations, no includes.
 * It is safe to pull into any V6CLANG runtime header without dragging
 * in math prototypes or libc surface.
 *
 * Attribute rationale (see also docs/V6ClangRuntimeAndInlineAsm.md):
 *   - static: per-TU local symbol; no multi-definition link errors.
 *   - noinline + used: keeps the IR definition alive across `-O2`
 *     even when no source statement directly mentions the symbol —
 *     libcalls are inserted post-IR, in CodeGen. `--gc-sections`
 *     (on by default for V6CLANG) then prunes unused copies at link time.
 *   - naked: no compiler-emitted prologue/epilogue. Body is exactly
 *     the inline-asm string; every byte hand-placed; relies on the
 *     V6CLANG C calling convention having operands already in named
 *     registers. Each body must emit its own `RET`.
 *   - v6clang_rt_helper: tag for V6ClangAsmPrinter to suppress these bodies
 *     from `.s` dumps by default. Lowered to the LLVM string function
 *     attribute "v6clang-rt-helper" — does NOT take the function's
 *     address and does NOT block IPO (IPSCCP / ArgumentPromotion /
 *     DeadArgumentElimination), unlike `annotate("v6clang-rt-helper")`
 *     which it replaces.
 */
/* No file-level include guard: each consumer header `#undef`s
 * `V6CLANG_RT` at end-of-file to keep the macro out of user code, so
 * re-including this file must re-establish the definition. The inner
 * `#ifndef V6CLANG_RT` keeps successive includes warning-free in case a
 * downstream header forgets to undef. */

#ifndef __V6CLANG__
#error "v6clang_rt_macros.h is V6CLANG-only; compile with -target i8080-unknown-v6clang"
#endif

#ifndef V6CLANG_RT
#define V6CLANG_RT static __attribute__((noinline, used, naked, \
                                     v6clang_rt_helper))
#endif

#ifndef V6CLANG_NOINLINE_ASM
#define V6CLANG_NOINLINE_ASM static __attribute__((noinline, leaf))
#endif

#ifndef V6CLANG_NOINLINE_ASM_EXTERN
#define V6CLANG_NOINLINE_ASM_EXTERN __attribute__((noinline, leaf))
#endif

#ifndef V6CLANG_NOINLINE
#define V6CLANG_NOINLINE static __attribute__((noinline))
#endif

#ifndef V6CLANG_INLINE
#define V6CLANG_INLINE static inline __attribute__((always_inline))
#endif

#ifndef V6CLANG_INLINE_NORETURN
#define V6CLANG_INLINE_NORETURN static inline __attribute__((always_inline, __noreturn__))
#endif
