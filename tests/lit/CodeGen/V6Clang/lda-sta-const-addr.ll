; RUN: llc -march=v6clang < %s | FileCheck %s

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

; Load i8 from constant address → LDA
; CHECK-LABEL: load_const_addr:
; CHECK:       LDA 0x100
; CHECK-NEXT:  RET
define i8 @load_const_addr() {
  %ptr = inttoptr i16 256 to ptr
  %val = load volatile i8, ptr %ptr
  ret i8 %val
}

; Store i8 to constant address → STA
; CHECK-LABEL: store_const_addr:
; CHECK:       STA 0x100
; CHECK-NEXT:  RET
define void @store_const_addr(i8 %val) {
  %ptr = inttoptr i16 256 to ptr
  store volatile i8 %val, ptr %ptr
  ret void
}

; Copy between two constant addresses → LDA + STA
; CHECK-LABEL: copy_const_addr:
; CHECK:       LDA 0x100
; CHECK-NEXT:  STA 0x200
; CHECK-NEXT:  RET
define void @copy_const_addr() {
  %src = inttoptr i16 256 to ptr
  %dst = inttoptr i16 512 to ptr
  %val = load volatile i8, ptr %src
  store volatile i8 %val, ptr %dst
  ret void
}

; Existing global-address LDA still works
@gvar = global i8 0
; CHECK-LABEL: load_global:
; CHECK:       LDA gvar
; CHECK-NEXT:  RET
define i8 @load_global() {
  %val = load i8, ptr @gvar
  ret i8 %val
}

; Existing global-address STA still works
; CHECK-LABEL: store_global:
; CHECK:       STA gvar
; CHECK-NEXT:  RET
define void @store_global(i8 %val) {
  store i8 %val, ptr @gvar
  ret void
}
