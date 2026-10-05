// O44 Adjacent XCHG Cancellation — feature test (v6clang version)
// Tests that adjacent XCHG pairs from consecutive DE spill/reload
// expansions are eliminated by the peephole pass.

volatile int arr1[100];
volatile int arr2[100];

// Two-array summation: triggers SPILL16-DE + LOAD16_P-DE adjacent pairs
// when compiled with --enable-deferred-spilling.
int sumarray(void) {
    int sum = 0;
    for (int i = 0; i < 100; ++i)
        sum += arr1[i] + arr2[i];
    return sum;
}

int main(void) {
    return sumarray();
}
