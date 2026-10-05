volatile unsigned char byte_sink;
volatile unsigned word_sink;

__attribute__((noinline)) void leaf(unsigned value) {
    unsigned local = value + 1;
    word_sink = local;
}

__attribute__((noinline)) void middle(unsigned value) {
    leaf(value + 2);
    byte_sink = (unsigned char)value;
}

int main(void) {
    byte_sink = 0x5a;
    middle(3);
    return 0;
}
