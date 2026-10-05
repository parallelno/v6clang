typedef unsigned int word_t;

enum mode { mode_zero, mode_one = 7 };

struct layout {
    unsigned char tag;
    word_t value;
    int values[3];
    enum mode current;
};

volatile int sink;
volatile struct layout sample = { 0xA5, 0x1234, { 0x0102, 0x3456, 0x789A }, mode_one };

__attribute__((always_inline)) static inline int inline_leaf(int value) {
    int local = value + sample.values[1];
    sink = local;
    __asm__ volatile("HLT" : : "p"(local) : "memory");
    return local;
}

__attribute__((always_inline)) static inline int inline_outer(int value) {
    return inline_leaf(value + sample.value);
}

__attribute__((noinline))
int inline_entry(int value) {
    return inline_outer(value);
}

int main(void) {
    return inline_entry(sample.tag + sample.current);
}