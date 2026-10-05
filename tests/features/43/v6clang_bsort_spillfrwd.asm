	.text
	.globl	bsort_for                       ; -- Begin function bsort_for
bsort_for:                              ; @bsort_for
	;=== void bsort_for(void* arg0, char arg1) ===
	;  arg0 = HL
	;  arg1 = E
; %bb.0:
	MOV	A, E
	SHLD	.LLo61_2+1
	MVI	L, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	H, L
	MOV	L, A
	CPI	2
	;--- V6CLANG_BRCOND ---
	RC
.LBB0_1:
	;--- V6CLANG_DCX16 ---
	DCX	HL
	LXI	DE, 0
	SHLD	.LLo61_5+1
.LBB0_2:                                ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB0_4 Depth 2
	XCHG
	SHLD	.LLo61_1+1
	XCHG
	;--- V6CLANG_SUB16 ---
	MOV	A, L
	SUB	E
	MOV	L, A
	MOV	A, H
	SBB	D
	MOV	H, A
	SHLD	.LLo61_4+1
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, H
	ORA	L
	JNZ	.LBB0_7
; %bb.3:                                ;   in Loop: Header=BB0_2 Depth=1
	INR	A
	STA	.LLo61_6+1
.LLo61_2:
	LXI	BC, 0
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_3+1
	JMP	.LBB0_4
.LBB0_6:                                ;   in Loop: Header=BB0_4 Depth=2
	MVI	A, 0
.LLo61_6:
	MVI	E, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	B, A
	MOV	C, E
	PUSH	HL
	MOV	L, C
	MOV	H, B
	SHLD	.LLo61_0+1
	POP	HL
	INR	E
	MOV	A, E
	STA	.LLo61_6+1
	SHLD	.LLo61_3+1
	MOV	B, H
	MOV	C, L
.LLo61_4:
	LXI	HL, 0
.LLo61_0:
	LXI	DE, 0
	;--- V6CLANG_BR_CC16 ---
	MOV	A, E
	SUB	L
	MOV	A, D
	SBB	H
	JNC	.LBB0_7
.LBB0_4:                                ;   Parent Loop BB0_2 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
.LLo61_3:
	LXI	DE, 0
	;--- V6CLANG_LOAD8_P ---
	LDAX	DE
	MOV	L, A
	;--- V6CLANG_INX16 ---
	INX	BC
	;--- V6CLANG_LOAD8_P ---
	LDAX	BC
	PUSH	PSW
	MOV	A, L
	STA	.LLo61_7+1
	POP	PSW
	CMP	L
	MOV	H, B
	MOV	L, C
	;--- V6CLANG_BRCOND ---
	JNC	.LBB0_6
; %bb.5:                                ;   in Loop: Header=BB0_4 Depth=2
	;--- V6CLANG_STORE8_P ---
	STAX	DE
	;--- V6CLANG_INX16 ---
	INX	DE
.LLo61_7:
	MVI	A, 0
	;--- V6CLANG_STORE8_P ---
	STAX	DE
	JMP	.LBB0_6
.LBB0_7:                                ;   in Loop: Header=BB0_2 Depth=1
.LLo61_1:
	LXI	DE, 0
	;--- V6CLANG_INX16 ---
	INX	DE
.LLo61_5:
	LXI	HL, 0
	;--- V6CLANG_BR_CC16 ---
	MOV	A, E
	CMP	L
	JNZ	.LBB0_2
; %bb.9:                                ;   in Loop: Header=BB0_2 Depth=1
	MOV	A, D
	CMP	H
	JNZ	.LBB0_2
; %bb.8:
	RET
                                        ; -- End function
	.globl	print_arr                       ; -- Begin function print_arr
print_arr:                              ; @print_arr
	;=== void print_arr(void* arg0, char arg1) ===
	;  arg0 = HL
	;  arg1 = E
; %bb.0:
	MOV	A, E
	ORA	A
	;--- V6CLANG_BRCOND ---
	RZ
.LBB1_2:
	MVI	E, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, E
	MOV	E, A
.LBB1_3:                                ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_LOAD8_P ---
	MOV	A, M
	OUT	0xed
	;--- V6CLANG_INX16 ---
	INX	HL
	;--- V6CLANG_DCX16 ---
	DCX	DE
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, D
	ORA	E
	JNZ	.LBB1_3
; %bb.1:
	RET
                                        ; -- End function
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== int main(int arg0, void* arg1) ===
	;  arg0 = HL
	;  arg1 = DE
; %bb.0:
	DI
	HLT
	LXI	HL, ARR
	MVI	E, 0x10
	CALL	bsort_for
	LXI	HL, ARR
	MVI	E, 0x10
	CALL	print_arr
	HLT
	LXI	HL, 0
	RET
                                        ; -- End function
	.section	.bss,"aw",@nobits
	.globl	ARR                             ; @ARR
ARR:

	.addrsig
	.addrsig_sym ARR
