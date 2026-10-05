	.text
	.section	.text.shape_a,"ax",@progbits
	.globl	shape_a                         ; -- Begin function shape_a
shape_a:                                ; @shape_a
	;=== char shape_a(char arg0) ===
	;  arg0 = A
; %bb.0:
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	JZ	.LBB15_2
; %bb.1:
	MVI	A, 1
	RET
.LBB15_2:
	XRA	A
	RET
                                        ; -- End function
	.section	.text.shape_a_dead,"ax",@progbits
	.globl	shape_a_dead                    ; -- Begin function shape_a_dead
shape_a_dead:                           ; @shape_a_dead
	;=== char shape_a_dead(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = B
; %bb.0:
	;--- V6CLANG_CMP8_ZERO ---
	INR	B
	DCR	B
	RNZ
.LBB16_1:
	XRA	A
; %bb.2:
	RET
                                        ; -- End function
	.section	.text.shape_a_live,"ax",@progbits
	.globl	shape_a_live                    ; -- Begin function shape_a_live
shape_a_live:                           ; @shape_a_live
	;=== char shape_a_live(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = B
; %bb.0:
	;--- V6CLANG_CMP8_ZERO ---
	INR	B
	DCR	B
	JZ	.LBB17_2
; %bb.1:
	MVI	L, 1
	JMP	.LBB17_3
.LBB17_2:
	MVI	L, 0
.LBB17_3:
	;--- V6CLANG_SPILL8 ---
	MOV	B, A
	MOV	A, L
	STA	.LLo61_0+1
	MOV	A, B
	CALL	op1
	;--- V6CLANG_RELOAD8 ---
.LLo61_0:
	ADI	0
	RET
                                        ; -- End function
	.section	.text.shape_a_live_loop,"ax",@progbits
	.globl	shape_a_live_loop               ; -- Begin function shape_a_live_loop
shape_a_live_loop:                      ; @shape_a_live_loop
	;=== char shape_a_live_loop(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = B
; %bb.0:
	;--- V6CLANG_CMP8_ZERO ---
	INR	B
	DCR	B
	;--- V6CLANG_BRCOND ---
	RZ
.LBB18_1:                               ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_SPILL8 ---
	LXI	H, .LLo61_1+1
	MOV	M, B
	CALL	op1
	;--- V6CLANG_RELOAD8 ---
.LLo61_1:
	MVI	B, 0
	DCR	B
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB18_1
; %bb.2:
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	MVI	A, 1
	MVI	B, 0
	CALL	use2
	MVI	A, 0x22
	MVI	B, 0
	CALL	use2
	MVI	A, 0x55
	CALL	op1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_2+1
	MVI	A, 0x66
	CALL	op1
	MOV	B, A
	;--- V6CLANG_RELOAD8 ---
.LLo61_2:
	MVI	A, 0
	INR	A
	CALL	use2
	MVI	A, 0x77
	CALL	op1
	CALL	op1
	CALL	op1
	CALL	op1
	CALL	op1
	CALL	sink
	LXI	H, 0
	RET
                                        ; -- End function
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
