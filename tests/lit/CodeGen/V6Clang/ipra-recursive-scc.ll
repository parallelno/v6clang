; RUN: llc -march=v6clang -O2 < %s | FileCheck %s
;
; Verify that IPRA stays conservative for functions in a recursive SCC
; (strongly connected component) while still narrowing the mask for a
; simple leaf callee.
;
; ping ??? pong form a mutual-recursion SCC.  IPRA cannot compute a
; fixed-point clobber set for the cycle, so calls into the SCC must
; remain fully conservative (spill around the call).  A leaf callee
; that is NOT part of the SCC should still benefit from IPRA.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@sink = global i16 0, align 1

; --- SCC members: ping ??? pong ------------------------------------------

define void @pong(i16 %n) {
entry:
  store volatile i16 %n, ptr @sink, align 1
  %dec = add i16 %n, -1
  %cmp = icmp eq i16 %dec, 0
  br i1 %cmp, label %done, label %recurse
recurse:
  call void @ping(i16 %dec)
  ret void
done:
  ret void
}

define void @ping(i16 %n) {
entry:
  store volatile i16 %n, ptr @sink, align 1
  %dec = add i16 %n, -1
  %cmp = icmp eq i16 %dec, 0
  br i1 %cmp, label %done, label %recurse
recurse:
  call void @pong(i16 %dec)
  ret void
done:
  ret void
}

; --- Callers ------------------------------------------------------------

; Caller with a value live across a call into the SCC.
; IPRA must NOT narrow the mask ??? spill frame expected.
define i16 @caller_scc(i16 %x) {
entry:
  call void @ping(i16 %x)
  ret i16 %x
}

; Leaf outside the SCC ??? IPRA should narrow the mask, no spill needed.
define void @leaf() {
entry:
  store volatile i16 99, ptr @sink, align 1
  ret void
}

define i16 @caller_leaf(i16 %x) {
entry:
  call void @leaf()
  ret i16 %x
}

; CHECK-LABEL: caller_scc:
; CHECK:       PUSH PSW
; CHECK:       CALL ping
;
; CHECK-LABEL: caller_leaf:
; CHECK:       MOV D, H
; CHECK-NEXT:  MOV E, L
; CHECK-NEXT:  CALL leaf
; CHECK-NEXT:  XCHG
; CHECK-NEXT:  RET
; CHECK-NOT:   LXI H, 0xfffe
