	.text
	.globl	fill_array                      ; -- Begin function fill_array
fill_array:                             ; @fill_array
; %bb.0:
	MOV	L, A
	LXI	DE, array1
	LXI	BC, 1
.LBB0_1:                                ; =>This Inner Loop Header: Depth=1
	MOV	A, L
	STAX	DE
	INX	DE
	INR	L
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
	.globl	copy_array                      ; -- Begin function copy_array
copy_array:                             ; @copy_array
; %bb.0:
	LXI	HL, array2
	LXI	DE, array1
	LXI	BC, 1
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
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	MVI	A, 0x2a
	CALL	fill_array
	CALL	copy_array
	MVI	L, 0
	LDA	array2
	MOV	D, L
	MOV	E, A
	LDA	array2+99
	MOV	H, L
	MOV	L, A
	DAD	DE
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	array1                          ; @array1
array1:

	.globl	array2                          ; @array2
array2:

	.addrsig
