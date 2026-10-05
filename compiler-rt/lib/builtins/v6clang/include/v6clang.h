/*===---- v6clang.h - V6CLANG target-specific hardware instruction wrappers -------===
 *
 * Inline asm wrappers for i8080 instructions (IN, OUT, DI, EI, HLT, NOP,
 * LXI SP).  Always inlined; including this header has zero call overhead.
 *
 *===-----------------------------------------------------------------------===
 */

#ifndef __V6CLANG_V6CLANG_H
#define __V6CLANG_V6CLANG_H

#ifndef __V6CLANG__
#error "<v6clang.h> is only valid for the V6CLANG target"
#endif

#include <stdint.h>
#include "v6clang_rt_macros.h"

V6CLANG_INLINE
uint8_t v6clang_in(uint8_t port) {
    register uint8_t in_val asm("A");
    asm(
        "in %[_port]            \n\t"
        : "=r"(in_val)
        : [_port] "i"(port) /* input constraint: immediate value */
        : /* no clobbers */
    );
    return in_val;
}

V6CLANG_INLINE
void v6clang_out(uint8_t port, uint8_t val) {

    asm(
        "mov a, %[_val]         \n\t"
        "out %[_port]           \n\t"
        :
        : [_val] "r"(val), [_port] "i"(port) /* input constraints */
        : "A" /* clobbers */
    );
}

V6CLANG_INLINE
void v6clang_di(void)  { asm ("di"); }

V6CLANG_INLINE
void v6clang_ei(void)  { asm ("ei"); }

V6CLANG_INLINE
void v6clang_hlt(void) { asm("hlt"); }

V6CLANG_INLINE
void v6clang_nop(void) { asm("nop"); }

V6CLANG_INLINE
void v6clang_set_sp(uint16_t sp) {
    asm(
        "lxi sp, %0"
        :/* no output */
        : "i"(sp) /* input constraint: immediate value */
        : "SP" /* clobbers stack pointer */
    );
}

#endif /* __V6CLANG_V6CLANG_H */
