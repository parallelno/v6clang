volatile int sink;

__attribute__((noinline))
int static_probe(int parameter) {
    int local = parameter + 0x123;
    volatile int addressable = local + 1;
    sink = addressable;
    __builtin_v6clang_hlt();
    return local;
}

__attribute__((noinline))
int dynamic_probe(int parameter) {
    int local = parameter + 0x234;
    volatile int addressable = local + 1;
    sink = addressable;
    __builtin_v6clang_hlt();
    return local;
}

int (*volatile keep_dynamic)(int) = dynamic_probe;

int main(void) {
#ifdef DYNAMIC_PROBE
    return dynamic_probe(0x3344);
#else
    return static_probe(0x1122);
#endif
}
