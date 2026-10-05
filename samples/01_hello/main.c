// Minimal V6CLANG ROM: emits a byte on the debug port and halts.
//
// Build and run:
//   samples\01_hello\build.bat
//
// Expected output: TEST_OUT port=0xED value=0x42
#include <stdint.h>

int main(void) {
    __builtin_v6clang_out(0xED, 0x42);
    __builtin_v6clang_hlt();
    return 0;
}
