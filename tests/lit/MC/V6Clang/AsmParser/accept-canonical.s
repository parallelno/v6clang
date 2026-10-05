; RUN: clang --target=i8080-unknown-v6clang -c %s -o %t.o
; RUN: llvm-readelf -x .text %t.o | FileCheck %s

; Verify every i8080-canonical mnemonic class produces correct bytes.

        NOP                     ; 00
        MOV     A, B            ; 78
        MOV     M, A            ; 77
        MOV     A, M            ; 7E
        MVI     L, 0x42         ; 2E 42
        LDA     0x1234          ; 3A 34 12
        STA     0x5678          ; 32 78 56
        LDAX    D               ; 1A
        STAX    B               ; 02
        LHLD    0x4000          ; 2A 00 40
        SHLD    0x4002          ; 22 02 40
        LXI     H, 0x1234       ; 21 34 12
        LXI     SP, 0xFF00      ; 31 00 FF
        XCHG                    ; EB
        PUSH    H               ; E5
        PUSH    PSW             ; F5
        POP     B               ; C1
        POP     PSW             ; F1
        SPHL                    ; F9
        XTHL                    ; E3
        ADD     B               ; 80
        SUB     C               ; 91
        ANA     D               ; A2
        ORA     E               ; B3
        XRA     L               ; AD
        CMP     H               ; BC
        ADC     A               ; 8F
        SBB     B               ; 98
        ADD     M               ; 86
        ANA     M               ; A6
        CMP     M               ; BE
        ADI     0x10            ; C6 10
        SUI     0x20            ; D6 20
        ANI     0x30            ; E6 30
        ORI     0x40            ; F6 40
        XRI     0x50            ; EE 50
        CPI     0x60            ; FE 60
        DAD     B               ; 09
        DAD     SP              ; 39
        INX     H               ; 23
        DCX     D               ; 1B
        INR     A               ; 3C
        DCR     L               ; 2D
        RLC                     ; 07
        RRC                     ; 0F
        RAL                     ; 17
        RAR                     ; 1F
        CMA                     ; 2F
        STC                     ; 37
        CMC                     ; 3F
        DAA                     ; 27
        EI                      ; FB
        DI                      ; F3
        HLT                     ; 76
        IN      0x01            ; DB 01
        OUT     0x02            ; D3 02
        JMP     0x1234          ; C3 34 12
        JNZ     0x1234          ; C2 34 12
        JZ      0x1234          ; CA 34 12
        CALL    0x5678          ; CD 78 56
        RET                     ; C9
        RNZ                     ; C0
        RZ                      ; C8
        RST     0               ; C7
        RST     7               ; FF

; CHECK:      0x00000000 0078777e 2e423a34 12327856 1a022a00
; CHECK-NEXT: 0x00000010 40220240 21341231 00ffebe5 f5c1f1f9
; CHECK-NEXT: 0x00000020 e38091a2 b3adbc8f 9886a6be c610d620
; CHECK-NEXT: 0x00000030 e630f640 ee50fe60 0939231b 3c2d070f
; CHECK-NEXT: 0x00000040 171f2f37 3f27fbf3 76db01d3 02c33412
; CHECK-NEXT: 0x00000050 c23412ca 3412cd78 56c9c0c8 c7ff
