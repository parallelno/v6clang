// RUN: clang -target i8080-unknown-v6clang -O2 -fno-omit-frame-pointer -S -emit-llvm %s -o - | FileCheck %s
// CHECK: "frame-pointer"="all"
int simple(int x) { return x + 1; }
