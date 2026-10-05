/* O18 Loop Counter DEC+Branch Peephole - v6clang test */

extern volatile unsigned char output_port;

/* Simple countdown loop — counter in A, Pattern A */
void countdown(unsigned char n) {
    while (n != 0) {
        output_port = n;
        n--;
    }
}

/* Simple decrement-and-test loop */
unsigned char count_down(unsigned char n) {
    while (n != 0) {
        n--;
    }
    return n;
}

int main(int argc, char **argv) {
    countdown(5);
    return count_down(10);
}
