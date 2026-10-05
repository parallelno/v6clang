; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -filetype=obj -mv6clang-spill-patched-reload -v6clang-disable-shld-lhld-fold %s -o %t.o
; RUN: lld -flavor gnu -m elf32v6clang --unresolved-symbols=ignore-all -e one_reload -o %t.elf %t.o
; RUN: llvm-dwarfdump --debug-info --debug-loclists %t.elf | FileCheck %s --check-prefix=DWARF
; RUN: llvm-dwarfdump --verify %t.elf

; DWARF: DW_TAG_variable
; DWARF: DW_AT_location{{.*}}loclist
; DWARF: DW_OP_reg9 HL
; DWARF: DW_OP_addrx
; DWARF: DW_OP_plus_uconst 0x1
; DWARF: DW_AT_name{{.*}}("carried")

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare i16 @op(i16)
declare void @llvm.dbg.value(metadata, metadata, metadata)

define i16 @one_reload(i16 %x) norecurse !dbg !10 {
entry:
  %a = call i16 @op(i16 %x), !dbg !16
  call void @llvm.dbg.value(metadata i16 %a, metadata !14, metadata !DIExpression()), !dbg !16
  %b1 = call i16 @op(i16 %a), !dbg !17
  %b2 = call i16 @op(i16 %a), !dbg !18
  %r = add i16 %b1, %b2, !dbg !19
  ret i16 %r, !dbg !20
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!6, !7}
!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "V6CLANG test", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "debug-o61-patched-location.c", directory: "/")
!6 = !{i32 2, !"Dwarf Version", i32 5}
!7 = !{i32 2, !"Debug Info Version", i32 3}
!10 = distinct !DISubprogram(name: "one_reload", scope: !1, file: !1, line: 1, type: !11, scopeLine: 1, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !0)
!11 = !DISubroutineType(types: !12)
!12 = !{!13, !13}
!13 = !DIBasicType(name: "int", size: 16, encoding: DW_ATE_signed)
!14 = !DILocalVariable(name: "carried", scope: !10, file: !1, line: 2, type: !13)
!16 = !DILocation(line: 2, column: 3, scope: !10)
!17 = !DILocation(line: 3, column: 3, scope: !10)
!18 = !DILocation(line: 4, column: 3, scope: !10)
!19 = !DILocation(line: 5, column: 3, scope: !10)
!20 = !DILocation(line: 6, column: 3, scope: !10)