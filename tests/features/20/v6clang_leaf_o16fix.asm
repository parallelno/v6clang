	.text
	.globl	interleaved_add                 ; -- Begin function interleaved_add
interleaved_add:                        ; @interleaved_add
	;=== void interleaved_add(void* arg0, void* arg1, void* arg2, char arg3) ===
	;  arg0 = HL
	;  arg1 = DE
	;  arg2 = BC
	;  arg3 = stack
; %bb.0:
	;--- V6CLANG_SPILL16 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.interleaved_add+2
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	__v6clang_ss.interleaved_add
	XCHG
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.interleaved_add+7
	;--- V6CLANG_LEA_FI ---
	LXI	HL, 0
	DAD	SP
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	ORA	A
	;--- V6CLANG_BRCOND ---
	JZ	.LBB0_3
; %bb.1:
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	B, L
	MOV	C, A
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.interleaved_add+7
	XCHG
.LBB0_2:                                ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_SPILL16 ---
	MOV	L, C
	MOV	H, B
	PUSH	HL
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.interleaved_add
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	;--- V6CLANG_SPILL8 ---
	STA	__v6clang_ss.interleaved_add+6
	;--- V6CLANG_RELOAD16 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.interleaved_add+2
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	;--- V6CLANG_LOAD8_P ---
	LDAX	BC
	;--- V6CLANG_RELOAD8 ---
	PUSH	DE
	MOV	D, H
	LXI	HL, __v6clang_ss.interleaved_add+6
	MOV	L, M
	MOV	H, D
	POP	DE
	ADD	L
	;--- V6CLANG_STORE8_P ---
	STAX	DE
	;--- V6CLANG_INX16 ---
	INX	HL
	;--- V6CLANG_SPILL16 ---
	SHLD	__v6clang_ss.interleaved_add
	;--- V6CLANG_INX16 ---
	INX	BC
	;--- V6CLANG_SPILL16 ---
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.interleaved_add+2
	;--- V6CLANG_RELOAD16 ---
	POP	HL
	MOV	C, L
	MOV	B, H
	;--- V6CLANG_INX16 ---
	INX	DE
	;--- V6CLANG_DCX16 ---
	DCX	BC
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, B
	ORA	C
	JNZ	.LBB0_2
.LBB0_3:
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.interleaved_add+7
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	JMP	use8
                                        ; -- End function
	.globl	multi_live                      ; -- Begin function multi_live
multi_live:                             ; @multi_live
	;=== char multi_live(char arg0, char arg1, char arg2) ===
	;  arg0 = A
	;  arg1 = E
	;  arg2 = C
; %bb.0:
	;--- V6CLANG_SPILL8 ---
	LXI	HL, __v6clang_ss.multi_live
	MOV	M, E
	;--- V6CLANG_SPILL8 ---
	STA	__v6clang_ss.multi_live+1
	MOV	A, C
	CALL	use8
	;--- V6CLANG_RELOAD8 ---
	LDA	__v6clang_ss.multi_live+1
	;--- V6CLANG_RELOAD8 ---
	LXI	HL, __v6clang_ss.multi_live
	MOV	L, M
	ADD	L
	ADI	3
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(void) ===
; %bb.0:
	LXI	HL, 0xffff
	DAD	SP
	SPHL
	;--- V6CLANG_LEA_FI ---
	LXI	BC, __v6clang_ss.main
	;--- V6CLANG_SPILL16 ---
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.main+13
	MOV	H, B
	MOV	L, C
	;--- V6CLANG_INX16 ---
	INX	HL
	INX	HL
	LXI	DE, 0
	;--- V6CLANG_STORE16_P ---
	MOV	M, E
	INX	HL
	MOV	M, D
	;--- V6CLANG_STORE16_P ---
	MOV	H, B
	MOV	L, C
	MOV	M, E
	INX	HL
	MOV	M, D
	;--- V6CLANG_LEA_FI ---
	LXI	DE, __v6clang_ss.main+4
	MOV	H, D
	MOV	L, E
	;--- V6CLANG_INX16 ---
	INX	HL
	INX	HL
	LXI	BC, 0x281e
	;--- V6CLANG_STORE16_P ---
	MOV	M, C
	INX	HL
	MOV	M, B
	LXI	HL, 0x140a
	;--- V6CLANG_STORE16_P ---
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	;--- V6CLANG_LEA_FI ---
	LXI	BC, __v6clang_ss.main+8
	;--- V6CLANG_SPILL16 ---
	MOV	L, C
	MOV	H, B
	SHLD	__v6clang_ss.main+15
	;--- V6CLANG_INX16 ---
	INX	BC
	INX	BC
	LXI	HL, 0x403
	;--- V6CLANG_STORE16_P ---
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	LXI	HL, 0x201
	;--- V6CLANG_RELOAD16 ---
	PUSH	HL
	LXI	HL, __v6clang_ss.main+15
	MOV	C, M
	INX	HL
	MOV	B, M
	POP	HL
	;--- V6CLANG_STORE16_P ---
	PUSH	BC
	MOV	A, L
	STAX	BC
	INX	BC
	MOV	A, H
	STAX	BC
	POP	BC
	LXI	HL, 0
	DAD	SP
	MVI	A, 4
	;--- V6CLANG_STORE8_P ---
	MOV	M, A
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.main+13
	CALL	interleaved_add
	;--- V6CLANG_RELOAD16 ---
	LHLD	__v6clang_ss.main+13
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	;--- V6CLANG_LEA_FI ---
	LXI	HL, __v6clang_ss.main+12
	;--- V6CLANG_SPILL16 ---
	PUSH	HL
	;--- V6CLANG_STORE8_P ---
	MOV	M, A
	MVI	A, 3
	CALL	use8
	MVI	A, 6
	;--- V6CLANG_RELOAD16 ---
	POP	HL
	;--- V6CLANG_STORE8_P ---
	MOV	M, A
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	XCHG
	LXI	HL, 1
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.local	__v6clang_ss.interleaved_add        ; @__v6clang_ss.interleaved_add
	.comm	__v6clang_ss.interleaved_add,9,1
	.local	__v6clang_ss.multi_live             ; @__v6clang_ss.multi_live
	.comm	__v6clang_ss.multi_live,2,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,17,1
	.addrsig
