// extern_func is inlined into main; the inline asm emits CALL func1
// and lists only "a" + "memory" as clobbers. BC/DE must NOT be saved
// or restored around the call (verified by FileCheck on the .s listing
// in tests/lit/CodeGen/V6CLANG/inline-asm/clobber-style-b.ll).
#ifndef V6CLANG_INLINE_ASM_CLOBBER_EXTERNAL_H
#define V6CLANG_INLINE_ASM_CLOBBER_EXTERNAL_H

static inline __attribute__((always_inline)) void extern_func(void) {
    __asm__ volatile("CALL func1" : : : "A", "memory");
}

#endif
