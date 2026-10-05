// Test ASM inlining + custom calling convention.

// compile:
// llvm-build\bin\clang -target i8080-unknown-v6clang -O3 -S`
//    temp\asm_inline\custom_cc.c -o temp\asm_inline\custom_cc.rom

#include <stdint.h>

#define V6CLANG_RT static __attribute__((noinline, used))

// The default CC passes arg0 in HL and returns an int in HL.
// `custom_cc` implements a manually-defined alternate CC that takes its
// argument in BC and returns its result in BC. The goal is to show that the
// alternate CC works and that it can relieve the register pressure that the
// default HL-based CC would create in the caller (main).
//
// Custom CC contract for `custom_cc`:
//   IN:    B = high byte of the u16 arg
//          C = u8 value to add
//          A = same u8 value (a copy of C; supplied by the caller)
//   OUT:   B = (high_byte_of_arg + original_A + C)
//          C = (low_byte_of_arg  + original_A)        i.e. low byte of arg + A
//   CLOBBERS: A, FLAGS
//
// The function body is pure asm with no extended-asm operands: there are no
// inputs/outputs/clobbers declared because the C-level function has no
// parameters or return value. The compiler therefore does not know that
// BC and A carry data across this call -- that contract is upheld entirely
// by the caller's register-asm bindings (see custom_cc_wrapper) plus the
// `noinline` attribute that prevents the body from being inlined and reordered.
// The closing `}` of the C function emits the standard RET.
V6CLANG_RT void custom_cc() {
    asm (
        "STAX B           \n\t"   // store A at address BC (scratch / side-effect use)
        "ADD C            \n\t"   // A = A + C
        "MOV C, A         \n\t"   // C = A      -> low byte of result
        "ADD B            \n\t"   // A = A + B  (A already held original_A + C)
        "MOV B, A         \n\t"   // B = A      -> high byte of result
        // No `: outputs : inputs : clobbers` lists are present: the asm
        // template above is a "basic asm" (no operands). Data flow in/out
        // is invisible to the compiler and managed by the caller.
    );
}

__attribute__((always_inline)) static
uint16_t custom_cc_wrapper(uint16_t arg0_i16, uint8_t a) {
    // Inline-asm wrapper that issues an explicit `call custom_cc` while
    // pinning BC across the call site. Because this function is
    // always_inline, the bindings below appear directly in `main`, so the
    // compiler is forced to materialize arg0_i16 in BC just before the
    // call and to read the returned value back from BC after the call --
    // even under heavy register pressure (HL/DE held live by main).
    //
    // How the bindings work:
    //   `register uint16_t bc_in asm("BC") = arg0_i16;`
    //       -> declares a local register variable pinned to physical reg BC.
    //          Initialized from arg0_i16, so the compiler emits whatever
    //          moves are needed to land arg0_i16 in BC before the asm.
    //   `register uint16_t out_val asm("BC");`
    //       -> another BC-pinned local register variable, uninitialized.
    //          After the asm, reading `out_val` reads whatever BC holds.
    //
    // Operand list anatomy:  asm( template : outputs : inputs : clobbers )
    //   "=r"(out_val) : output. `=` means write-only; `r` means any GPR
    //                   (forced to BC by the register-asm binding above).
    //   "r"(bc_in)    : input.  `r` means any GPR (forced to BC).
    //   "FLAGS"       : clobber. Tells the compiler the asm trashes flags
    //                   so it must not assume condition codes survive.
    //
    // No "memory" clobber: this asm does not read/write arbitrary memory
    // visible to C (the STAX inside custom_cc writes to address BC, which
    // is not pointing at any C object here).
    register uint16_t bc_in asm("BC") = arg0_i16;
    register uint16_t out_val asm("BC");
    __asm__ volatile (
        "call custom_cc\n\t"
        : "=r"(out_val) : "r"(bc_in) : "FLAGS"
    );
    return out_val;
}

uint16_t main(void) {
    // create reg pressure to demostrate that the custom CC correctly used in custom_cc call.
    uint16_t* pointer1 = (void*)0x1111; // must be in HL
    uint16_t* pointer2 = (void*)0x2222; // must be in DE
    *pointer1 = 0x1141;
    *pointer2 = 0x2252;

    uint16_t result = custom_cc_wrapper(0x3333, 0x63);

    __builtin_v6clang_out(0xDE, result & 0xFF);
    __builtin_v6clang_out(0xDE, result >> 8);
    return 0;
}
