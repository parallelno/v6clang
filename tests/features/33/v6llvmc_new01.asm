	.text
	.globl	hl_one_spill                    ; -- Begin function hl_one_spill
hl_one_spill:                           ; @hl_one_spill
; %bb.0:
	XCHG
	SHLD	__v6clang_ss.hl_one_spill
	XCHG
	CALL	op1
	SHLD	__v6clang_ss.hl_one_spill+2
	LHLD	__v6clang_ss.hl_one_spill
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
	SHLD	.LLo61_0+1
	CALL	op2
	SHLD	__v6clang_ss.hl_two_reloads
.LLo61_0:
	LXI	HL, 0
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
	SHLD	__v6clang_ss.main
	LXI	HL, 0x5678
	CALL	op2
	XCHG
	LHLD	__v6clang_ss.main
	XCHG
	DAD	DE
	SHLD	g1
	LXI	HL, 0xabcd
	CALL	op1
	SHLD	.LLo61_1+1
	CALL	op2
	SHLD	__v6clang_ss.main
.LLo61_1:
	LXI	HL, 0
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
