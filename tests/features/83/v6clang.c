volatile int sink;

__attribute__((always_inline)) static inline int inline_leaf(int value) {
    int local = value + 0x21;
    sink = local;
    __asm__ volatile("HLT" : : "p"(local) : "memory");
    return local;
}

__attribute__((always_inline)) static inline int inline_outer(int value) {
    int local = value + 0x10;
    return inline_leaf(local);
}

__attribute__((noinline))
int leaf(int parameter) {
    int local = parameter + 0x100;
    return inline_outer(local);
}

__attribute__((noinline))
int middle(int parameter) {
    int local = parameter + 0x200;
    return leaf(local);
}

int main(void) {
    return middle(0x1234);
}