	.text
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(int arg0, void* arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	LXI	H, __v6clang_a.main
	MVI	E, 0xff
	MVI	A, 7
.LBB15_1:                               ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_STORE8_P ---
	MOV	M, A
	ADI	0x1f
	;--- V6CLANG_INX16 ---
	INX	H
	DCR	E
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_1
; %bb.2:
	MVI	L, 0xfe
.LBB15_3:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB15_4 Depth 2
	LXI	B, __v6clang_a.main
	;--- V6CLANG_SPILL8 ---
	MOV	A, L
	STA	.LLo61_0+1
	LXI	D, __v6clang_a.main
.LBB15_4:                               ;   Parent Loop BB15_3 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;--- V6CLANG_LOAD8_P ---
	LDAX	B
	MOV	H, A
	;--- V6CLANG_INX16 ---
	INX	D
	;--- V6CLANG_LOAD8_P ---
	LDAX	D
	CMP	H
	;--- V6CLANG_BRCOND ---
	JNC	.LBB15_6
; %bb.5:                                ;   in Loop: Header=BB15_4 Depth=2
	;--- V6CLANG_STORE8_P ---
	STAX	B
	;--- V6CLANG_INX16 ---
	INX	B
	;--- V6CLANG_STORE8_P ---
	MOV	A, H
	STAX	B
.LBB15_6:                               ;   in Loop: Header=BB15_4 Depth=2
	DCR	L
	MOV	B, D
	MOV	C, E
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_4
; %bb.7:                                ;   in Loop: Header=BB15_3 Depth=1
	;--- V6CLANG_RELOAD8 ---
.LLo61_0:
	MVI	L, 0
	DCR	L
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_3
; %bb.8:
	XRA	A
	LXI	H, __v6clang_a.main
	MVI	E, 0xff
.LBB15_9:                               ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_ADD_M_P ---
	ADD	M
	;--- V6CLANG_INX16 ---
	INX	H
	DCR	E
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB15_9
; %bb.10:
	OUT	0xed
	HLT
                                        ; -- End function
	.local	__v6clang_a.main                    ; @__v6clang_a.main
	.comm	__v6clang_a.main,255,1
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
