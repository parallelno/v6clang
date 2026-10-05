	.text
	.section	.text.a_spill_r8_reload,"ax",@progbits
	.globl	a_spill_r8_reload               ; -- Begin function a_spill_r8_reload
a_spill_r8_reload:                      ; @a_spill_r8_reload
	;=== char a_spill_r8_reload(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = B
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	LXI	H, .LLo61_0+1
	MOV	M, B
	CALL	op1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_1+1
	;--- V6CLANG_RELOAD8 ---
.LLo61_0:
	MVI	A, 0
	CALL	op2
	;--- V6CLANG_RELOAD8 ---
.LLo61_1:
	ADI	0
	RET
                                        ; -- End function
	.section	.text.k2_i8,"ax",@progbits
	.globl	k2_i8                           ; -- Begin function k2_i8
k2_i8:                                  ; @k2_i8
	;=== char k2_i8(char arg0, char arg1, char arg2) ===
	;  arg0 = A
	;  arg1 = B
	;  arg2 = C
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	LXI	H, .LLo61_2+1
	MOV	M, C
	;--- V6CLANG_SPILL8 ---
	LXI	H, .LLo61_3+1
	MOV	M, B
	CALL	op1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_4+1
	;--- V6CLANG_RELOAD8 ---
.LLo61_3:
	MVI	A, 0
	CALL	op2
	MOV	H, A
	;--- V6CLANG_RELOAD8 ---
.LLo61_4:
	MVI	A, 0
	ADD	A
	MOV	L, A
	MOV	A, H
	ADD	L
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_4+1
	;--- V6CLANG_RELOAD8 ---
.LLo61_2:
	MVI	A, 0
	CALL	op2
	MOV	L, A
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_4+1
	ADD	L
	RET
                                        ; -- End function
	.section	.text.multi_src_i8,"ax",@progbits
	.globl	multi_src_i8                    ; -- Begin function multi_src_i8
multi_src_i8:                           ; @multi_src_i8
	;=== char multi_src_i8(char arg0, char arg1, char arg2) ===
	;  arg0 = A
	;  arg1 = B
	;  arg2 = C
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	LXI	H, .LLo61_5+1
	MOV	M, B
	;--- V6CLANG_CMP8_ZERO ---
	INR	C
	DCR	C
	;--- V6CLANG_BRCOND ---
	JZ	.LBB17_2
; %bb.1:
	CALL	op1
	JMP	.LBB17_3
.LBB17_2:
	CALL	op2
.LBB17_3:
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_6+1
	;--- V6CLANG_RELOAD8 ---
.LLo61_5:
	MVI	A, 0
	CALL	op2
	;--- V6CLANG_RELOAD8 ---
.LLo61_6:
	ADI	0
	RET
                                        ; -- End function
	.section	.text.mixed_widths,"ax",@progbits
	.globl	mixed_widths                    ; -- Begin function mixed_widths
mixed_widths:                           ; @mixed_widths
	;=== void mixed_widths(int arg0, char arg1) ===
	;  arg0 = HL
	;  arg1 = A
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_9+1
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_7+1
	MOV	A, L
	CALL	op1
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	;--- V6CLANG_RELOAD16 ---
.LLo61_7:
	LXI	D, 0
	;--- V6CLANG_ADD16 ---
	DAD	D
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_8+1
	;--- V6CLANG_RELOAD8 ---
.LLo61_9:
	MVI	A, 0
	CALL	op2
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_10+1
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_7+1
	MOV	A, L
	CALL	op2
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	;--- V6CLANG_RELOAD16 ---
.LLo61_8:
	LXI	D, 0
	;--- V6CLANG_ADD16 ---
	DAD	D
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_7+1
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_9+1
	CALL	op1
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_7+1
	;--- V6CLANG_STORE16_G ---
	SHLD	g_u16
	;--- V6CLANG_RELOAD8 ---
.LLo61_10:
	ADI	0
	STA	g_u8
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	MVI	A, 0x11
	CALL	op1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_14+1
	MVI	A, 0x22
	CALL	op2
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_12+1
	MVI	A, 0x33
	CALL	op1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_13+1
	MVI	A, 0x44
	CALL	op2
	MOV	H, A
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_12+1
	;--- V6CLANG_RELOAD8 ---
.LLo61_14:
	ADI	0
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_12+1
	;--- V6CLANG_RELOAD8 ---
.LLo61_13:
	MVI	A, 0
	ADD	A
	MOV	L, A
	MOV	A, H
	ADD	L
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_14+1
	MVI	A, 0x55
	CALL	op2
	MOV	L, A
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_14+1
	ADD	L
	MOV	B, A
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_12+1
	CALL	use2
	MVI	A, 0x66
	CALL	op1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_12+1
	MVI	A, 0x77
	CALL	op2
	;--- V6CLANG_RELOAD8 ---
.LLo61_12:
	ADI	0
	MVI	B, 0
	CALL	use2
	MVI	A, 0xcd
	CALL	op1
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_11+1
	MVI	A, 0xef
	CALL	op2
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_12+1
	MVI	A, 0xcd
	CALL	op2
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	;--- V6CLANG_RELOAD16 ---
.LLo61_11:
	LXI	D, 0
	;--- V6CLANG_ADD16 ---
	DAD	D
	LXI	D, 0xabcd
	;--- V6CLANG_ADD16 ---
	DAD	D
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_11+1
	MVI	A, 0xef
	CALL	op1
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_11+1
	;--- V6CLANG_STORE16_G ---
	SHLD	g_u16
	;--- V6CLANG_RELOAD8 ---
	LXI	H, .LLo61_12+1
	ADD	M
	STA	g_u8
	LXI	H, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_u16                           ; @g_u16
g_u16:
	DW	0                               ; 0x0

	.globl	g_u8                            ; @g_u8
g_u8:
	DB	0                               ; 0x0

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
