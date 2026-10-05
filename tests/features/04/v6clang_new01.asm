	.text
	.globl	read_offset1                    ; -- Begin function read_offset1
read_offset1:                           ; @read_offset1
; %bb.0:
	INX	HL
	MOV	A, M
	RET
                                        ; -- End function
	.globl	read_offset2                    ; -- Begin function read_offset2
read_offset2:                           ; @read_offset2
; %bb.0:
	INX	HL
	INX	HL
	MOV	A, M
	RET
                                        ; -- End function
	.globl	read_offset3                    ; -- Begin function read_offset3
read_offset3:                           ; @read_offset3
; %bb.0:
	INX	HL
	INX	HL
	INX	HL
	MOV	A, M
	RET
                                        ; -- End function
	.globl	read_offset4                    ; -- Begin function read_offset4
read_offset4:                           ; @read_offset4
; %bb.0:
	LXI	DE, 4
	DAD	DE
	MOV	A, M
	RET
                                        ; -- End function
	.globl	sum_adjacent                    ; -- Begin function sum_adjacent
sum_adjacent:                           ; @sum_adjacent
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	MOV	H, D
	MOV	L, E
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	LXI	DE, 1
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	MOV	A, M
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	DAD	DE
	MVI	E, 0
	MOV	B, E
	MOV	C, A
	MOV	A, M
	MOV	H, E
	MOV	L, A
	DAD	BC
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.globl	sum_three                       ; -- Begin function sum_three
sum_three:                              ; @sum_three
; %bb.0:
	MOV	D, H
	MOV	E, L
	LXI	HL, 0xfffe
	DAD	SP
	SPHL
	MOV	H, D
	MOV	L, E
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	XCHG
	POP	DE
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	MOV	A, M
	MVI	L, 0
	MOV	B, L
	MOV	C, A
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	INX	HL
	MOV	A, M
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	MOV	A, L
	ADD	C
	MOV	C, A
	MOV	A, H
	ADC	B
	MOV	B, A
	LXI	DE, 2
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	DAD	DE
	PUSH	DE
	XCHG
	LXI	HL, 2
	DAD	SP
	MOV	M, E
	INX	HL
	MOV	M, D
	POP	DE
	PUSH	DE
	LXI	HL, 2
	DAD	SP
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	POP	DE
	MOV	A, M
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	DAD	BC
	XCHG
	LXI	HL, 2
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	mem                             ; @mem
mem:

	.addrsig
