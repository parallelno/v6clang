/* v6clang.ld - Default linker script for V6CLANG (Vector-06c / i8080) targets.
 *
 * Used by clang's V6CLANG driver as the default `-T` argument for ld.lld.
 * The user can override it with their own `-T script.ld`, or tweak
 * specific symbols with e.g.:
 *   -Wl,--defsym=__stack_top=0xF000   (move initial SP)
 *   -Wl,--defsym=__entry=myStart      (use a function other than `main`)
 *
 * Memory map:
 *   0x0000 .. 0x00FF  - reserved (V6CLANG boot vector area)
 *   0x0100 ..         - .text, .rodata, .data, .bss.pack, .bss in that order
 *   __stack_top = 0x0000 - first PUSH wraps SP to 0xFFFE (top of RAM)
 *
 * crt0 places `_start` in `.text._start`, and the KEEP clause below
 * pins it at 0x0100 regardless of link order.
 */

ENTRY(_start)

SECTIONS {
  . = 0x0100;
  .text   : { KEEP(*(.text._start)) *(.text*) }
  .rodata : { *(.rodata*) }
  .data   : { *(.data*) }
  . = ALIGN(1);
  __bss_start = .;
  .bss.pack : {
    *(.bss.pack.align)
    *(.bss.pack.window)
    *(.bss.pack)
  }
  .bss    : { *(.bss .bss.* COMMON) }
  __bss_end = .;
  __stack_top = 0x0000;
  /* Default C entry alias.  Override with -Wl,--defsym=__entry=myStart.
   * PROVIDE is a no-op when --defsym already defines __entry. */
  PROVIDE(__entry = main);
}
