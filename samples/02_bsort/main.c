// Bubble-sort demo: sorts a statically initialized array and emits each
// element on the debug port.
//
// Build and run:
//   samples\02_bsort\build.bat
//
// Expected output on port 0xED:
//   0x42 0x43 0x44 0x45 0x46 0x47 0x48 0x49
//   0x4A 0x4B 0x4C 0x4D 0x4E 0x4F 0x50 0x51
//
#include <stdint.h>

#define N 16

// Statically initialised random data.
static uint8_t arr[N] = {
    0x0F, 0x0E, 0x0D, 0x0C, 0x0B, 0x0A, 0x09, 0x08,
    0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00,
};

__attribute__((noinline))
static void bsort(uint8_t *a, uint8_t n) {
    for (uint8_t i = 0; i < n - 1; i++) {
        for (uint8_t j = 0; j < n - 1 - i; j++) {
            if (a[j] > a[j + 1]) {
                uint8_t tmp = a[j];
                a[j]     = a[j + 1];
                a[j + 1] = tmp;
            }
        }
    }
}

__attribute__((noinline))
static void print_arr(const uint8_t *a, uint8_t n) {
    for (uint8_t i = 0; i < n; i++) {
        __builtin_v6clang_out(0xED, a[i] + 0x42);
    }
}

int main(void) {
    __builtin_v6clang_di();
    bsort(arr, N);
    print_arr(arr, N);
    __builtin_v6clang_hlt();
    return 0;
}
