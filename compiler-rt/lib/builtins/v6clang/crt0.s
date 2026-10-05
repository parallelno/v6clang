; crt0.s - V6CLANG C runtime startup
;
; Canonical V6CLANG startup. Linked in by ld.lld via the default linker script
; (clang/lib/Driver/ToolChains/V6Clang/v6clang.ld).
;
; Responsibilities:
;   1. Set SP = __stack_top
;   2. Zero [__bss_start, __bss_end).
;   3. CALL __entry  (defaults to `main`; override with --defsym=__entry=NAME).
;   4. HLT on return (no exit syscall on bare V6CLANG).
;
; Symbols supplied by the linker script:
;   __stack_top  - initial SP value (default 0x0000 -> first PUSH lands at 0xFFFE)
;   __bss_start  - first byte of .bss (inclusive)
;   __bss_end    - one-past-last byte of .bss (exclusive)
;   __entry      - C entry point alias (default: main).
;                  Override at link time: -Wl,--defsym=__entry=myStart
;                  The PROVIDE in v6clang.ld makes __entry = main unless --defsym
;                  defines it first.
;
; Symbol supplied by user code:
;   main (or the function named by __entry) - C entry point, normal V6CLANG
;                  calling convention
;
; Calling convention reminder (V6CLANG_CConv):
;   main's return value lands in A (i8) or HL (i16); ignored here.

    .section .text._start, "ax"
    .globl _start
_start:
    DI                       ; Disable interrupts during setup
    LXI SP, __stack_top      ; Initialize stack pointer

    ; Zero [__bss_start, __bss_end). Empty range is handled correctly
    ; (loop exits immediately when HL == DE).
    LXI H, __bss_start
    LXI D, __bss_end
_crt0_bss_loop:
    MOV A, L
    CMP E
    JNZ _crt0_bss_step       ; L != E -> not done
    MOV A, H
    CMP D
    JZ  _crt0_bss_done       ; H == D and L == E -> done
_crt0_bss_step:
    MVI M, 0                 ; [HL] = 0
    INX H                    ; HL++
    JMP _crt0_bss_loop
_crt0_bss_done:

    CALL __entry             ; Run user entry (default: main; override: --defsym=__entry=NAME)

    DI                       ; Disable interrupts before halting
    HLT                      ; Stop the CPU on return
