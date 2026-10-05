	.text
	.globl	hl_one_spill                    ; -- Begin function hl_one_spill
hl_one_spill:                           ; @hl_one_spill
; %bb.0:
	XCHG
	PUSH	HL
	XCHG
	CALL	op1
	SHLD	__v6clang_ss.hl_one_spill+2
	POP	HL
	CALL	op2
	XCHG
	LHLD	__v6clang_ss.hl_one_spill+2
	DAD	DE
	RET
                                        ; -- End function
	.globl	hl_two_reloads                  ; -- Begin function hl_two_reloads
hl_two_reloads:                         ; @hl_two_reloads
; %bb.0:
	CALL	op1
	PUSH	HL
	CALL	op2
	SHLD	__v6clang_ss.hl_two_reloads
	POP	HL
	CALL	op2
	XCHG
	LHLD	__v6clang_ss.hl_two_reloads
	DAD	DE
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
; %bb.0:
	LXI	HL, 0x1234
	CALL	op1
	PUSH	HL
	LXI	HL, 0x5678
	CALL	op2
	XCHG
	POP	HL
	XCHG
	DAD	DE
	SHLD	g1
	LXI	HL, 0xabcd
	CALL	op1
	PUSH	HL
	CALL	op2
	SHLD	__v6clang_ss.main
	POP	HL
	CALL	op2
	XCHG
	LHLD	__v6clang_ss.main
	DAD	DE
	SHLD	g2
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	g1                              ; @g1
g1:
	DW	0                               ; 0x0

	.globl	g2                              ; @g2
g2:
	DW	0                               ; 0x0

	.local	__v6clang_ss.hl_one_spill           ; @__v6clang_ss.hl_one_spill
	.comm	__v6clang_ss.hl_one_spill,4,1
	.local	__v6clang_ss.hl_two_reloads         ; @__v6clang_ss.hl_two_reloads
	.comm	__v6clang_ss.hl_two_reloads,4,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,4,1
	.addrsig
