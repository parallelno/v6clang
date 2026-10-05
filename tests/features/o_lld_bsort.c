// End-to-end test for the O-LLD plan (native ld.lld + linker script).
//
// Self-contained ROM that exercises .text (multiple functions), .data
// (statically initialized array), and pointer-mediated writes through
// a noinline helper. Verifies that ld.lld correctly resolves
// cross-section references and that llvm-objcopy emits the right flat
// binary layout starting at 0x0100.
//
// Expected output on V6CLANG debug port 0xED, in order:
//   0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
//   0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51
//
// Notes on the startup convention used here:
//   * V6CLANG has no MC AsmParser, so crt0.s cannot be assembled to ELF
//     today. We work around this by placing main() in `.text._start`
//     so the linker script's `KEEP(*(.text._start))` rule puts it at
//     the load address (0x0100).
//   * `--defsym=_start=main` satisfies the script's ENTRY(_start) so
//     ld.lld emits a valid entry point for the ELF.
//   * main() ends with __builtin_v6clang_hlt() before the implicit return,
//     which prevents the function epilogue from executing on a stack
//     that was never initialized by a real crt0.
//   * SP at v6emul reset is 0x0000; the first CALL pushes the return
//     address at 0xFFFE/F (RAM), which matches the canonical
//     `__stack_top = 0x0000` convention from clang/lib/Driver/ToolChains/V6Clang/v6clang.ld.

#include <stdint.h>

#define N 16

// Statically initialized -> must end up in .data, not .bss.
uint8_t ARR[N] = {
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
    0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
};

// noinline forces a real CALL site that ld.lld must resolve via R_V6CLANG_16.
__attribute__((noinline))
void bias_arr(uint8_t *arr, uint8_t n, uint8_t bias) {
    for (uint8_t i = 0; i < n; i++) {
        arr[i] = arr[i] + bias;
    }
}

__attribute__((noinline))
void print_arr(const uint8_t *arr, uint8_t n) {
    for (uint8_t i = 0; i < n; i++) {
        __builtin_v6clang_out(0xED, arr[i]);
    }
}

// Place main() in .text._start so the linker script's
// `KEEP(*(.text._start))` rule puts it at the load address (0x0100).
__attribute__((section(".text._start")))
int main(int argc, char **argv) {
    (void)argc; (void)argv;
    __builtin_v6clang_di();
    bias_arr(ARR, N, 0x42);
    print_arr(ARR, N);
    __builtin_v6clang_hlt();
    return 0;
}
