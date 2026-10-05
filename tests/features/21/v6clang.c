// Static Stack Allocation — O10 feature test
// Test: non-reentrant functions with spills should use static memory
// instead of stack-relative access (eliminating DAD SP and prologue/epilogue).

// Provide implementations so LLVM can prove functions are non-recursive.
// (PostOrderFunctionAttrs needs visible callee bodies to infer norecurse.)
// noinline prevents inlining which would increase register pressure.
volatile int sink_val;
__attribute__((noinline)) void use_val(int x) { sink_val = x; }
__attribute__((noinline)) int get_val(void)    { return sink_val; }

// Case 1: Three values live across calls — forces spills with only 3 reg pairs.
int heavy_spill(int a, int b) {
    int x = a + 1;
    int y = b + 2;
    int z = a + b;
    use_val(x);     // y, z must survive → needs 2 of 3 pairs + HL for call arg
    use_val(y);     // x, z must survive
    use_val(z);     // x, y must survive
    return x + y + z;
}

// Case 2: Nested calls with values preserved.
int nested_calls(int n) {
    int a = get_val();
    int b = get_val();
    int c = a + b + n;
    use_val(c);     // a, b must survive
    return a + b;
}

int main(void) {
    int r;
    r = heavy_spill(10, 20);
    use_val(r);
    r = nested_calls(5);
    use_val(r);
    return r;
}
