	.text
	.globl	sumarray                        ; -- Begin function sumarray
sumarray:                               ; @sumarray
; %bb.0:
	LXI	BC, arr2
	LXI	DE, arr1
	LXI	HL, 0
.LBB0_1:                                ; =>This Inner Loop Header: Depth=1
	SHLD	__v6clang_ss.sumarray
	XCHG
	SHLD	__v6clang_ss.sumarray+2
	XCHG
	XCHG
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	LHLD	__v6clang_ss.sumarray
	DAD	DE
	SHLD	__v6clang_ss.sumarray
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LHLD	__v6clang_ss.sumarray
	DAD	DE
	XCHG
	LHLD	__v6clang_ss.sumarray+2
	XCHG
	INX	BC
	INX	BC
	INX	DE
	INX	DE
	MVI	A, <(arr1+400)
	CMP	E
	JNZ	.LBB0_1
; %bb.3:                                ;   in Loop: Header=BB0_1 Depth=1
	MVI	A, >(arr1+400)
	CMP	D
	JNZ	.LBB0_1
; %bb.2:
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	BC, arr2
	LXI	DE, arr1
	LXI	HL, 0
.LBB1_1:                                ; =>This Inner Loop Header: Depth=1
	SHLD	__v6clang_ss.main
	XCHG
	SHLD	__v6clang_ss.main+2
	XCHG
	XCHG
	MOV	E, M
	INX	HL
	MOV	D, M
	XCHG
	LHLD	__v6clang_ss.main
	DAD	DE
	SHLD	__v6clang_ss.main
	MOV	H, B
	MOV	L, C
	MOV	E, M
	INX	HL
	MOV	D, M
	LHLD	__v6clang_ss.main
	DAD	DE
	XCHG
	LHLD	__v6clang_ss.main+2
	XCHG
	INX	BC
	INX	BC
	INX	DE
	INX	DE
	MVI	A, <(arr1+400)
	CMP	E
	JNZ	.LBB1_1
; %bb.3:                                ;   in Loop: Header=BB1_1 Depth=1
	MVI	A, >(arr1+400)
	CMP	D
	JNZ	.LBB1_1
; %bb.2:
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	arr1                            ; @arr1
arr1:

	.globl	arr2                            ; @arr2
arr2:

	.local	__v6clang_ss.sumarray               ; @__v6clang_ss.sumarray
	.comm	__v6clang_ss.sumarray,4,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,4,1
	.addrsig
	.addrsig_sym arr1
	.addrsig_sym arr2
