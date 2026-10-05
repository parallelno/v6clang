// O83 — POP/PUSH pair elimination test case.
//
// Uses a simplified Sieve of Eratosthenes kernel (SIZE=200) which is known
// to generate redundant POP/PUSH pairs in the outer loop maintenance code.
// The pairs arise when:
//   (a) V6CLANG_ADD16 pseudo expansion wraps DAD with PUSH/POP HL, and
//   (b) the immediately following V6CLANG_SPILL16 also begins with PUSH HL.
// Both the ADD16-epilogue POP and the SPILL16-prologue PUSH are redundant
// because HL is immediately overwritten by the spill's MOV H,B / MOV L,C.
//
// Case 1 (trivially adjacent):
//   POP H          ← ADD16 epilogue, restores HL
//   PUSH H         ← SPILL16 prologue, saves same HL  (redundant pair)
//   MOV L, C       HL overwritten ⇒ HL dead at PUSH H
//   MOV H, B
//
// Case 3 (INX B between):
//   POP H          ← RELOAD16 epilogue
//   INX B          does not touch HL
//   PUSH H         ← SPILL16 prologue (redundant pair)
//   MOV L, C       HL overwritten ⇒ HL dead at PUSH H
//   MOV H, B
//
// After O83 both pairs are eliminated.
//
// Compile (baseline, before O83):
//   llvm-build\bin\clang -target i8080-unknown-v6clang -O2 -S ^
//       tests\features\64\v6clang.c -o tests\features\64\v6clang_old.asm

typedef unsigned short u16;
typedef unsigned char  u8;

static u8 flags[200];

// sieve_count: count primes up to n using the Sieve of Eratosthenes.
// The outer loop body (i_sq update) generates ADD16 + SPILL16 + INX16
// sequences that expose the redundant POP/PUSH pattern.
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
