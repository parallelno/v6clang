; TEST: bsort
; DESC: Bubble sort an 8-element uint8 array in memory; OUT each sorted value.
;       Regression test for O27 i16-zero-test polarity bug — the outer-loop
;       guard `(n - 1 - i) > 0` is exactly the `sgt i16, 0` pattern that
;       triggered the inverted JNZ in V6CLANG_BR_CC16_IMM. Pure-asm version here
;       proves the algorithm; the compiled-C variant lives in
;       tests/features/43/v6clang_bsort_spillfrwd.c.
; EXPECT_HALT: yes
; EXPECT_OUTPUT: 1, 2, 3, 4, 5, 6, 7, 8

    .org 0
    LXI SP, 0xFFFF

    ; ----- bubble sort -----
    ; arr (DE) base address, n (B) length
    ; for (i = n - 1; i > 0; i--)
    ;   for (j = 0; j < i; j++)
    ;     if (arr[j] > arr[j+1]) swap

    LXI D, ARR              ; DE = base
    MVI B, 8                ; B = n

    DCR B                   ; B = n - 1 = outer trip count
outer_loop:
    MOV A, B
    ORA A                   ; outer counter == 0?
    JZ done

    MOV C, B                ; C = inner trip count = i
    PUSH D                  ; save base
    ; HL = &arr[0]
    XCHG                    ; HL = base
inner_loop:
    MOV A, M                ; A = arr[j]
    INX H
    CMP M                   ; A - arr[j+1]; carry=1 if A < arr[j+1]
    JC no_swap              ; arr[j] < arr[j+1] → no swap
    JZ no_swap              ; equal → no swap

    ; swap arr[j] (HL-1 indirect via DCX/INX) with arr[j+1] (HL)
    MOV D, M                ; D = arr[j+1]
    DCX H                   ; HL = &arr[j]
    MOV E, M                ; E = arr[j]
    MOV M, D                ; arr[j] = D
    INX H                   ; HL = &arr[j+1]
    MOV M, E                ; arr[j+1] = E
    JMP inner_step

no_swap:
    ; HL already at &arr[j+1]; nothing else needed

inner_step:
    DCR C
    JNZ inner_loop

    POP D                   ; restore base
    DCR B
    JMP outer_loop

done:
    ; ----- print sorted array -----
    LXI H, ARR
    MVI B, 8
print_loop:
    MOV A, M
    OUT 0xED
    INX H
    DCR B
    JNZ print_loop

    HLT

ARR:
    DB 7, 3, 5, 1, 8, 2, 6, 4
