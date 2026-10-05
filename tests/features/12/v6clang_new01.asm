	.text
	.globl	select_second                   ; -- Begin function select_second
select_second:                          ; @select_second
; %bb.0:
	MOV	A, H
	ORA	L
	JNZ	.LBB0_2
; %bb.1:
	MOV	D, B
	MOV	E, C
.LBB0_2:
	XCHG
	RET
                                        ; -- End function
	.globl	select_on_zero                  ; -- Begin function select_on_zero
select_on_zero:                         ; @select_on_zero
; %bb.0:
	MOV	A, H
	ORA	L
	JNZ	.LBB1_2
; %bb.1:
	MOV	B, D
	MOV	C, E
.LBB1_2:
	MOV	H, B
	MOV	L, C
	RET
                                        ; -- End function
	.globl	select_nonzero                  ; -- Begin function select_nonzero
select_nonzero:                         ; @select_nonzero
; %bb.0:
	MOV	A, H
	ORA	L
	JNZ	.LBB2_2
; %bb.1:
	MOV	D, B
	MOV	E, C
.LBB2_2:
	XCHG
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
	LXI	HL, 0xa
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0x14
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	HL, 0x64
	PUSH	DE
	MOV	A, L
	STAX	DE
	INX	DE
	MOV	A, H
	STAX	DE
	POP	DE
	LXI	BC, 0xc8
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	MOV	H, D
	MOV	L, E
	MOV	M, C
	INX	HL
	MOV	M, B
	LXI	HL, 0x64
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
