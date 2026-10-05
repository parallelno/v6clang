// O42 Liveness-Aware Pseudo Expansion — feature test (v6clang version)
// Tests PUSH/POP elimination when preserved register is dead.

volatile int arr1[100];
volatile int arr2[100];

// Two-array summation: causes BC spills/reloads with HL dead
// at expansion points (HL killed by preceding SHLD spill).
int sumarray(void) {
    int sum = 0;
    for (int i = 0; i < 100; ++i)
        sum += arr1[i] + arr2[i];
    return sum;
}

// Single-array sum: simpler spill/reload pattern
volatile int data[50];
int singlesum(void) {
    int total = 0;
    for (int i = 0; i < 50; ++i)
        total += data[i];
    return total;
}

int main(void) {
    return sumarray() + singlesum();
}
