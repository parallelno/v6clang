// Test case for O6: LDA/STA for Absolute Address Loads/Stores
// Tests that loads/stores from constant integer addresses use
// LDA/STA instead of LXI + MOV A,M / MOV M,A.

// Memory-mapped I/O ports at fixed addresses
#define PORT_A  (*(volatile unsigned char*)0x100)
#define PORT_B  (*(volatile unsigned char*)0x200)

// Test 1: Read from constant address → should use LDA
unsigned char read_port(void) {
    return PORT_A;
}

// Test 2: Write to constant address → should use STA
void write_port(unsigned char val) {
    PORT_A = val;
}

// Test 3: Copy between ports (read + write) → LDA + STA
void copy_port(void) {
    PORT_B = PORT_A;
}

int main(void) {
    write_port(42);
    copy_port();
    unsigned char r = read_port();
    return r;
}
