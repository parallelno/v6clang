	.text
	.globl	fill_array                      ; -- Begin function fill_array
fill_array:                             ; @fill_array
; %bb.0:
	MOV	L, A
	LXI	DE, array1
.LBB0_1:                                ; =>This Inner Loop Header: Depth=1
	MOV	A, L
	STAX	DE
	INR	L
	INX	DE
	MVI	A, <(array1+100)
	CMP	E
	JNZ	.LBB0_1
; %bb.3:                                ;   in Loop: Header=BB0_1 Depth=1
	MVI	A, >(array1+100)
	CMP	D
	JNZ	.LBB0_1
; %bb.2:
	RET
                                        ; -- End function
	.globl	copy_loop                       ; -- Begin function copy_loop
copy_loop:                              ; @copy_loop
; %bb.0:
	LXI	HL, array2
	LXI	DE, array1
.LBB1_1:                                ; =>This Inner Loop Header: Depth=1
	LDAX	DE
	MOV	M, A
	INX	HL
	INX	DE
	MVI	A, <(array1+100)
	CMP	E
	JNZ	.LBB1_1
; %bb.3:                                ;   in Loop: Header=BB1_1 Depth=1
	MVI	A, >(array1+100)
	CMP	D
	JNZ	.LBB1_1
; %bb.2:
	RET
                                        ; -- End function
	.globl	add_small                       ; -- Begin function add_small
add_small:                              ; @add_small
; %bb.0:
	INX	HL
	INX	HL
	RET
                                        ; -- End function
	.globl	sub_small                       ; -- Begin function sub_small
sub_small:                              ; @sub_small
; %bb.0:
	DCX	HL
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0xa
	CALL	fill_array
	CALL	copy_loop
	LXI	HL, 0x64
	CALL	add_small
	LXI	DE, 0xff
	MOV	A, L
	ANA	E
	MOV	C, A
	MOV	A, H
	ANA	D
	MOV	B, A
	LXI	HL, 0xc8
	CALL	sub_small
	MOV	A, L
	ANA	E
	MOV	L, A
	MOV	A, H
	ANA	D
	MOV	H, A
	DAD	BC
	MVI	E, 0
	LDA	array2
	MOV	B, E
	MOV	C, A
	DAD	BC
	LDA	array2+99
	MOV	D, E
	MOV	E, A
	DAD	DE
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	array1                          ; @array1
array1:

	.globl	array2                          ; @array2
array2:

	.addrsig
