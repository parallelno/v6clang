	.text
	.globl	sumarray                        ; -- Begin function sumarray
sumarray:                               ; @sumarray
; %bb.0:
	LXI	HL, arr2
	SHLD	__v6clang_ss.sumarray
	LXI	HL, arr1
	LXI	DE, 0
.LBB0_1:                                ; =>This Inner Loop Header: Depth=1
	SHLD	__v6clang_ss.sumarray+4
	MOV	B, D
	MOV	C, E
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	DAD	BC
	SHLD	__v6clang_ss.sumarray+2
	LHLD	__v6clang_ss.sumarray
	MOV	C, L
	MOV	B, H
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LHLD	__v6clang_ss.sumarray+2
	DAD	DE
	XCHG
	LHLD	__v6clang_ss.sumarray+4
	INX	BC
	INX	BC
	PUSH	HL
	LXI	HL, __v6clang_ss.sumarray
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	INX	HL
	INX	HL
	MVI	A, <(arr1+400)
	CMP	L
	JNZ	.LBB0_1
; %bb.3:                                ;   in Loop: Header=BB0_1 Depth=1
	MVI	A, >(arr1+400)
	CMP	H
	JNZ	.LBB0_1
; %bb.2:
	XCHG
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, arr2
	SHLD	__v6clang_ss.main
	LXI	HL, arr1
	LXI	DE, 0
.LBB1_1:                                ; =>This Inner Loop Header: Depth=1
	SHLD	__v6clang_ss.main+4
	MOV	B, D
	MOV	C, E
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	DAD	BC
	SHLD	__v6clang_ss.main+2
	LHLD	__v6clang_ss.main
	MOV	C, L
	MOV	B, H
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LHLD	__v6clang_ss.main+2
	DAD	DE
	XCHG
	LHLD	__v6clang_ss.main+4
	INX	BC
	INX	BC
	PUSH	HL
	LXI	HL, __v6clang_ss.main
	MOV	M, C
	INX	HL
	MOV	M, B
	POP	HL
	INX	HL
	INX	HL
	MVI	A, <(arr1+400)
	CMP	L
	JNZ	.LBB1_1
; %bb.3:                                ;   in Loop: Header=BB1_1 Depth=1
	MVI	A, >(arr1+400)
	CMP	H
	JNZ	.LBB1_1
; %bb.2:
	XCHG
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	arr1                            ; @arr1
arr1:

	.globl	arr2                            ; @arr2
arr2:

	.local	__v6clang_ss.sumarray               ; @__v6clang_ss.sumarray
	.comm	__v6clang_ss.sumarray,6,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,6,1
	.addrsig
	.addrsig_sym arr1
	.addrsig_sym arr2
