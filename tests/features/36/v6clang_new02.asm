	.text
	.globl	multi_src_de                    ; -- Begin function multi_src_de
multi_src_de:                           ; @multi_src_de
	;=== int multi_src_de(int arg0, int arg1, int arg2) ===
	;  arg0 = HL
	;  arg1 = DE
	;  arg2 = BC
; %bb.0:
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	__v6clang_ss.multi_src_de
	XCHG
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, B
	ORA	C
	JZ	.LBB0_2
; %bb.1:
	CALL	op1
	JMP	.LBB0_3
.LBB0_2:
	CALL	op2
.LBB0_3:
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.multi_src_de+2
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.multi_src_de
	CALL	op2
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	__v6clang_ss.multi_src_de+2
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	DE
	RET
                                        ; -- End function
	.globl	k2_two_reloads                  ; -- Begin function k2_two_reloads
k2_two_reloads:                         ; @k2_two_reloads
	;=== int k2_two_reloads(int arg0, int arg1, int arg2) ===
	;  arg0 = HL
	;  arg1 = DE
	;  arg2 = BC
; %bb.0:
	;--- V6CLANG_SPILL16 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.k2_two_reloads
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	__v6clang_ss.k2_two_reloads+2
	XCHG
	CALL	op1
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.k2_two_reloads+4
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.k2_two_reloads+2
	CALL	op2
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	__v6clang_ss.k2_two_reloads+4
	XCHG
	;--- V6CLANG_ADD16 ---
	MOV	A, E
	ADD	E
	MOV	E, A
	MOV	A, D
	ADC	D
	MOV	D, A
	;--- V6CLANG_ADD16 ---
	DAD	DE
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.k2_two_reloads+2
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.k2_two_reloads
	CALL	op2
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	__v6clang_ss.k2_two_reloads+2
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	DE
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	LXI	HL, 0x1234
	CALL	op1
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.main
	LXI	HL, 0x5678
	CALL	op2
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	__v6clang_ss.main
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	DE
	SHLD	g1
	LXI	HL, 0xaaaa
	CALL	op1
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.main
	LXI	HL, 0xbbbb
	CALL	op2
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	__v6clang_ss.main
	XCHG
	;--- V6CLANG_ADD16 ---
	MOV	A, E
	ADD	E
	MOV	E, A
	MOV	A, D
	ADC	D
	MOV	D, A
	;--- V6CLANG_ADD16 ---
	DAD	DE
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.main
	LXI	HL, 0xcccc
	CALL	op2
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	__v6clang_ss.main
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	DE
	SHLD	g2
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g1                              ; @g1
g1:
	DW	0                               ; 0x0

	.globl	g2                              ; @g2
g2:
	DW	0                               ; 0x0

	.local	__v6clang_ss.multi_src_de           ; @__v6clang_ss.multi_src_de
	.comm	__v6clang_ss.multi_src_de,4,1
	.local	__v6clang_ss.k2_two_reloads         ; @__v6clang_ss.k2_two_reloads
	.comm	__v6clang_ss.k2_two_reloads,6,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,2,1
	.addrsig
