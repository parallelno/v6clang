// Bubble sort microbenchmark for O51 — LSR Cost Tuning A/B comparison.
//
// Inner loop in `bsort` carries:
//   - j (counter)
//   - &arr[j], &arr[j+1] (two live i16 pointers)
//   - swap temporaries
// `bsort_two` raises pressure further by walking two extra output
// pointers alongside the in-place swap (4 live i16 IVs + counter).
// On a 3-pair GP target this puts the inner loop at the boundary
// where regs-first vs insns-first orderings can diverge.
//
// Compile A/B:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\43\v6clang_bsort.c \
//       -o tests\features\43\v6clang_bsort_regs.asm \
//       -mllvm -v6clang-lsr-strategy=regs-first
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\43\v6clang_bsort.c \
//       -o tests\features\43\v6clang_bsort_insns.asm \
//       -mllvm -v6clang-lsr-strategy=insns-first

#define N 16

int ARR[N];
int OUT_LO[N];
int OUT_HI[N];

// Classic ascending bubble sort over int[]. Two live pointers in the
// inner loop: &arr[j] and &arr[j+1].
void bsort(int *arr, int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - 1 - i; j++) {
            int a = arr[j];
            int b = arr[j + 1];
            if (a > b) {
                arr[j]     = b;
                arr[j + 1] = a;
            }
        }
    }
}

// Variant that walks two output streams alongside the in-place swap
// to raise inner-loop register pressure (4 live i16 IVs + counter).
void bsort_two(int *arr, int *out_lo, int *out_hi, int n) {
    for (int i = 0; i < n - 1; i++) {
        for (int j = 0; j < n - 1 - i; j++) {
            int a = arr[j];
            int b = arr[j + 1];
            int lo = a < b ? a : b;
            int hi = a < b ? b : a;
            arr[j]     = lo;
            arr[j + 1] = hi;
            out_lo[j]  = lo;
            out_hi[j]  = hi;
        }
    }
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    bsort(ARR, N);
    bsort_two(ARR, OUT_LO, OUT_HI, N);
    return ARR[0];
}
