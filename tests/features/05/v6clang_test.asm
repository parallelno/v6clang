	.text
	.globl	use8                            ; -- Begin function use8
use8:                                   ; @use8
; %bb.0:
	STA	sink8
	RET
                                        ; -- End function
	.globl	use16                           ; -- Begin function use16
use16:                                  ; @use16
; %bb.0:
	SHLD	sink16
	RET
                                        ; -- End function
	.globl	get8                            ; -- Begin function get8
get8:                                   ; @get8
; %bb.0:
	LDA	sink8
	RET
                                        ; -- End function
	.globl	test_multi_zext                 ; -- Begin function test_multi_zext
test_multi_zext:                        ; @test_multi_zext
; %bb.0:
	MVI	L, 0
	MOV	B, L
	MOV	C, A
	MOV	H, L
	MOV	L, E
	DAD	BC
	SHLD	sink16
	RET
                                        ; -- End function
	.globl	test_same_imm                   ; -- Begin function test_same_imm
test_same_imm:                          ; @test_same_imm
; %bb.0:
	MVI	A, 0x2a
	STA	sink8
	STA	sink8
	RET
                                        ; -- End function
	.globl	test_sequential_values          ; -- Begin function test_sequential_values
test_sequential_values:                 ; @test_sequential_values
; %bb.0:
	MVI	A, 0xa
	STA	sink8
	INR	A
	STA	sink8
	RET
                                        ; -- End function
	.globl	test_mov_propagation            ; -- Begin function test_mov_propagation
test_mov_propagation:                   ; @test_mov_propagation
; %bb.0:
	MVI	L, 0
	MOV	H, L
	MOV	L, A
	SHLD	sink16
	SHLD	sink16
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0xf
	SHLD	sink16
	MVI	A, 0x2a
	STA	sink8
	STA	sink8
	MVI	A, 0xa
	STA	sink8
	INR	A
	STA	sink8
	LXI	HL, 7
	SHLD	sink16
	SHLD	sink16
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	sink8                           ; @sink8
sink8:
	DB	0                               ; 0x0

	.globl	sink16                          ; @sink16
sink16:
	DW	0                               ; 0x0

	.addrsig
	.addrsig_sym sink8
	.addrsig_sym sink16
