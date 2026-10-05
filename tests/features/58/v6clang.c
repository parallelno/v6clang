// O76 — V6CLANG_LOAD8_P per-shape redesign feature test.
//
// Exercises the new priority-4 sub-shapes:
//   - case7_de_b/c/h/l : addr=DE, dst=non-A, A live → XCHG bypass (3B/16cc)
//   - case6a_bc_b      : addr=BC, dst=non-A, A live, SpareR avail → SpareR-A (4B/32cc)
// Plus a control case that exercises the unchanged paths.
//
// All test functions take (de_ptr, hl_keep, a_keep) and pin:
//   - HL = hl_keep   (1st i16 arg via free-list CC)
//   - DE = de_ptr    (2nd i16 arg)
//   - A  = a_keep    (1st i8 arg, which exhausts the i8 list down to A)
//
// The trailing inline-asm sinks force HL, A, and the loaded value
// to be live-out of the load, ensuring priority-4 (A live) fires.

#include <stdint.h>

void test_de_b(unsigned hl_keep, const uint8_t *de_ptr, uint8_t a_keep) {
    register uint8_t v asm("B");
    v = *de_ptr;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
    asm volatile ("OUT 0xde" :: "r"(v));
}

void test_de_c(unsigned hl_keep, const uint8_t *de_ptr, uint8_t a_keep) {
    register uint8_t v asm("C");
    v = *de_ptr;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
    asm volatile ("OUT 0xde" :: "r"(v));
}

void test_de_h(unsigned hl_keep, const uint8_t *de_ptr, uint8_t a_keep) {
    register uint8_t v asm("H");
    v = *de_ptr;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(v));
}

void test_de_l(unsigned hl_keep, const uint8_t *de_ptr, uint8_t a_keep) {
    register uint8_t v asm("L");
    v = *de_ptr;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(v));
}

// addr=DE, dst=D, with HL, BC, A live across the load. DE itself is
// dead-after the load (only D — half of DE — is consumed downstream),
// so RA legally allocates dst=D and the XCHG bypass fires with the
// partner-MOV trick `MOV H, M`. Expected:
//   XCHG; MOV H, M; XCHG
// After the second XCHG, D = loaded byte, E = (clobbered, dead),
// HL = original HL (preserved), BC = original BC (untouched).
void test_de_d(unsigned hl_keep, const uint8_t *de_ptr,
               unsigned bc_keep, uint8_t a_keep) {
    register uint8_t v asm("D");
    v = *de_ptr;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
    asm volatile ("OUT 0xde" :: "r"(bc_keep));
    asm volatile ("OUT 0xde" :: "r"(v));
}

// addr=BC, dst=B, A live. Force pointer to BC by consuming HL+DE first.
void test_bc_b(unsigned hl_keep, unsigned de_keep, const uint8_t *bc_ptr, uint8_t a_keep) {
    register uint8_t v asm("B");
    v = *bc_ptr;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
    asm volatile ("OUT 0xde" :: "r"(de_keep));
    asm volatile ("OUT 0xde" :: "r"(v));
}

// Driver — exercises every test function so the assembly is comparable.
volatile uint8_t  g_a    = 0x12;
volatile uint8_t  g_buf[1] = { 0x77 };
volatile unsigned g_hl   = 0x1234;
volatile unsigned g_de   = 0x5678;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    const uint8_t *p = (const uint8_t *)g_buf;
    test_de_b(g_hl, p, g_a);
    test_de_c(g_hl, p, g_a);
    test_de_h(g_hl, p, g_a);
    test_de_l(g_hl, p, g_a);
    test_de_d(g_hl, p, g_de, g_a);
    test_bc_b(g_hl, g_de, p, g_a);
    return 0;
}
