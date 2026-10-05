	.text
	.section	.text.sieve_count,"ax",@progbits
	.globl	sieve_count                     ; -- Begin function sieve_count
sieve_count:                            ; @sieve_count
.Lfunc_begin0:
	;=== int sieve_count(int n) ===
	;  n = HL
; %bb.0:
	;DEBUG_VALUE: sieve_count:n <- $hl
	;DEBUG_VALUE: sieve_count:k <- 0
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, H
	ORA	L
	JZ	.LBB15_11
; %bb.1:
	;DEBUG_VALUE: sieve_count:k <- 0
	;DEBUG_VALUE: sieve_count:n <- $hl
	LXI	B, flags
	LXI	D, 0
.LBB15_2:                               ; =>This Inner Loop Header: Depth=1
	;DEBUG_VALUE: sieve_count:n <- $hl
	;DEBUG_VALUE: sieve_count:k <- $de
	;--- V6CLANG_STORE8_IMM_P ---
	XRA	A
	STAX	B
	;--- V6CLANG_INX16 ---
	INX	B
	;--- V6CLANG_INX16 ---
	INX	D
	;DEBUG_VALUE: sieve_count:k <- $de
	;--- V6CLANG_BR_CC16 ---
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	JC	.LBB15_2
; %bb.3:
	;DEBUG_VALUE: sieve_count:k <- $de
	;DEBUG_VALUE: sieve_count:n <- $hl
	MOV	D, H
	MOV	E, L
	;--- V6CLANG_DCX16 ---
	DCX	D
	DCX	D
	;DEBUG_VALUE: sieve_count:i <- 2
	;DEBUG_VALUE: sieve_count:i_sq <- 4
	;DEBUG_VALUE: sieve_count:count <- $de
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_1+1
	XCHG
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_BR_CC16_IMM ---
	MVI	A, 4
	SUB	L
	MVI	A, 0
	SBB	H
	JNC	.LBB15_12
; %bb.4:
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- 4
	;DEBUG_VALUE: sieve_count:i <- 2
	LXI	B, 2
	LXI	D, 4
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_2+1
	XCHG
	LXI	D, 5
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_3+1
	XCHG
	LXI	D, flags+4
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_6+1
	XCHG
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_5+1
.LBB15_5:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_7 Depth 2
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i <- $bc
	;--- V6CLANG_SPILL16 ---
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_0+1
	LXI	H, flags
	;--- V6CLANG_DAD ---
	DAD	B
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_10
; %bb.6:                                ;   in Loop: Header=BB15_5 Depth=1
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_6+1
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	.LLo61_2+1
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_4+1
	XCHG
.LBB15_7:                               ;   Parent Loop BB15_5 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_RELOAD16 ---
.LLo61_0:
	LXI	D, 0
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	MVI	E, 0
	MOV	A, E
	JNZ	.LBB15_9
; %bb.8:                                ;   in Loop: Header=BB15_7 Depth=2
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	MVI	A, 1
.LBB15_9:                               ;   in Loop: Header=BB15_7 Depth=2
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, E
	MOV	E, A
	;--- V6CLANG_RELOAD16 ---
.LLo61_1:
	LXI	B, 0
	;--- V6CLANG_SUB16 ---
	MOV	A, C
	SUB	E
	MOV	C, A
	MOV	A, B
	SBB	D
	;DEBUG_VALUE: sieve_count:count <- $bc
	;--- V6CLANG_SPILL16 ---
	PUSH	H
	MOV	L, C
	MOV	H, A
	SHLD	.LLo61_1+1
	POP	H
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_STORE8_IMM_P ---
	MVI	M, 1
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	.LLo61_0+1
	XCHG
	;--- V6CLANG_ADD16 ---
	DAD	D
	;--- V6CLANG_RELOAD16 ---
.LLo61_4:
	LXI	B, 0
	;--- V6CLANG_ADD16 ---
	XCHG
	DAD	B
	XCHG
	MOV	B, D
	MOV	C, E
	;DEBUG_VALUE: sieve_count:k <- $bc
	;--- V6CLANG_RELOAD16 ---
.LLo61_5:
	LXI	D, 0
	;--- V6CLANG_SPILL16 ---
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_4+1
	POP	H
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;--- V6CLANG_BR_CC16 ---
	MOV	A, C
	SUB	E
	MOV	A, B
	SBB	D
	JC	.LBB15_7
