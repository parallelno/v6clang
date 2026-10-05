// Test case for O62 — c8080 reference version.

void u16_shl8 (unsigned int  x, unsigned int  *p, unsigned int  *q) { *p = x; *q = x << 8;  }
void u16_shl10(unsigned int  x, unsigned int  *p, unsigned int  *q) { *p = x; *q = x << 10; }
void u16_srl8 (unsigned int  x, unsigned int  *p, unsigned int  *q) { *p = x; *q = x >> 8;  }
void u16_srl10(unsigned int  x, unsigned int  *p, unsigned int  *q) { *p = x; *q = x >> 10; }

// NOTE: i16_shl8/shl10 are intentionally omitted from the c8080
// reference — c8080 lowers signed 16-bit left shifts via __mulhi3
// and asserts on signed mul (OutMul16.cpp:26). v6clang.c keeps them
// because they exercise V6CLANG_SHL16, the O62 target.
void i16_sra8 (         int  x,          int  *p,          int  *q) { *p = x; *q = x >> 8;  }
void i16_sra10(         int  x,          int  *p,          int  *q) { *p = x; *q = x >> 10; }

void u8_shl3(unsigned char x, unsigned char *p, unsigned char *q) { *p = x; *q = x << 3; }
void i8_shl3(  signed char x,   signed char *p,   signed char *q) { *p = x; *q = x << 3; }

unsigned int  u16_p, u16_q;
         int  i16_p, i16_q;
unsigned char u8_p,  u8_q;
  signed char i8_p,  i8_q;

int main(int argc, char **argv) {
    u16_shl8 (0x1234, &u16_p, &u16_q);
    u16_shl10(0x1234, &u16_p, &u16_q);
    u16_srl8 (0x1234, &u16_p, &u16_q);
    u16_srl10(0x1234, &u16_p, &u16_q);

    i16_sra8 (-1234,  &i16_p, &i16_q);
    i16_sra10(-1234,  &i16_p, &i16_q);

    u8_shl3(0x12, &u8_p, &u8_q);
    i8_shl3(0x12, &i8_p, &i8_q);
    return 0;
}
