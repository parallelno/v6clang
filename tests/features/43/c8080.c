// c8080 reference for O51 test. Same shape as v6clang.c.

#define N 8

int OUT[N];
int A[N];
int B[N];
int C[N];
int D1[N];
int D2[N];

int g_dot;

void axpy3(int *out, int *a, int *b, int *c, unsigned n) {
    unsigned i;
    for (i = 0; i < n; i = i + 1) {
        out[i] = a[i] + b[i] + c[i];
    }
}

int dot(int *a, int *b, unsigned n) {
    unsigned i;
    int acc;
    acc = 0;
    for (i = 0; i < n; i = i + 1) {
        acc = acc + a[i] * b[i];
    }
    return acc;
}

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
