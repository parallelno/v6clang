; V6CLANG Encoding Validation Test
; Assemble with v6asm and verify opcode bytes against TableGen definitions.
; v6asm uses 0xNN for hex (NOT NNh suffix).

; === Miscellaneous ===
    NOP             ; Expected: 0x00
    HLT             ; Expected: 0x76

; === Data Move: MOV r,r (01_DDD_SSS) ===
    MOV A, A        ; Expected: 0x7F
    MOV A, B        ; Expected: 0x78
    MOV B, A        ; Expected: 0x47
    MOV B, C        ; Expected: 0x41
    MOV C, D        ; Expected: 0x4A
    MOV D, E        ; Expected: 0x53
    MOV E, H        ; Expected: 0x5C
    MOV H, L        ; Expected: 0x65
    MOV L, A        ; Expected: 0x6F

; === Data Move: MOV r,M / MOV M,r ===
    MOV A, M        ; Expected: 0x7E
    MOV B, M        ; Expected: 0x46
    MOV M, A        ; Expected: 0x77
    MOV M, B        ; Expected: 0x70

; === Data Move: MVI ===
    MVI A, 0x42     ; Expected: 0x3E 0x42
    MVI B, 0x00     ; Expected: 0x06 0x00
    MVI C, 0xFF     ; Expected: 0x0E 0xFF
    MVI D, 0x10     ; Expected: 0x16 0x10
    MVI E, 0x20     ; Expected: 0x1E 0x20
    MVI H, 0x30     ; Expected: 0x26 0x30
    MVI L, 0x40     ; Expected: 0x2E 0x40
    MVI M, 0x55     ; Expected: 0x36 0x55

; === Data Move: LDA, STA ===
    LDA 0x1234      ; Expected: 0x3A 0x34 0x12
    STA 0x5678      ; Expected: 0x32 0x78 0x56

; === Data Move: LDAX, STAX ===
    LDAX B          ; Expected: 0x0A
    LDAX D          ; Expected: 0x1A
    STAX B          ; Expected: 0x02
    STAX D          ; Expected: 0x12

; === Data Move: LHLD, SHLD ===
    LHLD 0x1234     ; Expected: 0x2A 0x34 0x12
    SHLD 0x5678     ; Expected: 0x22 0x78 0x56

; === Data Move: LXI ===
    LXI B, 0x1234   ; Expected: 0x01 0x34 0x12
    LXI D, 0x5678   ; Expected: 0x11 0x78 0x56
    LXI H, 0x9ABC   ; Expected: 0x21 0xBC 0x9A
    LXI SP, 0xDEF0  ; Expected: 0x31 0xF0 0xDE

; === Data Move: XCHG ===
    XCHG            ; Expected: 0xEB

; === Stack: PUSH, POP ===
    PUSH B          ; Expected: 0xC5
    PUSH D          ; Expected: 0xD5
    PUSH H          ; Expected: 0xE5
    PUSH PSW        ; Expected: 0xF5
    POP B           ; Expected: 0xC1
    POP D           ; Expected: 0xD1
    POP H           ; Expected: 0xE1
    POP PSW         ; Expected: 0xF1

; === Stack: SPHL, XTHL ===
    SPHL            ; Expected: 0xF9
    XTHL            ; Expected: 0xE3

; === ALU 8-bit register: ADD, ADC, SUB, SBB, ANA, XRA, ORA, CMP ===
    ADD A           ; Expected: 0x87
    ADD B           ; Expected: 0x80
    ADC A           ; Expected: 0x8F
    ADC B           ; Expected: 0x88
    SUB A           ; Expected: 0x97
    SUB B           ; Expected: 0x90
    SBB A           ; Expected: 0x9F
    SBB B           ; Expected: 0x98
    ANA A           ; Expected: 0xA7
    ANA B           ; Expected: 0xA0
    XRA A           ; Expected: 0xAF
    XRA B           ; Expected: 0xA8
    ORA A           ; Expected: 0xB7
    ORA B           ; Expected: 0xB0
    CMP A           ; Expected: 0xBF
    CMP B           ; Expected: 0xB8

; === ALU 8-bit memory ===
    ADD M           ; Expected: 0x86
    ADC M           ; Expected: 0x8E
    SUB M           ; Expected: 0x96
    SBB M           ; Expected: 0x9E
    ANA M           ; Expected: 0xA6
    XRA M           ; Expected: 0xAE
    ORA M           ; Expected: 0xB6
    CMP M           ; Expected: 0xBE

