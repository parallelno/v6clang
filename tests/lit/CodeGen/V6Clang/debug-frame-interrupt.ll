; RUN: llc -mtriple=i8080-unknown-v6clang -filetype=obj %s -o %t.o
; RUN: lld -flavor gnu -m elf32v6clang -e isr %t.o -o %t.elf
; RUN: llvm-dwarfdump --debug-frame %t.elf | FileCheck %s
; RUN: llvm-dwarfdump --verify %t.elf

; CHECK: Return address column: 11
; CHECK: FDE
; CHECK: DW_CFA_def_cfa: SP +2
; CHECK-NEXT: DW_CFA_undefined: PC
; CHECK: CFA=SP+2: PC=undefined

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

define void @isr() #0 !dbg !10 {
entry:
  ret void, !dbg !13
}

attributes #0 = { "interrupt" }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!6, !7}
!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "V6CLANG test", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)
!1 = !DIFile(filename: "interrupt.c", directory: "/")
!6 = !{i32 2, !"Dwarf Version", i32 5}
!7 = !{i32 2, !"Debug Info Version", i32 3}
!10 = distinct !DISubprogram(name: "isr", scope: !1, file: !1, line: 1, type: !11, scopeLine: 1, spFlags: DISPFlagDefinition, unit: !0)
!11 = !DISubroutineType(types: !12)
!12 = !{null}
!13 = !DILocation(line: 2, column: 1, scope: !10)
