// Multi-.c project test for the O-LLD plan: the linker resolves
// cross-translation-unit calls. main.c references symbols in math.c
// and io.c; clang's driver invokes ld.lld with the canonical v6clang.ld.
//
// Build (one command):
//   llvm-build/bin/clang -target i8080-unknown-v6clang -O2 \
//       -nostartfiles -nodefaultlibs "-Wl,--defsym=_start=main" \
//       tests/features/o_lld_multifile/main.c \
//       tests/features/o_lld_multifile/math.c \
//       tests/features/o_lld_multifile/io.c \
//       -o tests/features/o_lld_multifile/out.rom

#include <stdint.h>

uint8_t add_u8(uint8_t a, uint8_t b);    // defined in math.c
void emit_u8(uint8_t x);                 // defined in io.c

__attribute__((section(".text._start")))
int main(void) {
    __builtin_v6clang_di();
    emit_u8(add_u8(0x10, 0x07));   // 0x17
    emit_u8(add_u8(0x40, 0x02));   // 0x42
    emit_u8(add_u8(0xF0, 0x0F));   // 0xFF
    __builtin_v6clang_hlt();
    return 0;
}
