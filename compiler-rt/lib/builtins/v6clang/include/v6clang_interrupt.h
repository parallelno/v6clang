/*===---- v6clang_interrupt.h - V6CLANG i8080 interrupt utilities -------------===*
 *
 * Minimal interrupt support utilities for the V6CLANG target.
 *
 * Provided functionality
 * ----------------------
 *   • Install a custom interrupt handler at INT_ADDR (0x38) by writing
 *     a JMP instruction and target address.
 *
 *   • Provide a default "empty" interrupt handler that simply re-enables
 *     interrupts (EI) and returns. This is useful when interrupts must
 *     remain enabled but no handling is required.
 *
 * Notes
 * -----
 *   • The interrupt vector is patched in-place with a JMP opcode followed
 *     by the handler address.
 *
 *   • The handler must follow the platform calling convention (address
 *     passed in HL).
 *
 *   • No state preservation or stack repair is performed by the default
 *     handler.
 *
 * Public API
 * ----------
 *   v6clang_set_interrupt_handler(void* handler)
 *       Install a handler at INT_ADDR.
 *
 *   v6clang_empty_interrupt_handler()
 *       Minimal ISR: enables interrupts and returns.
 *
 *   v6clang_set_empty_interrupt_handler()
 *       Convenience wrapper to install the empty handler.
 *
 *===-------------------------------------------------------------------===*/

#ifndef __V6CLANG_V6CLANG_INTERRUPT_H
#define __V6CLANG_V6CLANG_INTERRUPT_H

#ifndef __V6CLANG__
#error "<v6clang_interrupt.h> is only valid for the V6CLANG target"
#endif

#include <stdint.h>
#include "v6clang_rt_macros.h"
#include "v6clang_consts.h"

V6CLANG_INLINE
void v6clang_set_interrupt_handler(void* handler) {
    // `handler` must be in HL according the calling convention.
    register void* _handler asm("HL") = handler;
    __asm__ volatile (
        "MVI A, %[op_call]          \n"
        "STA %[int_addr]            \n"
        "SHLD %[int_addr] + 1       \n"
        : /* no outputs */
          /* input constraints */
        : [int_addr] "i"(INT_ADDR), "r" (_handler), [op_call] "i"(OPCODE_JMP)
        /* clobbers */
        : "A", "HL"
    );
}


V6CLANG_NOINLINE
/*
 * interruption subroutine.
 *
 * Invoked by the hardware at INT_ADDR (0x38) via JMP.
 * Minimal handler for when interrupts are enabled but no specific handling is
 * needed. Mostly useful for tests to set a color palette.
 */
void v6clang_empty_interrupt_handler() {
    v6clang_ei();
    return;
}


V6CLANG_NOINLINE
void v6clang_set_empty_interrupt_handler() {
    v6clang_set_interrupt_handler(v6clang_empty_interrupt_handler);
}

#undef V6CLANG_RT
#endif /* __V6CLANG_V6CLANG_INTERRUPT_H */
