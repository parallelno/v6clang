// O84 — INX/DCX-through-spill round-trip fold test case.
//
// Uses a simplified Sieve of Eratosthenes kernel (SIZE=200) which is known
// to generate INX/DCX-through-spill round-trip sequences in the outer loop:
//
//   MOV   C, L         ; save HL into BC
//   MOV   B, H         ;
//   INX   B            ; BC++  (the actual increment)
//   MOV   L, C         ; restore L from BC
//   MOV   H, B         ; restore H from BC
//   SHLD  .LLo61_12+1  ; write HL back to spill slot
//
// BC is dead after SHLD.  The four MOVs are pure round-trip overhead.
// After O84 the sequence is replaced with:
//   INX   H
//   SHLD  .LLo61_12+1
//
// A second Pattern B also appears (.LLo61_10, .LLo61_12):
//   MOV   B, H
//   MOV   C, L
//   MOV   L, C         ; no-op restore
//   MOV   H, B         ; no-op restore
//   SHLD  ...
// After O84 the four MOVs are simply dropped.
//
// Compile (baseline, before O84):
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
//       tests\features\65\v6clang.c -o tests\features\65\v6clang_old.asm

typedef unsigned short u16;
typedef unsigned char  u8;

static u8 flags[200];

// sieve_count: count primes up to n using the Sieve of Eratosthenes.
// The outer loop body (i_sq update) generates ADD16 + SPILL16 + INX16
// sequences that expose the INX/DCX-through-spill round-trip pattern.
u16 sieve_count(u16 n) {
    u16 i, k, count, i_sq;

    for (k = 0; k < n; k++) flags[k] = 0;

    count = (u16)(n - 2);
    i_sq  = 4;
    for (i = 2; i_sq < n; ++i) {
        if (!flags[i]) {
            for (k = i_sq; k < n; k = (u16)(k + i)) {
                if (!flags[k]) count = (u16)(count - 1);
                flags[k] = 1;
            }
        }
        i_sq = (u16)(i_sq + i + i + 1);   /* (n+1)^2 = n^2 + 2n + 1 */
    }
    return count;
}

int main(void) {
    u16 c = sieve_count(200);
    /* XOR the two bytes to get a single-byte result */
    return (int)((u8)c ^ (u8)(c >> 8));
}
