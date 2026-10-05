	.text
	.section	.text.reset_int,"ax",@progbits
reset_int:                              ; -- Begin function reset_int
                                        ; @reset_int
	;=== void reset_int(void) ===
; %bb.0:
	;APP
	MVI	A, 0xc9
	STA	0x38

	;NO_APP
	RET
                                        ; -- End function
	.section	.text.palette_init,"ax",@progbits
palette_init:                           ; -- Begin function palette_init
                                        ; @palette_init
	;=== void palette_init(void* arg0) ===
	;  arg0 = HL
; %bb.0:
	;APP
	HLT

	MVI	A, 0x88
	OUT	0
	MVI	B, 0xf
loop:
	MOV	A, B
	OUT	2
	MOV	A, M
	OUT	0xc
	PUSH	PSW
	POP	PSW
	PUSH	PSW
	POP	PSW
	DCX	H
	DCR	B
	OUT	0xc
	JP	loop
	RET


	;NO_APP
	RET
                                        ; -- End function
	.section	.text.draw_char,"ax",@progbits
draw_char:                              ; -- Begin function draw_char
                                        ; @draw_char
	;=== void draw_char(char arg0, void* arg1) ===
	;  arg0 = A
	;  arg1 = HL
; %bb.0:
	MVI	E, 0
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, E
	MOV	E, A
	;--- V6CLANG_ADD16 ---
	XCHG
	DAD	H
	;--- V6CLANG_ADD16 ---
	DAD	H
	;--- V6CLANG_ADD16 ---
	DAD	H
	LXI	B, font-520
	;--- V6CLANG_ADD16 ---
	DAD	B
	XCHG
	MVI	A, 8
.LBB17_1:                               ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_LOAD8_P ---
	XCHG
	MOV	C, M
	XCHG
	;--- V6CLANG_STORE8_P ---
	MOV	M, C
	;--- V6CLANG_DCX16 ---
	DCX	H
	;--- V6CLANG_INX16 ---
	INX	D
	DCR	A
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB17_1
; %bb.2:
	RET
                                        ; -- End function
	.section	.text.draw_text,"ax",@progbits
draw_text:                              ; -- Begin function draw_text
                                        ; @draw_text
	;=== void draw_text(void* arg0, char arg1, char arg2) ===
	;  arg0 = HL
	;  arg1 = A
	;  arg2 = B
; %bb.0:
	PUSH	D
	PUSH	D
	MOV	D, H
	MOV	E, L
	;--- V6CLANG_LOAD8_P ---
	XCHG
	MOV	E, M
	XCHG
	;--- V6CLANG_CMP8_ZERO ---
	INR	L
	DCR	L
	;--- V6CLANG_BRCOND ---
	JZ	.LBB18_3
; %bb.1:
	MVI	H, 0
	;--- V6CLANG_SPILL16 ---
	PUSH	H
	LXI	H, 4
	DAD	SP
	MOV	M, E
	INX	H
	MOV	M, D
	POP	H
	;--- V6CLANG_BUILD_PAIR ---
	MOV	D, H
	MOV	E, B
	;--- V6CLANG_BUILD_PAIR ---
	MOV	B, A
	MOV	C, H
	;--- V6CLANG_OR16 ---
	MOV	A, C
	ORA	E
	MOV	E, A
	MOV	A, B
	ORA	D
	MOV	D, A
	LXI	B, 0x8000
	;--- V6CLANG_XOR16 ---
	MOV	A, E
	XRA	C
	MOV	C, A
	MOV	A, D
	XRA	B
	MOV	B, A
	;--- V6CLANG_RELOAD16 ---
	PUSH	H
	LXI	H, 4
	DAD	SP
	MOV	E, M
	INX	H
	MOV	D, M
	POP	H
	MOV	A, L
	;--- V6CLANG_INX16 ---
	INX	D
