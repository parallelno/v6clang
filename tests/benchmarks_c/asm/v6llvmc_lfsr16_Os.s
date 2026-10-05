	.text
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(int arg0, void* arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	LXI	H, 0xace1
	;--- V6CLANG_STORE16_G ---
	SHLD	__v6clang_a.main
	LXI	H, 0
	LXI	D, 0x1000
	;--- V6CLANG_LOAD16_G ---
	LDA	__v6clang_a.main
	MOV	C, A
	LDA	__v6clang_a.main+1
	MOV	B, A
.LBB15_1:                               ; =>This Inner Loop Header: Depth=1
	MOV	A, C
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_0+1
	;--- V6CLANG_SRL16_RAR ---
	MOV	A, B
	ORA	A
	RAR
	MOV	B, A
	MOV	A, C
	RAR
	MOV	C, A
	;--- V6CLANG_RELOAD8 ---
.LLo61_0:
	MVI	A, 0
	ANI	1
	JZ	.LBB15_3
; %bb.2:                                ;   in Loop: Header=BB15_1 Depth=1
	;--- V6CLANG_XOR16_IMM ---
	MVI	A, 0xb4
	XRA	B
	MOV	B, A
.LBB15_3:                               ;   in Loop: Header=BB15_1 Depth=1
	;--- V6CLANG_XOR16 ---
	MOV	A, C
	XRA	L
	MOV	L, A
	MOV	A, B
	XRA	H
	MOV	H, A
	;--- V6CLANG_DCX16 ---
	DCX	D
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, D
	ORA	E
	JNZ	.LBB15_1
; %bb.4:
	;--- V6CLANG_SRL16_BYTE ---
	;--- V6CLANG_XOR16 ---
	MOV	A, H
	XRA	L
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