; === ALU 8-bit immediate ===
    ADI 0x42        ; Expected: 0xC6 0x42
    ACI 0x42        ; Expected: 0xCE 0x42
    SUI 0x42        ; Expected: 0xD6 0x42
    SBI 0x42        ; Expected: 0xDE 0x42
    ANI 0x42        ; Expected: 0xE6 0x42
    XRI 0x42        ; Expected: 0xEE 0x42
    ORI 0x42        ; Expected: 0xF6 0x42
    CPI 0x42        ; Expected: 0xFE 0x42

; === ALU 16-bit: DAD, INX, DCX ===
    DAD B           ; Expected: 0x09
    DAD D           ; Expected: 0x19
    DAD H           ; Expected: 0x29
    DAD SP          ; Expected: 0x39
    INX B           ; Expected: 0x03
    INX D           ; Expected: 0x13
    INX H           ; Expected: 0x23
    INX SP          ; Expected: 0x33
    DCX B           ; Expected: 0x0B
    DCX D           ; Expected: 0x1B
    DCX H           ; Expected: 0x2B
    DCX SP          ; Expected: 0x3B

; === Increment/Decrement 8-bit ===
    INR A           ; Expected: 0x3C
    INR B           ; Expected: 0x04
    INR C           ; Expected: 0x0C
    INR D           ; Expected: 0x14
    INR E           ; Expected: 0x1C
    INR H           ; Expected: 0x24
    INR L           ; Expected: 0x2C
    INR M           ; Expected: 0x34
    DCR A           ; Expected: 0x3D
    DCR B           ; Expected: 0x05
    DCR C           ; Expected: 0x0D
    DCR D           ; Expected: 0x15
    DCR E           ; Expected: 0x1D
    DCR H           ; Expected: 0x25
    DCR L           ; Expected: 0x2D
    DCR M           ; Expected: 0x35

; === Rotate ===
    RLC             ; Expected: 0x07
    RRC             ; Expected: 0x0F
    RAL             ; Expected: 0x17
    RAR             ; Expected: 0x1F

; === Branch: JMP, Jcc ===
    JMP 0x1234      ; Expected: 0xC3 0x34 0x12
    JNZ 0x1234      ; Expected: 0xC2 0x34 0x12
    JZ  0x1234      ; Expected: 0xCA 0x34 0x12
    JNC 0x1234      ; Expected: 0xD2 0x34 0x12
    JC  0x1234      ; Expected: 0xDA 0x34 0x12
    JPO 0x1234      ; Expected: 0xE2 0x34 0x12
    JPE 0x1234      ; Expected: 0xEA 0x34 0x12
    JP  0x1234      ; Expected: 0xF2 0x34 0x12
    JM  0x1234      ; Expected: 0xFA 0x34 0x12
    PCHL            ; Expected: 0xE9

; === Call: CALL, Ccc ===
    CALL 0x1234     ; Expected: 0xCD 0x34 0x12
    CNZ  0x1234     ; Expected: 0xC4 0x34 0x12
    CZ   0x1234     ; Expected: 0xCC 0x34 0x12
    CNC  0x1234     ; Expected: 0xD4 0x34 0x12
    CC   0x1234     ; Expected: 0xDC 0x34 0x12
    CPO  0x1234     ; Expected: 0xE4 0x34 0x12
    CPE  0x1234     ; Expected: 0xEC 0x34 0x12
    CP   0x1234     ; Expected: 0xF4 0x34 0x12
    CM   0x1234     ; Expected: 0xFC 0x34 0x12

; === Return: RET, Rcc ===
    RET             ; Expected: 0xC9
    RNZ             ; Expected: 0xC0
    RZ              ; Expected: 0xC8
    RNC             ; Expected: 0xD0
    RC              ; Expected: 0xD8
    RPO             ; Expected: 0xE0
    RPE             ; Expected: 0xE8
    RP              ; Expected: 0xF0
    RM              ; Expected: 0xF8

; === RST ===
    RST 0           ; Expected: 0xC7
    RST 1           ; Expected: 0xCF
    RST 2           ; Expected: 0xD7
    RST 3           ; Expected: 0xDF
    RST 4           ; Expected: 0xE7
    RST 5           ; Expected: 0xEF
    RST 6           ; Expected: 0xF7
    RST 7           ; Expected: 0xFF

; === Misc ===
    CMA             ; Expected: 0x2F
    STC             ; Expected: 0x37
    CMC             ; Expected: 0x3F
    DAA             ; Expected: 0x27
    EI              ; Expected: 0xFB
    DI              ; Expected: 0xF3

; === I/O ===
    IN 0x42         ; Expected: 0xDB 0x42
    OUT 0x42        ; Expected: 0xD3 0x42
