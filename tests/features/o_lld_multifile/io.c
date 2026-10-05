#include <stdint.h>

__attribute__((noinline))
void emit_u8(uint8_t x) {
    __builtin_v6clang_out(0xED, x);
}
