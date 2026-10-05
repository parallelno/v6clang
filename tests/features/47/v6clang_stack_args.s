	.text
	.section	.text.error_stack_arg,"ax",@progbits
	.globl	error_stack_arg                 ; -- Begin function error_stack_arg
error_stack_arg:                        ; @error_stack_arg
	;=== int error_stack_arg(int arg0, int arg1, int arg2, int arg3, int arg4) ===
	;  arg0 = HL
	;  arg1 = DE
	;  arg2 = BC
	;  arg3 = stack
	;  arg4 = stack
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
	XCHG
	;--- V6CLANG_LOAD16_FI ---
	LXI	H, 4
	DAD	SP
	MOV	C, M
	INX	H
	MOV	B, M
	;--- V6CLANG_ADD16 ---
	XCHG
	DAD	B
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
	PUSH	PSW
	;--- V6CLANG_LOAD16_G ---
	LHLD	i_p
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_0+1
	;--- V6CLANG_LOAD16_G ---
	LHLD	i_p+2
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_2+1
	;--- V6CLANG_LOAD16_G ---
	LHLD	i_p+4
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_1+1
	;--- V6CLANG_LOAD16_G ---
	XCHG
	LHLD	i_p+6
	XCHG
	;--- V6CLANG_LOAD16_G ---
	LHLD	i_p+8
	MOV	B, H
	MOV	C, L
	LXI	H, 0
	DAD	SP
	;--- V6CLANG_STORE16_P ---
	MOV	M, E
	INX	H
	MOV	M, D
	DCX	H
	;--- V6CLANG_INX16 ---
	INX	H
	INX	H
	;--- V6CLANG_STORE16_P ---
	MOV	M, C
	INX	H
	MOV	M, B
	;--- V6CLANG_RELOAD16 ---
.LLo61_0:
	LXI	H, 0
	;--- V6CLANG_RELOAD16 ---
.LLo61_2:
	LXI	D, 0
	;--- V6CLANG_RELOAD16 ---
.LLo61_1:
	LXI	B, 0
	CALL	error_stack_arg
	MOV	A, L
	OUT	0xed
	;--- V6CLANG_LOAD16_G ---
	LHLD	i_p
	;--- V6CLANG_LOAD16_G ---
	XCHG
	LHLD	i_p+2
	;--- V6CLANG_ADD16 ---
	DAD	H
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	D
	MOV	A, L
	OUT	0xed
	HLT
	LXI	H, 0
	POP	PSW
	POP	PSW
	RET
                                        ; -- End function
	.data
	.globl	i_p                             ; @i_p
i_p:
	DW	1                               ; 0x1
	DW	2                               ; 0x2
	DW	3                               ; 0x3
	DW	4                               ; 0x4
	DW	5                               ; 0x5

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
	.addrsig_sym i_p
