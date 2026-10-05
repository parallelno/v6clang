#define N 16
#include <stdint.h>
uint8_t ARR[N];

// Bubble sort with one while loop for less register pressure.
__attribute__((noinline))
void bsort_for(uint8_t *arr, uint8_t n) {
    uint8_t i = 0;
    for(i = 0; i < n - 1; i++) {
        uint8_t j = 0;
        while (j < n - 1 - i) {
            uint8_t a = arr[j];
            uint8_t b = arr[j + 1];
            if (a > b) {
                arr[j]     = b;
                arr[j + 1] = a;
            }
            j++;
        }
    }
}

__attribute__((noinline))
void print_arr(uint8_t *arr, uint8_t n) {
    for (uint8_t i = 0; i < n; i++) {
        __builtin_v6clang_out(0xED, arr[i]);
    }
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    __builtin_v6clang_di();
    __builtin_v6clang_hlt();
    bsort_for(ARR, N);
    print_arr(ARR, N);
    __builtin_v6clang_hlt();
    return 0;
}
