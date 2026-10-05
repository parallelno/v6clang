// Test case for O62: Efficient i16 Shift Expansion (Constant Amount).
//
// Each function forces the original value to remain live across the
// shift (by storing it through *p) so that the register allocator
// must place the shift's destination in a different register pair from
// its source. This triggers the V6CLANG_S{HL,RL,RA}16 expander branch
// where the leading 2-MOV "Src -> Dst" copy is dead for ShAmt >= 8.
//
// Coverage matrix:
//
//   type   | shl  | srl/sra
//   -------+------+--------
//   u16    |  X   |   X     <-- O62 target (>=8)
//   i16    |  X   |   X     <-- O62 target (>=8, sra also)
//   u8     |  X   |   X     <-- routed via V6CLANG_S*16 amt 1..7 (NOT improved)
//   i8     |  X   |   X     <-- routed via V6CLANG_S*16 amt 1..7 (NOT improved)

// ---------- u16 (O62 primary target) ----------
void u16_shl8 (unsigned int  x, unsigned int  *p, unsigned int  *q) { *p = x; *q = x << 8;  }
void u16_shl10(unsigned int  x, unsigned int  *p, unsigned int  *q) { *p = x; *q = x << 10; }
void u16_srl8 (unsigned int  x, unsigned int  *p, unsigned int  *q) { *p = x; *q = x >> 8;  }
void u16_srl10(unsigned int  x, unsigned int  *p, unsigned int  *q) { *p = x; *q = x >> 10; }

// ---------- i16 (O62 primary target, includes sra) ----------
void i16_shl8 (         int  x,          int  *p,          int  *q) { *p = x; *q = x << 8;  }
void i16_shl10(         int  x,          int  *p,          int  *q) { *p = x; *q = x << 10; }
void i16_sra8 (         int  x,          int  *p,          int  *q) { *p = x; *q = x >> 8;  }
void i16_sra10(         int  x,          int  *p,          int  *q) { *p = x; *q = x >> 10; }

// ---------- u8 / i8 left shift (control case: pure i8 ALU, no V6CLANG_S*16) ----------
// shl const lowers to repeated `ADD A, A` in i8 domain; never enters
// the 16-bit pseudo path that O62 rewrites. O62 must not regress these.
void u8_shl3(unsigned char x, unsigned char *p, unsigned char *q) { *p = x; *q = x << 3; }
void i8_shl3(  signed char x,   signed char *p,   signed char *q) { *p = x; *q = x << 3; }

// NOTE: u8_srl3 / i8_sra3 are intentionally omitted. They route through
// V6ClangISD::SRL16/SRA16 with ShAmt=3 (the unchanged `< 8` branch of
// V6CLANG_S*L16 / V6CLANG_SRA16, so unaffected by O62), but they also trigger a
// PRE-EXISTING ISel gap ("Cannot select: trunc-store i16 -> i8" on the
// post-shift TRUNCATE store). That bug is separate from O62 and is
// noted as Future Enhancement §7 in plan_efficient_shift_expansion.md.

unsigned int  u16_p, u16_q;
         int  i16_p, i16_q;
unsigned char u8_p,  u8_q;
  signed char i8_p,  i8_q;

int main(void) {
    u16_shl8 (0x1234, &u16_p, &u16_q);
    u16_shl10(0x1234, &u16_p, &u16_q);
    u16_srl8 (0x1234, &u16_p, &u16_q);
    u16_srl10(0x1234, &u16_p, &u16_q);

    i16_shl8 (-1234,  &i16_p, &i16_q);
    i16_shl10(-1234,  &i16_p, &i16_q);
    i16_sra8 (-1234,  &i16_p, &i16_q);
    i16_sra10(-1234,  &i16_p, &i16_q);

    u8_shl3(0x12, &u8_p, &u8_q);
    i8_shl3(0x12, &i8_p, &i8_q);
    return 0;
}
