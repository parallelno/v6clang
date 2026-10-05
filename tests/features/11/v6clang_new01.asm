	.text
	.globl	return_second                   ; -- Begin function return_second
return_second:                          ; @return_second
; %bb.0:
	XCHG
	RET
                                        ; -- End function
	.globl	select_second                   ; -- Begin function select_second
select_second:                          ; @select_second
; %bb.0:
	PUSH	HL
	PUSH	DE
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	INX	HL
	MOV	A, M
	INX	HL
	MOV	H, M
	MOV	L, A
	PUSH	HL
	LXI	HL, 6
	DAD	SP
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	LXI	BC, 0
	MOV	A, L
	SUB	C
	MOV	A, H
	SBB	B
	JNZ	.LBB1_2
; %bb.1:
	PUSH	HL
	LXI	HL, 6
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	POP	HL
.LBB1_2:
	XCHG
	XCHG
	LXI	HL, 6
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.globl	add_and_return                  ; -- Begin function add_and_return
add_and_return:                         ; @add_and_return
; %bb.0:
	DAD	DE
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	LXI	DE, 0
	DAD	SP
	LXI	HL, 2
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0xa
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 7
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.addrsig
