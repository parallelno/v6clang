	.text
	.globl	sum_add                         ; -- Begin function sum_add
sum_add:                                ; @sum_add
	;=== char sum_add(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	ADD	E
	RET
                                        ; -- End function
	.globl	sum_and                         ; -- Begin function sum_and
sum_and:                                ; @sum_and
	;=== char sum_and(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	ANA	E
	RET
                                        ; -- End function
	.globl	sum_or                          ; -- Begin function sum_or
sum_or:                                 ; @sum_or
	;=== char sum_or(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	ORA	E
	RET
                                        ; -- End function
	.globl	sum_xor                         ; -- Begin function sum_xor
sum_xor:                                ; @sum_xor
	;=== char sum_xor(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	XRA	E
	RET
                                        ; -- End function
	.globl	both_live                       ; -- Begin function both_live
both_live:                              ; @both_live
	;=== char both_live(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	STA	g_sink8
	MOV	L, A
	MOV	A, E
	STA	g_sink8
	ADD	L
	RET
                                        ; -- End function
	.globl	spill_pressure                  ; -- Begin function spill_pressure
spill_pressure:                         ; @spill_pressure
	;=== char spill_pressure(char arg0, char arg1, char arg2, char arg3) ===
	;  arg0 = A
	;  arg1 = E
	;  arg2 = C
	;  arg3 = stack
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	LXI	HL, __v6clang_ss.spill_pressure
	MOV	M, E
	MOV	B, A
	;--- V6CLANG_LEA_FI ---
	LXI	HL, 0
	DAD	SP
	XCHG
	;--- V6CLANG_LOAD8_P ---
	LDAX	DE
	ADD	C
	STA	g_sink8
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.spill_pressure
	ADD	B
	RET
                                        ; -- End function
	.globl	sum16                           ; -- Begin function sum16
sum16:                                  ; @sum16
	;=== int sum16(int arg0, int arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	;--- V6CLANG_ADD16 ---
	DAD	DE
	RET
                                        ; -- End function
	.globl	chain4                          ; -- Begin function chain4
chain4:                                 ; @chain4
	;=== char chain4(char arg0, char arg1, char arg2, char arg3) ===
	;  arg0 = A
	;  arg1 = E
	;  arg2 = C
	;  arg3 = stack
; %bb.0:
	ADD	E
	ADD	C
	;--- V6CLANG_LEA_FI ---
	LXI	HL, 0
	DAD	SP
	XCHG
	;--- V6CLANG_LOAD8_P ---
	PUSH	HL
	XCHG
	MOV	L, M
	POP	HL
	ADD	L
	RET
                                        ; -- End function
	.globl	sibling2                        ; -- Begin function sibling2
sibling2:                               ; @sibling2
	;=== char sibling2(char arg0, char arg1, char arg2, char arg3) ===
	;  arg0 = A
	;  arg1 = E
	;  arg2 = C
	;  arg3 = stack
; %bb.0:
	ADD	E
	MOV	B, A
	;--- V6CLANG_LEA_FI ---
	LXI	HL, 0
	DAD	SP
	XCHG
	;--- V6CLANG_LOAD8_P ---
	LDAX	DE
	XRA	C
	ORA	B
	RET
                                        ; -- End function
	.globl	mixed_imm                       ; -- Begin function mixed_imm
mixed_imm:                              ; @mixed_imm
	;=== char mixed_imm(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	ADD	E
	ADI	7
	RET
                                        ; -- End function
	.globl	two_args_two_ops                ; -- Begin function two_args_two_ops
two_args_two_ops:                       ; @two_args_two_ops
	;=== char two_args_two_ops(char arg0, char arg1, char arg2, char arg3) ===
	;  arg0 = A
	;  arg1 = E
	;  arg2 = C
	;  arg3 = stack
; %bb.0:
	ADD	E
	STA	g_sink8
	;--- V6CLANG_LEA_FI ---
	LXI	HL, 0
	DAD	SP
	XCHG
	;--- V6CLANG_LOAD8_P ---
	LDAX	DE
	XRA	C
	RET
                                        ; -- End function
	.globl	arr_sum                         ; -- Begin function arr_sum
arr_sum:                                ; @arr_sum
	;=== char arr_sum(void* arg0, int arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	__v6clang_ss.arr_sum+7
	XCHG
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, D
	ORA	E
	JZ	.LBB11_1
; %bb.3:
	MVI	E, 0
	;--- V6CLANG_RELOAD16 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.arr_sum+7
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	MOV	A, E
	;--- V6CLANG_SPILL8 ---
	STA	__v6clang_ss.arr_sum+2
.LBB11_4:                               ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_SPILL16 ---
	PUSH	HL
	;--- V6CLANG_SPILL8 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.arr_sum+6
	MOV	M, E
	POP	HL
	;--- V6CLANG_SPILL16 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.arr_sum+4
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	;--- V6CLANG_SPILL8 ---
	STA	__v6clang_ss.arr_sum+3
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.arr_sum+7
	XRA	L
	;--- V6CLANG_DCX16 ---
	DCX	HL
	;--- V6CLANG_LOAD8_P ---
	MOV	L, M
	ORA	L
	CALL	use8
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.arr_sum+4
	MOV	C, L
	MOV	B, H
	;--- V6CLANG_RELOAD8 ---
	LXI	HL, __v6clang_ss.arr_sum+6
	MOV	E, M
	;--- V6CLANG_RELOAD16 ---
	POP	HL
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.arr_sum+3
	ANA	E
	;--- V6CLANG_RELOAD8 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.arr_sum+2
	MOV	D, M
	POP	HL
	ADD	D
	INR	E
	;--- V6CLANG_INX16 ---
	INX	HL
	;--- V6CLANG_DCX16 ---
	DCX	BC
	MOV	D, A
	;--- V6CLANG_SPILL8 ---
	STA	__v6clang_ss.arr_sum+2
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, B
	ORA	C
	JNZ	.LBB11_4
; %bb.2:
	MOV	A, D
	RET
.LBB11_1:
	MOV	A, D
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	MVI	A, 7
	CALL	use8
	MVI	A, 0
	CALL	use8
	MVI	A, 0x30
	CALL	use8
	MVI	A, 0xff
	CALL	use8
	MVI	A, 7
	STA	g_sink8
	MVI	A, 9
	STA	g_sink8
	MVI	A, 0x10
	CALL	use8
	MVI	A, 7
	STA	g_sink8
	MVI	A, 3
	CALL	use8
	LXI	HL, 0x68ac
	CALL	use16
	MVI	A, 0xa
	CALL	use8
	MVI	A, 7
	CALL	use8
	MVI	A, 0x12
	CALL	use8
	MVI	A, 3
	STA	g_sink8
	MVI	A, 7
	CALL	use8
	;--- V6CLANG_LOAD16_G ---
	XCHG
	LHLD	arr
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.main
	XCHG
	MOV	H, D
	MOV	L, E
	;--- V6CLANG_DCX16 ---
	DCX	HL
	;--- V6CLANG_LOAD8_P ---
	MOV	L, M
	;--- V6CLANG_LOAD8_P ---
	LDAX	DE
	XRI	4
	ORA	L
	CALL	use8
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.main
	XCHG
	MOV	H, D
	MOV	L, E
	;--- V6CLANG_INX16 ---
	INX	HL
	;--- V6CLANG_SPILL16 ---
	PUSH	HL
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	XRI	4
	;--- V6CLANG_LOAD8_P ---
	PUSH	HL
	MOV	H, D
	MOV	L, E
	MOV	L, M
	POP	HL
	ORA	L
	CALL	use8
	;--- V6CLANG_RELOAD16 ---
	POP	HL
	;--- V6CLANG_LOAD8_P ---
	MOV	L, M
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	__v6clang_ss.main
	XCHG
	;--- V6CLANG_INX16 ---
	INX	DE
	INX	DE
	;--- V6CLANG_SPILL16 ---
	XCHG
	PUSH	HL
	XCHG
	;--- V6CLANG_LOAD8_P ---
	LDAX	DE
	XRI	4
	ORA	L
	CALL	use8
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.main
	XCHG
	;--- V6CLANG_INX16 ---
	INX	DE
	INX	DE
	INX	DE
	;--- V6CLANG_RELOAD16 ---
	POP	HL
	;--- V6CLANG_LOAD8_P ---
	MOV	L, M
	;--- V6CLANG_LOAD8_P ---
	LDAX	DE
	XRI	4
	ORA	L
	CALL	use8
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_sink8                         ; @g_sink8
g_sink8:
	DB	0                               ; 0x0

	.globl	arr                             ; @arr
arr:
	DW	0

	.local	__v6clang_ss.spill_pressure         ; @__v6clang_ss.spill_pressure
	.comm	__v6clang_ss.spill_pressure,1,1
	.local	__v6clang_ss.arr_sum                ; @__v6clang_ss.arr_sum
	.comm	__v6clang_ss.arr_sum,9,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,4,1
	.addrsig
	.addrsig_sym g_sink8