.LBB15_10:                              ;   in Loop: Header=BB15_5 Depth=1
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_0+1
	;--- V6CLANG_ADD16 ---
	DAD	H
	;--- V6CLANG_RELOAD16 ---
.LLo61_2:
	LXI	B, 0
	;--- V6CLANG_ADD16 ---
	DAD	B
	MOV	B, H
	MOV	C, L
	;--- V6CLANG_RELOAD16 ---
.LLo61_3:
	LXI	H, 0
	;--- V6CLANG_RELOAD16 ---
.LLo61_6:
	LXI	D, 0
	;--- V6CLANG_ADD16 ---
	XCHG
	DAD	D
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_6+1
	XCHG
	;--- V6CLANG_INX16 ---
	INX	H
	INX	H
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_3+1
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_0+1
	;--- V6CLANG_INX16 ---
	INX	H
	;DEBUG_VALUE: sieve_count:i <- $hl
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_0+1
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	MOV	D, B
	MOV	E, C
	;--- V6CLANG_INX16 ---
	INX	D
	;DEBUG_VALUE: sieve_count:i_sq <- $de
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_5+1
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_2+1
	XCHG
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;--- V6CLANG_RELOAD16 ---
	PUSH	H
	LHLD	.LLo61_0+1
	MOV	C, L
	MOV	B, H
	POP	H
	;DEBUG_VALUE: sieve_count:i <- $bc
	;--- V6CLANG_BR_CC16 ---
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	JC	.LBB15_5
	JMP	.LBB15_12
.LBB15_11:
	;DEBUG_VALUE: sieve_count:k <- 0
	;DEBUG_VALUE: sieve_count:n <- $hl
	LXI	H, 0xfffe
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_1+1
.LBB15_12:
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_1+1
	RET
.Lfunc_end0:
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
.Lfunc_begin1:
	;=== int main(void) ===
	;  [folded: n=200]
; %bb.0:
	LXI	H, flags
	;DEBUG_VALUE: sieve_count:k <- 0
	;DEBUG_VALUE: sieve_count:n <- 200
.LBB16_1:                               ; =>This Inner Loop Header: Depth=1
	;DEBUG_VALUE: sieve_count:n <- 200
	;DEBUG_VALUE: sieve_count:k <- undef
	;--- V6CLANG_STORE8_IMM_P ---
	MVI	M, 0
	;--- V6CLANG_INX16 ---
	INX	H
	;--- V6CLANG_BR_CC16_IMM ---
	MVI	A, <(flags+200)
	CMP	L
	JNZ	.LBB16_1
; %bb.10:                               ;   in Loop: Header=BB16_1 Depth=1
	;DEBUG_VALUE: sieve_count:n <- 200
	MVI	A, >(flags+200)
	CMP	H
	JNZ	.LBB16_1
; %bb.2:
	;DEBUG_VALUE: sieve_count:n <- 200
	LXI	D, 2
	LXI	H, 0xc6
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_7+1
	LXI	H, 4
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_12+1
	INX	H
	LXI	B, flags+4
	;--- V6CLANG_SPILL16 ---
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_10+1
	POP	H
.LBB16_3:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB16_5 Depth 2
	;DEBUG_VALUE: sieve_count:n <- 200
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i <- $de
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_13+1
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_8+1
	SHLD	.LLo61_9+1
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_8+1
	;DEBUG_VALUE: sieve_count:i <- $hl
	LXI	D, flags
	;--- V6CLANG_DAD ---
	DAD	D
	XCHG
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;--- V6CLANG_LOAD8_P ---
	LDAX	D
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;--- V6CLANG_RELOAD16 ---
.LLo61_9:
	LXI	D, 0
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB16_8
; %bb.4:                                ;   in Loop: Header=BB16_3 Depth=1
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:n <- 200
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_10+1
	MOV	C, L
	MOV	B, H
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_12+1
.LBB16_5:                               ;   Parent Loop BB16_3 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:n <- 200
	;DEBUG_VALUE: sieve_count:k <- $hl
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_11+1
	;--- V6CLANG_LOAD8_P ---
	LDAX	B
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	MVI	L, 0
	MOV	A, L
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	JNZ	.LBB16_7
; %bb.6:                                ;   in Loop: Header=BB16_5 Depth=2
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:n <- 200
	MVI	A, 1
