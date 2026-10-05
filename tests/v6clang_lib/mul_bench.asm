	.text
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	LXI	H, 0
	XRA	A
	STA	.LLo61_4+1
	LXI	D, 0
.LBB0_1:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB0_2 Depth 2
	SHLD	.LLo61_3+1
	LXI	B, A_TAB
	LXI	H, B_TAB
	MVI	A, 0x10
.LBB0_2:                                ;   Parent Loop BB0_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	STA	.LLo61_5+1
	SHLD	.LLo61_0+1
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_1+1
	XCHG
	SHLD	.LLo61_2+1
.LLo61_0:
	LXI	H, 0
	;--- V6CLANG_LOAD16_P ---
	MOV	A, M
	INX	H
	MOV	H, M
	MOV	L, A
	;--- V6CLANG_LOAD16_P ---
	PUSH	H
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	H
	MOV	D, M
	POP	H
	CALL	__mulhi3
.LLo61_1:
	LXI	B, 0
.LLo61_2:
	LXI	D, 0
	;--- V6CLANG_XOR16 ---
	MOV	A, L
	XRA	E
	MOV	E, A
	MOV	A, H
	XRA	D
	MOV	D, A
.LLo61_5:
	MVI	A, 0
	LHLD	.LLo61_0+1
	;--- V6CLANG_INX16 ---
	INX	H
	INX	H
	;--- V6CLANG_INX16 ---
	INX	B
	INX	B
	DCR	A
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB0_2
; %bb.4:                                ;   in Loop: Header=BB0_1 Depth=1
.LLo61_3:
	LXI	H, 0
	;--- V6CLANG_ADD16 ---
	DAD	D
	XCHG
.LLo61_4:
	MVI	C, 0
	INR	C
	XRA	A
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, A
	MOV	L, C
	MOV	A, C
	STA	.LLo61_4+1
	CPI	0x40
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB0_1
; %bb.3:
	;--- V6CLANG_SRL16 ---
	MOV	L, D
	MOV	A, L
	OUT	0xed
	MOV	A, E
	OUT	0xed
	HLT
                                        ; -- End function
	.section	.rodata.cst32,"aM",@progbits,32
	.p2align	1, 0x0                          ; @A_TAB
A_TAB:
	DW	0                               ; 0x0
	DW	1                               ; 0x1
	DW	2                               ; 0x2
	DW	3                               ; 0x3
	DW	15                              ; 0xf
	DW	16                              ; 0x10
	DW	255                             ; 0xff
	DW	256                             ; 0x100
	DW	4660                            ; 0x1234
	DW	17185                           ; 0x4321
	DW	43690                           ; 0xaaaa
	DW	21845                           ; 0x5555
	DW	32768                           ; 0x8000
	DW	65535                           ; 0xffff
	DW	32767                           ; 0x7fff
	DW	51966                           ; 0xcafe

	.p2align	1, 0x0                          ; @B_TAB
B_TAB:
	DW	1                               ; 0x1
	DW	2                               ; 0x2
	DW	4660                            ; 0x1234
	DW	255                             ; 0xff
	DW	257                             ; 0x101
	DW	65535                           ; 0xffff
	DW	7                               ; 0x7
	DW	43981                           ; 0xabcd
	DW	22136                           ; 0x5678
	DW	4369                            ; 0x1111
	DW	65535                           ; 0xffff
	DW	65535                           ; 0xffff
	DW	2                               ; 0x2
	DW	65535                           ; 0xffff
	DW	65535                           ; 0xffff
	DW	47806                           ; 0xbabe

	.addrsig
