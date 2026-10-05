// Test case for O32: XCHG in copyPhysReg
// Functions that return their second argument trigger DE->HL copy.
// With KillSrc=true, copyPhysReg should emit XCHG instead of MOV H,D; MOV L,E.

int return_second(int a, int b) {
    return b;
}

int select_second(int a, int b, int c) {
    if (a)
        return b;
    return c;
}

int add_and_return(int a, int b) {
    return a + b;
}

int main() {
    volatile int x;
    x = return_second(1, 2);
    x = select_second(1, 10, 20);
    x = add_and_return(3, 4);
    return 0;
}
