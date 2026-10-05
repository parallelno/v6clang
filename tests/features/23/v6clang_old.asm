	.text
	.globl	fill_array                      ; -- Begin function fill_array
fill_array:                             ; @fill_array
; %bb.0:
	MOV	E, A
	LXI	BC, array1
.LBB0_1:                                ; =>This Inner Loop Header: Depth=1
	MOV	H, B
	MOV	L, C
	MOV	M, E
	INX	BC
	INR	E
	MVI	A, <(array1+100)
	CMP	C
	JNZ	.LBB0_1
; %bb.3:                                ;   in Loop: Header=BB0_1 Depth=1
	MVI	A, >(array1+100)
	CMP	B
	JNZ	.LBB0_1
; %bb.2:
	RET
                                        ; -- End function
	.globl	copy_array                      ; -- Begin function copy_array
copy_array:                             ; @copy_array
; %bb.0:
	LXI	DE, array2
	LXI	BC, array1
.LBB1_1:                                ; =>This Inner Loop Header: Depth=1
	LDAX	BC
	STAX	DE
	INX	DE
	INX	BC
	MVI	A, <(array1+100)
	CMP	C
	JNZ	.LBB1_1
; %bb.3:                                ;   in Loop: Header=BB1_1 Depth=1
	MVI	A, >(array1+100)
	CMP	B
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
	.addrsig_sym array1
	.addrsig_sym array2
