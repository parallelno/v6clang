	.text
	.globl	sum_add                         ; -- Begin function sum_add
sum_add:                                ; @sum_add
	;=== char sum_add(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	MOV	L, A
	MOV	A, E
	ADD	L
	RET
                                        ; -- End function
	.globl	sum_and                         ; -- Begin function sum_and
sum_and:                                ; @sum_and
	;=== char sum_and(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	MOV	L, A
	MOV	A, E
	ANA	L
	RET
                                        ; -- End function
	.globl	sum_or                          ; -- Begin function sum_or
sum_or:                                 ; @sum_or
	;=== char sum_or(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	MOV	L, A
	MOV	A, E
	ORA	L
	RET
                                        ; -- End function
	.globl	sum_xor                         ; -- Begin function sum_xor
sum_xor:                                ; @sum_xor
	;=== char sum_xor(char arg0, char arg1) ===
	;  arg0 = A
	;  arg1 = E
; %bb.0:
	MOV	L, A
	MOV	A, E
	XRA	L
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
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g_sink8                         ; @g_sink8
g_sink8:
	DB	0                               ; 0x0

	.local	__v6clang_ss.spill_pressure         ; @__v6clang_ss.spill_pressure
	.comm	__v6clang_ss.spill_pressure,1,1
	.addrsig
	.addrsig_sym g_sink8
