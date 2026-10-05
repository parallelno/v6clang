// O78 — V6CLANG_STORE8_IMM_P per-shape redesign feature test.
//
// Exercises the seven shapes of the new dispatch table:
//   row 1: addr=HL                                   → MVI M, imm
//   row 2: addr=BC, A dead                           → MVI A,imm; STAX B
//   row 3: addr=DE, A dead                           → MVI A,imm; STAX D
//   row 4: addr=DE, A live                           → XCHG; MVI M; XCHG
//   row 5: addr=BC, A live, HL dead                  → MOV L,C; MOV H,B; MVI M
//   row 6: addr=BC, A live, HL live, DE dead         → MOV D,B; MOV E,C; XCHG; MVI M; XCHG
//   row 7: addr=BC, all live                         → PUSH H; ...; POP H (legacy)
//
// Free-list CC pinning: 1st i16 arg → HL, 2nd → DE, 3rd → BC.
// Inline-asm OUT 0xde sinks force the named operand live across the store.

#include <stdint.h>

// Row 1: addr=HL.
void test_hl(uint8_t *hl_ptr) {
    *hl_ptr = 0x42;
}

// Row 2: addr=BC, A dead. (HL/DE consumed first; A unused after store.)
void test_bc_a_dead(unsigned hl_keep, unsigned de_keep, uint8_t *bc_ptr) {
    *bc_ptr = 0x42;
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
    asm volatile ("OUT 0xde" :: "r"(de_keep));
}

// Row 3: addr=DE, A dead.
void test_de_a_dead(unsigned hl_keep, uint8_t *de_ptr) {
    *de_ptr = 0x42;
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
}

// Row 4: addr=DE, A live (a_keep sink keeps A live).
void test_de_a_live(unsigned hl_keep, uint8_t *de_ptr, uint8_t a_keep) {
    *de_ptr = 0x42;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
}

// Row 5: addr=BC, A live, HL dead.
// Sink hl_keep BEFORE the store so HL is dead at the pseudo;
// keep a_keep & de_keep alive past the store.
void test_bc_hl_dead(unsigned hl_keep, unsigned de_keep,
                          uint8_t *bc_ptr, uint8_t a_keep) {
    asm volatile ("OUT 0xde" :: "r"(hl_keep)); // HL consumed before store
    *bc_ptr = 0x42;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(de_keep));
}

// Row 6: addr=BC, A live, HL live, DE dead.
// Sink de_keep before the store (DE dead). Keep hl_keep alive past the
// store (HL live). Keep a_keep alive past the store (A live).
void test_bc_de_dead(unsigned hl_keep, unsigned de_keep,
                    uint8_t *bc_ptr, uint8_t a_keep) {
    asm volatile ("OUT 0xde" :: "r"(de_keep)); // DE consumed before store
    *bc_ptr = 0x42;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
}

// Row 7: addr=BC, all live.
void test_bc_all_live(unsigned hl_keep, unsigned de_keep,
                      uint8_t *bc_ptr, uint8_t a_keep) {
    *bc_ptr = 0x42;
    asm volatile ("OUT 0xde" :: "a"(a_keep));
    asm volatile ("OUT 0xde" :: "r"(hl_keep));
    asm volatile ("OUT 0xde" :: "r"(de_keep));
}

// Driver — calls every test so the assembly is fully comparable.
volatile uint8_t  g_a    = 0x12;
volatile uint8_t  g_buf[1] = { 0x00 };
volatile unsigned g_hl   = 0x1234;
volatile unsigned g_de   = 0x5678;

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    uint8_t *p = (uint8_t *)g_buf;
    test_hl(p);
    test_bc_a_dead(g_hl, g_de, p);
    test_de_a_dead(g_hl, p);
    test_de_a_live(g_hl, p, g_a);
    test_bc_hl_dead(g_hl, g_de, p, g_a);
    test_bc_de_dead(g_hl, g_de, p, g_a);
    test_bc_all_live(g_hl, g_de, p, g_a);
    return 0;
}
