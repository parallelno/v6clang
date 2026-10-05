// O43: SHLD/LHLD to PUSH/POP — feature test
// Two-array summation loop that triggers HL spills in static stack mode.

volatile int arr1[200];
volatile int arr2[200];

int sumarray(void) {
    int sum = 0;
    for (int i = 0; i < 200; ++i)
        sum += arr1[i] + arr2[i];
    return sum;
}

int main(void) {
    return sumarray();
}
