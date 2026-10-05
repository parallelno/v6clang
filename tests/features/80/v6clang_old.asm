	.text
	.section	.text.static_probe,"ax",@progbits
	.globl	static_probe                    ; -- Begin function static_probe
static_probe:                           ; @static_probe
; %bb.0:
	SHLD	__v6clang_a.static_probe
	LHLD	__v6clang_a.static_probe
	LXI	D, 0x123
	DAD	D
	SHLD	__v6clang_a.static_probe+2
	LHLD	__v6clang_a.static_probe+2
	INX	H
	SHLD	__v6clang_a.static_probe+4
	LHLD	__v6clang_a.static_probe+4
	SHLD	sink
	HLT
	LHLD	__v6clang_a.static_probe+2
	RET
                                        ; -- End function
	.section	.text.dynamic_probe,"ax",@progbits
	.globl	dynamic_probe                   ; -- Begin function dynamic_probe
dynamic_probe:                          ; @dynamic_probe
; %bb.0:
	XCHG
	LXI	H, 0xfff4
	DAD	SP
	SPHL
	MOV	B, D
	MOV	C, E
	LXI	H, 0xa
	DAD	SP
	MOV	M, C
	INX	H
	MOV	M, B
	LXI	H, 0xa
	DAD	SP
	MOV	E, M
	INX	H
	MOV	D, M
	LXI	H, 0
	DAD	SP
	MOV	M, E
	INX	H
	MOV	M, D
	XCHG
	LXI	D, 0x234
	DAD	D
	MOV	B, H
	MOV	C, L
	LXI	H, 8
	DAD	SP
	MOV	M, C
	INX	H
	MOV	M, B
	LXI	H, 8
	DAD	SP
	MOV	C, M
	INX	H
	MOV	B, M
	INX	B
	LXI	H, 6
	DAD	SP
	MOV	M, C
	INX	H
	MOV	M, B
	LXI	H, 6
	DAD	SP
	MOV	E, M
	INX	H
	MOV	D, M
	LXI	H, 2
	DAD	SP
	MOV	M, E
	INX	H
	MOV	M, D
	XCHG
	SHLD	sink
	HLT
	LXI	H, 8
	DAD	SP
	MOV	E, M
	INX	H
	MOV	D, M
	LXI	H, 4
	DAD	SP
	MOV	M, E
	INX	H
	MOV	M, D
	MOV	H, D
	LXI	H, 0xc
	DAD	SP
	SPHL
	XCHG
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	H, 0x1122
	JMP	static_probe
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	sink                            ; @sink
sink:
	DW	0                               ; 0x0

	.data
	.globl	keep_dynamic                    ; @keep_dynamic
keep_dynamic:
	DW	dynamic_probe

	.local	__v6clang_a.static_probe            ; @__v6clang_a.static_probe
	.comm	__v6clang_a.static_probe,6,1
	.addrsig
	.addrsig_sym __mulqi3
	.addrsig_sym __v6clang_mulqihi3
	.addrsig_sym __mulhi3
	.addrsig_sym __v6clang_udivmod16_body
	.addrsig_sym __udivhi3
	.addrsig_sym __umodhi3
	.addrsig_sym __udivmodhi4
	.addrsig_sym __divmodhi4
	.addrsig_sym __v6clang_neg_hl_body
	.addrsig_sym __v6clang_neg_de_body
	.addrsig_sym __divhi3
	.addrsig_sym __modhi3
	.addrsig_sym __ashlhi3
	.addrsig_sym __lshrhi3
	.addrsig_sym __ashrhi3
	.addrsig_sym static_probe
	.addrsig_sym dynamic_probe
	.addrsig_sym sink
	.addrsig_sym __v6clang_a.static_probe
