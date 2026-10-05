// O77 — V6CLANG_STORE8_P per-shape redesign feature test.
//
// Exercises the new priority-4 sub-shapes:
//   - case7_de_b/c/d/e/h/l : addr=DE, src=non-A, A live → XCHG bypass (3B/16cc)
//   - case6a_bc_b          : addr=BC, src=non-A, A live, SpareR avail → SpareR-A (4B/32cc)
// Plus a control case that exercises the unchanged paths.
//
// Each test takes (de_ptr, hl_keep, a_keep) and pins:
//   - HL = hl_keep   (1st i16 arg via free-list CC)
//   - DE = de_ptr    (2nd i16 arg)
//   - A  = a_keep    (i8 arg)
//
// The trailing inline-asm sinks force HL, A, and the source value
// to be live-out of the store, ensuring priority-4 (A live) fires.

#include <stdint.h>

void test_de_b(unsigned hl_keep, uint8_t *de_ptr, uint8_t a_keep, uint8_t v_in) {
    register uint8_t v asm("B") = v_in;
    *de_ptr = v;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
}

void test_de_c(unsigned hl_keep, uint8_t *de_ptr, uint8_t a_keep, uint8_t v_in) {
    register uint8_t v asm("C") = v_in;
    *de_ptr = v;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
}

void test_de_h(unsigned hl_keep, uint8_t *de_ptr, uint8_t a_keep, uint8_t v_in) {
    register uint8_t v asm("H") = v_in;
    *de_ptr = v;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
}

void test_de_l(unsigned hl_keep, uint8_t *de_ptr, uint8_t a_keep, uint8_t v_in) {
    register uint8_t v asm("L") = v_in;
    *de_ptr = v;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
}

// Unlike the load (O76), src ∈ {D, E} for addr=DE is universally safe
// here — the XCHG bypass body MOV M,r writes only memory, so XCHG2
// fully restores DE regardless of post-pseudo liveness. Expected:
//   XCHG; MOV M, H; XCHG  (partner-MOV: D was swapped into H)
void test_de_d(unsigned hl_keep, uint8_t *de_ptr, uint8_t a_keep, uint8_t v_in) {
    register uint8_t v asm("D") = v_in;
    *de_ptr = v;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
}

// Expected: XCHG; MOV M, L; XCHG  (partner-MOV: E was swapped into L)
void test_de_e(unsigned hl_keep, uint8_t *de_ptr, uint8_t a_keep, uint8_t v_in) {
    register uint8_t v asm("E") = v_in;
    *de_ptr = v;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
}

// addr=BC, src=B, A live. Force pointer to BC by consuming HL+DE first.
// Expected: SpareR-A path (e.g. MOV D,A; MOV A,B; STAX B; MOV A,D).
void test_bc_b(unsigned hl_keep, unsigned de_keep, uint8_t *bc_ptr,
               uint8_t a_keep, uint8_t v_in) {
    register uint8_t v asm("B") = v_in;
    *bc_ptr = v;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
    asm volatile ("OUT 0xde" :: "r"(de_keep));
}

// Driver — exercises every test function so the assembly is comparable.
volatile uint8_t  g_a    = 0x12;
volatile uint8_t  g_v    = 0x77;
volatile uint8_t  g_buf[1] = { 0x00 };
volatile unsigned g_hl   = 0x1234;
volatile unsigned g_de   = 0x5678;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    uint8_t *p = (uint8_t *)g_buf;
    test_de_b(g_hl, p, g_a, g_v);
    test_de_c(g_hl, p, g_a, g_v);
    test_de_h(g_hl, p, g_a, g_v);
    test_de_l(g_hl, p, g_a, g_v);
    test_de_d(g_hl, p, g_a, g_v);
    test_de_e(g_hl, p, g_a, g_v);
    test_bc_b(g_hl, g_de, p, g_a, g_v);
    return 0;
}
