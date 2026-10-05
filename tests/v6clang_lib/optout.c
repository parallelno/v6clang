/* O70 Step 3.15 — opt-out validation.
 *
 * Compile with:
 *   llvm-build\bin\clang.exe --target=i8080-unknown-v6clang -O2 \
 *       -fno-v6clang-auto-include optout.c -o optout.rom
 *
 * Expected: ld.lld linker error  "undefined symbol: __mulhi3"
 *           (and similar for any other operator used). This documents
 *           that -fno-v6clang-auto-include genuinely suppresses the runtime
 *           and the user is on their own.
 *
 * Used by hand-rolled toolchain authors who supply their own runtime.
 * Not part of automated regression — link-failure-as-success is awkward
 * to script.
 */

typedef unsigned short u16;
typedef unsigned char  u8;

static void out_port(u8 port, u8 v) { __builtin_v6clang_out(port, v); }

int main(void) {
    /* Force a libcall ISel cannot inline. */
    volatile u16 a = 0x1234, b = 0x5678;
    u16 r = a * b;
    out_port(0xED, (u8)r);
    __builtin_v6clang_hlt();
    __builtin_unreachable();
    return 0;
}
