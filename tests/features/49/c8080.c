// Conditional Call Optimization c8080 baseline.
// Same workload as v6clang.c, adapted for c8080 (no __attribute__,
// no stdint, main has argc/argv).

extern void notify(void);
extern unsigned char observed;

unsigned char cb_eq(unsigned char x) {
    if (x == 0) notify();
    return observed + 1;
}

unsigned char cb_ne(unsigned char x) {
    if (x != 0) notify();
    return observed + 1;
}

unsigned char cb_ult(unsigned int x) {
    if (x < 100) notify();
    return observed + 1;
}

unsigned char cb_uge(unsigned int x) {
    if (x >= 100) notify();
    return observed + 1;
}

unsigned char cb_slt(int x) {
    if (x < 0) notify();
    return observed + 1;
}

unsigned char cb_sge(int x) {
    if (x >= 0) notify();
    return observed + 1;
}

extern unsigned char produce(void);

unsigned char cb_value_used(unsigned char x) {
    unsigned char v;
    v = 7;
    if (x) v = produce();
    return v + observed;
}

unsigned char observed;

void notify(void) { observed += 1; }
unsigned char produce(void) { return observed + 5; }

int main(int argc, char **argv) {
    cb_eq(0);
    cb_ne(1);
    cb_ult(50);
    cb_uge(200);
    cb_slt(-1);
    cb_sge(0);
    return cb_value_used(5) + observed;
}
