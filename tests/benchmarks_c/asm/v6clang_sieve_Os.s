	.text
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(int arg0, void* arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	LXI	H, flags
.LBB15_1:                               ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_STORE8_IMM_P ---
	MVI	M, 0
	;--- V6CLANG_INX16 ---
	INX	H
	;--- V6CLANG_BR_CC16_IMM ---
	MVI	A, <(flags+8000)
	CMP	L
	JNZ	.LBB15_1
; %bb.10:                               ;   in Loop: Header=BB15_1 Depth=1
	MVI	A, >(flags+8000)
	CMP	H
	JNZ	.LBB15_1
; %bb.2:
	MVI	A, 2
	LXI	H, 4
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_5+1
	LXI	H, 0x1f3e
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_0+1
	LXI	H, 5
	LXI	D, flags+4
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_2+1
	XCHG
.LBB15_3:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_5 Depth 2
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_3+1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_6+1
	;--- V6CLANG_BUILD_PAIR ---
	MVI	D, 0
	MOV	E, A
	LXI	H, flags
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_1+1
	XCHG
	;--- V6CLANG_DAD ---
	DAD	D
	XCHG
	;--- V6CLANG_LOAD8_P ---
	LDAX	D
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_8
; %bb.4:                                ;   in Loop: Header=BB15_3 Depth=1
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_2+1
	XCHG
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_5+1
.LBB15_5:                               ;   Parent Loop BB15_3 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_4+1
	;--- V6CLANG_LOAD8_P ---
	LDAX	D
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	MVI	L, 0
	MOV	A, L
	JNZ	.LBB15_7
; %bb.6:                                ;   in Loop: Header=BB15_5 Depth=2
	MVI	A, 1
.LBB15_7:                               ;   in Loop: Header=BB15_5 Depth=2
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	;--- V6CLANG_RELOAD16 ---
.LLo61_0:
	LXI	B, 0
	;--- V6CLANG_SUB16 ---
	MOV	A, C
	SUB	L
	MOV	L, A
	MOV	A, B
	SBB	H
	;--- V6CLANG_SPILL16 ---
	MOV	H, A
	SHLD	.LLo61_0+1
	;--- V6CLANG_STORE8_IMM_P ---
	MVI	A, 1
	STAX	D
	;--- V6CLANG_RELOAD16 ---
.LLo61_1:
	LXI	H, 0
	;--- V6CLANG_ADD16 ---
	XCHG
	DAD	D
	XCHG
	;--- V6CLANG_RELOAD16 ---
.LLo61_4:
	LXI	B, 0
	;--- V6CLANG_ADD16 ---
	DAD	B
	;--- V6CLANG_BR_CC16_IMM ---
	MVI	A, 0x3f
	SUB	L
	MVI	A, 0x1f
	SBB	H
	JNC	.LBB15_5
.LBB15_8:                               ;   in Loop: Header=BB15_3 Depth=1
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_1+1
	;--- V6CLANG_SHL16_DAD ---
	DAD	H
	;--- V6CLANG_RELOAD16 ---
.LLo61_5:
	LXI	D, 0
	;--- V6CLANG_ADD16 ---
	DAD	D
	XCHG
	;--- V6CLANG_RELOAD16 ---
.LLo61_3:
	LXI	H, 0
	;--- V6CLANG_RELOAD16 ---
.LLo61_2:
	LXI	B, 0
	;--- V6CLANG_ADD16 ---
	PUSH	H
	DAD	B
	MOV	C, L
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_2+1
	POP	H
	;--- V6CLANG_INX16 ---
	INX	H
	INX	H
	;--- V6CLANG_RELOAD8 ---
.LLo61_6:
	MVI	A, 0
	INR	A
	CPI	0x5a
	;--- V6CLANG_INX16 ---
	INX	D
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_5+1
	XCHG
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_3
; %bb.9:
	;--- V6CLANG_RELOAD16 ---
	LHLD	.LLo61_0+1
	XCHG
	;--- V6CLANG_SRL16_BYTE ---
	;--- V6CLANG_XOR16 ---
	MOV	A, D
	XRA	E
	OUT	0xed
	HLT
                                        ; -- End function
	.local	flags                           ; @flags
	.comm	flags,8000,1
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
