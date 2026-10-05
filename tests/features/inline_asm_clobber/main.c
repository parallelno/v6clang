// Phase 4 end-to-end test: inline-asm clobber lists honored AND
// --gc-sections drops asm functions unreachable from _start.
//
// Build (see run.py):
//   clang -target i8080-unknown-v6clang -O2 -ffunction-sections \
//         main.c external.s -Wl,--gc-sections -o out.rom
//
// Expected behavior:
//   _start (crt0) -> main -> [inline asm] CALL func1 -> CALL func2.
//   func1 emits '1', func2 emits '2', then HLT.
//   func3 and func4 are unreferenced -> dropped by --gc-sections.
//
// Expected v6emul TEST_OUT stream on port 0xED: 0x31 0x32  (i.e. "12").

#include "external.h"

int main(void) {
    extern_func();
    __builtin_v6clang_hlt();
    return 0;
}
