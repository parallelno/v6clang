// RUN: clang -target i8080-unknown-v6clang -S -emit-llvm %s -o - | FileCheck %s
//
// Verify that type sizes match design §2.3:
//   sizeof(char)==1, sizeof(short)==2, sizeof(int)==2,
//   sizeof(long)==4, sizeof(void*)==2

// Use global arrays sized by sizeof() to check via IR.

char arr_char[sizeof(char)];
// CHECK: @arr_char = {{.*}} [1 x i8]

char arr_short[sizeof(short)];
// CHECK: @arr_short = {{.*}} [2 x i8]

char arr_int[sizeof(int)];
// CHECK: @arr_int = {{.*}} [2 x i8]

char arr_long[sizeof(long)];
// CHECK: @arr_long = {{.*}} [4 x i8]

char arr_ptr[sizeof(void*)];
// CHECK: @arr_ptr = {{.*}} [2 x i8]
