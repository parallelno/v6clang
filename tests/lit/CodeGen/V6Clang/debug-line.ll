; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj -o %t.o %s
; RUN: llvm-readelf -S %t.o | FileCheck %s
; RUN: llvm-readelf -r %t.o | FileCheck %s --check-prefix=RELOC
; RUN: lld -flavor gnu -m elf32v6clang -e answer -o %t.elf %t.o
; RUN: llvm-readobj --file-headers %t.elf | FileCheck %s --check-prefix=FORMAT
; RUN: llvm-readelf -S %t.elf | FileCheck %s --check-prefix=LINKED
; RUN: llvm-readelf -r %t.elf | FileCheck %s --check-prefix=LINKED-RELOC
; RUN: llvm-dwarfdump --verify %t.elf

; CHECK-DAG: {{[[:space:]]}}.debug_info{{[[:space:]]}}
; CHECK-DAG: {{[[:space:]]}}.debug_abbrev{{[[:space:]]}}
; CHECK-DAG: {{[[:space:]]}}.debug_line{{[[:space:]]}}
; CHECK-DAG: {{[[:space:]]}}.debug_str{{[[:space:]]}}
; CHECK-DAG: {{[[:space:]]}}.debug_str_offsets{{[[:space:]]}}
; CHECK-DAG: {{[[:space:]]}}.debug_addr{{[[:space:]]}}

; RELOC: Relocation section '.rela.debug_info'
; RELOC-DAG: R_V6CLANG_32{{.*}}.debug_abbrev
; RELOC-DAG: R_V6CLANG_32{{.*}}.debug_str_offsets
; RELOC-DAG: R_V6CLANG_32{{.*}}.debug_line
; RELOC-DAG: R_V6CLANG_32{{.*}}.debug_addr

; LINKED-DAG: {{[[:space:]]}}.debug_info{{[[:space:]]}}
; LINKED-DAG: {{[[:space:]]}}.debug_abbrev{{[[:space:]]}}
; LINKED-DAG: {{[[:space:]]}}.debug_line{{[[:space:]]}}
; LINKED-DAG: {{[[:space:]]}}.debug_str{{[[:space:]]}}
; LINKED-DAG: {{[[:space:]]}}.debug_str_offsets{{[[:space:]]}}
; LINKED-DAG: {{[[:space:]]}}.debug_addr{{[[:space:]]}}

; LINKED-RELOC: There are no relocations in this file.

; FORMAT: Format: elf32-v6clang
; FORMAT: Arch: i8080

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define i8 @answer() !dbg !10 {
entry:
  ret i8 42, !dbg !13
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!6, !7}
!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "V6CLANG test", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "debug-line.c", directory: "/")
!6 = !{i32 2, !"Dwarf Version", i32 5}
!7 = !{i32 2, !"Debug Info Version", i32 3}
!10 = distinct !DISubprogram(name: "answer", scope: !1, file: !1, line: 1, type: !11, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)
!11 = !DISubroutineType(types: !12)
!12 = !{!14}
!13 = !DILocation(line: 2, column: 3, scope: !10)
!14 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)