.LBB16_7:                               ;   in Loop: Header=BB16_5 Depth=2
	;DEBUG_VALUE: sieve_count:k <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:n <- 200
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	;--- V6CLANG_RELOAD16 ---
.LLo61_7:
	LXI	D, 0
	;--- V6CLANG_SUB16 ---
	MOV	A, E
	SUB	L
	MOV	E, A
	MOV	A, D
	SBB	H
	MOV	D, A
	;DEBUG_VALUE: sieve_count:count <- $de
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_7+1
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_STORE8_IMM_P ---
	MVI	A, 1
	STAX	B
	;--- V6CLANG_RELOAD16 ---
.LLo61_8:
	LXI	D, 0
	;--- V6CLANG_ADD16 ---
	MOV	A, C
	ADD	E
	MOV	C, A
	MOV	A, B
	ADC	D
	MOV	B, A
	;--- V6CLANG_RELOAD16 ---
.LLo61_11:
	LXI	H, 0
	;--- V6CLANG_ADD16 ---
	DAD	D
	;DEBUG_VALUE: sieve_count:k <- $hl
	;--- V6CLANG_BR_CC16_IMM ---
	MVI	A, 0xc7
	SUB	L
	MVI	A, 0
	SBB	H
	JNC	.LBB16_5
.LBB16_8:                               ;   in Loop: Header=BB16_3 Depth=1
	;DEBUG_VALUE: sieve_count:i <- [$sp+0]
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:n <- 200
	;DEBUG_VALUE: sieve_count:count <- [$sp+0]
	;--- V6CLANG_ADD16 ---
	MOV	H, D
	MOV	L, E
	DAD	D
	;--- V6CLANG_RELOAD16 ---
.LLo61_12:
	LXI	B, 0
	;--- V6CLANG_ADD16 ---
	DAD	B
	MOV	B, H
	MOV	C, L
	;--- V6CLANG_SPILL16 ---
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_12+1
	;--- V6CLANG_RELOAD16 ---
.LLo61_13:
	LXI	H, 0
	;--- V6CLANG_RELOAD16 ---
.LLo61_10:
	LXI	B, 0
	;--- V6CLANG_ADD16 ---
	PUSH	H
	DAD	B
	MOV	B, H
	MOV	C, L
	;--- V6CLANG_SPILL16 ---
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_10+1
	POP	H
	;--- V6CLANG_INX16 ---
	INX	H
	INX	H
	;--- V6CLANG_RELOAD16 ---
	PUSH	H
	LHLD	.LLo61_12+1
	MOV	C, L
	MOV	B, H
	;--- V6CLANG_INX16 ---
	INX	B
	;DEBUG_VALUE: sieve_count:i_sq <- $bc
	;--- V6CLANG_SPILL16 ---
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_12+1
	POP	H
	;DEBUG_VALUE: sieve_count:i_sq <- [$sp+0]
	;DEBUG_VALUE: sieve_count:i_sq <- undef
	;--- V6CLANG_INX16 ---
	INX	D
	;DEBUG_VALUE: sieve_count:i <- $de
	;--- V6CLANG_BR_CC16_IMM ---
	MVI	A, 0xf
	CMP	E
	JNZ	.LBB16_3
; %bb.11:                               ;   in Loop: Header=BB16_3 Depth=1
	;DEBUG_VALUE: sieve_count:i <- $de
	;DEBUG_VALUE: sieve_count:n <- 200
	XRA	A
	CMP	D
	JNZ	.LBB16_3
; %bb.9:
	;DEBUG_VALUE: main:c <- [$sp+0]
	LXI	H, 0xff
	;--- V6CLANG_RELOAD16 ---
	XCHG
	LHLD	.LLo61_7+1
	XCHG
	;DEBUG_VALUE: main:c <- $de
	;--- V6CLANG_AND16 ---
	MOV	A, E
	ANA	L
	MOV	L, A
	MOV	A, D
	ANA	H
	MOV	H, A
	;--- V6CLANG_SRL16 ---
	MOV	E, D
	MVI	D, 0
	;--- V6CLANG_XOR16 ---
	MOV	A, L
	XRA	E
	MOV	L, A
	MOV	A, H
	XRA	D
	MOV	H, A
	RET
.Lfunc_end1:
                                        ; -- End function
	.local	flags                           ; @flags
	.comm	flags,200,1
	.local	__v6clang_ss.sieve_count            ; @__v6clang_ss.sieve_count
	.comm	__v6clang_ss.sieve_count,8,1
	.local	__v6clang_ss.main                   ; @__v6clang_ss.main
	.comm	__v6clang_ss.main,8,1
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
