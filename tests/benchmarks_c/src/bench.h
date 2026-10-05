/*
 * bench.h - Per-compiler glue for V6CLANG / i8080 C-compiler benchmarks.
 *
 * Every benchmark program ends with bench_finish(checksum):
 *   - writes the checksum byte to port 0xED (TEST_OUT)
 *   - executes HLT
 *
 * v6emul --halt-exit --dump-cpu prints:
 *   TEST_OUT port=0xED value=0x..    <-- checksum (correctness invariant)
 *   HALT at PC=0x.... after N cpu_cycles M frames
 *
 * Detection macros:
 *   __V6CLANG__          -> v6clang (clang -target i8080-unknown-v6clang)
 *   __C8080_COMPILER -> c8080
 *   __SCCZ80         -> z88dk sccz80
 *   __ACK            -> Amsterdam Compiler Kit (best-effort)
 *
 * NOTE: c8080's preprocessor mishandles `#elif defined(...)` chains:
 * function bodies inside an #elif branch are silently dropped at
 * code-gen time. We therefore use independent `#ifdef/#endif`
 * blocks plus a `BENCH_HAVE_FINISH` sentinel.
 */
#ifndef BENCH_H
#define BENCH_H

typedef unsigned char  u8;
typedef unsigned short u16;

/* ------------------------------------------------------------------ */
#ifdef __V6CLANG__
static inline void bench_finish(unsigned char checksum) {
    __builtin_v6clang_out(0xED, checksum);
    __builtin_v6clang_hlt();
    __builtin_unreachable();
}
#define BENCH_HAVE_FINISH 1
#endif

/* ------------------------------------------------------------------ */
#ifdef __C8080_COMPILER
/* In c8080 __global mode the lone u8 arg arrives in A. */
void __global bench_finish(unsigned char checksum) {
    asm {
        out  (0xED), a
        halt
    }
}
#define BENCH_HAVE_FINISH 1
#endif

/* ------------------------------------------------------------------ */
#if defined(__SCCZ80) || defined(SCCZ80) || defined(__Z88DK)
/* sccz80 (z88dk +cpm -clib=8080) passes the i8 arg as the low byte
 * of a 16-bit stack slot. */
void bench_finish(unsigned char checksum) {
#asm
    pop  bc          ; ret addr -> BC
    pop  hl          ; checksum lo in L
    ld   a, l
    out  (0xED), a
    halt
#endasm
}
#define BENCH_HAVE_FINISH 1
#endif

/* ------------------------------------------------------------------ */
#ifdef __ACK
extern void bench_finish(unsigned char checksum);
#define BENCH_HAVE_FINISH 1
#endif

#ifndef BENCH_HAVE_FINISH
extern void bench_finish(unsigned char checksum);
#endif

#endif /* BENCH_H */
