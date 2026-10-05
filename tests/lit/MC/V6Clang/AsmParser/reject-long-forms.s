; RUN: not clang --target=i8080-unknown-v6clang -c %s -o %t.o 2>&1 | FileCheck %s

; Long pair forms HL/DE/BC are NOT accepted in any instruction.

        PUSH    HL
; CHECK: error: invalid operand for instruction

        POP     DE
; CHECK: error: invalid operand for instruction

        INX     BC
; CHECK: error: invalid operand for instruction

        DCX     HL
; CHECK: error: invalid operand for instruction

        DAD     DE
; CHECK: error: invalid operand for instruction

        LDAX    BC
; CHECK: error: invalid operand for instruction

        STAX    DE
; CHECK: error: invalid operand for instruction

        LXI     HL, 0x1234
; CHECK: error: invalid operand for instruction

; LDAX / STAX must use B or D — never H.
        LDAX    H
; CHECK: error: invalid operand for instruction

        STAX    H
; CHECK: error: invalid operand for instruction
