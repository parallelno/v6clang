// Test case for O51 — LSR Cost Tuning (isLSRCostLess Insns-first).
//
// The functions below put four streams (axpy3 — out, a, b, c) and three
// streams (dot — a, b, accumulator) under register pressure. The current
// register-first LSR ordering collapses pointer IVs and reloads bases
// every iteration. With `-mllvm -v6clang-lsr-insns-first` LSR keeps separate
// pointer IVs and the inner loop becomes mostly INX rp / MOV M-r.
//
// scale_copy is the control case (only 2 pointers + counter — fits 3 GP
// pairs). Both orderings should produce the same asm here.
//
// Compile baseline / new:
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\43\v6clang.c -o tests\features\43\v6clang_old.asm
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S \
//       tests\features\43\v6clang.c -o tests\features\43\v6clang_new01.asm \
//       -mllvm -v6clang-lsr-insns-first

#define N 8

int OUT[N];
int A[N];
int B[N];
int C[N];
int D1[N];
int D2[N];

int g_dot;

// Four-stream loop: out = a + b + c element-wise. Four live pointers
// + counter against three register pairs. The headline pressure case.
void axpy3(int *out, int *a, int *b, int *c, unsigned n) {
    unsigned i;
    for (i = 0; i < n; i = i + 1) {
        out[i] = a[i] + b[i] + c[i];
    }
}

// Three streams: two pointers + accumulator + counter. The accumulator
// adds enough pressure to force a similar collapse under register-first.
int dot(int *a, int *b, unsigned n) {
    unsigned i;
    int acc;
    acc = 0;
    for (i = 0; i < n; i = i + 1) {
        acc = acc + a[i] * b[i];
    }
    return acc;
}

// Two pointers + counter — fits in three pairs. Control case.
void scale_copy(int *dst, int *src, unsigned n) {
    unsigned i;
    for (i = 0; i < n; i = i + 1) {
        dst[i] = src[i] + src[i];
    }
}

void seed(void) {
    unsigned i;
    for (i = 0; i < N; i = i + 1) {
        A[i] = (int)i;
        B[i] = (int)(i + 1);
        C[i] = (int)(i + 2);
        D1[i] = 0;
        D2[i] = 0;
    }
}

int main(int argc, char **argv) {
    (void)argc; (void)argv;
    seed();
    axpy3(OUT, A, B, C, N);
    g_dot = dot(A, B, N);
    scale_copy(D1, D2, N);
    return OUT[0] + g_dot + D1[0];
}
