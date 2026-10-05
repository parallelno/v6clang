extern volatile unsigned char filler_block[40];
extern volatile unsigned char anchor_block[300];
extern volatile unsigned char window_block[200];

static unsigned char check_zero(volatile unsigned char *block,
                                unsigned short last) {
    return block[0] == 0 && block[last] == 0;
}

int main(void) {
    unsigned char ok = check_zero(filler_block, 39) &&
                       check_zero(anchor_block, 299) &&
                       check_zero(window_block, 199);

    filler_block[0] = 0x11;
    filler_block[39] = 0x12;
    anchor_block[0] = 0x21;
    anchor_block[299] = 0x22;
    window_block[0] = 0x31;
    window_block[199] = 0x32;

    ok = ok && filler_block[0] == 0x11 && filler_block[39] == 0x12 &&
         anchor_block[0] == 0x21 && anchor_block[299] == 0x22 &&
         window_block[0] == 0x31 && window_block[199] == 0x32;
    __builtin_v6clang_out(0xED, ok ? 0x5A : 0xEE);
    return 0;
}
