/* stdlib.h - V6CLANG <stdlib.h>.
 *
 * Single canonical <stdlib.h> for the V6CLANG bare-metal target.
 * Provides the standard C subset that makes sense on a freestanding
 * i8080 target plus common embedded convenience macros.
 *
 * Contents:
 *   EXIT_SUCCESS / EXIT_FAILURE — standard exit codes
 *   abort() / exit()            — noreturn; both spin on HLT (no OS)
 *   abs() / labs()              — standard C integer absolute value
 *   RAND_MAX / rand() / srand() — 16-bit xorshift PRNG
 *   min() / max()               — embedded convenience macros
 */
#ifndef V6CLANG_STDLIB_H_INCLUDED
#define V6CLANG_STDLIB_H_INCLUDED

#ifndef __V6CLANG__
#error "<stdlib.h> here is V6CLANG-only; compile with -target i8080-unknown-v6clang"
#endif

#include <stdint.h>
#include "v6clang_rt_macros.h"

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1

V6CLANG_INLINE_NORETURN
void abort(void) {
    for (;;)
        __builtin_v6clang_hlt();
}

V6CLANG_INLINE_NORETURN
void exit(uint8_t __status) {
    (void)__status;
    for (;;)
        __builtin_v6clang_hlt();
}

#ifndef abs
#define abs(x)  ((x) < 0 ? -(x) : (x))
#endif

#ifndef labs
#define labs(x) ((long)(x) < 0 ? -(x) : (x))
#endif

#ifndef min
#define min(a,b) (((a) < (b)) ? (a) : (b))
#endif

#ifndef max
#define max(a,b) (((a) > (b)) ? (a) : (b))
#endif


/* -----------------------------------------------------------------------
 * PRNG — rand() / srand() / RAND_MAX
 *
 * 16-bit xorshift generator.
 * Reference: http://www.retroprogramming.com/2017/07/xorshift-pseudorandom-numbers-in-z80.html
 *
 * rand()  returns int in [0, RAND_MAX] (~22 bytes / ~120 cc per call).
 * srand() re-seeds the generator; seed 0 is clamped to 1 because
 * xorshift state must never be 0.
 *
 * State is file-scope static: each translation unit that includes
 * <stdlib.h> gets its own independent PRNG instance.  For typical
 * single-TU V6CLANG programs this is identical to a global state.
 * ----------------------------------------------------------------------- */
#ifndef RAND_MAX
#define RAND_MAX 0xFFFF
#endif

/* Internal PRNG state — 16-bit, must not be 0. */
static uint16_t __v6clang_rand_state = 1u;

V6CLANG_INLINE
void srand(uint16_t __seed) {
    __v6clang_rand_state = __seed ? __seed : 1u;
}

/* rand() — xorshift16(7,9,8), result masked to [0, RAND_MAX]. */
V6CLANG_NOINLINE_ASM
uint16_t rand(void) {
    register uint16_t _out asm("HL");
    __asm__ volatile (
    "1:  lhld   %[rand_state]       \n"
        "mov    a, h                \n"  /* --- seed ^= seed >> 9 --- */
        "rar                        \n"  /* A  = H >> 1  (CY = H.0)  */
        "mov    a, l                \n"
        "rar                        \n"  /* A  = L >> 1 | H.0 << 7  */
        "xra    h                   \n"
        "mov    h, a                \n"  /* H' = H ^ (seed>>9).hi    */
        "mov    a, l                \n"  /* --- seed ^= seed >> 1 (via RAR chain) --- */
        "rar                        \n"
        "mov    a, h                \n"
        "rar                        \n"
        "xra    l                   \n"
        "mov    l, a                \n"
        "xra    h                   \n"  /* --- seed ^= seed << 8 --- */
        "mov    h, a                \n"  /* H  = old-L ^ ...         */
        "shld   %[rand_state]       \n"  /* store updated state       */
        : "=r"(_out)
        : /* inputs constrain */
          [rand_state] "i"(&__v6clang_rand_state)
          /* clobbers */
        : "HL", "A", "FLAGS"
    );
    return _out;
}

#endif /* V6CLANG_STDLIB_H_INCLUDED */
