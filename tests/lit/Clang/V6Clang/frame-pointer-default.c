// RUN: clang -target i8080-unknown-v6clang -O2 -S -emit-llvm %s -o - | FileCheck %s
// CHECK-NOT: "frame-pointer"="all"
// CHECK-NOT: "frame-pointer"="non-leaf"
int simple(int x) { return x + 1; }
