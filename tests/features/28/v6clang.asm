	.text
	.globl	test_ult                        ; -- Begin function test_ult
test_ult:                               ; @test_ult
; %bb.0:
	MVI	A, 0xe7
	SUB	L
	MVI	A, 3
	SBB	H
	RC
.LBB0_1:
	LXI	HL, 1
	SHLD	result
; %bb.2:
	RET
                                        ; -- End function
	.globl	test_uge                        ; -- Begin function test_uge
test_uge:                               ; @test_uge
; %bb.0:
	MVI	A, 0xe7
	SUB	L
	MVI	A, 3
	SBB	H
	RNC
.LBB1_1:
	LXI	HL, 2
	SHLD	result
; %bb.2:
	RET
                                        ; -- End function
	.globl	test_ugt                        ; -- Begin function test_ugt
test_ugt:                               ; @test_ugt
; %bb.0:
	MVI	A, 0xe8
	SUB	L
	MVI	A, 3
	SBB	H
	RNC
.LBB2_1:
	LXI	HL, 3
	SHLD	result
; %bb.2:
	RET
                                        ; -- End function
	.globl	test_ule                        ; -- Begin function test_ule
test_ule:                               ; @test_ule
; %bb.0:
	MVI	A, 0xe8
	SUB	L
	MVI	A, 3
	SBB	H
	RC
.LBB3_1:
	LXI	HL, 4
	SHLD	result
; %bb.2:
	RET
                                        ; -- End function
	.globl	test_slt                        ; -- Begin function test_slt
test_slt:                               ; @test_slt
; %bb.0:
	MVI	A, 0xf3
	SUB	L
	MVI	A, 1
	SBB	H
	RM
.LBB4_1:
	LXI	HL, 5
	SHLD	result
; %bb.2:
	RET
                                        ; -- End function
	.globl	test_sge                        ; -- Begin function test_sge
test_sge:                               ; @test_sge
; %bb.0:
	MVI	A, 0xf3
	SUB	L
	MVI	A, 1
	SBB	H
	RP
.LBB5_1:
	LXI	HL, 6
	SHLD	result
; %bb.2:
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 1
	SHLD	result
	LXI	HL, 2
	SHLD	result
	LXI	HL, 3
	SHLD	result
	LXI	HL, 4
	SHLD	result
	LXI	HL, 5
	SHLD	result
	LXI	HL, 6
	SHLD	result
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	result                          ; @result
result:
	DW	0                               ; 0x0

	.addrsig
	.addrsig_sym result