.LBB18_2:                               ; =>This Inner Loop Header: Depth=1
	;--- V6CLANG_SPILL16 ---
	LXI	H, 0
	DAD	SP
	MOV	M, C
	INX	H
	MOV	M, B
	;--- V6CLANG_SPILL16 ---
	LXI	H, 2
	DAD	SP
	MOV	M, E
	INX	H
	MOV	M, D
	MOV	H, B
	MOV	L, C
	CALL	draw_char
	;--- V6CLANG_RELOAD16 ---
	LXI	H, 0
	DAD	SP
	MOV	C, M
	INX	H
	MOV	B, M
	;--- V6CLANG_RELOAD16 ---
	LXI	H, 2
	DAD	SP
	MOV	E, M
	INX	H
	MOV	D, M
	LXI	H, 0x100
	;--- V6CLANG_ADD16 ---
	DAD	B
	MOV	B, H
	MOV	C, L
	;--- V6CLANG_LOAD8_P ---
	LDAX	D
	;--- V6CLANG_INX16 ---
	INX	D
	;--- V6CLANG_CMP8_ZERO ---
	ORA	A
	;--- V6CLANG_BRCOND ---
	JNZ	.LBB18_2
.LBB18_3:
	POP	PSW
	POP	PSW
	RET
                                        ; -- End function
	.section	.text.fill_rect,"ax",@progbits
fill_rect:                              ; -- Begin function fill_rect
                                        ; @fill_rect
	;=== void fill_rect(void) ===
; %bb.0:
	LXI	D, 8
	LXI	H, 0x8832
.LBB19_1:                               ; =>This Loop Header: Depth=1
                                        ;     Child Loop BB19_2 Depth 2
	;--- V6CLANG_SPILL16 ---
	XCHG
	SHLD	.LLo61_0+1
	XCHG
	LXI	B, 0x9c
	MOV	D, H
	MOV	E, L
.LBB19_2:                               ;   Parent Loop BB19_1 Depth=1
                                        ; =>  This Inner Loop Header: Depth=2
	;--- V6CLANG_STORE8_IMM_P ---
	MVI	A, 0xff
	STAX	D
	;--- V6CLANG_INX16 ---
	INX	D
	;--- V6CLANG_DCX16 ---
	DCX	B
	;--- V6CLANG_BR_CC16_IMM ---
	MOV	A, B
	ORA	C
	JNZ	.LBB19_2
; %bb.4:                                ;   in Loop: Header=BB19_1 Depth=1
	LXI	D, 0x100
	;--- V6CLANG_ADD16 ---
	DAD	D
	;--- V6CLANG_RELOAD16 ---
.LLo61_0:
	LXI	D, 0
	;--- V6CLANG_INX16 ---
	INX	D
	;--- V6CLANG_BR_CC16_IMM ---
	MVI	A, 0x18
	CMP	E
	JNZ	.LBB19_1
; %bb.5:                                ;   in Loop: Header=BB19_1 Depth=1
	XRA	A
	CMP	D
	JNZ	.LBB19_1
; %bb.3:
	RET
                                        ; -- End function
	.section	.text.main,"ax",@progbits
	.globl	main                            ; -- Begin function main
main:                                   ; @main
	;=== void main(void) ===
; %bb.0:
	EI
	CALL	reset_int
	LXI	H, palette
	CALL	palette_init
	CALL	fill_rect
	LXI	H, .str
	MVI	A, 0xb
	MVI	B, 0xa
	CALL	draw_text
	DI
	HLT
	RET
                                        ; -- End function
	.data
	.globl	font                            ; @font
font:
	.ascii	"\000\030$B~BB\000\000|B|BB|\000\000<B@@B<\000\000xDBBDx\000\000~@|@@~\000\000~@|@@@\000\000<B@NB<\000\000BB~BBB\000\000>\b\b\b\b>\000\000\002\002\002\002B<\000\000BDxDBB\000\000@@@@@~\000\000BfZBBB\000\000BbRJFB\000\000<BBBB<\000\000|BB|@@\000\000<BBJD:\000\000|BB|DB\000\000<B0\fB<\000\000\177\b\b\b\b\b\000\000BBBBB<\000\000BBBB$\030\000\000BBBZfB\000\000B$\030\030$B\000\000A\"\024\b\b\b\000\000~\004\b\020 ~\000"

	.globl	palette                         ; @palette
palette:
	.ascii	"\000\021\"3DUfw\210\231\252\273\314\335\356\377"

	.section	.rodata.str1.1,"aMS",@progbits,1
.str:                                   ; @.str
	.ascii	"HELLOWORLD\000"

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
	.addrsig_sym reset_int
	.addrsig_sym palette_init
	.addrsig_sym draw_char
	.addrsig_sym draw_text
	.addrsig_sym palette
