; RUN: llc -mtriple=i8080-unknown-v6clang -O0 -filetype=obj %s -o %t.o
; RUN: lld -flavor gnu -m elf32v6clang -e nested_locals -o %t.o0.elf %t.o
; RUN: llvm-dwarfdump --debug-info --debug-loclists %t.o0.elf | FileCheck %s --check-prefix=O0
; RUN: llvm-dwarfdump --verify %t.o0.elf
; RUN: llc -mtriple=i8080-unknown-v6clang -O1 -filetype=obj %s -o %t.o
; RUN: lld -flavor gnu -m elf32v6clang -e nested_locals -o %t.o1.elf %t.o
; RUN: llvm-dwarfdump --debug-info --debug-loclists %t.o1.elf | FileCheck %s --check-prefix=O1
; RUN: llvm-dwarfdump --verify %t.o1.elf
; RUN: llc -mtriple=i8080-unknown-v6clang -O2 -filetype=obj %s -o %t.o
; RUN: lld -flavor gnu -m elf32v6clang -e nested_locals -o %t.o2.elf %t.o
; RUN: llvm-dwarfdump --debug-info --debug-loclists %t.o2.elf | FileCheck %s --check-prefix=O2
; RUN: llvm-dwarfdump --verify %t.o2.elf

; O0: DW_TAG_variable
; O0: DW_AT_location{{.*}}DW_OP_addrx
; O0: DW_AT_name{{.*}}("outer")
; O0: DW_TAG_lexical_block
; O0: DW_TAG_variable
; O0: DW_AT_location{{.*}}DW_OP_addrx
; O0: DW_AT_name{{.*}}("inner")
; O0: DW_TAG_lexical_block
; O0: DW_TAG_variable
; O0: DW_AT_location{{.*}}DW_OP_addrx
; O0: DW_AT_name{{.*}}("block_local")

; O1: DW_AT_name{{.*}}("outer")
; O1: DW_AT_name{{.*}}("inner")
; O1: DW_AT_name{{.*}}("block_local")

; O2: DW_AT_name{{.*}}("outer")
; O2: DW_AT_name{{.*}}("inner")
; O2: DW_AT_name{{.*}}("block_local")

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

declare void @llvm.dbg.declare(metadata, metadata, metadata)

define i8 @nested_locals(i8 %input) norecurse !dbg !10 {
entry:
  %outer = alloca i8, align 1
  %inner = alloca i8, align 1
  %block_local = alloca i8, align 1
  call void @llvm.dbg.declare(metadata ptr %outer, metadata !14, metadata !DIExpression()), !dbg !20
  store i8 %input, ptr %outer, align 1, !dbg !20
  br label %loop, !dbg !20

loop:
  call void @llvm.dbg.declare(metadata ptr %inner, metadata !15, metadata !DIExpression()), !dbg !21
  %outer_value = load i8, ptr %outer, align 1, !dbg !21
  store i8 %outer_value, ptr %inner, align 1, !dbg !21
  br i1 true, label %then, label %exit, !dbg !21

then:
  call void @llvm.dbg.declare(metadata ptr %block_local, metadata !16, metadata !DIExpression()), !dbg !22
  %inner_value = load i8, ptr %inner, align 1, !dbg !22
  store i8 %inner_value, ptr %block_local, align 1, !dbg !22
  br label %exit, !dbg !22

exit:
  %result = load i8, ptr %outer, align 1, !dbg !20
  ret i8 %result, !dbg !20
}

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!6, !7}
!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "V6CLANG test", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "debug-nested-static-locals.c", directory: "/")
!6 = !{i32 2, !"Dwarf Version", i32 5}
!7 = !{i32 2, !"Debug Info Version", i32 3}
!10 = distinct !DISubprogram(name: "nested_locals", scope: !1, file: !1, line: 1, type: !11, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)
!11 = !DISubroutineType(types: !12)
!12 = !{!13, !13}
!13 = !DIBasicType(name: "unsigned char", size: 8, encoding: DW_ATE_unsigned_char)
!14 = !DILocalVariable(name: "outer", scope: !10, file: !1, line: 2, type: !13)
!15 = !DILocalVariable(name: "inner", scope: !17, file: !1, line: 4, type: !13)
!16 = !DILocalVariable(name: "block_local", scope: !18, file: !1, line: 6, type: !13)
!17 = distinct !DILexicalBlock(scope: !10, file: !1, line: 3, column: 1)
!18 = distinct !DILexicalBlock(scope: !17, file: !1, line: 5, column: 1)
!20 = !DILocation(line: 2, column: 1, scope: !10)
!21 = !DILocation(line: 4, column: 1, scope: !17)
!22 = !DILocation(line: 6, column: 1, scope: !18)