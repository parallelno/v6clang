# O6. LDA/STA for Absolute Address Loads

## Problem

Loading from a known constant address currently generates `LXI HL, addr`
(10cc, 3 bytes) + `MOV A, M` (8cc, 1 byte) = 18cc, 4 bytes.
The 8080 has `LDA addr` (16cc, 3 bytes) which loads directly from a
16-bit address into A — fewer bytes and comparable speed.

## Before → After

```asm
; Before                          ; After
LXI  HL, 0     ; 10cc, 3B        LDA  0         ; 16cc, 3B
MOV  A, M      ;  8cc, 1B        ; saves 1 byte, 2cc slower
; Total: 18cc, 4B                 ; Total: 16cc, 3B  ← actually FASTER
```

Note: on standard i8080, LDA is 13cc and LXI+MOV is 17cc. On Vector 06c
the timings differ (LDA = 16cc, LXI = 10cc, MOV r,M = 8cc = 18cc total).
So LDA saves 2cc AND 1 byte.

## Implementation

ISel pattern: when loading `i8` from a constant address into A, select
`LDA` instead of `LXI` + `V6CLANG_LOAD8_P`. Similarly `STA` for stores.

## Benefit

- **Savings per instance**: 2cc + 1 byte
- **Frequency**: Common in memory-mapped I/O, global variable access
- **Test case savings**: 6cc (three absolute loads)

## Complexity

Low. Simple ISel pattern addition.

## Risk

Low. LDA/STA are well-defined 8080 instructions. Only affects loads/stores
where dest/src is A and address is a constant.
