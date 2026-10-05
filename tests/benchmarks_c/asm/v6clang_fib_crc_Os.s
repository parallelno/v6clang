	.text
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(int arg0, void* arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	MVI	A, 0
	STA	__v6clang_a.main
	MOV	H, A
	INR	A
	STA	__v6clang_a.main+1
	LXI	B, 0xffff
	LDA	__v6clang_a.main
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, H
	MOV	E, A
	LDA	__v6clang_a.main+1
	;--- V6CLANG_SPILL8 ---
	PUSH	PSW
	XRA	A
	STA	.LLo61_1+1
	POP	PSW
	;--- V6CLANG_BUILD_PAIR ---
	MOV	L, A
.LBB15_1:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_2 Depth 2
                                        ;     Child Loop BB15_6 Depth 2
	;--- V6CLANG_ADD16 ---
	XCHG
	DAD	D
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_0+1
	XCHG
	;--- V6CLANG_AND16_IMM ---
	;--- V6CLANG_XOR16 ---
	MOV	A, E
	XRA	C
	MOV	C, A
	XRA	A
	XRA	B
	MOV	B, A
	MVI	E, 8
.LBB15_2:                               ;   Parent Loop BB15_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	MOV	D, C
	;--- V6CLANG_SRL16_RAR ---
	MOV	A, B
	ORA	A
	RAR
	MOV	B, A
	MOV	A, C
	RAR
	MOV	C, A
	MOV	A, D
	ANI	1
	JZ	.LBB15_4
; %bb.3:                                ;   in Loop: Header=BB15_2 Depth=2
	;--- V6CLANG_XOR16_IMM ---
	MVI	A, 1
	XRA	C
	MOV	C, A
	MVI	A, 0xa0
	XRA	B
	MOV	B, A
.LBB15_4:                               ;   in Loop: Header=BB15_2 Depth=2
	DCR	E
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_2
; %bb.5:                                ;   in Loop: Header=BB15_1 Depth=1
	;--- V6CLANG_RELOAD16 ---
.LLo61_0:
	LXI	D, 0
	;--- V6CLANG_SRL16_BYTE ---
	MOV	E, D
	MVI	D, 0
	;--- V6CLANG_XOR16 ---
	MOV	A, C
	XRA	E
	MOV	C, A
	MOV	A, B
	XRA	D
	MOV	B, A
	MVI	E, 8
.LBB15_6:                               ;   Parent Loop BB15_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	MOV	D, C
	;--- V6CLANG_SRL16_RAR ---
	MOV	A, B
	ORA	A
	RAR
	MOV	B, A
	MOV	A, C
	RAR
	MOV	C, A
	MOV	A, D
	ANI	1
	JZ	.LBB15_8
; %bb.7:                                ;   in Loop: Header=BB15_6 Depth=2
	;--- V6CLANG_XOR16_IMM ---
	MVI	A, 1
	XRA	C
	MOV	C, A
	MVI	A, 0xa0
	XRA	B
	MOV	B, A
.LBB15_8:                               ;   in Loop: Header=BB15_6 Depth=2
	DCR	E
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_6
; %bb.9:                                ;   in Loop: Header=BB15_1 Depth=1
	;--- V6CLANG_RELOAD8 ---
.LLo61_1:
	MVI	A, 0
	INR	A
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_1+1
	CPI	0x18
	XCHG
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_0+1
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_1
; %bb.10:
	MOV	A, C
	OUT	0xed
	HLT
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,2,1
	.addrsig
	.addrsig_sym __mulqi3
	.addrsig_sym __v6clang_mulqihi3
	.addrsig_sym __mulhi3
	.addrsig_sym __v6clang_udivmod16_body
	.addrsig_sym __udivhi3
	.addrsig_sym __umodhi3
	.addrsig_sym __udivmodhi4
	.addrsig_sym __divmodhi4
	.addrsig_sym __v6clang_neg_hl_body
	.addrsig_sym __v6clang_neg_de_body
	.addrsig_sym __divhi3
	.addrsig_sym __modhi3
	.addrsig_sym __ashlhi3
	.addrsig_sym __lshrhi3
	.addrsig_sym __ashrhi3
	.addrsig_sym __v6clang_a.main
