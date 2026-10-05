	.text
	.globl	de_bc_three                     ; -- Begin function de_bc_three
de_bc_three:                            ; @de_bc_three
	;=== int de_bc_three(int arg0, int arg1, int arg2) ===
	;  arg0 = HL
	;  arg1 = DE
	;  arg2 = BC
; %bb.0:
	PUSH	HL
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_1+1
	POP	HL
	XCHG
	SHLD	.LLo61_2+1
	XCHG
	CALL	op_u16
	SHLD	.LLo61_0+1
	LHLD	.LLo61_2+1
	CALL	op2_u16
	SHLD	.LLo61_2+1
	LHLD	.LLo61_1+1
	CALL	op_u16
	SHLD	.LLo61_1+1
.LLo61_0:
	LXI	HL, 0
.LLo61_2:
	LXI	DE, 0
	MOV	C, L
	MOV	B, H
	CALL	use3_u16
	LHLD	.LLo61_0+1
	XCHG
	LHLD	.LLo61_2+1
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	DE
.LLo61_1:
	LXI	DE, 0
	;--- V6CLANG_ADD16 ---
	DAD	DE
	RET
                                        ; -- End function
	.globl	de_one_reload                   ; -- Begin function de_one_reload
de_one_reload:                          ; @de_one_reload
	;=== int de_one_reload(int arg0, int arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	XCHG
	SHLD	.LLo61_3+1
	XCHG
	CALL	op_u16
	SHLD	.LLo61_4+1
.LLo61_3:
	LXI	HL, 0
	CALL	op2_u16
.LLo61_4:
	LXI	DE, 0
	;--- V6CLANG_ADD16 ---
	DAD	DE
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	LXI	HL, 0x1111
	CALL	op_u16
	SHLD	.LLo61_7+1
	LXI	HL, 0x2222
	CALL	op2_u16
	SHLD	.LLo61_6+1
	LXI	HL, 0x3333
	CALL	op_u16
	SHLD	.LLo61_5+1
	LHLD	.LLo61_7+1
.LLo61_6:
	LXI	DE, 0
	MOV	C, L
	MOV	B, H
	CALL	use3_u16
	LHLD	.LLo61_7+1
	XCHG
	LHLD	.LLo61_6+1
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	DE
	SHLD	.LLo61_7+1
	LXI	HL, 0x4444
	CALL	op_u16
	SHLD	.LLo61_6+1
	LXI	HL, 0x5555
	CALL	op2_u16
.LLo61_5:
	LXI	DE, 0
.LLo61_7:
	LXI	BC, 0
	;--- V6CLANG_ADD16 ---
	MOV	A, C
	ADD	E
	MOV	C, A
	MOV	A, B
	ADC	D
	MOV	B, A
	XCHG
	LHLD	.LLo61_6+1
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	DE
	XCHG
	MOV	H, B
	MOV	L, C
	CALL	use2_u16
	LXI	HL, 0
	RET
                                        ; -- End function
	.local	__v6clang_ss.de_bc_three            ; @__v6clang_ss.de_bc_three
	.comm	__v6clang_ss.de_bc_three,6,1
	.local	__v6clang_ss.de_one_reload          ; @__v6clang_ss.de_one_reload
	.comm	__v6clang_ss.de_one_reload,4,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,6,1
	.addrsig
