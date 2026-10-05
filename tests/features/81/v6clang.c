volatile int sink;

__attribute__((noinline))
int transform(int value) {
    return value + 1;
}

__attribute__((noinline))
void consume(int first, int second, int third) {
    sink = first + second + third;
}

__attribute__((noinline))
int optimized_locations(int input) {
    int first = transform(input);
    int second = transform(first);
    int third = transform(second);
    consume(first, second, third);
    __asm__ volatile("HLT" : : "p"(first) : "memory");
    sink = first + second + third;
    return second;
}

int main(void) {
    return optimized_locations(0x1234);
}