typedef signed char s8;
typedef signed short s16;

volatile s16 g_i16 = (s16)0x8123;
volatile s8 g_i8 = (s8)0x93;
volatile s16 out_i16;
volatile s8 out_i8;

s16 neg_i16_unary(s16 x) { return -x; }
/* c8080 accepts this spelling more reliably than casts in expressions. */
s16 neg_i16_mul_left(s16 x) { return (s16)(-1) * x; }
s16 neg_i16_mul_right(s16 x) { return x * (s16)(-1); }

s8 neg_i8_unary(s8 x) { return -x; }

s16 neg_i16_global_unary(void) { return -g_i16; }
s8 neg_i8_global_unary(void) { return -g_i8; }

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;

  out_i16 = neg_i16_unary(g_i16);
  out_i16 = neg_i16_mul_left(g_i16);
  out_i16 = neg_i16_mul_right(g_i16);
  out_i16 = neg_i16_global_unary();

  out_i8 = neg_i8_unary(g_i8);
  out_i8 = neg_i8_global_unary();
  return 0;
}