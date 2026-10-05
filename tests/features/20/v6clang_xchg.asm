	.text
	.globl	interleaved_add                 ; -- Begin function interleaved_add
interleaved_add:                        ; @interleaved_add
	;=== void interleaved_add(void* arg0, void* arg1, void* arg2, char arg3) ===
	;  arg0 = HL
	;  arg1 = DE
	;  arg2 = BC
	;  arg3 = stack
; %bb.0:
	PUSH	HL
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_0+1
	POP	HL
	XCHG
	SHLD	.LLo61_2+1
	XCHG
	SHLD	.LLo61_3+1
	;--- V6CLANG_LEA_FI ---
	LXI	HL, 0
	DAD	SP
	MOV	B, H
	MOV	C, L
	;--- V6CLANG_LOAD8_P ---
	LDAX	BC
	ORA	A
	;--- V6CLANG_BRCOND ---
	JZ	.LBB0_3
; %bb.1:
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, L
	MOV	E, A
	LHLD	.LLo61_3+1
.LBB0_2:                                ; =>This Inner Loop Header: Depth=1
	XCHG
	SHLD	.LLo61_1+1
	XCHG
.LLo61_0:
	LXI	BC, 0
	;--- V6CLANG_LOAD8_P ---
	LDAX	BC
.LLo61_2:
	LXI	DE, 0
	;--- V6CLANG_ADD_M_P ---
	XCHG
	ADD	M
	XCHG
	;--- V6CLANG_STORE8_P ---
	MOV	M, A
	;--- V6CLANG_INX16 ---
	INX	DE
	XCHG
	SHLD	.LLo61_2+1
	XCHG
.LLo61_1:
	LXI	DE, 0
	;--- V6CLANG_INX16 ---
	INX	BC
	PUSH	HL
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_0+1
	POP	HL
	;--- V6CLANG_INX16 ---
	INX	HL
	;--- V6CLANG_DCX16 ---
	DCX	DE
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, D
	ORA	E
	JNZ	.LBB0_2
.LBB0_3:
.LLo61_3:
	LXI	HL, 0
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
	LXI	HL, .LLo61_4+1
	MOV	M, E
	STA	.LLo61_5+1
	MOV	A, C
	CALL	use8
.LLo61_5:
	MVI	A, 0
.LLo61_4:
	MVI	L, 0
	ADD	L
	ADI	3
	RET
                                        ; -- End function
	.globl	sum                             ; -- Begin function sum
sum:                                    ; @sum
	;=== char sum(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	MOV	L, A
	MOV	A, E
	ADD	L
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
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_6+1
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
	XCHG
	SHLD	.LLo61_7+1
	XCHG
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
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	;--- V6CLANG_LEA_FI ---
	LXI	DE, __v6clang_ss.main+8
	MOV	B, D
	MOV	C, E
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
	MOV	B, D
	MOV	C, E
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
	;--- V6CLANG_STORE8_IMM_P ---
	MVI	M, 4
.LLo61_6:
	LXI	HL, 0
.LLo61_7:
	LXI	DE, 0
	CALL	interleaved_add
	LHLD	.LLo61_6+1
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	;--- V6CLANG_LEA_FI ---
	LXI	DE, __v6clang_ss.main+12
	XCHG
	SHLD	.LLo61_6+1
	XCHG
	;--- V6CLANG_STORE8_P ---
	STAX	DE
	MVI	A, 3
	CALL	use8
	LHLD	.LLo61_6+1
	;--- V6CLANG_STORE8_IMM_P ---
	MVI	M, 6
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
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,13,1
	.addrsig
