	.text
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(int arg0, void* arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	MVI	A, 7
	STA	__v6clang_a.main
	LDA	__v6clang_a.main
	MOV	E, A
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	;--- V6CLANG_BRCOND ---
	JZ	.LBB15_3
; %bb.1:
	MVI	D, 0
	LXI	H, perm1
.LBB15_2:                               ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_STORE8_P ---
	MOV	M, D
	INR	D
	CMP	D
	;--- V6CLANG_INX16 ---
	INX	H
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_2
.LBB15_3:
	XRA	A
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_3+1
	MOV	H, E
	;--- V6CLANG_SPILL8 ---
	MOV	A, H
	STA	.LLo61_5+1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_6+1
.LBB15_4:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_8 Depth 2
                                        ;     Child Loop BB15_11 Depth 2
                                        ;     Child Loop BB15_13 Depth 2
                                        ;       Child Loop BB15_14 Depth 3
                                        ;     Child Loop BB15_21 Depth 2
                                        ;       Child Loop BB15_23 Depth 3
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_5+1
	CPI	1
	;--- V6CLANG_BRCOND ---
	JZ	.LBB15_6
; %bb.7:                                ;   in Loop: Header=BB15_4 Depth=1
	LXI	B, count-1
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_5+1
.LBB15_8:                               ;   Parent Loop BB15_4 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	;--- V6CLANG_DAD ---
	PUSH	H
	MOV	H, L
	MOV	L, A
	DAD	B
	XCHG
	POP	H
	;--- V6CLANG_STORE8_P ---
	STAX	D
	DCR	A
	CPI	1
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_8
; %bb.5:                                ;   in Loop: Header=BB15_4 Depth=1
	MVI	A, 1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_5+1
.LBB15_6:                               ;   in Loop: Header=BB15_4 Depth=1
	;--- V6CLANG_CMP8_ZERO ---
	XRA	A
	CMP	H
	;--- V6CLANG_BRCOND ---
	JZ	.LBB15_9
; %bb.10:                               ;   in Loop: Header=BB15_4 Depth=1
	LXI	B, perm1
	LXI	D, perm
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_6+1
.LBB15_11:                              ;   Parent Loop BB15_4 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;--- V6CLANG_LOAD8_P ---
	MOV	L, A
	LDAX	B
	MOV	H, A
	MOV	A, L
	;--- V6CLANG_STORE8_P ---
	XCHG
	MOV	M, D
	XCHG
	;--- V6CLANG_INX16 ---
	INX	D
	;--- V6CLANG_INX16 ---
	INX	B
	DCR	A
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_11
.LBB15_9:                               ;   in Loop: Header=BB15_4 Depth=1
	LDA	perm
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	;--- V6CLANG_BRCOND ---
	JZ	.LBB15_16
; %bb.12:                               ;   in Loop: Header=BB15_4 Depth=1
	MVI	H, 0
	MOV	E, H
.LBB15_13:                              ;   Parent Loop BB15_4 Depth=1
                                        ; =>  This Loop Header: Depth=2
                                        ;       Child Loop BB15_14 Depth 3
	;--- V6CLANG_SPILL8 ---
	MOV	B, A
	MOV	A, H
	STA	.LLo61_8+1
	MOV	D, B
	LXI	B, perm
	MVI	L, 1
	;--- V6CLANG_SPILL8 ---
	MOV	A, L
	STA	.LLo61_2+1
	MOV	H, D
.LBB15_14:                              ;   Parent Loop BB15_4 Depth=1
                                        ;     Parent Loop BB15_13 Depth=2
                                        ; =>    This Inner Loop Header: Depth=3
	;--- V6CLANG_SPILL16 ---
	PUSH	H
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_1+1
	POP	H
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, E
	MOV	E, H
	LXI	B, perm
	;--- V6CLANG_DAD ---
	PUSH	H
	XCHG
	DAD	B
	XCHG
	POP	H
	;--- V6CLANG_RELOAD16 ---
.LLo61_1:
	LXI	B, 0
	;--- V6CLANG_LOAD8_P ---
	XCHG
	MOV	E, M
	XCHG
	;--- V6CLANG_SPILL8 ---
	PUSH	PSW
	MOV	A, L
	STA	.LLo61_4+1
	;--- V6CLANG_LOAD8_P ---
	LDAX	B
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_7+1
	;--- V6CLANG_RELOAD8 ---
.LLo61_4:
	MVI	L, 0
	;--- V6CLANG_STORE8_P ---
	MOV	A, L
	STAX	B
	POP	PSW
	;--- V6CLANG_RELOAD8 ---
.LLo61_7:
	MVI	L, 0
	;--- V6CLANG_STORE8_P ---
	XCHG
	MOV	M, E
	XCHG
	MVI	E, 0
	DCR	H
	MOV	D, A
	INR	D
	;--- V6CLANG_RELOAD8 ---
.LLo61_2:
	MVI	A, 0
	CMP	H
	;--- V6CLANG_INX16 ---
	INX	B
	MOV	A, D
	;--- V6CLANG_SPILL8 ---
	PUSH	H
	LXI	H, .LLo61_2+1
	MOV	M, D
	POP	H
	;--- V6CLANG_BRCOND ---
	JC	.LBB15_14
; %bb.15:                               ;   in Loop: Header=BB15_13 Depth=2
	;--- V6CLANG_RELOAD8 ---
.LLo61_8:
	MVI	H, 0
	INR	H
	LDA	perm
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_13
	JMP	.LBB15_17
.LBB15_16:                              ;   in Loop: Header=BB15_4 Depth=1
	MVI	H, 0
	MOV	E, H
.LBB15_17:                              ;   in Loop: Header=BB15_4 Depth=1
	;--- V6CLANG_RELOAD8 ---
.LLo61_3:
	MVI	A, 0
	CMP	H
	JNC	.LBB15_19
; %bb.18:                               ;   in Loop: Header=BB15_4 Depth=1
	;--- V6CLANG_SPILL8 ---
	MOV	A, H
	STA	.LLo61_3+1
.LBB15_19:                              ;   in Loop: Header=BB15_4 Depth=1
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_6+1
	CPI	1
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_5+1
	;--- V6CLANG_BRCOND ---
	JZ	.LBB15_20
.LBB15_21:                              ;   Parent Loop BB15_4 Depth=1
                                        ; =>  This Loop Header: Depth=2
                                        ;       Child Loop BB15_23 Depth 3
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, E
	MOV	L, A
	;--- V6CLANG_SPILL16 ---
	SHLD	.LLo61_0+1
	;--- V6CLANG_SPILL8 ---
	STA	.LLo61_5+1
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	LDA	perm1
	;--- V6CLANG_BRCOND ---
	JZ	.LBB15_24
; %bb.22:                               ;   in Loop: Header=BB15_21 Depth=2
	LXI	B, perm1
	;--- V6CLANG_RELOAD8 ---
.LLo61_5:
	MVI	H, 0
	LXI	D, perm1
.LBB15_23:                              ;   Parent Loop BB15_4 Depth=1
                                        ;     Parent Loop BB15_21 Depth=2
                                        ; =>    This Inner Loop Header: Depth=3
	;--- V6CLANG_INX16 ---
	INX	D
	;--- V6CLANG_LOAD8_P ---
	XCHG
	MOV	E, M
	XCHG
	;--- V6CLANG_STORE8_P ---
	PUSH	PSW
	MOV	A, L
	STAX	B
	POP	PSW
	DCR	H
	MOV	B, D
	MOV	C, E
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_23
.LBB15_24:                              ;   in Loop: Header=BB15_21 Depth=2
	LXI	H, perm1
	;--- V6CLANG_RELOAD16 ---
.LLo61_0:
	LXI	D, 0
	;--- V6CLANG_DAD ---
	DAD	D
	;--- V6CLANG_STORE8_P ---
	MOV	M, A
	LXI	H, count
	;--- V6CLANG_DAD ---
	DAD	D
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	DCR	A
	;--- V6CLANG_STORE8_P ---
	MOV	M, A
	;--- V6CLANG_RELOAD8 ---
.LLo61_6:
	MVI	H, 0
	MVI	E, 0
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_4
; %bb.25:                               ;   in Loop: Header=BB15_21 Depth=2
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_5+1
	INR	A
	CMP	H
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_21
.LBB15_20:
	;--- V6CLANG_RELOAD8 ---
	LDA	.LLo61_3+1
	OUT	0xed
	HLT
                                        ; -- End function
	.local	perm1                           ; @perm1
	.comm	perm1,7,1
	.local	count                           ; @count
	.comm	count,7,1
	.local	perm                            ; @perm
	.comm	perm,7,1
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,1,1
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
	.addrsig_sym __v6clang_a.main
