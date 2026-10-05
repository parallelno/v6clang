	.text
	.section	.text.load8_stack_arg,"ax",@progbits
	.globl	load8_stack_arg                 ; -- Begin function load8_stack_arg
load8_stack_arg:                        ; @load8_stack_arg
	;=== char load8_stack_arg(char arg0, char arg1, char arg2, char arg3, char arg4, char arg5, char arg6, char arg7) ===
	;  arg0 = A
	;  arg1 = B
	;  arg2 = C
	;  arg3 = D
	;  arg4 = E
	;  arg5 = L
	;  arg6 = H
	;  arg7 = stack
; %bb.0:
	;--- V6CLANG_LOAD8_FI ---
	LXI	H, 2
	DAD	SP
	MOV	A, M
	RET
                                        ; -- End function
	.section	.text.load16_stack_arg,"ax",@progbits
	.globl	load16_stack_arg                ; -- Begin function load16_stack_arg
load16_stack_arg:                       ; @load16_stack_arg
	;=== int load16_stack_arg(int arg0, int arg1, int arg2, int arg3) ===
	;  arg0 = HL
	;  arg1 = DE
	;  arg2 = BC
	;  arg3 = stack
; %bb.0:
	;--- V6CLANG_ADD16 ---
	DAD	D
	;--- V6CLANG_ADD16 ---
	DAD	B
	XCHG
	;--- V6CLANG_LOAD16_FI ---
	LXI	H, 2
	DAD	SP
	MOV	C, M
	INX	H
	MOV	B, M
	;--- V6CLANG_ADD16 ---
	XCHG
	DAD	B
	RET
                                        ; -- End function
	.section	.text.store8_local,"ax",@progbits
	.globl	store8_local                    ; -- Begin function store8_local
store8_local:                           ; @store8_local
	;=== char store8_local(char arg0) ===
	;  arg0 = A
; %bb.0:
	LXI	H, 0xffff
	DAD	SP
	SPHL
	;--- V6CLANG_STORE8_FI ---
	LXI	H, 0
	DAD	SP
	MOV	M, A
	;--- V6CLANG_LOAD8_FI ---
	LXI	H, 0
	DAD	SP
	MOV	A, M
	LXI	H, 1
	DAD	SP
	SPHL
	RET
                                        ; -- End function
	.section	.text.store16_local,"ax",@progbits
	.globl	store16_local                   ; -- Begin function store16_local
store16_local:                          ; @store16_local
	;=== int store16_local(int arg0) ===
	;  arg0 = HL
; %bb.0:
	PUSH	PSW
	MOV	B, H
	MOV	C, L
	;--- V6CLANG_STORE16_FI ---
	LXI	H, 0
	DAD	SP
	MOV	M, C
	INX	H
	MOV	M, B
	;--- V6CLANG_LOAD16_FI ---
	LXI	H, 0
	DAD	SP
	MOV	E, M
	INX	H
	MOV	D, M
	XCHG
	POP	PSW
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(int arg0, void* arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	PUSH	PSW
	MVI	A, 8
	STA	g8
	LXI	H, 0
	DAD	SP
	LXI	D, 4
	;--- V6CLANG_STORE16_P ---
	MOV	M, E
	INX	H
	MOV	M, D
	LXI	H, 1
	LXI	D, 2
	LXI	B, 3
	CALL	load16_stack_arg
	;--- V6CLANG_STORE16_G ---
	PUSH	H
	LDA	g8
	CALL	store8_local
	STA	g8
	;--- V6CLANG_LOAD16_G ---
	POP	H
	CALL	store16_local
	;--- V6CLANG_STORE16_G ---
	PUSH	H
	LDA	g8
	OUT	0xed
	;--- V6CLANG_LOAD16_G ---
	POP	H
	MOV	A, L
	OUT	0xed
	HLT
	LXI	H, 0
	POP	PSW
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g8                              ; @g8
g8:
	DB	0                               ; 0x0

	.globl	g16                             ; @g16
g16:
	DW	0                               ; 0x0

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
	.addrsig_sym g8
	.addrsig_sym g16
